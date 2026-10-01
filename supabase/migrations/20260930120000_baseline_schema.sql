-- ============================================================================
-- CommonGoods: Baseline Schema (single source of truth)
-- Generated from live database on 2026-09-30
-- Replaces all previous migration history
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Enable extensions
-- ----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_cron";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "btree_gin";

-- ----------------------------------------------------------------------------
-- 2. Custom types / enums
-- ----------------------------------------------------------------------------
CREATE TYPE public.delivery_stage AS ENUM (
  'pending', 'offered', 'claimed', 'en_route', 'in_progress', 'completed', 'cancelled'
);

-- ----------------------------------------------------------------------------
-- 3. Core tables (must exist before private functions that reference them)
-- ----------------------------------------------------------------------------

-- profiles (extends auth.users) - MUST BE FIRST since private functions reference it
CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('customer', 'driver', 'partner', 'admin')) DEFAULT 'customer',
  full_name text,
  phone text,
  is_admin boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  cancellation_rate numeric(5,4),
  historical_tip_ratio numeric(5,4),
  lifetime_deliveries integer,
  priority_score numeric(10,4)
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- 4. Private schema functions (now that profiles exists)
-- ----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS private;

CREATE OR REPLACE FUNCTION private.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND is_admin = true
  );
$$;

CREATE OR REPLACE FUNCTION private.current_role_is(p_target_role text)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT role = p_target_role FROM public.profiles WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION private.get_my_role()
RETURNS text
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT role FROM public.profiles WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION private.check_user_role(p_required_role text)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT role = p_required_role FROM public.profiles WHERE id = auth.uid();
$$;

-- ----------------------------------------------------------------------------
-- 5. Policies and triggers for profiles
-- ----------------------------------------------------------------------------

CREATE POLICY "profiles_select_own" ON public.profiles
  FOR SELECT USING (id = auth.uid() OR private.is_admin());

CREATE POLICY "profiles_insert_own" ON public.profiles
  FOR INSERT WITH CHECK (id = auth.uid());

CREATE POLICY "profiles_update_own" ON public.profiles
  FOR UPDATE USING (id = auth.uid()) WITH CHECK (id = auth.uid());

-- triggers to protect is_admin and role
CREATE OR REPLACE FUNCTION private.prevent_admin_role_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF OLD.is_admin IS DISTINCT FROM NEW.is_admin THEN
    RAISE EXCEPTION 'is_admin cannot be changed directly';
  END IF;
  IF OLD.role IS DISTINCT FROM NEW.role THEN
    RAISE EXCEPTION 'role cannot be changed directly';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER profiles_protect_admin_role
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION private.prevent_admin_role_change();

GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated, service_role;

-- partners
CREATE TABLE public.partners (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id uuid UNIQUE REFERENCES public.profiles(id) ON DELETE SET NULL,
  business_name text NOT NULL,
  address text NOT NULL,
  lat double precision,
  lng double precision,
  approved boolean NOT NULL DEFAULT false,
  average_prep_time_minutes integer,
  founding_merchant boolean NOT NULL DEFAULT false,
  joined_during_pilot boolean NOT NULL DEFAULT false,
  merchant_priority_score numeric(10,4),
  onboarding_fee_paid boolean NOT NULL DEFAULT false,
  pickup_notes text,
  pos_system text,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.partners ENABLE ROW LEVEL SECURITY;

CREATE POLICY "partners_select_approved" ON public.partners
  FOR SELECT USING (approved = true OR profile_id = auth.uid() OR private.is_admin());

CREATE POLICY "partners_insert_own" ON public.partners
  FOR INSERT WITH CHECK (profile_id = auth.uid());

CREATE POLICY "partners_update_own" ON public.partners
  FOR UPDATE USING (profile_id = auth.uid()) WITH CHECK (profile_id = auth.uid());

GRANT SELECT ON public.partners TO authenticated, service_role;
GRANT INSERT, UPDATE ON public.partners TO authenticated, service_role;

-- drivers
CREATE TABLE public.drivers (
  id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  approved boolean,
  is_online boolean NOT NULL DEFAULT false,
  vehicle_type text,
  updated_at timestamptz
);

ALTER TABLE public.drivers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "drivers_select_own" ON public.drivers
  FOR SELECT USING (id = auth.uid() OR private.is_admin());

CREATE POLICY "drivers_update_own" ON public.drivers
  FOR UPDATE USING (id = auth.uid()) WITH CHECK (id = auth.uid());

-- freeze trigger for approved
CREATE OR REPLACE FUNCTION private.freeze_drivers_approved()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF OLD.approved IS DISTINCT FROM NEW.approved THEN
    RAISE EXCEPTION 'drivers.approved cannot be changed directly';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER drivers_freeze_approved
  BEFORE UPDATE ON public.drivers
  FOR EACH ROW EXECUTE FUNCTION private.freeze_drivers_approved();

GRANT SELECT, UPDATE ON public.drivers TO authenticated, service_role;

-- partner_applications
CREATE TABLE public.partner_applications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_name text NOT NULL,
  address text NOT NULL,
  contact_name text NOT NULL,
  contact_email text NOT NULL,
  contact_phone text NOT NULL,
  pos_system text,
  notes text,
  status text NOT NULL CHECK (status IN ('pending', 'approved', 'rejected')) DEFAULT 'pending',
  submitted_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.partner_applications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "partner_applications_insert_public" ON public.partner_applications
  FOR INSERT WITH CHECK (status = 'pending');

CREATE POLICY "partner_applications_select_admin" ON public.partner_applications
  FOR SELECT USING (private.is_admin());

GRANT INSERT ON public.partner_applications TO anon, authenticated;
GRANT SELECT ON public.partner_applications TO service_role;

-- menu_items
CREATE TABLE public.menu_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id uuid REFERENCES public.partners(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text,
  price numeric(10,2) NOT NULL,
  category text,
  active boolean NOT NULL DEFAULT true,
  photo_url text,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.menu_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "menu_items_select_active" ON public.menu_items
  FOR SELECT USING (active = true);

CREATE POLICY "menu_items_manage_partner" ON public.menu_items
  FOR ALL USING (
    partner_id IN (SELECT id FROM public.partners WHERE profile_id = auth.uid())
    OR private.is_admin()
  ) WITH CHECK (
    partner_id IN (SELECT id FROM public.partners WHERE profile_id = auth.uid())
    OR private.is_admin()
  );

GRANT SELECT ON public.menu_items TO authenticated, service_role;
GRANT INSERT, UPDATE, DELETE ON public.menu_items TO authenticated, service_role;

-- menu_item_options
CREATE TABLE public.menu_item_options (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  menu_item_id uuid REFERENCES public.menu_items(id) ON DELETE CASCADE,
  name text NOT NULL,
  price_modifier numeric(10,2),
  is_available boolean NOT NULL DEFAULT true
);

ALTER TABLE public.menu_item_options ENABLE ROW LEVEL SECURITY;

CREATE POLICY "menu_item_options_select" ON public.menu_item_options
  FOR SELECT USING (
    menu_item_id IN (SELECT id FROM public.menu_items WHERE active = true)
  );

CREATE POLICY "menu_item_options_manage_partner" ON public.menu_item_options
  FOR ALL USING (
    menu_item_id IN (
      SELECT id FROM public.menu_items
      WHERE partner_id IN (SELECT id FROM public.partners WHERE profile_id = auth.uid())
    ) OR private.is_admin()
  ) WITH CHECK (
    menu_item_id IN (
      SELECT id FROM public.menu_items
      WHERE partner_id IN (SELECT id FROM public.partners WHERE profile_id = auth.uid())
    ) OR private.is_admin()
  );

GRANT SELECT ON public.menu_item_options TO authenticated, service_role;
GRANT INSERT, UPDATE, DELETE ON public.menu_item_options TO authenticated, service_role;

-- deliveries
CREATE TABLE public.deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  driver_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  partner_id uuid REFERENCES public.partners(id) ON DELETE SET NULL,
  category text NOT NULL,
  pickup_address text NOT NULL,
  pickup_lat double precision NOT NULL,
  pickup_lng double precision NOT NULL,
  dropoff_address text NOT NULL,
  dropoff_lat double precision NOT NULL,
  dropoff_lng double precision NOT NULL,
  distance_miles numeric(10,2),
  estimated_duration_minutes integer,
  zone_assigned integer,
  fee_charged numeric(10,2),
  driver_payout numeric(10,2),
  platform_cut numeric(10,2),
  base_fee_applied numeric(10,2),
  per_mile_rate_applied numeric(10,2),
  surge_multiplier_applied numeric(5,4),
  dynamic_boost_incentive numeric(10,2),
  status public.delivery_stage NOT NULL DEFAULT 'pending',
  cancel_stage text,
  cancel_reason_code text,
  cancellation_reason_code text,
  cancelled_by text,
  compensation_amount numeric(10,2),
  tip_amount numeric(10,2),
  route_polyline text,
  transport_type text,
  requested_at timestamptz NOT NULL DEFAULT now(),
  claimed_at timestamptz,
  offered_at timestamptz,
  en_route_at timestamptz,
  arrived_pickup_at timestamptz,
  picked_up_at timestamptz,
  ready_for_pickup_at timestamptz,
  arrived_dropoff_at timestamptz,
  delivered_at timestamptz,
  actual_duration_minutes integer,
  driver_arrived_at_pickup_at timestamptz,
  driver_arrived_at_dropoff_at timestamptz,
  notes text
);

ALTER TABLE public.deliveries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "deliveries_select_participant" ON public.deliveries
  FOR SELECT USING (
    customer_id = auth.uid()
    OR driver_id = auth.uid()
    OR partner_id IN (SELECT id FROM public.partners WHERE profile_id = auth.uid())
    OR private.is_admin()
  );

CREATE POLICY "deliveries_insert_service" ON public.deliveries
  FOR INSERT TO service_role WITH CHECK (true);

CREATE POLICY "deliveries_update_service" ON public.deliveries
  FOR UPDATE TO service_role USING (true);

GRANT SELECT ON public.deliveries TO authenticated, service_role;
GRANT INSERT, UPDATE ON public.deliveries TO service_role;

-- delivery_items
CREATE TABLE public.delivery_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id uuid REFERENCES public.deliveries(id) ON DELETE CASCADE,
  menu_item_id uuid REFERENCES public.menu_items(id) ON DELETE SET NULL,
  quantity integer NOT NULL DEFAULT 1,
  price_at_purchase numeric(10,2) NOT NULL
);

ALTER TABLE public.delivery_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "delivery_items_select_participant" ON public.delivery_items
  FOR SELECT USING (
    delivery_id IN (
      SELECT id FROM public.deliveries
      WHERE customer_id = auth.uid()
         OR driver_id = auth.uid()
         OR partner_id IN (SELECT id FROM public.partners WHERE profile_id = auth.uid())
    ) OR private.is_admin()
  );

GRANT SELECT ON public.delivery_items TO authenticated, service_role;
GRANT INSERT ON public.delivery_items TO service_role;

-- delivery_item_options
CREATE TABLE public.delivery_item_options (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_item_id uuid REFERENCES public.delivery_items(id) ON DELETE CASCADE,
  menu_item_option_id uuid REFERENCES public.menu_item_options(id) ON DELETE SET NULL,
  price_at_purchase numeric(10,2) NOT NULL
);

ALTER TABLE public.delivery_item_options ENABLE ROW LEVEL SECURITY;

CREATE POLICY "delivery_item_options_select_participant" ON public.delivery_item_options
  FOR SELECT USING (
    delivery_item_id IN (
      SELECT id FROM public.delivery_items
      WHERE delivery_id IN (
        SELECT id FROM public.deliveries
        WHERE customer_id = auth.uid()
           OR driver_id = auth.uid()
           OR partner_id IN (SELECT id FROM public.partners WHERE profile_id = auth.uid())
      )
    ) OR private.is_admin()
  );

GRANT SELECT ON public.delivery_item_options TO authenticated, service_role;
GRANT INSERT ON public.delivery_item_options TO service_role;

-- delivery_messages
CREATE TABLE public.delivery_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id uuid REFERENCES public.deliveries(id) ON DELETE CASCADE,
  sender_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  message_text text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.delivery_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "delivery_messages_select_participant" ON public.delivery_messages
  FOR SELECT USING (
    delivery_id IN (
      SELECT id FROM public.deliveries
      WHERE customer_id = auth.uid()
         OR driver_id = auth.uid()
         OR partner_id IN (SELECT id FROM public.partners WHERE profile_id = auth.uid())
    ) OR private.is_admin()
  );

CREATE POLICY "delivery_messages_insert_participant" ON public.delivery_messages
  FOR INSERT WITH CHECK (
    sender_id = auth.uid()
    AND delivery_id IN (
      SELECT id FROM public.deliveries
      WHERE customer_id = auth.uid()
         OR driver_id = auth.uid()
    )
  );

GRANT SELECT, INSERT ON public.delivery_messages TO authenticated, service_role;

-- delivery_status_history
CREATE TABLE public.delivery_status_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id uuid REFERENCES public.deliveries(id) ON DELETE CASCADE,
  actor_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  status public.delivery_stage NOT NULL,
  lat double precision,
  lng double precision,
  changed_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.delivery_status_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "delivery_status_history_select_participant" ON public.delivery_status_history
  FOR SELECT USING (
    delivery_id IN (
      SELECT id FROM public.deliveries
      WHERE customer_id = auth.uid()
         OR driver_id = auth.uid()
         OR partner_id IN (SELECT id FROM public.partners WHERE profile_id = auth.uid())
    ) OR private.is_admin()
  );

GRANT SELECT ON public.delivery_status_history TO authenticated, service_role;
GRANT INSERT ON public.delivery_status_history TO service_role;

-- ----------------------------------------------------------------------------
-- 5. Pricing & Configuration
-- ----------------------------------------------------------------------------

-- config_registry
CREATE TABLE public.config_registry (
  key text PRIMARY KEY,
  category text NOT NULL,
  type text NOT NULL CHECK (type IN ('string', 'number', 'boolean', 'json')),
  default_value jsonb NOT NULL,
  min_value jsonb,
  max_value jsonb,
  json_schema jsonb,
  unit text,
  description text NOT NULL,
  requires_approval boolean NOT NULL DEFAULT false,
  risk_level text NOT NULL CHECK (risk_level IN ('low', 'medium', 'high')) DEFAULT 'low',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.config_registry ENABLE ROW LEVEL SECURITY;

CREATE POLICY "config_registry_select_authenticated" ON public.config_registry
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "config_registry_modify_admin" ON public.config_registry
  FOR ALL USING (private.is_admin()) WITH CHECK (private.is_admin());

GRANT SELECT ON public.config_registry TO authenticated, service_role;
GRANT INSERT, UPDATE, DELETE ON public.config_registry TO service_role;

-- config_values
CREATE TABLE public.config_values (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key text NOT NULL REFERENCES public.config_registry(key),
  value jsonb NOT NULL,
  scope_type text NOT NULL CHECK (scope_type IN ('global', 'partner', 'zone')),
  scope_id uuid,
  status text NOT NULL CHECK (status IN ('pending', 'approved', 'rejected')) DEFAULT 'pending',
  effective_from timestamptz NOT NULL DEFAULT now(),
  effective_to timestamptz,
  created_by uuid REFERENCES public.profiles(id),
  approved_by uuid REFERENCES public.profiles(id),
  reason text,
  governance_proposal_id uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_config_values_key ON public.config_values(key);
CREATE INDEX idx_config_values_scope ON public.config_values(scope_type, scope_id);

ALTER TABLE public.config_values ENABLE ROW LEVEL SECURITY;

CREATE POLICY "config_values_select_authenticated" ON public.config_values
  FOR SELECT TO authenticated USING (status = 'approved');

CREATE POLICY "config_values_modify_admin" ON public.config_values
  FOR ALL USING (private.is_admin()) WITH CHECK (private.is_admin());

GRANT SELECT ON public.config_values TO authenticated, service_role;
GRANT INSERT, UPDATE, DELETE ON public.config_values TO service_role;

-- config_snapshots
CREATE TABLE public.config_snapshots (
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

-- config_audit
CREATE TABLE public.config_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key text NOT NULL,
  old_value jsonb,
  new_value jsonb,
  changed_by uuid REFERENCES public.profiles(id),
  scope_id uuid,
  scope_type text,
  reason text,
  ip_address inet,
  user_agent text,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.config_audit ENABLE ROW LEVEL SECURITY;

CREATE POLICY "config_audit_select_admin" ON public.config_audit
  FOR SELECT USING (private.is_admin());

GRANT INSERT ON public.config_audit TO service_role;

-- config_constraints
CREATE TABLE public.config_constraints (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  expression text NOT NULL,
  message text NOT NULL,
  severity text NOT NULL CHECK (severity IN ('warning', 'error')) DEFAULT 'error',
  created_at timestamptz NOT NULL DEFAULT now(),
  is_active boolean NOT NULL DEFAULT true
);

ALTER TABLE public.config_constraints ENABLE ROW LEVEL SECURITY;

CREATE POLICY "config_constraints_select_authenticated" ON public.config_constraints
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "config_constraints_modify_admin" ON public.config_constraints
  FOR ALL USING (private.is_admin()) WITH CHECK (private.is_admin());

GRANT SELECT ON public.config_constraints TO authenticated, service_role;
GRANT INSERT, UPDATE, DELETE ON public.config_constraints TO service_role;

-- algorithm_versions
CREATE TABLE public.algorithm_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind text NOT NULL CHECK (kind IN ('pricing', 'dispatch', 'pay')),
  name text NOT NULL,
  version text NOT NULL,
  status text NOT NULL CHECK (status IN ('draft', 'active', 'deprecated', 'archived')) DEFAULT 'draft',
  code_ref text NOT NULL,
  description text,
  config_schema jsonb NOT NULL DEFAULT '{}',
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

-- quotes
CREATE TABLE public.quotes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id uuid REFERENCES public.deliveries(id) ON DELETE SET NULL,
  customer_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  partner_id uuid REFERENCES public.partners(id) ON DELETE SET NULL,
  pickup_lat double precision NOT NULL,
  pickup_lng double precision NOT NULL,
  dropoff_lat double precision NOT NULL,
  dropoff_lng double precision NOT NULL,
  distance_miles double precision NOT NULL,
  estimated_duration_minutes integer,
  zone_assigned integer NOT NULL,
  customer_total numeric(10,2) NOT NULL,
  components jsonb NOT NULL DEFAULT '[]',
  platform_cut numeric(10,2) NOT NULL,
  driver_payout numeric(10,2) NOT NULL,
  pricing_algorithm_version uuid NOT NULL REFERENCES public.algorithm_versions(id),
  config_snapshot_id uuid NOT NULL REFERENCES public.config_snapshots(id),
  status text NOT NULL CHECK (status IN ('generated', 'accepted', 'expired', 'cancelled')) DEFAULT 'generated',
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '15 minutes'),
  created_at timestamptz NOT NULL DEFAULT now(),
  accepted_at timestamptz
);

CREATE INDEX idx_quotes_customer ON public.quotes (customer_id);
CREATE INDEX idx_quotes_delivery ON public.quotes (delivery_id);
CREATE INDEX idx_quotes_status ON public.quotes (status);
CREATE INDEX idx_quotes_algorithm ON public.quotes (pricing_algorithm_version);

ALTER TABLE public.quotes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "quotes_select_customer" ON public.quotes
  FOR SELECT USING (customer_id = auth.uid() OR private.is_admin());

CREATE POLICY "quotes_insert_service" ON public.quotes
  FOR INSERT TO service_role WITH CHECK (true);

CREATE POLICY "quotes_update_service" ON public.quotes
  FOR UPDATE TO service_role USING (true);

GRANT SELECT ON public.quotes TO authenticated, service_role;
GRANT INSERT, UPDATE ON public.quotes TO service_role;

-- pricing_decisions
CREATE TABLE public.pricing_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id uuid NOT NULL UNIQUE REFERENCES public.deliveries(id) ON DELETE CASCADE,
  actual_distance_miles double precision,
  actual_duration_minutes integer,
  zone_assigned integer NOT NULL,
  customer_total numeric(10,2) NOT NULL,
  components jsonb NOT NULL DEFAULT '[]',
  platform_cut numeric(10,2) NOT NULL,
  driver_payout numeric(10,2) NOT NULL,
  adjustments jsonb DEFAULT '[]',
  pricing_algorithm_version uuid NOT NULL REFERENCES public.algorithm_versions(id),
  config_snapshot_id uuid NOT NULL REFERENCES public.config_snapshots(id),
  inputs jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_pricing_decisions_delivery ON public.pricing_decisions (delivery_id);
CREATE INDEX idx_pricing_decisions_algorithm ON public.pricing_decisions (pricing_algorithm_version);

ALTER TABLE public.pricing_decisions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pricing_decisions_select_participant" ON public.pricing_decisions
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.deliveries d
      WHERE d.id = pricing_decisions.delivery_id
        AND (d.customer_id = auth.uid() OR d.driver_id = auth.uid()
           OR d.partner_id IN (SELECT id FROM public.partners WHERE profile_id = auth.uid()))
    ) OR private.is_admin()
  );

CREATE POLICY "pricing_decisions_insert_service" ON public.pricing_decisions
  FOR INSERT TO service_role WITH CHECK (true);

GRANT SELECT ON public.pricing_decisions TO authenticated, service_role;
GRANT INSERT ON public.pricing_decisions TO service_role;

-- dispatch_decisions
CREATE TABLE public.dispatch_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id uuid NOT NULL REFERENCES public.deliveries(id) ON DELETE CASCADE,
  candidates jsonb NOT NULL DEFAULT '[]',
  chosen_driver_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  reason text,
  dispatch_algorithm_version uuid NOT NULL REFERENCES public.algorithm_versions(id),
  config_snapshot_id uuid NOT NULL REFERENCES public.config_snapshots(id),
  inputs jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_dispatch_decisions_delivery ON public.dispatch_decisions (delivery_id);
CREATE INDEX idx_dispatch_decisions_algorithm ON public.dispatch_decisions (dispatch_algorithm_version);

ALTER TABLE public.dispatch_decisions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "dispatch_decisions_select_participant" ON public.dispatch_decisions
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.deliveries d
      WHERE d.id = dispatch_decisions.delivery_id
        AND (d.customer_id = auth.uid() OR d.driver_id = auth.uid()
           OR d.partner_id IN (SELECT id FROM public.partners WHERE profile_id = auth.uid()))
    ) OR private.is_admin()
  );

CREATE POLICY "dispatch_decisions_insert_service" ON public.dispatch_decisions
  FOR INSERT TO service_role WITH CHECK (true);

GRANT SELECT ON public.dispatch_decisions TO authenticated, service_role;
GRANT INSERT ON public.dispatch_decisions TO service_role;

-- dispatch_offers
CREATE TABLE public.dispatch_offers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id uuid NOT NULL REFERENCES public.deliveries(id) ON DELETE CASCADE,
  driver_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  offered_at timestamptz NOT NULL DEFAULT now(),
  viewed_at timestamptz,
  responded_at timestamptz,
  response text CHECK (response IN ('accepted', 'declined', 'expired')),
  decline_reason text,
  offered_pay numeric(10,2) NOT NULL,
  driver_distance_to_pickup_miles double precision,
  driver_rating numeric(3,2),
  driver_acceptance_rate numeric(5,4),
  driver_idle_time_minutes integer,
  rank integer NOT NULL,
  score numeric(10,6) NOT NULL,
  alternatives_shown integer DEFAULT 0,
  dispatch_algorithm_version uuid NOT NULL REFERENCES public.algorithm_versions(id),
  config_snapshot_id uuid NOT NULL REFERENCES public.config_snapshots(id),
  latency_ms integer,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_dispatch_offers_delivery ON public.dispatch_offers (delivery_id);
CREATE INDEX idx_dispatch_offers_driver ON public.dispatch_offers (driver_id);
CREATE INDEX idx_dispatch_offers_response ON public.dispatch_offers (response);

ALTER TABLE public.dispatch_offers ENABLE ROW LEVEL SECURITY.

CREATE POLICY "dispatch_offers_select_driver" ON public.dispatch_offers
  FOR SELECT USING (driver_id = auth.uid() OR private.is_admin());

CREATE POLICY "dispatch_offers_select_partner" ON public.dispatch_offers
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.deliveries d
      WHERE d.id = dispatch_offers.delivery_id
        AND d.partner_id IN (SELECT id FROM public.partners WHERE profile_id = auth.uid())
    )
  );

CREATE POLICY "dispatch_offers_insert_service" ON public.dispatch_offers
  FOR INSERT TO service_role WITH CHECK (true);

GRANT SELECT ON public.dispatch_offers TO authenticated, service_role;
GRANT INSERT ON public.dispatch_offers TO service_role;

-- ----------------------------------------------------------------------------
-- 6. Earnings & Financial
-- ----------------------------------------------------------------------------

CREATE TABLE public.earnings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  delivery_id uuid REFERENCES public.deliveries(id) ON DELETE SET NULL,
  amount numeric(10,2) NOT NULL,
  platform_cut numeric(10,2) NOT NULL,
  paid_out boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.earnings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "earnings_select_driver" ON public.earnings
  FOR SELECT USING (driver_id = auth.uid() OR private.is_admin());

CREATE POLICY "earnings_insert_service" ON public.earnings
  FOR INSERT TO service_role WITH CHECK (true);

GRANT SELECT ON public.earnings TO authenticated, service_role;
GRANT INSERT ON public.earnings TO service_role;

-- tax_mileage_rates
CREATE TABLE public.tax_mileage_rates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_cents integer NOT NULL,
  charity_cents integer,
  medical_cents integer,
  notes text,
  source_url text,
  effective_from date NOT NULL,
  effective_to date,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.tax_mileage_rates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tax_mileage_rates_select_authenticated" ON public.tax_mileage_rates
  FOR SELECT TO authenticated USING (true);

GRANT SELECT ON public.tax_mileage_rates TO authenticated, service_role;
GRANT INSERT, UPDATE ON public.tax_mileage_rates TO service_role;

-- performance_metrics
CREATE TABLE public.performance_metrics (
  delivery_id uuid PRIMARY KEY REFERENCES public.deliveries(id) ON DELETE CASCADE,
  estimated_prep_minutes integer,
  actual_prep_minutes integer,
  estimated_transit_minutes integer,
  actual_transit_minutes integer,
  driver_wait_at_merchant_minutes integer,
  prep_delay_minutes integer,
  transit_delay_minutes integer,
  had_interaction_issues boolean
);

ALTER TABLE public.performance_metrics ENABLE ROW LEVEL SECURITY;

CREATE POLICY "performance_metrics_select_participant" ON public.performance_metrics
  FOR SELECT USING (
    delivery_id IN (
      SELECT id FROM public.deliveries
      WHERE customer_id = auth.uid()
         OR driver_id = auth.uid()
         OR partner_id IN (SELECT id FROM public.partners WHERE profile_id = auth.uid())
    ) OR private.is_admin()
  );

GRANT SELECT ON public.performance_metrics TO authenticated, service_role;
GRANT INSERT, UPDATE ON public.performance_metrics TO service_role;

-- ----------------------------------------------------------------------------
-- 7. Referral System
-- ----------------------------------------------------------------------------

CREATE TABLE public.referral_codes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  role text NOT NULL CHECK (role IN ('customer', 'driver', 'partner')),
  label text,
  is_active boolean NOT NULL DEFAULT true,
  used_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  used_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.referral_codes ENABLE ROW LEVEL SECURITY.

CREATE POLICY "referral_codes_select_authenticated" ON public.referral_codes
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "referral_codes_insert_admin" ON public.referral_codes
  FOR INSERT USING (private.is_admin()) WITH CHECK (private.is_admin());

-- freeze trigger
CREATE OR REPLACE FUNCTION private.freeze_referral_codes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF OLD.is_active IS DISTINCT FROM NEW.is_active
     OR OLD.used_by IS DISTINCT FROM NEW.used_by
     OR OLD.used_at IS DISTINCT FROM NEW.used_at THEN
    RAISE EXCEPTION 'referral_codes trust columns cannot be changed directly';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER referral_codes_freeze
  BEFORE UPDATE ON public.referral_codes
  FOR EACH ROW EXECUTE FUNCTION private.freeze_referral_codes();

GRANT SELECT ON public.referral_codes TO authenticated, service_role;
GRANT INSERT, UPDATE ON public.referral_codes TO service_role;

CREATE TABLE public.referral_redemptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  referral_code_id uuid REFERENCES public.referral_codes(id) ON DELETE CASCADE,
  redeemed_by uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
  redeemed_at timestamptz NOT NULL DEFAULT now(),
  role text NOT NULL CHECK (role IN ('customer', 'driver', 'partner'))
);

ALTER TABLE public.referral_redemptions ENABLE ROW LEVEL SECURITY.

CREATE POLICY "referral_redemptions_select_own" ON public.referral_redemptions
  FOR SELECT USING (redeemed_by = auth.uid() OR private.is_admin());

GRANT SELECT ON public.referral_redemptions TO authenticated, service_role;
GRANT INSERT ON public.referral_redemptions TO service_role;

-- ----------------------------------------------------------------------------
-- 8. Events & Analytics
-- ----------------------------------------------------------------------------

CREATE TABLE public.event_catalog (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  category text NOT NULL,
  description text,
  json_schema jsonb,
  retention_days integer NOT NULL DEFAULT 90,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.event_catalog ENABLE ROW LEVEL SECURITY.

CREATE POLICY "event_catalog_select_authenticated" ON public.event_catalog
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "event_catalog_modify_admin" ON public.event_catalog
  FOR ALL USING (private.is_admin()) WITH CHECK (private.is_admin());

GRANT SELECT ON public.event_catalog TO authenticated, service_role;
GRANT INSERT, UPDATE ON public.event_catalog TO service_role;

-- partitioned events table
CREATE TABLE public.events (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  occurred_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL,
  actor_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  actor_type text NOT NULL,
  entity_type text,
  entity_id uuid,
  name text NOT NULL,
  props jsonb,
  config_snapshot_id uuid REFERENCES public.config_snapshots(id),
  app_version text,
  device_id uuid,
  experiment_assignments jsonb,
  idempotency_key text,
  session_id uuid,
  os text
) PARTITION BY RANGE (occurred_at);

ALTER TABLE public.events ENABLE ROW LEVEL SECURITY.

CREATE POLICY "events_select_admin" ON public.events
  FOR SELECT USING (private.is_admin());

CREATE POLICY "events_insert_service" ON public.events
  FOR INSERT TO service_role WITH CHECK (true);

GRANT SELECT ON public.events TO authenticated, service_role;
GRANT INSERT ON public.events TO service_role;

-- monthly partitions (example for 2026-09 through 2027-09)
CREATE TABLE public.events_2026_09 PARTITION OF public.events
  FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE public.events_2026_10 PARTITION OF public.events
  FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE public.events_2026_11 PARTITION OF public.events
  FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');
CREATE TABLE public.events_2026_12 PARTITION OF public.events
  FOR VALUES FROM ('2026-12-01') TO ('2027-01-01');
CREATE TABLE public.events_2027_01 PARTITION OF public.events
  FOR VALUES FROM ('2027-01-01') TO ('2027-02-01');
CREATE TABLE public.events_2027_02 PARTITION OF public.events
  FOR VALUES FROM ('2027-02-01') TO ('2027-03-01');
CREATE TABLE public.events_2027_03 PARTITION OF public.events
  FOR VALUES FROM ('2027-03-01') TO ('2027-04-01');
CREATE TABLE public.events_2027_04 PARTITION OF public.events
  FOR VALUES FROM ('2027-04-01') TO ('2027-05-01');
CREATE TABLE public.events_2027_05 PARTITION OF public.events
  FOR VALUES FROM ('2027-05-01') TO ('2027-06-01');
CREATE TABLE public.events_2027_06 PARTITION OF public.events
  FOR VALUES FROM ('2027-06-01') TO ('2027-07-01');
CREATE TABLE public.events_2027_07 PARTITION OF public.events
  FOR VALUES FROM ('2027-07-01') TO ('2027-08-01');
CREATE TABLE public.events_2027_08 PARTITION OF public.events
  FOR VALUES FROM ('2027-08-01') TO ('2027-09-01');
CREATE TABLE public.events_2027_09 PARTITION OF public.events
  FOR VALUES FROM ('2027-09-01') TO ('2027-10-01');

-- default partition
CREATE TABLE public.events_default PARTITION OF public.events DEFAULT;

-- ----------------------------------------------------------------------------
-- 9. Ratings & Reviews
-- ----------------------------------------------------------------------------

CREATE TABLE public.ratings_and_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id uuid REFERENCES public.deliveries(id) ON DELETE SET NULL,
  reviewer_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  reviewee_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  reviewee_type text NOT NULL CHECK (reviewee_type IN ('driver', 'partner', 'customer')),
  rating_stars integer NOT NULL CHECK (rating_stars BETWEEN 1 AND 5),
  written_review text,
  tags text[],
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.ratings_and_reviews ENABLE ROW LEVEL SECURITY.

CREATE POLICY "ratings_select_participant" ON public.ratings_and_reviews
  FOR SELECT USING (
    reviewer_id = auth.uid()
    OR reviewee_id = auth.uid()
    OR delivery_id IN (
      SELECT id FROM public.deliveries
      WHERE customer_id = auth.uid()
         OR driver_id = auth.uid()
         OR partner_id IN (SELECT id FROM public.partners WHERE profile_id = auth.uid())
    ) OR private.is_admin()
  );

CREATE POLICY "ratings_insert_reviewer" ON public.ratings_and_reviews
  FOR INSERT WITH CHECK (reviewer_id = auth.uid());

GRANT SELECT ON public.ratings_and_reviews TO authenticated, service_role;
GRANT INSERT ON public.ratings_and_reviews TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 10. Route Points
-- ----------------------------------------------------------------------------

CREATE TABLE public.route_points (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id uuid REFERENCES public.deliveries(id) ON DELETE CASCADE,
  lat double precision NOT NULL,
  lng double precision NOT NULL,
  driver_speed double precision,
  recorded_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.route_points ENABLE ROW LEVEL SECURITY.

CREATE POLICY "route_points_select_driver" ON public.route_points
  FOR SELECT USING (
    delivery_id IN (
      SELECT id FROM public.deliveries WHERE driver_id = auth.uid()
    ) OR private.is_admin()
  );

GRANT SELECT ON public.route_points TO authenticated, service_role;
GRANT INSERT ON public.route_points TO service_role;

-- ----------------------------------------------------------------------------
-- 11. Helper Functions
-- ----------------------------------------------------------------------------

-- resolve_config
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
  v_reg RECORD;
  v_val jsonb;
BEGIN
  SELECT * INTO v_reg FROM public.config_registry WHERE key = p_key;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Config key % not found in registry', p_key;
  END IF;

  SELECT value INTO v_val
  FROM public.config_values
  WHERE key = p_key
    AND status = 'approved'
    AND effective_from <= p_at
    AND (effective_to IS NULL OR effective_to > p_at)
    AND (
      (scope_type = 'global' AND scope_id IS NULL)
      OR (scope_type = 'partner' AND scope_id = COALESCE(p_ctx->>'partner_id', '')::uuid)
      OR (scope_type = 'zone' AND scope_id = COALESCE(p_ctx->>'zone', '')::uuid)
    )
  ORDER BY
    CASE scope_type WHEN 'global' THEN 3 WHEN 'partner' THEN 2 WHEN 'zone' THEN 1 END DESC,
    effective_from DESC
  LIMIT 1;

  IF v_val IS NULL THEN
    v_val := v_reg.default_value;
  END IF;

  RETURN v_val;
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_config(text, jsonb, timestamptz) TO authenticated, service_role;

-- resolve_all_config
CREATE OR REPLACE FUNCTION public.resolve_all_config(
  p_ctx jsonb DEFAULT '{}'::jsonb,
  p_at timestamptz DEFAULT now()
)
RETURNS SETOF record
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_row RECORD;
  v_resolved jsonb := '{}'::jsonb;
BEGIN
  FOR v_row IN SELECT key FROM public.config_registry LOOP
    v_resolved := v_resolved || jsonb_build_object(v_row.key, public.resolve_config(v_row.key, p_ctx, p_at));
  END LOOP;
  RETURN QUERY SELECT v_resolved AS config, encode(sha256(v_resolved::text::bytea), 'hex') AS hash;
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_all_config(jsonb, timestamptz) TO authenticated, service_role;

-- get_mileage_rate
CREATE OR REPLACE FUNCTION public.get_mileage_rate(p_date date DEFAULT CURRENT_DATE)
RETURNS TABLE (
  business_cents integer,
  charity_cents integer,
  medical_cents integer
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT business_cents, COALESCE(charity_cents, 0), COALESCE(medical_cents, 0)
  FROM public.tax_mileage_rates
  WHERE effective_from <= p_date
    AND (effective_to IS NULL OR effective_to >= p_date)
  ORDER BY effective_from DESC
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_mileage_rate(date) TO authenticated, service_role;

-- is_peak_hour
CREATE OR REPLACE FUNCTION public.is_peak_hour(p_peak_hours jsonb, p_at timestamptz DEFAULT now())
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_day int;
  v_time text;
  v_period jsonb;
BEGIN
  v_day := EXTRACT(DOW FROM p_at)::int; -- 0 = Sunday
  v_time := TO_CHAR(p_at, 'HH24:MI');

  IF p_peak_hours IS NULL THEN
    RETURN false;
  END IF;

  FOR v_period IN SELECT * FROM jsonb_array_elements(p_peak_hours) LOOP
    IF v_day = ANY((v_period->'days')::int[]) THEN
      IF v_time >= v_period->>'start' AND v_time <= v_period->>'end' THEN
        RETURN true;
      END IF;
    END IF;
  END LOOP;

  RETURN false;
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_peak_hour(jsonb, timestamptz) TO authenticated, service_role;

-- zone_pricing
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
  SELECT config INTO v_config FROM public.resolve_all_config('{}'::jsonb, now());

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

GRANT EXECUTE ON FUNCTION public.zone_pricing(double precision) TO authenticated, service_role;

-- get_active_algorithm_version
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

-- validate_config_constraints
CREATE OR REPLACE FUNCTION public.validate_config_constraints(p_proposed jsonb)
RETURNS TABLE (
  constraint_name text,
  message text,
  passed boolean
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_row RECORD;
  v_passed boolean;
  v_msg text;
BEGIN
  FOR v_row IN SELECT name, expression, message FROM public.config_constraints WHERE is_active LOOP
    BEGIN
      EXECUTE format('SELECT (%s)::boolean', replace(v_row.expression, 'proposed', 'p_proposed'))
        INTO v_passed USING p_proposed;
      IF v_passed THEN
        v_msg := 'OK';
      ELSE
        v_msg := v_row.message;
      END IF;
      RETURN QUERY SELECT v_row.name, v_msg, v_passed;
    EXCEPTION WHEN OTHERS THEN
      RETURN QUERY SELECT v_row.name, 'Constraint evaluation error: ' || SQLERRM, false;
    END;
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.validate_config_constraints(jsonb) TO service_role;

-- preview_config_impact
CREATE OR REPLACE FUNCTION public.preview_config_impact(
  p_days_lookback integer DEFAULT 30,
  p_proposed jsonb
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
  v_current jsonb;
  v_metric text;
  v_curr_val numeric;
  v_prop_val numeric;
BEGIN
  SELECT config INTO v_current FROM public.resolve_all_config('{}'::jsonb, now());

  -- Example metrics - expand as needed
  FOR v_metric IN SELECT * FROM jsonb_object_keys(p_proposed) LOOP
    v_curr_val := (v_current->>v_metric)::numeric;
    v_prop_val := (p_proposed->>v_metric)::numeric;

    RETURN QUERY SELECT
      v_metric,
      v_curr_val,
      v_prop_val,
      v_prop_val - v_curr_val,
      CASE WHEN v_curr_val != 0 THEN ((v_prop_val - v_curr_val) / v_curr_val) * 100 ELSE NULL END;
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.preview_config_impact(integer, jsonb) TO service_role;

-- ----------------------------------------------------------------------------
-- 12. Auth hook
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  INSERT INTO public.profiles (id, role, full_name, is_admin)
  VALUES (NEW.id, 'customer', NEW.raw_user_meta_data->>'full_name', false)
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ----------------------------------------------------------------------------
-- 13. Seed initial data
-- ----------------------------------------------------------------------------

-- Seed algorithm versions
DO $$
DECLARE
  v_admin_id uuid;
BEGIN
  SELECT id INTO v_admin_id FROM public.profiles WHERE is_admin = true LIMIT 1;

  IF v_admin_id IS NOT NULL THEN
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
     v_admin_id)
    ON CONFLICT (kind, name, version) DO NOTHING;
  END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- 14. pg_cron job for monthly partition maintenance
-- ----------------------------------------------------------------------------

SELECT cron.schedule(
  'create-monthly-events-partition',
  '0 0 1 * *', -- first day of month at midnight
  $$
  DO $$
  DECLARE
    v_next_month date := date_trunc('month', now() + interval '1 month')::date;
    v_partition_name text := 'events_' || to_char(v_next_month, 'YYYY_MM');
    v_start date := v_next_month;
    v_end date := v_next_month + interval '1 month';
  BEGIN
    EXECUTE format('CREATE TABLE IF NOT EXISTS public.%I PARTITION OF public.events FOR VALUES FROM (%L) TO (%L)',
      v_partition_name, v_start, v_end);
  END;
  $$
);

-- ============================================================================
-- End of baseline migration
-- ============================================================================