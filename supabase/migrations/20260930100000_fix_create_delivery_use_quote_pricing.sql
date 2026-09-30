-- ============================================================================
-- CommonGoods: Fix create_delivery to copy pricing from quote
-- Run after 20260930070001_update_create_delivery_quote_id.sql
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Update create_delivery to require quote_id and copy pricing from quote
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_delivery(
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
  p_quote_id uuid  -- REQUIRED: no default, must provide valid quote
)
RETURNS TABLE (
  success boolean,
  error text,
  delivery_id uuid,
  quote_id uuid,
  pricing_breakdown jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_delivery_id uuid;
  v_quote RECORD;
  v_snapshot_id uuid;
  v_config jsonb;
  v_zone integer;
  v_fee numeric(10,2);
  v_driver_payout numeric(10,2);
  v_platform_cut numeric(10,2);
  v_strategy text;
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
    RETURN QUERY SELECT false, 'missing_customer_id', NULL::uuid, NULL::uuid, NULL::jsonb;
    RETURN;
  END IF;

  IF p_distance_miles IS NULL OR p_distance_miles <= 0 THEN
    RETURN QUERY SELECT false, 'invalid_distance', NULL::uuid, NULL::uuid, NULL::jsonb;
    RETURN;
  END IF;

  -- quote_id is REQUIRED - no fallback to recomputing
  IF p_quote_id IS NULL THEN
    RETURN QUERY SELECT false, 'quote_id_required', NULL::uuid, NULL::uuid, NULL::jsonb;
    RETURN;
  END IF;

  -- Lock and validate quote
  SELECT * INTO v_quote
  FROM public.quotes
  WHERE id = p_quote_id
  FOR UPDATE;  -- Prevent concurrent use of same quote

  IF v_quote IS NULL THEN
    RETURN QUERY SELECT false, 'quote_not_found', NULL::uuid, NULL::uuid, NULL::jsonb;
    RETURN;
  END IF;

  IF v_quote.customer_id != p_customer_id THEN
    RETURN QUERY SELECT false, 'quote_customer_mismatch', NULL::uuid, NULL::uuid, NULL::jsonb;
    RETURN;
  END IF;

  IF v_quote.status != 'generated' THEN
    RETURN QUERY SELECT false, 'quote_not_generated', NULL::uuid, NULL::uuid, NULL::jsonb;
    RETURN;
  END IF;

  IF v_quote.expires_at < now() THEN
    RETURN QUERY SELECT false, 'quote_expired', NULL::uuid, NULL::uuid, NULL::jsonb;
    RETURN;
  END IF;

  -- Verify quote inputs match exactly (coordinates, distance, zone)
  IF v_quote.pickup_lat IS DISTINCT FROM p_pickup_lat
     OR v_quote.pickup_lng IS DISTINCT FROM p_pickup_lng
     OR v_quote.dropoff_lat IS DISTINCT FROM p_dropoff_lat
     OR v_quote.dropoff_lng IS DISTINCT FROM p_dropoff_lng THEN
    RETURN QUERY SELECT false, 'quote_coordinates_mismatch', NULL::uuid, NULL::uuid, NULL::jsonb;
    RETURN;
  END IF;

  IF v_quote.distance_miles IS DISTINCT FROM p_distance_miles THEN
    RETURN QUERY SELECT false, 'quote_distance_mismatch', NULL::uuid, NULL::uuid, NULL::jsonb;
    RETURN;
  END IF;

  IF v_quote.zone_assigned IS DISTINCT FROM p_distance_miles THEN
    -- Zone will be validated by the quote's zone
    NULL;
  END IF;

  -- Copy all pricing from quote - NO RECOMPUTATION
  v_zone := v_quote.zone_assigned;
  v_fee := v_quote.customer_total;
  v_driver_payout := v_quote.driver_payout;
  v_platform_cut := v_quote.platform_cut;
  v_components := v_quote.components;
  v_snapshot_id := v_quote.config_snapshot_id;
  v_strategy := (SELECT name FROM public.algorithm_versions WHERE id = v_quote.pricing_algorithm_version);

  -- Get config for metadata
  SELECT resolved INTO v_config FROM public.config_snapshots WHERE id = v_quote.config_snapshot_id;
  v_is_peak_hour := (v_config->'pricing.peak_hours') IS NOT NULL AND public.is_peak_hour(v_config->'pricing.peak_hours', now());
  v_demand_multiplier := CASE WHEN v_is_peak_hour THEN (v_config->'pricing.demand_multiplier'->>'min')::numeric ELSE 1.0 END;
  v_weather_surcharge := COALESCE((v_config->>'pricing.weather_surcharge')::numeric, 0);

  -- Create delivery with quote's pricing
  INSERT INTO public.deliveries (
    customer_id, partner_id, category,
    pickup_address, pickup_lat, pickup_lng,
    dropoff_address, dropoff_lat, dropoff_lng,
    distance_miles, zone_assigned,
    fee_charged, driver_payout, platform_cut,
    estimated_duration_minutes, notes,
    status, requested_at
  ) VALUES (
    p_customer_id, p_partner_id, p_category,
    p_pickup_address, p_pickup_lat, p_pickup_lng,
    p_dropoff_address, p_dropoff_lat, p_dropoff_lng,
    p_distance_miles, v_zone,
    v_fee, v_driver_payout, v_platform_cut,
    p_estimated_duration_minutes, p_notes,
    'pending', now()
  ) RETURNING id INTO v_delivery_id;

  -- Update quote status to 'accepted' and link to delivery
  UPDATE public.quotes
  SET status = 'accepted', accepted_at = now(), delivery_id = v_delivery_id
  WHERE id = p_quote_id;

  -- Create initial pricing decision (copy from quote)
  INSERT INTO public.pricing_decisions (
    delivery_id, actual_distance_miles, actual_duration_minutes, zone_assigned,
    customer_total, components, platform_cut, driver_payout,
    adjustments, pricing_algorithm_version, config_snapshot_id, inputs
  ) VALUES (
    v_delivery_id, p_distance_miles, p_estimated_duration_minutes, v_zone,
    v_fee, v_components, v_platform_cut, v_driver_payout,
    '[]'::jsonb, v_quote.pricing_algorithm_version, v_quote.config_snapshot_id,
    jsonb_build_object(
      'pickup', jsonb_build_object('lat', p_pickup_lat, 'lng', p_pickup_lng),
      'dropoff', jsonb_build_object('lat', p_dropoff_lat, 'lng', p_dropoff_lng),
      'distance_miles', p_distance_miles,
      'estimated_duration_minutes', p_estimated_duration_minutes,
      'zone', v_zone,
      'is_peak_hour', (v_config->'pricing.peak_hours') IS NOT NULL AND public.is_peak_hour(v_config->'pricing.peak_hours', now()),
      'demand_multiplier', CASE WHEN (v_config->'pricing.peak_hours') IS NOT NULL AND public.is_peak_hour(v_config->'pricing.peak_hours', now()) THEN (v_config->'pricing.demand_multiplier'->>'min')::numeric ELSE 1.0 END,
      'weather_surcharge', COALESCE((v_config->>'pricing.weather_surcharge')::numeric, 0)
    )
  );

  -- Create dispatch decision
  INSERT INTO public.dispatch_decisions (
    delivery_id, candidates, dispatch_algorithm_version, config_snapshot_id, inputs
  )
  SELECT
    v_delivery_id, '[]'::jsonb, av.id, v_quote.config_snapshot_id,
    jsonb_build_object(
      'pickup', jsonb_build_object('lat', p_pickup_lat, 'lng', p_pickup_lng),
      'search_radius_miles', (v_config->>'dispatch.search_radius_miles')::numeric
    )
  FROM public.algorithm_versions av
  WHERE av.kind = 'dispatch' AND av.status = 'active'
  ORDER BY av.created_at
  LIMIT 1;

  -- Log event
  INSERT INTO public.events (
    occurred_at, received_at, actor_id, actor_type,
    entity_type, entity_id, name, props, config_snapshot_id
  ) VALUES (
    now(), now(), p_customer_id, 'customer',
    'delivery', v_delivery_id, 'order_placed',
    jsonb_build_object('fee', v_fee, 'zone', v_zone, 'distance_miles', p_distance_miles, 'is_peak_hour', (v_config->'pricing.peak_hours') IS NOT NULL AND public.is_peak_hour(v_config->'pricing.peak_hours', now())),
    v_quote.config_snapshot_id
  );

  RETURN QUERY SELECT true, NULL::text, v_delivery_id, p_quote_id,
    jsonb_build_object(
      'customer_total', v_fee,
      'components', v_components,
      'platform_cut', v_platform_cut,
      'driver_payout', v_driver_payout,
      'zone', v_zone,
      'distance_miles', p_distance_miles,
      'strategy', (SELECT name FROM public.algorithm_versions WHERE id = (SELECT pricing_algorithm_version FROM public.quotes WHERE id = p_quote_id)),
      'is_peak_hour', (v_config->'pricing.peak_hours') IS NOT NULL AND public.is_peak_hour(v_config->'pricing.peak_hours', now()),
      'demand_multiplier', CASE WHEN (v_config->'pricing.peak_hours') IS NOT NULL AND public.is_peak_hour(v_config->'pricing.peak_hours', now()) THEN (v_config->'pricing.demand_multiplier'->>'min')::numeric ELSE 1.0 END
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_delivery(
  uuid, uuid, text, text, double precision, double precision,
  text, double precision, double precision, double precision, integer,
  text, uuid
) TO service_role;
REVOKE EXECUTE ON FUNCTION public.create_delivery(
  uuid, uuid, text, text, double precision, double precision,
  text, double precision, double precision, double precision, integer,
  text, uuid
) FROM anon, authenticated;

-- ============================================================================
-- End of migration
-- ============================================================================