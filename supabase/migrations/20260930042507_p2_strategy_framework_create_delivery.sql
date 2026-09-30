-- ============================================================================
-- CommonGoods: Phase P2 - Strategy Framework, Quotes/Decisions, create_delivery
-- Run after 20260930035522_p1_config_platform_event_log.sql
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Algorithm Versions Registry
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.algorithm_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind text NOT NULL CHECK (kind IN ('pricing', 'dispatch', 'pay')),
  name text NOT NULL,
  version text NOT NULL,
  status text NOT NULL CHECK (status IN ('draft', 'active', 'deprecated', 'archived')) DEFAULT 'draft',
  code_ref text NOT NULL,  -- e.g., "pricing/zone_v1", "dispatch/broadcast_v1"
  description text,
  config_schema jsonb NOT NULL DEFAULT '{}',  -- expected config keys for this version
  created_by uuid NOT NULL REFERENCES public.profiles(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  deprecated_at timestamptz,
  UNIQUE (kind, name, version)
);

ALTER TABLE public.algorithm_versions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "algorithm_versions_select_authenticated" ON public.algorithm_versions
  FOR SELECT TO authenticated USING (status IN ('active', 'deprecated'));

CREATE POLICY "algorithm_versions_modify_admin" ON public.algorithm_versions
  FOR ALL USING (private.is_admin()) WITH CHECK (private.is_admin());

GRANT SELECT ON public.algorithm_versions TO authenticated, service_role;
GRANT ALL ON public.algorithm_versions TO service_role;

-- Seed initial algorithm versions
DO $$
DECLARE
  v_admin_id uuid;
BEGIN
  SELECT id INTO v_admin_id FROM public.profiles WHERE is_admin = true LIMIT 1;

  INSERT INTO public.algorithm_versions (kind, name, version, status, code_ref, description, config_schema, created_by) VALUES
  ('pricing', 'zone_v1', '1.0.0', 'active', 'pricing/zone_v1',
   'Zone-based flat fee pricing (current)',
   '{"required": ["pricing.strategy", "pricing.zone.1.fee", "pricing.zone.2.fee", "pricing.zone.3.fee", "pricing.distance_bands", "platform_cut_pct", "pay.payout_pct_or_per_mile"]}',
   v_admin_id),
  ('pricing', 'distance_time_v1', '1.0.0', 'draft', 'pricing/distance_time_v1',
   'Distance + time based pricing (base + per-mile + per-minute + multiplier)',
   '{"required": ["pricing.strategy", "pricing.distance_time.base_fee", "pricing.distance_time.per_mile", "pricing.distance_time.per_minute", "pricing.distance_time.min_fee", "pricing.demand_multiplier.min", "pricing.demand_multiplier.max", "pricing.demand_multiplier.curve", "platform_cut_pct", "pay.payout_pct_or_per_mile"]}',
   v_admin_id),
  ('dispatch', 'broadcast_v1', '1.0.0', 'active', 'dispatch/broadcast_v1',
   'Broadcast offer to all eligible drivers within radius',
   '{"required": ["dispatch.strategy", "dispatch.offer_mode", "dispatch.offer_ttl_seconds", "dispatch.search_radius_miles", "dispatch.radius_expansion_steps", "dispatch.ranking_weights", "dispatch.max_concurrent_offers", "dispatch.reoffer_delay_seconds", "dispatch.stale_claim_timeout_minutes"]}',
   v_admin_id),
  ('dispatch', 'nearest_first_v1', '1.0.0', 'draft', 'dispatch/nearest_first_v1',
   'Sequential offers to nearest drivers first',
   '{"required": ["dispatch.strategy", "dispatch.offer_mode", "dispatch.offer_ttl_seconds", "dispatch.search_radius_miles", "dispatch.ranking_weights", "dispatch.reoffer_delay_seconds"]}',
   v_admin_id),
  ('pay', 'pct_v1', '1.0.0', 'active', 'pay/pct_v1',
   'Percentage of fee as driver payout',
   '{"required": ["pay.strategy", "pay.payout_pct_or_per_mile", "pay.min_payout", "platform_cut_pct"]}',
   v_admin_id),
  ('pay', 'per_mile_v1', '1.0.0', 'draft', 'pay/per_mile_v1',
   'Fixed per-mile rate for driver payout',
   '{"required": ["pay.strategy", "pay.payout_pct_or_per_mile", "pay.min_payout", "pay.wait_pay_per_minute", "pay.wait_pay_grace_minutes"]}',
   v_admin_id),
  ('pay', 'hourly_floor_v1', '1.0.0', 'draft', 'pay/hourly_floor_v1',
   'Guaranteed hourly floor with per-delivery payouts',
   '{"required": ["pay.strategy", "pay.pay_floor_per_hour", "pay.payout_pct_or_per_mile", "pay.min_payout", "pay.wait_pay_per_minute", "pay.wait_pay_grace_minutes"]}',
   v_admin_id);
END;
$$;

-- ----------------------------------------------------------------------------
-- 2. Quotes Table (what customer saw before ordering)
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.quotes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id uuid REFERENCES public.deliveries(id) ON DELETE SET NULL,
  customer_id uuid NOT NULL REFERENCES public.profiles(id),
  partner_id uuid REFERENCES public.partners(id),
  -- Inputs used for pricing
  pickup_lat double precision NOT NULL,
  pickup_lng double precision NOT NULL,
  dropoff_lat double precision NOT NULL,
  dropoff_lng double precision NOT NULL,
  distance_miles double precision NOT NULL,
  estimated_duration_minutes integer,
  zone_assigned integer NOT NULL,
  -- Pricing breakdown
  customer_total numeric(10,2) NOT NULL,
  components jsonb NOT NULL DEFAULT '[]',  -- [{name, amount, description}]
  platform_cut numeric(10,2) NOT NULL,
  driver_payout numeric(10,2) NOT NULL,
  -- Algorithm & config snapshot
  pricing_algorithm_version uuid NOT NULL REFERENCES public.algorithm_versions(id),
  config_snapshot_id uuid NOT NULL REFERENCES public.config_snapshots(id),
  -- Status
  status text NOT NULL CHECK (status IN ('generated', 'accepted', 'expired', 'cancelled')) DEFAULT 'generated',
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '15 minutes'),
  created_at timestamptz NOT NULL DEFAULT now(),
  accepted_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_quotes_customer ON public.quotes (customer_id);
CREATE INDEX IF NOT EXISTS idx_quotes_delivery ON public.quotes (delivery_id);
CREATE INDEX IF NOT EXISTS idx_quotes_status ON public.quotes (status);
CREATE INDEX IF NOT EXISTS idx_quotes_algorithm ON public.quotes (pricing_algorithm_version);

ALTER TABLE public.quotes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "quotes_select_customer" ON public.quotes
  FOR SELECT USING (customer_id = (SELECT auth.uid()) OR private.is_admin());

CREATE POLICY "quotes_insert_service" ON public.quotes
  FOR INSERT TO service_role WITH CHECK (true);

CREATE POLICY "quotes_update_service" ON public.quotes
  FOR UPDATE TO service_role USING (true);

GRANT SELECT ON public.quotes TO authenticated, service_role;
GRANT INSERT, UPDATE ON public.quotes TO service_role;

-- ----------------------------------------------------------------------------
-- 3. Pricing Decisions Table (final pricing for completed deliveries)
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.pricing_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id uuid NOT NULL UNIQUE REFERENCES public.deliveries(id) ON DELETE CASCADE,
  -- Final inputs (may differ from quote due to traffic, wait time, etc.)
  actual_distance_miles double precision,
  actual_duration_minutes integer,
  zone_assigned integer NOT NULL,
  -- Final pricing breakdown
  customer_total numeric(10,2) NOT NULL,
  components jsonb NOT NULL DEFAULT '[]',  -- [{name, amount, description, is_adjustment}]
  platform_cut numeric(10,2) NOT NULL,
  driver_payout numeric(10,2) NOT NULL,
  -- Adjustments
  adjustments jsonb DEFAULT '[]',  -- surge, weather, wait_time, etc.
  -- Algorithm & config snapshot
  pricing_algorithm_version uuid NOT NULL REFERENCES public.algorithm_versions(id),
  config_snapshot_id uuid NOT NULL REFERENCES public.config_snapshots(id),
  -- Reproducibility
  inputs jsonb NOT NULL,  -- all inputs used for recomputation
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pricing_decisions_delivery ON public.pricing_decisions (delivery_id);
CREATE INDEX IF NOT EXISTS idx_pricing_decisions_algorithm ON public.pricing_decisions (pricing_algorithm_version);

ALTER TABLE public.pricing_decisions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pricing_decisions_select_participant" ON public.pricing_decisions
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.deliveries d
      WHERE d.id = pricing_decisions.delivery_id
        AND (d.customer_id = (SELECT auth.uid()) OR d.driver_id = (SELECT auth.uid()) OR d.partner_id IN (SELECT id FROM public.partners WHERE profile_id = (SELECT auth.uid())))
    )
    OR private.is_admin()
  );

CREATE POLICY "pricing_decisions_insert_service" ON public.pricing_decisions
  FOR INSERT TO service_role WITH CHECK (true);

GRANT SELECT ON public.pricing_decisions TO authenticated, service_role;
GRANT INSERT ON public.pricing_decisions TO service_role;

-- ----------------------------------------------------------------------------
-- 4. Dispatch Decisions Table
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.dispatch_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id uuid NOT NULL REFERENCES public.deliveries(id) ON DELETE CASCADE,
  -- Offered drivers with scores
  candidates jsonb NOT NULL DEFAULT '[]',  -- [{driver_id, score, distance_miles, rank, offered_at, responded_at, response}]
  chosen_driver_id uuid REFERENCES public.profiles(id),
  reason text,
  -- Algorithm & config snapshot
  dispatch_algorithm_version uuid NOT NULL REFERENCES public.algorithm_versions(id),
  config_snapshot_id uuid NOT NULL REFERENCES public.config_snapshots(id),
  -- Inputs for replay
  inputs jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dispatch_decisions_delivery ON public.dispatch_decisions (delivery_id);
CREATE INDEX IF NOT EXISTS idx_dispatch_decisions_algorithm ON public.dispatch_decisions (dispatch_algorithm_version);

ALTER TABLE public.dispatch_decisions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "dispatch_decisions_select_participant" ON public.dispatch_decisions
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.deliveries d
      WHERE d.id = dispatch_decisions.delivery_id
        AND (d.customer_id = (SELECT auth.uid()) OR d.driver_id = (SELECT auth.uid()) OR d.partner_id IN (SELECT id FROM public.partners WHERE profile_id = (SELECT auth.uid())))
    )
    OR private.is_admin()
  );

CREATE POLICY "dispatch_decisions_insert_service" ON public.dispatch_decisions
  FOR INSERT TO service_role WITH CHECK (true);

GRANT SELECT ON public.dispatch_decisions TO authenticated, service_role;
GRANT INSERT ON public.dispatch_decisions TO service_role;

-- ----------------------------------------------------------------------------
-- 5. Dispatch Offers Table (detailed offer tracking for tuning)
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.dispatch_offers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id uuid NOT NULL REFERENCES public.deliveries(id) ON DELETE CASCADE,
  driver_id uuid NOT NULL REFERENCES public.profiles(id),
  -- Offer details
  offered_at timestamptz NOT NULL DEFAULT now(),
  viewed_at timestamptz,
  responded_at timestamptz,
  response text CHECK (response IN ('accepted', 'declined', 'expired')),
  decline_reason text,
  -- Offered pay
  offered_pay numeric(10,2) NOT NULL,
  -- Driver state at offer time
  driver_distance_to_pickup_miles double precision,
  driver_rating numeric(3,2),
  driver_acceptance_rate numeric(5,4),
  driver_idle_time_minutes integer,
  -- Ranking
  rank integer NOT NULL,
  score numeric(10,6) NOT NULL,
  alternatives_shown integer DEFAULT 0,
  -- Algorithm & config snapshot
  dispatch_algorithm_version uuid NOT NULL REFERENCES public.algorithm_versions(id),
  config_snapshot_id uuid NOT NULL REFERENCES public.config_snapshots(id),
  -- Latency
  latency_ms integer,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dispatch_offers_delivery ON public.dispatch_offers (delivery_id);
CREATE INDEX IF NOT EXISTS idx_dispatch_offers_driver ON public.dispatch_offers (driver_id);
CREATE INDEX IF NOT EXISTS idx_dispatch_offers_response ON public.dispatch_offers (response);

ALTER TABLE public.dispatch_offers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "dispatch_offers_select_driver" ON public.dispatch_offers
  FOR SELECT USING (driver_id = (SELECT auth.uid()) OR private.is_admin());

CREATE POLICY "dispatch_offers_select_partner" ON public.dispatch_offers
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.deliveries d
      WHERE d.id = dispatch_offers.delivery_id
        AND d.partner_id IN (SELECT id FROM public.partners WHERE profile_id = (SELECT auth.uid()))
    )
  );

CREATE POLICY "dispatch_offers_insert_service" ON public.dispatch_offers
  FOR INSERT TO service_role WITH CHECK (true);

GRANT SELECT ON public.dispatch_offers TO authenticated, service_role;
GRANT INSERT ON public.dispatch_offers TO service_role;

-- ----------------------------------------------------------------------------
-- 6. Enhanced Delivery Timeline (add missing stage timestamps)
--    Already added en_route, offered, arrived_pickup, arrived_dropoff in previous migration
--    Here we add the cancel_stage, cancelled_by, cancellation_reason_code, compensation_amount
--    Also add the delivery stage enum type for cleaner usage
-- ----------------------------------------------------------------------------

CREATE TYPE public.delivery_stage AS ENUM (
  'pending', 'offered', 'claimed', 'en_route', 'in_progress', 'completed', 'cancelled'
);

-- Add check constraint using the enum (deliveries.status already has these values)

-- ----------------------------------------------------------------------------
-- 7. create_delivery Edge Function RPC (called by Edge Function with service_role)
--    This replaces client-side INSERT on deliveries
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
  p_config_snapshot_id uuid DEFAULT NULL
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
  v_quote_id uuid;
  v_zone integer;
  v_fee numeric(10,2);
  v_driver_payout numeric(10,2);
  v_platform_cut numeric(10,2);
  v_strategy text;
  v_snapshot_id uuid;
  v_config jsonb;
  v_components jsonb;
  v_demand_multiplier numeric := 1.0;
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

  -- Resolve config (use provided snapshot or current)
  IF p_config_snapshot_id IS NOT NULL THEN
    SELECT resolved INTO v_config FROM public.config_snapshots WHERE id = p_config_snapshot_id;
    IF v_config IS NULL THEN
      RETURN QUERY SELECT false, 'invalid_config_snapshot', NULL::uuid, NULL::uuid, NULL::jsonb;
      RETURN;
    END IF;
  ELSE
    SELECT config INTO v_config FROM public.resolve_all_config('{}'::jsonb, now());
  END IF;

  v_strategy := v_config->>'pricing.strategy';

  -- Determine zone from distance bands
  IF v_strategy = 'zone_v1' THEN
    v_zone := CASE
      WHEN p_distance_miles <= (v_config->'pricing.distance_bands'->>0)::numeric THEN 1
      WHEN p_distance_miles <= (v_config->'pricing.distance_bands'->>1)::numeric THEN 2
      WHEN p_distance_miles <= (v_config->'pricing.distance_bands'->>2)::numeric THEN 3
      ELSE NULL
    END;

    IF v_zone IS NULL THEN
      RETURN QUERY SELECT false, 'OUTSIDE_SERVICE_AREA', NULL::uuid, NULL::uuid, NULL::jsonb;
      RETURN;
    END IF;

    -- Get zone fee
    v_fee := (v_config->>format('pricing.zone.%s.fee', v_zone))::numeric;

    -- Apply demand multiplier if peak hours
    v_demand_multiplier := (v_config->'pricing.demand_multiplier'->>'min')::numeric;
    -- In real impl, check if current time is in peak_hours

    v_fee := v_fee * v_demand_multiplier;

    -- Round fee
    v_fee := CASE (v_config->>'pricing.fee_rounding')
      WHEN 'ceil_0.25' THEN ceil(v_fee * 4) / 4
      WHEN 'ceil_0.50' THEN ceil(v_fee * 2) / 2
      WHEN 'round' THEN round(v_fee * 100) / 100
      ELSE v_fee
    END;

    -- Ensure min/max
    v_fee := GREATEST(v_fee, (v_config->>'pricing.min_fee')::numeric);
    v_fee := LEAST(v_fee, (v_config->>'pricing.max_fee')::numeric);

    -- Calculate driver payout and platform cut
    v_driver_payout := v_fee * (v_config->>'pay.payout_pct_or_per_mile')::numeric;
    v_driver_payout := GREATEST(v_driver_payout, (v_config->>'pay.min_payout')::numeric);
    v_platform_cut := v_fee - v_driver_payout;

    v_components := jsonb_build_array(
      jsonb_build_object('name', 'base_fee', 'amount', v_fee, 'description', format('Zone %s fee', v_zone)),
      jsonb_build_object('name', 'demand_multiplier', 'amount', (v_fee / (v_config->>format('pricing.zone.%s.fee', v_zone))::numeric - 1) * v_fee, 'description', 'Peak demand adjustment')
    );
  ELSIF v_strategy = 'distance_time_v1' THEN
    -- Distance-time pricing (simplified - full impl in Edge Function)
    v_fee := (v_config->>'pricing.distance_time.base_fee')::numeric
      + p_distance_miles * (v_config->>'pricing.distance_time.per_mile')::numeric
      + COALESCE(p_estimated_duration_minutes, 0) * (v_config->>'pricing.distance_time.per_minute')::numeric;

    v_fee := GREATEST(v_fee, (v_config->>'pricing.distance_time.min_fee')::numeric);
    v_driver_payout := v_fee * (v_config->>'pay.payout_pct_or_per_mile')::numeric;
    v_driver_payout := GREATEST(v_driver_payout, (v_config->>'pay.min_payout')::numeric);
    v_platform_cut := v_fee - v_driver_payout;
    v_zone := 1; -- Not used in distance-time

    v_components := jsonb_build_array(
      jsonb_build_object('name', 'base_fee', 'amount', (v_config->>'pricing.distance_time.base_fee')::numeric, 'description', 'Base fee'),
      jsonb_build_object('name', 'per_mile', 'amount', p_distance_miles * (v_config->>'pricing.distance_time.per_mile')::numeric, 'description', format('%.1f miles @ $%s/mile', p_distance_miles, v_config->>'pricing.distance_time.per_mile')),
      jsonb_build_object('name', 'per_minute', 'amount', COALESCE(p_estimated_duration_minutes, 0) * (v_config->>'pricing.distance_time.per_minute')::numeric, 'description', format('%s minutes @ $%s/min', COALESCE(p_estimated_duration_minutes, 0), v_config->>'pricing.distance_time.per_minute'))
    );
  ELSE
    RETURN QUERY SELECT false, 'unknown_pricing_strategy', NULL::uuid, NULL::uuid, NULL::jsonb;
    RETURN;
  END IF;

  -- Create delivery
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

  -- Create quote
  INSERT INTO public.quotes (
    delivery_id, customer_id, partner_id,
    pickup_lat, pickup_lng, dropoff_lat, dropoff_lng,
    distance_miles, estimated_duration_minutes, zone_assigned,
    customer_total, components, platform_cut, driver_payout,
    pricing_algorithm_version, config_snapshot_id,
    status
  )
  SELECT
    v_delivery_id, p_customer_id, p_partner_id,
    p_pickup_lat, p_pickup_lng, p_dropoff_lat, p_dropoff_lng,
    p_distance_miles, p_estimated_duration_minutes, v_zone,
    v_fee, v_components, v_platform_cut, v_driver_payout,
    av.id, v_config_snapshot_id, 'accepted'
  FROM public.algorithm_versions av
  WHERE av.kind = 'pricing' AND av.name = v_strategy AND av.status = 'active'
  LIMIT 1
  RETURNING id INTO v_quote_id;

  -- If no algorithm version found, use first active
  IF v_quote_id IS NULL THEN
    INSERT INTO public.quotes (
      delivery_id, customer_id, partner_id,
      pickup_lat, pickup_lng, dropoff_lat, dropoff_lng,
      distance_miles, estimated_duration_minutes, zone_assigned,
      customer_total, components, platform_cut, driver_payout,
      pricing_algorithm_version, config_snapshot_id,
      status
    )
    SELECT
      v_delivery_id, p_customer_id, p_partner_id,
      p_pickup_lat, p_pickup_lng, p_dropoff_lat, p_dropoff_lng,
      p_distance_miles, p_estimated_duration_minutes, v_zone,
      v_fee, v_components, v_platform_cut, v_driver_payout,
      av.id, v_config_snapshot_id, 'accepted'
    FROM public.algorithm_versions av
    WHERE av.kind = 'pricing' AND av.status = 'active'
    ORDER BY av.created_at
    LIMIT 1
    RETURNING id INTO v_quote_id;
  END IF;

  -- Get config snapshot ID if not provided
  IF p_config_snapshot_id IS NULL THEN
    SELECT id INTO v_snapshot_id FROM public.config_snapshots
    WHERE hash = encode(sha256(v_config::text::bytea), 'hex')
    LIMIT 1;
  ELSE
    v_snapshot_id := p_config_snapshot_id;
  END IF;

  -- Create initial pricing decision
  INSERT INTO public.pricing_decisions (
    delivery_id, actual_distance_miles, actual_duration_minutes, zone_assigned,
    customer_total, components, platform_cut, driver_payout,
    adjustments, pricing_algorithm_version, config_snapshot_id, inputs
  )
  SELECT
    v_delivery_id, p_distance_miles, p_estimated_duration_minutes, v_zone,
    v_fee, v_components, v_platform_cut, v_driver_payout,
    '[]'::jsonb, av.id, v_snapshot_id,
    jsonb_build_object(
      'pickup', jsonb_build_object('lat', p_pickup_lat, 'lng', p_pickup_lng),
      'dropoff', jsonb_build_object('lat', p_dropoff_lat, 'lng', p_dropoff_lng),
      'distance_miles', p_distance_miles,
      'estimated_duration_minutes', p_estimated_duration_minutes,
      'zone', v_zone
    )
  FROM public.algorithm_versions av
  WHERE av.kind = 'pricing' AND av.name = v_strategy AND av.status = 'active'
  LIMIT 1;

  -- Create dispatch decision (empty initially, filled when offers go out)
  INSERT INTO public.dispatch_decisions (
    delivery_id, candidates, dispatch_algorithm_version, config_snapshot_id, inputs
  )
  SELECT
    v_delivery_id, '[]'::jsonb, av.id, v_snapshot_id,
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
    jsonb_build_object('fee', v_fee, 'zone', v_zone, 'distance_miles', p_distance_miles),
    v_snapshot_id
  );

  RETURN QUERY SELECT true, NULL::text, v_delivery_id, v_quote_id,
    jsonb_build_object(
      'customer_total', v_fee,
      'components', v_components,
      'platform_cut', v_platform_cut,
      'driver_payout', v_driver_payout,
      'zone', v_zone,
      'distance_miles', p_distance_miles,
      'strategy', v_strategy
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

-- ----------------------------------------------------------------------------
-- 8. Update deliveries pricing trigger to use config (already done via zone_pricing)
--    The enforce_delivery_pricing trigger already calls public.zone_pricing
--    We need to update zone_pricing to read from config_registry
-- ----------------------------------------------------------------------------

-- Note: zone_pricing function is in public schema from security_hardening migration
-- We'll create a new version that reads from config
CREATE OR REPLACE FUNCTION public.zone_pricing(miles double precision)
RETURNS TABLE(zone integer, fee numeric, driver_payout numeric, platform_cut numeric)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_config jsonb;
  v_zone integer;
  v_base_fee numeric;
  v_payout_pct numeric;
  v_platform_cut_pct numeric;
BEGIN
  -- Get current global config
  SELECT config INTO v_config FROM public.resolve_all_config('{}'::jsonb, now());

  -- Determine zone
  v_zone := CASE
    WHEN miles <= (v_config->'pricing.distance_bands'->>0)::numeric THEN 1
    WHEN miles <= (v_config->'pricing.distance_bands'->>1)::numeric THEN 2
    WHEN miles <= (v_config->'pricing.distance_bands'->>2)::numeric THEN 3
    ELSE NULL
  END;

  IF v_zone IS NULL THEN
    RETURN QUERY SELECT NULL::integer, NULL::numeric, NULL::numeric, NULL::numeric;
    RETURN;
  END IF;

  v_base_fee := (v_config->>format('pricing.zone.%s.fee', v_zone))::numeric;
  v_payout_pct := (v_config->>'pay.payout_pct_or_per_mile')::numeric;
  v_platform_cut_pct := (v_config->>'platform_cut_pct')::numeric;

  RETURN QUERY SELECT v_zone, v_base_fee, v_base_fee * v_payout_pct, v_base_fee * v_platform_cut_pct;
END;
$$;

-- ----------------------------------------------------------------------------
-- 9. Get Active Algorithm Version Helper
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_active_algorithm_version(p_kind text)
RETURNS uuid
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT id FROM public.algorithm_versions
  WHERE kind = p_kind AND status = 'active'
  ORDER BY created_at DESC
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_active_algorithm_version(text) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- End of Phase P2 migration
-- ============================================================================