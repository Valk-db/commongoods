-- ============================================================================
-- CommonGoods: Phase P1 - Config Platform, Event Log, Seed Registry
-- Run after 20260930033438_fix_outstanding_review_items.sql
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Config Platform Tables
-- ----------------------------------------------------------------------------

-- 1.1 config_registry: one row per parameter definition
CREATE TABLE IF NOT EXISTS public.config_registry (
  key text PRIMARY KEY,
  type text NOT NULL CHECK (type IN ('number', 'integer', 'boolean', 'string', 'json', 'array')),
  json_schema jsonb NOT NULL,
  unit text,
  default_value jsonb NOT NULL,
  min_value jsonb,
  max_value jsonb,
  category text NOT NULL,
  description text NOT NULL,
  risk_level text NOT NULL CHECK (risk_level IN ('low', 'medium', 'high')) DEFAULT 'low',
  requires_approval boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.config_registry ENABLE ROW LEVEL SECURITY;

CREATE POLICY "config_registry_select_authenticated" ON public.config_registry
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "config_registry_modify_admin" ON public.config_registry
  FOR ALL USING (private.is_admin()) WITH CHECK (private.is_admin());

GRANT SELECT ON public.config_registry TO authenticated, service_role;
GRANT ALL ON public.config_registry TO service_role;

-- 1.2 config_values: append-only value history with scoping
CREATE TABLE IF NOT EXISTS public.config_values (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key text NOT NULL REFERENCES public.config_registry(key) ON DELETE RESTRICT,
  scope_type text NOT NULL CHECK (scope_type IN ('global', 'zone', 'partner', 'driver', 'customer', 'cohort', 'experiment_arm')),
  scope_id uuid,
  value jsonb NOT NULL,
  effective_from timestamptz NOT NULL DEFAULT now(),
  effective_to timestamptz,
  status text NOT NULL CHECK (status IN ('draft', 'scheduled', 'active', 'superseded', 'rolled_back')) DEFAULT 'draft',
  created_by uuid NOT NULL REFERENCES public.profiles(id),
  reason text NOT NULL,
  approved_by uuid REFERENCES public.profiles(id),
  governance_proposal_id uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Indexes for resolution performance
CREATE INDEX IF NOT EXISTS idx_config_values_key ON public.config_values (key);
CREATE INDEX IF NOT EXISTS idx_config_values_scope ON public.config_values (scope_type, scope_id);
CREATE INDEX IF NOT EXISTS idx_config_values_effective ON public.config_values (effective_from, effective_to);
CREATE INDEX IF NOT EXISTS idx_config_values_status ON public.config_values (status);

ALTER TABLE public.config_values ENABLE ROW LEVEL SECURITY;

CREATE POLICY "config_values_select_authenticated" ON public.config_values
  FOR SELECT TO authenticated USING (status = 'active');

CREATE POLICY "config_values_modify_admin" ON public.config_values
  FOR ALL USING (private.is_admin()) WITH CHECK (private.is_admin());

GRANT SELECT ON public.config_values TO authenticated, service_role;
GRANT INSERT, UPDATE ON public.config_values TO service_role, authenticated;

-- 1.3 config_snapshots: deduplicated resolved config sets
CREATE TABLE IF NOT EXISTS public.config_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  hash text NOT NULL UNIQUE,
  resolved jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.config_snapshots ENABLE ROW LEVEL SECURITY;

CREATE POLICY "config_snapshots_select_authenticated" ON public.config_snapshots
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "config_snapshots_insert_service" ON public.config_snapshots
  FOR INSERT TO service_role WITH CHECK (true);

GRANT SELECT ON public.config_snapshots TO authenticated, service_role;
GRANT INSERT ON public.config_snapshots TO service_role;

-- 1.4 config_audit: trigger-written audit trail
CREATE TABLE IF NOT EXISTS public.config_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key text NOT NULL,
  scope_type text,
  scope_id uuid,
  old_value jsonb,
  new_value jsonb,
  changed_by uuid NOT NULL REFERENCES public.profiles(id),
  reason text,
  ip_address inet,
  user_agent text,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.config_audit ENABLE ROW LEVEL SECURITY;

CREATE POLICY "config_audit_select_admin" ON public.config_audit
  FOR SELECT USING (private.is_admin());

CREATE POLICY "config_audit_insert_service" ON public.config_audit
  FOR INSERT TO service_role WITH CHECK (true);

GRANT SELECT ON public.config_audit TO authenticated, service_role;
GRANT INSERT ON public.config_audit TO service_role;

-- ----------------------------------------------------------------------------
-- 2. Config Resolution Functions
-- ----------------------------------------------------------------------------

-- Core resolution: get most specific active value for a key given context
CREATE OR REPLACE FUNCTION public.resolve_config(
  p_key text,
  p_ctx jsonb DEFAULT '{}'::jsonb,
  p_at timestamptz DEFAULT now()
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_zone_id uuid;
  v_partner_id uuid;
  v_driver_id uuid;
  v_customer_id uuid;
  v_cohort_id uuid;
  v_experiment_arm_id uuid;
  v_value jsonb;
BEGIN
  -- Extract context IDs
  v_zone_id := p_ctx->>'zone_id';
  v_partner_id := p_ctx->>'partner_id';
  v_driver_id := p_ctx->>'driver_id';
  v_customer_id := p_ctx->>'customer_id';
  v_cohort_id := p_ctx->>'cohort_id';
  v_experiment_arm_id := p_ctx->>'experiment_arm_id';

  -- Priority order: experiment_arm > driver/customer/partner > cohort > zone > global > default
  -- Each level: latest effective_from <= p_at, status = 'active'

  -- 1. experiment_arm
  IF v_experiment_arm_id IS NOT NULL THEN
    SELECT value INTO v_value
    FROM public.config_values
    WHERE key = p_key
      AND scope_type = 'experiment_arm'
      AND scope_id = v_experiment_arm_id
      AND status = 'active'
      AND effective_from <= p_at
      AND (effective_to IS NULL OR effective_to > p_at)
    ORDER BY effective_from DESC
    LIMIT 1;
    IF v_value IS NOT NULL THEN RETURN v_value; END IF;
  END IF;

  -- 2. driver
  IF v_driver_id IS NOT NULL THEN
    SELECT value INTO v_value
    FROM public.config_values
    WHERE key = p_key
      AND scope_type = 'driver'
      AND scope_id = v_driver_id
      AND status = 'active'
      AND effective_from <= p_at
      AND (effective_to IS NULL OR effective_to > p_at)
    ORDER BY effective_from DESC
    LIMIT 1;
    IF v_value IS NOT NULL THEN RETURN v_value; END IF;
  END IF;

  -- 3. customer
  IF v_customer_id IS NOT NULL THEN
    SELECT value INTO v_value
    FROM public.config_values
    WHERE key = p_key
      AND scope_type = 'customer'
      AND scope_id = v_customer_id
      AND status = 'active'
      AND effective_from <= p_at
      AND (effective_to IS NULL OR effective_to > p_at)
    ORDER BY effective_from DESC
    LIMIT 1;
    IF v_value IS NOT NULL THEN RETURN v_value; END IF;
  END IF;

  -- 4. partner
  IF v_partner_id IS NOT NULL THEN
    SELECT value INTO v_value
    FROM public.config_values
    WHERE key = p_key
      AND scope_type = 'partner'
      AND scope_id = v_partner_id
      AND status = 'active'
      AND effective_from <= p_at
      AND (effective_to IS NULL OR effective_to > p_at)
    ORDER BY effective_from DESC
    LIMIT 1;
    IF v_value IS NOT NULL THEN RETURN v_value; END IF;
  END IF;

  -- 5. cohort
  IF v_cohort_id IS NOT NULL THEN
    SELECT value INTO v_value
    FROM public.config_values
    WHERE key = p_key
      AND scope_type = 'cohort'
      AND scope_id = v_cohort_id
      AND status = 'active'
      AND effective_from <= p_at
      AND (effective_to IS NULL OR effective_to > p_at)
    ORDER BY effective_from DESC
    LIMIT 1;
    IF v_value IS NOT NULL THEN RETURN v_value; END IF;
  END IF;

  -- 6. zone
  IF v_zone_id IS NOT NULL THEN
    SELECT value INTO v_value
    FROM public.config_values
    WHERE key = p_key
      AND scope_type = 'zone'
      AND scope_id = v_zone_id
      AND status = 'active'
      AND effective_from <= p_at
      AND (effective_to IS NULL OR effective_to > p_at)
    ORDER BY effective_from DESC
    LIMIT 1;
    IF v_value IS NOT NULL THEN RETURN v_value; END IF;
  END IF;

  -- 7. global
  SELECT value INTO v_value
  FROM public.config_values
  WHERE key = p_key
    AND scope_type = 'global'
    AND status = 'active'
    AND effective_from <= p_at
    AND (effective_to IS NULL OR effective_to > p_at)
  ORDER BY effective_from DESC
  LIMIT 1;
  IF v_value IS NOT NULL THEN RETURN v_value; END IF;

  -- 8. registry default
  SELECT default_value INTO v_value
  FROM public.config_registry
  WHERE key = p_key;

  RETURN v_value;
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_config(text, jsonb, timestamptz) TO authenticated, service_role;

-- Resolve all config for a context, return full set + snapshot ID
CREATE OR REPLACE FUNCTION public.resolve_all_config(
  p_ctx jsonb DEFAULT '{}'::jsonb,
  p_at timestamptz DEFAULT now()
)
RETURNS TABLE (
  snapshot_id uuid,
  config jsonb
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_result jsonb := '{}'::jsonb;
  v_registry RECORD;
  v_hash text;
  v_snapshot_id uuid;
BEGIN
  -- Resolve every key in registry
  FOR v_registry IN SELECT key FROM public.config_registry LOOP
    v_result := v_result || jsonb_build_object(v_registry.key, public.resolve_config(v_registry.key, p_ctx, p_at));
  END LOOP;

  -- Create or get snapshot
  v_hash := encode(sha256(v_result::text::bytea), 'hex');

  INSERT INTO public.config_snapshots (hash, resolved)
  VALUES (v_hash, v_result)
  ON CONFLICT (hash) DO UPDATE SET resolved = EXCLUDED.resolved
  RETURNING id INTO v_snapshot_id;

  RETURN QUERY SELECT v_snapshot_id, v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_all_config(jsonb, timestamptz) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 3. Config Audit Trigger
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.audit_config_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.config_audit (key, scope_type, scope_id, new_value, changed_by, reason)
    VALUES (NEW.key, NEW.scope_type, NEW.scope_id, NEW.value, NEW.created_by, NEW.reason);
  ELSIF TG_OP = 'UPDATE' THEN
    INSERT INTO public.config_audit (key, scope_type, scope_id, old_value, new_value, changed_by, reason)
    VALUES (NEW.key, NEW.scope_type, NEW.scope_id, OLD.value, NEW.value, NEW.created_by, NEW.reason);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_config_values ON public.config_values;
CREATE TRIGGER trg_audit_config_values
  AFTER INSERT OR UPDATE ON public.config_values
  FOR EACH ROW EXECUTE FUNCTION private.audit_config_change();

-- ----------------------------------------------------------------------------
-- 4. Event Log Tables (Section 4.1)
-- ----------------------------------------------------------------------------

-- 4.1 event_catalog: registry of allowed events with JSON schemas
CREATE TABLE IF NOT EXISTS public.event_catalog (
  name text PRIMARY KEY,
  description text NOT NULL,
  json_schema jsonb NOT NULL,
  category text NOT NULL,
  retention_days integer NOT NULL DEFAULT 365,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.event_catalog ENABLE ROW LEVEL SECURITY;

CREATE POLICY "event_catalog_select_authenticated" ON public.event_catalog
  FOR SELECT TO authenticated USING (is_active = true);

CREATE POLICY "event_catalog_modify_admin" ON public.event_catalog
  FOR ALL USING (private.is_admin()) WITH CHECK (private.is_admin());

GRANT SELECT ON public.event_catalog TO authenticated, service_role;
GRANT ALL ON public.event_catalog TO service_role;

-- 4.2 events: append-only event log, partitioned by month
-- Primary key must include partition key (received_at)
CREATE TABLE IF NOT EXISTS public.events (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  occurred_at timestamptz NOT NULL,        -- device timestamp
  received_at timestamptz NOT NULL DEFAULT now(),  -- server receipt
  actor_id uuid REFERENCES public.profiles(id),
  actor_type text NOT NULL CHECK (actor_type IN ('customer', 'driver', 'partner', 'admin', 'system')),
  session_id uuid,
  device_id text,
  app_version text,
  os text,
  entity_type text,                        -- delivery, order, driver, etc.
  entity_id uuid,
  name text NOT NULL REFERENCES public.event_catalog(name),
  props jsonb NOT NULL DEFAULT '{}'::jsonb,
  config_snapshot_id uuid REFERENCES public.config_snapshots(id),
  experiment_assignments jsonb DEFAULT '{}'::jsonb,
  idempotency_key text,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id, received_at)
) PARTITION BY RANGE (received_at);

-- Create monthly partitions for the next year
DO $$
DECLARE
  v_start date := date_trunc('month', now())::date;
  v_end date := v_start + interval '13 months';
  v_partition_name text;
  v_partition_start date;
  v_partition_end date;
BEGIN
  WHILE v_start < v_end LOOP
    v_partition_name := 'events_' || to_char(v_start, 'YYYY_MM');
    v_partition_start := v_start;
    v_partition_end := v_start + interval '1 month';

    EXECUTE format(
      'CREATE TABLE IF NOT EXISTS %I PARTITION OF public.events
       FOR VALUES FROM (%L) TO (%L)',
      v_partition_name, v_partition_start, v_partition_end
    );

    -- Indexes on each partition
    EXECUTE format(
      'CREATE INDEX IF NOT EXISTS %I_actor_id_idx ON %I (actor_id)',
      v_partition_name, v_partition_name
    );
    EXECUTE format(
      'CREATE INDEX IF NOT EXISTS %I_entity_idx ON %I (entity_type, entity_id)',
      v_partition_name, v_partition_name
    );
    EXECUTE format(
      'CREATE INDEX IF NOT EXISTS %I_name_idx ON %I (name)',
      v_partition_name, v_partition_name
    );
    EXECUTE format(
      'CREATE INDEX IF NOT EXISTS %I_received_idx ON %I (received_at)',
      v_partition_name, v_partition_name
    );
    EXECUTE format(
      'CREATE INDEX IF NOT EXISTS %I_idempotency_idx ON %I (idempotency_key)',
      v_partition_name, v_partition_name
    );

    v_start := v_partition_end;
  END LOOP;
END;
$$;

ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

-- Drivers see their own events + events for their active deliveries
CREATE POLICY "events_select_driver" ON public.events
  FOR SELECT TO authenticated USING (
    actor_id = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.deliveries d
      WHERE d.id = events.entity_id
        AND d.driver_id = (SELECT auth.uid())
        AND d.status IN ('claimed', 'en_route', 'in_progress')
    )
    OR EXISTS (
      SELECT 1 FROM public.deliveries d
      WHERE d.id = events.entity_id
        AND d.customer_id = (SELECT auth.uid())
    )
    OR private.is_admin()
  );

-- Service role can insert (client SDK calls Edge Function with service role)
CREATE POLICY "events_insert_service" ON public.events
  FOR INSERT TO service_role WITH CHECK (true);

GRANT SELECT ON public.events TO authenticated, service_role;
GRANT INSERT ON public.events TO service_role;

-- ----------------------------------------------------------------------------
-- 5. Cross-Parameter Constraints Table (Guardrails)
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.config_constraints (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  expression text NOT NULL,  -- SQL boolean expression referencing config keys
  message text NOT NULL,     -- Human-readable violation message
  severity text NOT NULL CHECK (severity IN ('warning', 'error')) DEFAULT 'error',
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.config_constraints ENABLE ROW LEVEL SECURITY;

CREATE POLICY "config_constraints_select_authenticated" ON public.config_constraints
  FOR SELECT TO authenticated USING (is_active = true);

CREATE POLICY "config_constraints_modify_admin" ON public.config_constraints
  FOR ALL USING (private.is_admin()) WITH CHECK (private.is_admin());

GRANT SELECT ON public.config_constraints TO authenticated, service_role;
GRANT ALL ON public.config_constraints TO service_role;

-- Function to validate proposed config values against constraints
CREATE OR REPLACE FUNCTION public.validate_config_constraints(
  p_proposed jsonb
)
RETURNS TABLE (
  constraint_name text,
  passed boolean,
  message text
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_constraint RECORD;
  v_passed boolean;
BEGIN
  FOR v_constraint IN
    SELECT name, expression, message FROM public.config_constraints WHERE is_active = true
  LOOP
    -- Evaluate expression with proposed values as variables
    EXECUTE format(
      'SELECT %s', v_constraint.expression
    ) USING p_proposed INTO v_passed;

    RETURN QUERY SELECT v_constraint.name, v_passed, v_constraint.message;
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.validate_config_constraints(jsonb) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 6. Seed Config Registry (Starter Parameter Inventory from Spec 1.4)
-- ----------------------------------------------------------------------------

INSERT INTO public.config_registry (key, type, json_schema, unit, default_value, min_value, max_value, category, description, risk_level, requires_approval) VALUES
-- Pricing
('pricing.strategy', 'string', '{"type": "string", "enum": ["zone_v1", "distance_time_v1"]}', NULL, '"zone_v1"', NULL, NULL, 'pricing', 'Active pricing algorithm version', 'high', true),
('pricing.base_fee', 'number', '{"type": "number", "minimum": 0}', 'USD', '8.00', '0', '100', 'pricing', 'Base fee charged to customer', 'high', true),
('pricing.per_mile', 'number', '{"type": "number", "minimum": 0}', 'USD/mile', '1.50', '0', '10', 'pricing', 'Per-mile rate', 'high', true),
('pricing.per_minute', 'number', '{"type": "number", "minimum": 0}', 'USD/minute', '0.30', '0', '5', 'pricing', 'Per-minute rate (for distance_time strategy)', 'high', true),
('pricing.min_fee', 'number', '{"type": "number", "minimum": 0}', 'USD', '5.00', '0', '50', 'pricing', 'Minimum order fee', 'medium', true),
('pricing.max_fee', 'number', '{"type": "number", "minimum": 0}', 'USD', '100.00', '0', '500', 'pricing', 'Maximum order fee', 'medium', true),
('pricing.zone.1.fee', 'number', '{"type": "number", "minimum": 0}', 'USD', '8.00', '0', '50', 'pricing', 'Zone 1 flat fee', 'high', true),
('pricing.zone.2.fee', 'number', '{"type": "number", "minimum": 0}', 'USD', '11.00', '0', '50', 'pricing', 'Zone 2 flat fee', 'high', true),
('pricing.zone.3.fee', 'number', '{"type": "number", "minimum": 0}', 'USD', '15.00', '0', '50', 'pricing', 'Zone 3 flat fee', 'high', true),
('pricing.distance_bands', 'json', '{"type": "array", "items": {"type": "number"}}', NULL, '[5, 10, 20]', NULL, NULL, 'pricing', 'Distance band boundaries in miles for zone assignment', 'medium', true),
('pricing.demand_multiplier.min', 'number', '{"type": "number", "minimum": 0.5, "maximum": 1}', NULL, '0.8', '0.5', '1', 'pricing', 'Minimum demand multiplier', 'medium', false),
('pricing.demand_multiplier.max', 'number', '{"type": "number", "minimum": 1, "maximum": 5}', NULL, '2.0', '1', '5', 'pricing', 'Maximum demand multiplier', 'medium', false),
('pricing.demand_multiplier.curve', 'string', '{"type": "string", "enum": ["linear", "exponential", "step"]}', NULL, '"linear"', NULL, NULL, 'pricing', 'Demand multiplier curve type', 'medium', false),
('pricing.peak_hours', 'json', '{"type": "array", "items": {"type": "object", "properties": {"start": {"type": "string"}, "end": {"type": "string"}, "days": {"type": "array", "items": {"type": "integer", "minimum": 0, "maximum": 6}}}}}', NULL, '[{"start": "17:00", "end": "20:00", "days": [1,2,3,4,5]}]', NULL, NULL, 'pricing', 'Peak hour definitions', 'medium', false),
('pricing.weather_surcharge', 'number', '{"type": "number", "minimum": 0, "maximum": 10}', 'USD', '0.00', '0', '10', 'pricing', 'Weather surcharge per delivery', 'low', false),
('pricing.tip_presets', 'json', '{"type": "array", "items": {"type": "number"}}', NULL, '[1, 2, 3, 5]', NULL, NULL, 'pricing', 'Tip preset amounts in USD', 'low', false),
('pricing.fee_rounding', 'string', '{"type": "string", "enum": ["none", "round", "ceil_0.25", "ceil_0.50"]}', NULL, '"ceil_0.25"', NULL, NULL, 'pricing', 'Fee rounding strategy', 'low', false),

-- Driver pay
('pay.strategy', 'string', '{"type": "string", "enum": ["pct_v1", "per_mile_v1", "hourly_floor_v1"]}', NULL, '"pct_v1"', NULL, NULL, 'driver_pay', 'Active driver pay algorithm version', 'high', true),
('pay.payout_pct_or_per_mile', 'number', '{"type": "number", "minimum": 0, "maximum": 1}', NULL, '0.75', '0', '1', 'driver_pay', 'Payout percentage (pct_v1) or per-mile rate (per_mile_v1)', 'high', true),
('pay.min_payout', 'number', '{"type": "number", "minimum": 0}', 'USD', '4.00', '0', '20', 'driver_pay', 'Minimum payout per delivery', 'medium', true),
('pay.pay_floor_per_hour', 'number', '{"type": "number", "minimum": 0}', 'USD/hour', '15.00', '0', '50', 'driver_pay', 'Guaranteed minimum hourly earnings', 'high', true),
('pay.wait_pay_per_minute', 'number', '{"type": "number", "minimum": 0}', 'USD/minute', '0.25', '0', '2', 'driver_pay', 'Wait time pay per minute', 'medium', true),
('pay.wait_pay_grace_minutes', 'integer', '{"type": "integer", "minimum": 0, "maximum": 30}', 'minutes', '5', '0', '30', 'driver_pay', 'Free wait minutes before wait pay starts', 'medium', false),
('pay.bonus.rules', 'json', '{"type": "array"}', NULL, '[]', NULL, NULL, 'driver_pay', 'Bonus rules configuration', 'medium', false),

-- Platform/co-op
('platform_cut_pct', 'number', '{"type": "number", "minimum": 0, "maximum": 0.5}', 'percent', '0.25', '0', '0.5', 'platform', 'Platform cut percentage', 'high', true),
('patronage_reserve_pct', 'number', '{"type": "number", "minimum": 0, "maximum": 0.3}', 'percent', '0.05', '0', '0.3', 'platform', 'Patronage reserve percentage', 'high', true),

-- Cancellation
('cancel.free_stages', 'json', '{"type": "array", "items": {"type": "string", "enum": ["pending", "offered", "claimed", "en_route", "in_progress"]}}', NULL, '["pending", "offered", "claimed"]', NULL, NULL, 'cancellation', 'Stages where cancellation is free for customer', 'high', true),
('cancel.comp.en_route', 'number', '{"type": "number", "minimum": 0}', 'USD', '3.00', '0', '50', 'cancellation', 'Compensation when customer cancels en_route', 'high', true),
('cancel.comp.in_progress', 'number', '{"type": "number", "minimum": 0}', 'USD', '8.00', '0', '100', 'cancellation', 'Compensation when customer cancels in_progress', 'high', true),
('cancel.customer_fee.pending', 'number', '{"type": "number", "minimum": 0}', 'USD', '0.00', '0', '20', 'cancellation', 'Customer fee for cancelling at pending', 'low', false),
('cancel.customer_fee.claimed', 'number', '{"type": "number", "minimum": 0}', 'USD', '2.00', '0', '20', 'cancellation', 'Customer fee for cancelling at claimed', 'low', false),
('cancel.customer_fee.en_route', 'number', '{"type": "number", "minimum": 0}', 'USD', '5.00', '0', '50', 'cancellation', 'Customer fee for cancelling en_route', 'medium', true),
('cancel.lockout_after_status', 'string', '{"type": "string", "enum": ["claimed", "en_route", "in_progress"]}', NULL, '"en_route"', NULL, NULL, 'cancellation', 'Status after which customer cannot cancel', 'medium', true),

-- Dispatch
('dispatch.strategy', 'string', '{"type": "string", "enum": ["broadcast_v1", "nearest_first_v1", "tiered_v1"]}', NULL, '"broadcast_v1"', NULL, NULL, 'dispatch', 'Active dispatch algorithm version', 'high', true),
('dispatch.offer_mode', 'string', '{"type": "string", "enum": ["broadcast", "sequential", "tiered"]}', NULL, '"broadcast"', NULL, NULL, 'dispatch', 'How offers are sent to drivers', 'high', true),
('dispatch.offer_ttl_seconds', 'integer', '{"type": "integer", "minimum": 10, "maximum": 300}', 'seconds', '30', '10', '300', 'dispatch', 'Time driver has to accept an offer', 'medium', false),
('dispatch.search_radius_miles', 'number', '{"type": "number", "minimum": 1, "maximum": 50}', 'miles', '5.0', '1', '50', 'dispatch', 'Initial search radius for drivers', 'medium', false),
('dispatch.radius_expansion_steps', 'json', '{"type": "array", "items": {"type": "number"}}', 'miles', '[2, 5, 10]', NULL, NULL, 'dispatch', 'Radius expansion steps in miles', 'medium', false),
('dispatch.ranking_weights', 'json', '{"type": "object", "properties": {"distance": {"type": "number"}, "rating": {"type": "number"}, "acceptance": {"type": "number"}, "idle_time": {"type": "number"}}}', NULL, '{"distance": 0.5, "rating": 0.2, "acceptance": 0.2, "idle_time": 0.1}', NULL, NULL, 'dispatch', 'Driver ranking weights (sum to 1)', 'high', true),
('dispatch.max_concurrent_offers', 'integer', '{"type": "integer", "minimum": 1, "maximum": 20}', NULL, '5', '1', '20', 'dispatch', 'Max simultaneous offers per job', 'medium', false),
('dispatch.reoffer_delay_seconds', 'integer', '{"type": "integer", "minimum": 0, "maximum": 60}', 'seconds', '5', '0', '60', 'dispatch', 'Delay before re-offering to next driver', 'low', false),
('dispatch.stale_claim_timeout_minutes', 'integer', '{"type": "integer", "minimum": 1, "maximum": 60}', 'minutes', '10', '1', '60', 'dispatch', 'Auto-release claimed job after timeout', 'medium', false),

-- Geo/service
('geo.max_distance_miles', 'number', '{"type": "number", "minimum": 1, "maximum": 100}', 'miles', '20', '1', '100', 'geo', 'Maximum delivery distance', 'high', true),
('geo.service_hours', 'json', '{"type": "object", "properties": {"start": {"type": "string"}, "end": {"type": "string"}}}', NULL, '{"start": "06:00", "end": "23:00"}', NULL, NULL, 'geo', 'Daily service hours', 'medium', false),
('geo.holiday_calendar', 'json', '{"type": "array", "items": {"type": "string", "format": "date"}}', NULL, '[]', NULL, NULL, 'geo', 'Holiday dates (ISO format)', 'low', false),

-- Limits
('limits.max_active_jobs_per_driver', 'integer', '{"type": "integer", "minimum": 1, "maximum": 10}', NULL, '1', '1', '10', 'limits', 'Max concurrent jobs per driver', 'high', true),
('limits.max_orders_per_customer_per_hour', 'integer', '{"type": "integer", "minimum": 1, "maximum": 50}', NULL, '10', '1', '50', 'limits', 'Max orders per customer per hour', 'medium', false),
('limits.referral_code_length', 'integer', '{"type": "integer", "minimum": 6, "maximum": 20}', NULL, '8', '6', '20', 'limits', 'Referral code length', 'low', false),
('limits.referral_ttl_days', 'integer', '{"type": "integer", "minimum": 1, "maximum": 365}', 'days', '90', '1', '365', 'limits', 'Referral code TTL in days', 'low', false),

-- Telemetry
('telemetry.gps.sample_interval_s', 'integer', '{"type": "integer", "minimum": 1, "maximum": 60}', 'seconds', '5', '1', '60', 'telemetry', 'GPS sampling interval while active', 'low', false),
('telemetry.gps.distance_filter_m', 'integer', '{"type": "integer", "minimum": 0, "maximum": 1000}', 'meters', '10', '0', '1000', 'telemetry', 'Minimum distance between GPS points', 'low', false),
('telemetry.gps.accuracy_threshold_m', 'integer', '{"type": "integer", "minimum": 1, "maximum": 100}', 'meters', '30', '1', '100', 'telemetry', 'Max GPS accuracy to accept point', 'low', false),
('telemetry.gps.upload_batch_size', 'integer', '{"type": "integer", "minimum": 1, "maximum": 500}', NULL, '50', '1', '500', 'telemetry', 'Batch size for GPS uploads', 'low', false),
('telemetry.gps.idle_sampling_multiplier', 'number', '{"type": "number", "minimum": 1, "maximum": 100}', NULL, '10', '1', '100', 'telemetry', 'Sampling interval multiplier when idle', 'low', false),
('telemetry.retention.location_pings_days', 'integer', '{"type": "integer", "minimum": 30, "maximum": 2555}', 'days', '730', '30', '2555', 'telemetry', 'Retention for raw location pings', 'medium', false),
('telemetry.retention.events_days', 'integer', '{"type": "integer", "minimum": 30, "maximum": 2555}', 'days', '1095', '30', '2555', 'telemetry', 'Retention for event log', 'medium', false),
('telemetry.retention.mileage_years', 'integer', '{"type": "integer", "minimum": 3, "maximum": 10}', 'years', '7', '3', '10', 'telemetry', 'Retention for mileage ledger', 'high', true),

-- Feature flags
('flag.new_driver_onboarding', 'boolean', '{"type": "boolean"}', NULL, 'false', NULL, NULL, 'feature', 'Enable new driver onboarding flow', 'low', false),
('flag.partner_self_serve_menu', 'boolean', '{"type": "boolean"}', NULL, 'true', NULL, NULL, 'feature', 'Enable partner self-serve menu editing', 'low', false),
('flag.experimental_dispatch', 'boolean', '{"type": "boolean"}', NULL, 'false', NULL, NULL, 'feature', 'Enable experimental dispatch algorithms', 'medium', true),

-- UX copy
('ux.copy.tip_prompt', 'string', '{"type": "string", "maxLength": 200}', NULL, '"Add a tip for your driver?"', NULL, NULL, 'ux', 'Tip prompt text', 'low', false),
('ux.copy.out_of_area', 'string', '{"type": "string", "maxLength": 300}', NULL, '"Sorry, we don''t deliver to this area yet."', NULL, NULL, 'ux', 'Out of area message', 'low', false),

-- Distance/Time pricing strategy params (for distance_time_v1)
('pricing.distance_time.base_fee', 'number', '{"type": "number", "minimum": 0}', 'USD', '5.00', '0', '50', 'pricing', 'Base fee for distance-time strategy', 'high', true),
('pricing.distance_time.per_mile', 'number', '{"type": "number", "minimum": 0}', 'USD/mile', '2.00', '0', '10', 'pricing', 'Per-mile for distance-time strategy', 'high', true),
('pricing.distance_time.per_minute', 'number', '{"type": "number", "minimum": 0}', 'USD/minute', '0.50', '0', '5', 'pricing', 'Per-minute for distance-time strategy', 'high', true),
('pricing.distance_time.min_fee', 'number', '{"type": "number", "minimum": 0}', 'USD', '7.00', '0', '50', 'pricing', 'Min fee for distance-time strategy', 'medium', true);

-- ----------------------------------------------------------------------------
-- 7. Seed Config Values (Global defaults, active immediately)
-- ----------------------------------------------------------------------------

INSERT INTO public.config_values (key, scope_type, scope_id, value, status, created_by, reason, effective_from)
SELECT key, 'global', NULL, default_value, 'active',
  (SELECT id FROM public.profiles WHERE is_admin = true LIMIT 1),
  'Initial seed from config registry',
  now()
FROM public.config_registry;

-- ----------------------------------------------------------------------------
-- 8. Seed Event Catalog (Minimum from Spec 4.1)
-- ----------------------------------------------------------------------------

INSERT INTO public.event_catalog (name, description, json_schema, category, retention_days) VALUES
('app_open', 'App launched', '{"type": "object", "properties": {"cold_start": {"type": "boolean"}}}', 'session', 365),
('screen_view', 'Screen viewed', '{"type": "object", "properties": {"screen": {"type": "string"}, "previous_screen": {"type": "string"}}}', 'navigation', 365),
('signup_step', 'Signup funnel step', '{"type": "object", "properties": {"step": {"type": "string"}, "success": {"type": "boolean"}}}', 'onboarding', 365),
('login', 'User logged in', '{"type": "object", "properties": {"method": {"type": "string"}}}', 'auth', 365),
('quote_viewed', 'Customer viewed delivery quote', '{"type": "object", "properties": {"distance_miles": {"type": "number"}, "fee": {"type": "number"}, "zone": {"type": "integer"}}}', 'pricing', 730),
('order_placed', 'Customer placed order', '{"type": "object", "properties": {"delivery_id": {"type": "string"}, "fee": {"type": "number"}, "zone": {"type": "integer"}}}', 'order', 730),
('order_edited', 'Customer edited order', '{"type": "object", "properties": {"delivery_id": {"type": "string"}, "changes": {"type": "object"}}}', 'order', 730),
('cancel_tapped', 'Customer tapped cancel button', '{"type": "object", "properties": {"delivery_id": {"type": "string"}, "stage": {"type": "string"}}}', 'cancellation', 730),
('search_no_results', 'Search returned no results', '{"type": "object", "properties": {"query": {"type": "string"}}}', 'search', 365),
('out_of_area', 'Address out of service area', '{"type": "object", "properties": {"address": {"type": "string"}, "distance_miles": {"type": "number"}}}', 'geo', 730),
('offer_shown', 'Delivery offer shown to driver', '{"type": "object", "properties": {"delivery_id": {"type": "string"}, "offered_pay": {"type": "number"}, "distance_to_pickup_miles": {"type": "number"}, "rank": {"type": "integer"}}}', 'dispatch', 730),
('offer_viewed', 'Driver viewed offer details', '{"type": "object", "properties": {"delivery_id": {"type": "string"}, "view_duration_seconds": {"type": "integer"}}}', 'dispatch', 730),
('offer_accepted', 'Driver accepted offer', '{"type": "object", "properties": {"delivery_id": {"type": "string"}, "response_time_seconds": {"type": "integer"}}}', 'dispatch', 730),
('offer_declined', 'Driver declined offer', '{"type": "object", "properties": {"delivery_id": {"type": "string"}, "reason": {"type": "string"}, "response_time_seconds": {"type": "integer"}}}', 'dispatch', 730),
('offer_expired', 'Offer expired without response', '{"type": "object", "properties": {"delivery_id": {"type": "string"}}}', 'dispatch', 730),
('driver_online', 'Driver went online', '{"type": "object", "properties": {"zone": {"type": "string"}}}', 'driver_status', 730),
('driver_offline', 'Driver went offline', '{"type": "object", "properties": {"zone": {"type": "string"}, "online_duration_minutes": {"type": "integer"}}}', 'driver_status', 730),
('delivery_started', 'Driver started driving to pickup', '{"type": "object", "properties": {"delivery_id": {"type": "string"}}}', 'delivery_timeline', 1095),
('arrived_pickup', 'Driver arrived at pickup location', '{"type": "object", "properties": {"delivery_id": {"type": "string"}}}', 'delivery_timeline', 1095),
('picked_up', 'Driver picked up order', '{"type": "object", "properties": {"delivery_id": {"type": "string"}}}', 'delivery_timeline', 1095),
('arrived_dropoff', 'Driver arrived at dropoff location', '{"type": "object", "properties": {"delivery_id": {"type": "string"}}}', 'delivery_timeline', 1095),
('delivered', 'Delivery completed', '{"type": "object", "properties": {"delivery_id": {"type": "string"}, "actual_duration_minutes": {"type": "integer"}}}', 'delivery_timeline', 1095),
('proof_captured', 'Proof of delivery captured', '{"type": "object", "properties": {"delivery_id": {"type": "string"}, "type": {"type": "string"}}}', 'delivery_timeline', 1095),
('tip_added', 'Customer added tip', '{"type": "object", "properties": {"delivery_id": {"type": "string"}, "amount": {"type": "number"}}}', 'payment', 1095),
('rating_given', 'Rating submitted', '{"type": "object", "properties": {"delivery_id": {"type": "string"}, "rating": {"type": "integer"}, "reviewee_type": {"type": "string"}}}', 'social', 1095),
('support_opened', 'Support chat opened', '{"type": "object", "properties": {"topic": {"type": "string"}}}', 'support', 365),
('permission_granted', 'Permission granted', '{"type": "object", "properties": {"permission": {"type": "string"}}}', 'permissions', 365),
('permission_denied', 'Permission denied', '{"type": "object", "properties": {"permission": {"type": "string"}}}', 'permissions', 365),
('crash', 'App crash', '{"type": "object", "properties": {"error": {"type": "string"}, "stack": {"type": "string"}}}', 'error', 365),
('error', 'Non-fatal error', '{"type": "object", "properties": {"error": {"type": "string"}, "context": {"type": "string"}}}', 'error', 365);

-- ----------------------------------------------------------------------------
-- 9. Seed Cross-Parameter Constraints (Guardrails)
-- ----------------------------------------------------------------------------

INSERT INTO public.config_constraints (name, expression, message, severity) VALUES
('driver_payout_min_per_mile',
 '($1->>''pay.payout_pct_or_per_mile'')::numeric <= ($1->>''pricing.per_mile'')::numeric',
 'Driver payout per mile cannot exceed customer per-mile charge', 'error'),
('platform_cut_pct_max',
 '($1->>''platform_cut_pct'')::numeric <= 0.40',
 'Platform cut cannot exceed 40%', 'error'),
('cancel_comp_en_route_le_driver_payout',
 '($1->>''cancel.comp.en_route'')::numeric <= ($1->>''pay.min_payout'')::numeric + (($1->>''pricing.per_mile'')::numeric * 5)',
 'en_route compensation cannot exceed reasonable driver payout', 'error'),
('cancel_comp_in_progress_le_driver_payout',
 '($1->>''cancel.comp.in_progress'')::numeric <= ($1->>''pay.min_payout'')::numeric + (($1->>''pricing.per_mile'')::numeric * 10)',
 'in_progress compensation cannot exceed reasonable driver payout', 'error'),
('fee_rounding_consistent',
 '($1->>''pricing.fee_rounding'')::text IN (''none'', ''round'', ''ceil_0.25'', ''ceil_0.50'')',
 'Fee rounding must be valid strategy', 'error'),
('ranking_weights_sum_to_one',
 'abs(($1->''dispatch.ranking_weights''->>''distance'')::numeric + ($1->''dispatch.ranking_weights''->>''rating'')::numeric + ($1->''dispatch.ranking_weights''->>''acceptance'')::numeric + ($1->''dispatch.ranking_weights''->>''idle_time'')::numeric - 1) < 0.001',
 'Dispatch ranking weights must sum to 1.0', 'error'),
('pay_floor_respects_min_wage',
 '($1->>''pay.pay_floor_per_hour'')::numeric >= 7.25',
 'Pay floor per hour must meet federal minimum wage', 'error');

-- ----------------------------------------------------------------------------
-- 10. Impact Preview Function (Spec 1.3)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.preview_config_impact(
  p_proposed jsonb,
  p_days_lookback integer DEFAULT 7
)
RETURNS TABLE (
  metric text,
  current_value numeric,
  proposed_value numeric,
  delta numeric,
  delta_pct numeric
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_current_config jsonb;
  v_proposed_config jsonb;
  v_delivery RECORD;
  v_current_total numeric := 0;
  v_proposed_total numeric := 0;
  v_current_driver_pay numeric := 0;
  v_proposed_driver_pay numeric := 0;
  v_current_platform_cut numeric := 0;
  v_proposed_platform_cut numeric := 0;
  v_count integer := 0;
BEGIN
  -- Get current global config
  SELECT jsonb_object_agg(key, default_value) INTO v_current_config
  FROM public.config_registry;

  -- Merge proposed changes
  v_proposed_config := v_current_config || p_proposed;

  -- Sample recent deliveries
  FOR v_delivery IN
    SELECT id, distance_miles, zone_assigned, fee_charged, driver_payout, platform_cut
    FROM public.deliveries
    WHERE requested_at >= now() - (p_days_lookback || ' days')::interval
      AND status = 'completed'
    LIMIT 1000
  LOOP
    -- Simulate pricing under current config (zone_v1)
    v_current_total := v_current_total + v_delivery.fee_charged;
    v_current_driver_pay := v_current_driver_pay + v_delivery.driver_payout;
    v_current_platform_cut := v_current_platform_cut + v_delivery.platform_cut;

    -- Simulate pricing under proposed config (simplified - would use actual strategy function)
    -- For preview, we just show the delta in config values
    v_count := v_count + 1;
  END LOOP;

  IF v_count > 0 THEN
    RETURN QUERY SELECT
      'avg_customer_price'::text,
      v_current_total / v_count,
      v_proposed_total / v_count,
      (v_proposed_total - v_current_total) / v_count,
      CASE WHEN v_current_total > 0 THEN ((v_proposed_total - v_current_total) / v_current_total) * 100 ELSE 0 END;

    RETURN QUERY SELECT
      'avg_driver_pay'::text,
      v_current_driver_pay / v_count,
      v_proposed_driver_pay / v_count,
      (v_proposed_driver_pay - v_current_driver_pay) / v_count,
      CASE WHEN v_current_driver_pay > 0 THEN ((v_proposed_driver_pay - v_current_driver_pay) / v_current_driver_pay) * 100 ELSE 0 END;

    RETURN QUERY SELECT
      'avg_platform_cut'::text,
      v_current_platform_cut / v_count,
      v_proposed_platform_cut / v_count,
      (v_proposed_platform_cut - v_current_platform_cut) / v_count,
      CASE WHEN v_current_platform_cut > 0 THEN ((v_proposed_platform_cut - v_current_platform_cut) / v_current_platform_cut) * 100 ELSE 0 END;
  ELSE
    RETURN QUERY SELECT
      'no_deliveries_to_sample'::text, 0, 0, 0, 0;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.preview_config_impact(jsonb, integer) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 11. Tax Mileage Rates Table (Spec 5.4)
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.tax_mileage_rates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  effective_from date NOT NULL,
  effective_to date,
  business_cents integer NOT NULL,
  medical_cents integer,
  charity_cents integer,
  source_url text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (effective_from)
);

ALTER TABLE public.tax_mileage_rates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tax_mileage_rates_select_authenticated" ON public.tax_mileage_rates
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "tax_mileage_rates_modify_admin" ON public.tax_mileage_rates
  FOR ALL USING (private.is_admin()) WITH CHECK (private.is_admin());

GRANT SELECT ON public.tax_mileage_rates TO authenticated, service_role;
GRANT ALL ON public.tax_mileage_rates TO service_role;

-- Seed with IRS rates (Spec 5.4)
INSERT INTO public.tax_mileage_rates (effective_from, effective_to, business_cents, medical_cents, charity_cents, source_url, notes) VALUES
('2024-01-01', '2024-12-31', 67, 21, 14, 'https://www.irs.gov/tax-professionals/standard-mileage-rates', '2024 rate'),
('2025-01-01', '2025-12-31', 70, 21, 14, 'https://www.irs.gov/tax-professionals/standard-mileage-rates', '2025 rate'),
('2026-01-01', '2026-06-30', 7250, 2100, 1400, 'https://www.irs.gov/tax-professionals/standard-mileage-rates', '2026 H1 rate (cents * 100 for precision)'),
('2026-07-01', '2026-12-31', 7600, 2100, 1400, 'https://www.irs.gov/tax-professionals/standard-mileage-rates', '2026 H2 rate (cents * 100 for precision)');

-- Function to get rate for a date
CREATE OR REPLACE FUNCTION public.get_mileage_rate(p_date date)
RETURNS TABLE (
  business_cents integer,
  medical_cents integer,
  charity_cents integer
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT business_cents, medical_cents, charity_cents
  FROM public.tax_mileage_rates
  WHERE effective_from <= p_date
    AND (effective_to IS NULL OR effective_to >= p_date)
  ORDER BY effective_from DESC
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_mileage_rate(date) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- End of Phase P1 migration
-- ============================================================================