-- ============================================================================
-- CommonGoods: Create get_quote SQL Function
-- Run after 20260930060002_fix_config_security.sql
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Create get_quote function that computes pricing and creates a quote row
--    without creating a delivery
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_quote(
  p_customer_id uuid,
  p_partner_id uuid,
  p_category text,
  p_pickup_address text,
  p_pickup_lat double precision,
  p_pickup_lng double precision,
  p_dropoff_address text,
  p_dropoff_lat double precision,
  p_dropoff_lng double precision,
  p_distance_miles double precision,
  p_estimated_duration_minutes integer,
  p_notes text DEFAULT NULL,
  p_config_snapshot_id uuid DEFAULT NULL
)
RETURNS TABLE (
  success boolean,
  error text,
  quote_id uuid,
  expires_at timestamptz,
  pricing_breakdown jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_quote_id uuid;
  v_snapshot_id uuid;
  v_config jsonb;
  v_strategy text;
  v_zone integer;
  v_fee numeric(10,2);
  v_base_fee numeric(10,2);
  v_driver_payout numeric(10,2);
  v_platform_cut numeric(10,2);
  v_components jsonb;
  v_demand_multiplier numeric := 1.0;
  v_is_peak_hour boolean := false;
  v_weather_surcharge numeric := 0.0;
  v_pre_multiplier_fee numeric;
  v_pre_rounding_fee numeric;
  v_pre_minmax_fee numeric;
BEGIN
  -- Validate inputs
  IF p_customer_id IS NULL THEN
    RETURN QUERY SELECT false, 'missing_customer_id', NULL::uuid, NULL::timestamptz, NULL::jsonb;
    RETURN;
  END IF;

  IF p_distance_miles IS NULL OR p_distance_miles <= 0 THEN
    RETURN QUERY SELECT false, 'invalid_distance', NULL::uuid, NULL::timestamptz, NULL::jsonb;
    RETURN;
  END IF;

  -- Resolve config (use provided snapshot or current)
  IF p_config_snapshot_id IS NOT NULL THEN
    SELECT resolved INTO v_config FROM public.config_snapshots WHERE id = p_config_snapshot_id;
    IF v_config IS NULL THEN
      RETURN QUERY SELECT false, 'invalid_config_snapshot', NULL::uuid, NULL::timestamptz, NULL::jsonb;
      RETURN;
    END IF;
  ELSE
    SELECT config INTO v_config FROM public.resolve_all_config('{}'::jsonb, now());
  END IF;

  v_strategy := v_config->>'pricing.strategy';
  v_weather_surcharge := COALESCE((v_config->>'pricing.weather_surcharge')::numeric, 0);

  -- Check peak hours
  v_is_peak_hour := public.is_peak_hour(v_config->'pricing.peak_hours', now());

  -- Determine zone from distance bands
  IF v_strategy = 'zone_v1' THEN
    v_zone := CASE
      WHEN p_distance_miles <= (v_config->'pricing.distance_bands'->>0)::numeric THEN 1
      WHEN p_distance_miles <= (v_config->'pricing.distance_bands'->>1)::numeric THEN 2
      WHEN p_distance_miles <= (v_config->'pricing.distance_bands'->>2)::numeric THEN 3
      ELSE NULL
    END;

    IF v_zone IS NULL THEN
      RETURN QUERY SELECT false, 'OUTSIDE_SERVICE_AREA', NULL::uuid, NULL::timestamptz, NULL::jsonb;
      RETURN;
    END IF;

    -- Get base zone fee (before any adjustments)
    v_base_fee := (v_config->>format('pricing.zone.%s.fee', v_zone))::numeric;
    v_pre_multiplier_fee := v_base_fee;

    -- Apply demand multiplier if peak hour
    IF v_is_peak_hour THEN
      v_demand_multiplier := (v_config->'pricing.demand_multiplier'->>'min')::numeric;
      v_fee := v_base_fee * v_demand_multiplier;
    ELSE
      v_demand_multiplier := 1.0;
      v_fee := v_base_fee;
    END IF;

    -- Add weather surcharge
    v_fee := v_fee + v_weather_surcharge;
    v_pre_rounding_fee := v_fee;

    -- Round fee
    v_fee := CASE (v_config->>'pricing.fee_rounding')
      WHEN 'ceil_0.25' THEN ceil(v_fee * 4) / 4
      WHEN 'ceil_0.50' THEN ceil(v_fee * 2) / 2
      WHEN 'round' THEN round(v_fee * 100) / 100
      ELSE v_fee
    END;

    v_pre_minmax_fee := v_fee;

    -- Ensure min/max
    v_fee := GREATEST(v_fee, (v_config->>'pricing.min_fee')::numeric);
    v_fee := LEAST(v_fee, (v_config->>'pricing.max_fee')::numeric);

    -- Calculate driver payout and platform cut
    v_driver_payout := v_fee * (v_config->>'pay.payout_pct_or_per_mile')::numeric;
    v_driver_payout := GREATEST(v_driver_payout, (v_config->>'pay.min_payout')::numeric);
    v_platform_cut := v_fee - v_driver_payout;

    -- Build components that SUM to customer_total
    v_components := '[]'::jsonb;

    -- 1. Base fee (pre-multiplier)
    v_components := v_components || jsonb_build_object(
      'name', 'base_fee',
      'amount', v_base_fee,
      'description', format('Zone %s fee', v_zone)
    );

    -- 2. Demand multiplier adjustment (only if peak hour)
    IF v_is_peak_hour AND v_demand_multiplier != 1.0 THEN
      v_components := v_components || jsonb_build_object(
        'name', 'demand_multiplier',
        'amount', round((v_base_fee * (v_demand_multiplier - 1))::numeric, 2),
        'description', format('Peak demand adjustment (%.0f%%)', v_demand_multiplier * 100)
      );
    END IF;

    -- 3. Weather surcharge
    IF v_weather_surcharge > 0 THEN
      v_components := v_components || jsonb_build_object(
        'name', 'weather_surcharge',
        'amount', v_weather_surcharge,
        'description', 'Weather surcharge'
      );
    END IF;

    -- 4. Rounding adjustment
    IF v_fee != v_pre_rounding_fee THEN
      v_components := v_components || jsonb_build_object(
        'name', 'rounding_adjustment',
        'amount', round((v_fee - v_pre_rounding_fee)::numeric, 2),
        'description', format('Fee rounding (%s)', v_config->>'pricing.fee_rounding'),
        'is_adjustment', true
      );
    END IF;

    -- 5. Min fee adjustment
    IF v_fee != v_pre_minmax_fee AND v_fee = (v_config->>'pricing.min_fee')::numeric AND v_pre_minmax_fee < (v_config->>'pricing.min_fee')::numeric THEN
      v_components := v_components || jsonb_build_object(
        'name', 'min_fee_adjustment',
        'amount', round(((v_config->>'pricing.min_fee')::numeric - v_pre_minmax_fee)::numeric, 2),
        'description', format('Minimum fee adjustment ($%s minimum)', v_config->>'pricing.min_fee'),
        'is_adjustment', true
      );
    END IF;

    -- 6. Max fee adjustment
    IF v_fee != v_pre_minmax_fee AND v_fee = (v_config->>'pricing.max_fee')::numeric AND v_pre_minmax_fee > (v_config->>'pricing.max_fee')::numeric THEN
      v_components := v_components || jsonb_build_object(
        'name', 'max_fee_adjustment',
        'amount', round(((v_config->>'pricing.max_fee')::numeric - v_pre_minmax_fee)::numeric, 2),
        'description', format('Maximum fee adjustment ($%s maximum)', v_config->>'pricing.max_fee'),
        'is_adjustment', true
      );
    END IF;

  ELSIF v_strategy = 'distance_time_v1' THEN
    -- Distance-time pricing
    v_zone := 1; -- Not used in distance-time

    v_fee := (v_config->>'pricing.distance_time.base_fee')::numeric
      + p_distance_miles * (v_config->>'pricing.distance_time.per_mile')::numeric
      + COALESCE(p_estimated_duration_minutes, 0) * (v_config->>'pricing.distance_time.per_minute')::numeric;

    v_pre_multiplier_fee := v_fee;

    -- Apply demand multiplier if peak hour
    IF v_is_peak_hour THEN
      v_demand_multiplier := (v_config->'pricing.demand_multiplier'->>'min')::numeric;
      v_fee := v_fee * v_demand_multiplier;
    ELSE
      v_demand_multiplier := 1.0;
    END IF;

    -- Add weather surcharge
    v_fee := v_fee + v_weather_surcharge;
    v_pre_rounding_fee := v_fee;

    -- Note: distance_time_v1 doesn't have fee_rounding in current config, but apply if present
    IF v_config ? 'pricing.fee_rounding' THEN
      v_fee := CASE (v_config->>'pricing.fee_rounding')
        WHEN 'ceil_0.25' THEN ceil(v_fee * 4) / 4
        WHEN 'ceil_0.50' THEN ceil(v_fee * 2) / 2
        WHEN 'round' THEN round(v_fee * 100) / 100
        ELSE v_fee
      END;
    END IF;

    v_pre_minmax_fee := v_fee;

    -- Apply min fee
    v_fee := GREATEST(v_fee, (v_config->>'pricing.distance_time.min_fee')::numeric);

    -- Calculate driver payout
    v_driver_payout := v_fee * (v_config->>'pay.payout_pct_or_per_mile')::numeric;
    v_driver_payout := GREATEST(v_driver_payout, (v_config->>'pay.min_payout')::numeric);
    v_platform_cut := v_fee - v_driver_payout;

    -- Build components for distance-time
    v_components := '[]'::jsonb;

    v_components := v_components || jsonb_build_object(
      'name', 'base_fee',
      'amount', (v_config->>'pricing.distance_time.base_fee')::numeric,
      'description', 'Base fee'
    );

    v_components := v_components || jsonb_build_object(
      'name', 'per_mile',
      'amount', round((p_distance_miles * (v_config->>'pricing.distance_time.per_mile')::numeric)::numeric, 2),
      'description', format('%.1f miles @ $%s/mile', p_distance_miles, v_config->>'pricing.distance_time.per_mile')
    );

    v_components := v_components || jsonb_build_object(
      'name', 'per_minute',
      'amount', round((COALESCE(p_estimated_duration_minutes, 0) * (v_config->>'pricing.distance_time.per_minute')::numeric)::numeric, 2),
      'description', format('%s minutes @ $%s/min', COALESCE(p_estimated_duration_minutes, 0), v_config->>'pricing.distance_time.per_minute')
    );

    -- Demand multiplier
    IF v_is_peak_hour AND v_demand_multiplier != 1.0 THEN
      v_components := v_components || jsonb_build_object(
        'name', 'demand_multiplier',
        'amount', round((v_pre_multiplier_fee * (v_demand_multiplier - 1))::numeric, 2),
        'description', format('Peak demand adjustment (%.0f%%)', v_demand_multiplier * 100)
      );
    END IF;

    -- Weather surcharge
    IF v_weather_surcharge > 0 THEN
      v_components := v_components || jsonb_build_object(
        'name', 'weather_surcharge',
        'amount', v_weather_surcharge,
        'description', 'Weather surcharge'
      );
    END IF;

    -- Rounding adjustment
    IF v_fee != v_pre_rounding_fee THEN
      v_components := v_components || jsonb_build_object(
        'name', 'rounding_adjustment',
        'amount', round((v_fee - v_pre_rounding_fee)::numeric, 2),
        'description', format('Fee rounding (%s)', v_config->>'pricing.fee_rounding'),
        'is_adjustment', true
      );
    END IF;

    -- Min fee adjustment
    IF v_fee != v_pre_minmax_fee AND v_fee = (v_config->>'pricing.distance_time.min_fee')::numeric AND v_pre_minmax_fee < (v_config->>'pricing.distance_time.min_fee')::numeric THEN
      v_components := v_components || jsonb_build_object(
        'name', 'min_fee_adjustment',
        'amount', round(((v_config->>'pricing.distance_time.min_fee')::numeric - v_pre_minmax_fee)::numeric, 2),
        'description', format('Minimum fee adjustment ($%s minimum)', v_config->>'pricing.distance_time.min_fee'),
        'is_adjustment', true
      );
    END IF;

  ELSE
    RETURN QUERY SELECT false, 'unknown_pricing_strategy', NULL::uuid, NULL::timestamptz, NULL::jsonb;
    RETURN;
  END IF;

  -- Get config snapshot ID if not provided
  IF p_config_snapshot_id IS NULL THEN
    SELECT id INTO v_snapshot_id FROM public.config_snapshots
    WHERE hash = encode(sha256(v_config::text::bytea), 'hex')
    LIMIT 1;
  ELSE
    v_snapshot_id := p_config_snapshot_id;
  END IF;

  -- Create quote (expires in 15 minutes)
  INSERT INTO public.quotes (
    customer_id, partner_id,
    pickup_lat, pickup_lng, dropoff_lat, dropoff_lng,
    distance_miles, estimated_duration_minutes, zone_assigned,
    customer_total, components, platform_cut, driver_payout,
    pricing_algorithm_version, config_snapshot_id,
    status, expires_at
  )
  SELECT
    p_customer_id, p_partner_id,
    p_pickup_lat, p_pickup_lng, p_dropoff_lat, p_dropoff_lng,
    p_distance_miles, p_estimated_duration_minutes, v_zone,
    v_fee, v_components, v_platform_cut, v_driver_payout,
    av.id, v_snapshot_id,
    'generated', now() + interval '15 minutes'
  FROM public.algorithm_versions av
  WHERE av.kind = 'pricing' AND av.name = v_strategy AND av.status = 'active'
  LIMIT 1
  RETURNING id INTO v_quote_id;

  -- If no algorithm version found, use first active
  IF v_quote_id IS NULL THEN
    INSERT INTO public.quotes (
      customer_id, partner_id,
      pickup_lat, pickup_lng, dropoff_lat, dropoff_lng,
      distance_miles, estimated_duration_minutes, zone_assigned,
      customer_total, components, platform_cut, driver_payout,
      pricing_algorithm_version, config_snapshot_id,
      status, expires_at
    )
    SELECT
      p_customer_id, p_partner_id,
      p_pickup_lat, p_pickup_lng, p_dropoff_lat, p_dropoff_lng,
      p_distance_miles, p_estimated_duration_minutes, v_zone,
      v_fee, v_components, v_platform_cut, v_driver_payout,
      av.id, v_snapshot_id,
      'generated', now() + interval '15 minutes'
    FROM public.algorithm_versions av
    WHERE av.kind = 'pricing' AND av.status = 'active'
    ORDER BY av.created_at
    LIMIT 1
    RETURNING id INTO v_quote_id;
  END IF;

  RETURN QUERY SELECT true, NULL::text, v_quote_id, now() + interval '15 minutes',
    jsonb_build_object(
      'customer_total', v_fee,
      'components', v_components,
      'platform_cut', v_platform_cut,
      'driver_payout', v_driver_payout,
      'zone', v_zone,
      'distance_miles', p_distance_miles,
      'strategy', v_strategy,
      'is_peak_hour', v_is_peak_hour,
      'demand_multiplier', v_demand_multiplier
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_quote(
  uuid, uuid, text, text, double precision, double precision,
  text, double precision, double precision, double precision, integer,
  text, uuid
) TO service_role;
REVOKE EXECUTE ON FUNCTION public.get_quote(
  uuid, uuid, text, text, double precision, double precision,
  text, double precision, double precision, double precision, integer,
  text, uuid
) FROM anon, authenticated;

-- ============================================================================
-- End of migration
-- ============================================================================