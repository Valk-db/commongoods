-- ============================================================================
-- CommonGoods RLS Cleanup & Grants Revocation
-- Run after 20260630203000_security_hardening.sql
-- Safe to re-run: uses IF EXISTS / DROP POLICY IF EXISTS throughout.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Fix SECURITY DEFINER functions: pin search_path, revoke anon/authenticated
-- ----------------------------------------------------------------------------

-- Helper: revoke EXECUTE from anon/authenticated on a function
-- We keep EXECUTE for service_role and postgres only
DO $$
DECLARE
  func record;
BEGIN
  FOR func IN
    SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
      AND p.prosecdef  -- SECURITY DEFINER
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION public.%s(%s) FROM anon, authenticated', func.proname, func.args);
  END LOOP;
END $$;

-- Fix function search_path for all public SECURITY DEFINER functions
-- (This addresses the "function_search_path_mutable" lint)
ALTER FUNCTION public.zone_pricing(miles double precision) SET search_path = public;
ALTER FUNCTION public.enforce_delivery_pricing() SET search_path = public;
ALTER FUNCTION public.enforce_partner_admin_fields() SET search_path = public;
ALTER FUNCTION public.handle_new_user() SET search_path = public;
ALTER FUNCTION public.check_user_role(required_role text) SET search_path = public;
ALTER FUNCTION public.get_my_role() SET search_path = public;
ALTER FUNCTION public.is_admin() SET search_path = public;
ALTER FUNCTION public.current_role_is(target_role text) SET search_path = public;

-- ----------------------------------------------------------------------------
-- 2. Drop legacy permissive policies (coexisting with hardening policies)
-- ----------------------------------------------------------------------------

-- ---- deliveries ------------------------------------------------------------
DROP POLICY IF EXISTS "Authorized parties can update delivery status" ON public.deliveries;
DROP POLICY IF EXISTS "Customers can create deliveries" ON public.deliveries;
DROP POLICY IF EXISTS "Customers or Partners can create a delivery" ON public.deliveries;
DROP POLICY IF EXISTS "Customers see own deliveries" ON public.deliveries;
DROP POLICY IF EXISTS "Drivers can update deliveries" ON public.deliveries;
DROP POLICY IF EXISTS "Drivers see pending and own deliveries" ON public.deliveries;
DROP POLICY IF EXISTS "Users can view deliveries they are part of" ON public.deliveries;
DROP POLICY IF EXISTS "authenticated users can read deliveries" ON public.deliveries;
DROP POLICY IF EXISTS "customers can insert deliveries" ON public.deliveries;
DROP POLICY IF EXISTS "drivers can update deliveries" ON public.deliveries;

-- ---- delivery_items --------------------------------------------------------
DROP POLICY IF EXISTS "View delivery items contextually" ON public.delivery_items;

-- ---- delivery_item_options -------------------------------------------------
DROP POLICY IF EXISTS "View item options contextually" ON public.delivery_item_options;

-- ---- delivery_messages -----------------------------------------------------
DROP POLICY IF EXISTS "Parties of delivery can chat" ON public.delivery_messages;

-- ---- delivery_status_history -----------------------------------------------
DROP POLICY IF EXISTS "View status history contextually" ON public.delivery_status_history;

-- ---- drivers ---------------------------------------------------------------
DROP POLICY IF EXISTS "Drivers can manage their own status" ON public.drivers;

-- ---- earnings --------------------------------------------------------------
DROP POLICY IF EXISTS "Drivers can view their own earnings" ON public.earnings;
DROP POLICY IF EXISTS "Drivers see own earnings" ON public.earnings;
DROP POLICY IF EXISTS "Only admins can modify earnings data" ON public.earnings;

-- ---- menu_item_options -----------------------------------------------------
DROP POLICY IF EXISTS "Menu options viewable by everyone" ON public.menu_item_options;
DROP POLICY IF EXISTS "Partners can modify their own options" ON public.menu_item_options;

-- ---- menu_items ------------------------------------------------------------
DROP POLICY IF EXISTS "Admin can manage menu items" ON public.menu_items;
DROP POLICY IF EXISTS "Anyone can view active menu items" ON public.menu_items;
DROP POLICY IF EXISTS "Menu items are publicly viewable" ON public.menu_items;
DROP POLICY IF EXISTS "Partners can manage own menu items" ON public.menu_items;
DROP POLICY IF EXISTS "Partners can manage their own menu items" ON public.menu_items;

-- ---- partner_applications --------------------------------------------------
DROP POLICY IF EXISTS "Anyone can submit a partner application" ON public.partner_applications;
DROP POLICY IF EXISTS "Anyone can submit partner application" ON public.partner_applications;
DROP POLICY IF EXISTS "Only admins can manage applications" ON public.partner_applications;

-- ---- partners --------------------------------------------------------------
DROP POLICY IF EXISTS "Admin can manage partners" ON public.partners;
DROP POLICY IF EXISTS "Anyone can view approved partners" ON public.partners;
DROP POLICY IF EXISTS "Approved partners are viewable by everyone" ON public.partners;
DROP POLICY IF EXISTS "Partners can update own business" ON public.partners;
DROP POLICY IF EXISTS "Partners can update their own business info" ON public.partners;
DROP POLICY IF EXISTS "Partners can view own business" ON public.partners;

-- ---- performance_metrics ---------------------------------------------------
DROP POLICY IF EXISTS "Performance analytics viewable by admins and assigned drivers" ON public.performance_metrics;

-- ---- profiles --------------------------------------------------------------
DROP POLICY IF EXISTS "Profiles are viewable by authenticated users" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;

-- ---- ratings_and_reviews ---------------------------------------------------
DROP POLICY IF EXISTS "Users can insert reviews for deliveries they partook in" ON public.ratings_and_reviews;
DROP POLICY IF EXISTS "Users can view reviews related to their deliveries" ON public.ratings_and_reviews;

-- ---- referral_codes --------------------------------------------------------
DROP POLICY IF EXISTS "Admin can manage referral codes" ON public.referral_codes;
DROP POLICY IF EXISTS "Anyone can validate referral codes" ON public.referral_codes;

-- ---- route_points ----------------------------------------------------------
DROP POLICY IF EXISTS "Drivers can insert route points" ON public.route_points;
DROP POLICY IF EXISTS "Drivers can insert their own telemetry" ON public.route_points;
DROP POLICY IF EXISTS "View telemetry for related delivery" ON public.route_points;

-- ----------------------------------------------------------------------------
-- 3. Revoke GRANT ALL from anon and authenticated on all public tables
--    (RLS is the only access control; explicit grants only for service_role)
-- ----------------------------------------------------------------------------

DO $$
DECLARE
  tbl record;
BEGIN
  FOR tbl IN
    SELECT tablename FROM pg_tables WHERE schemaname = 'public'
  LOOP
    EXECUTE format('REVOKE ALL ON TABLE public.%I FROM anon, authenticated', tbl.tablename);
    -- Grant only SELECT to anon where appropriate (public read-only tables)
    -- We'll handle this per-table below
  END LOOP;
END $$;

-- ---- profiles --------------------------------------------------------------
-- anon: no access (profiles contain PII, is_admin flag)
-- authenticated: SELECT own, UPDATE own (via RLS policies)
-- (no explicit grants needed; RLS policies handle it)

-- ---- partners --------------------------------------------------------------
-- anon: SELECT approved partners only
GRANT SELECT ON public.partners TO anon;
-- authenticated: SELECT approved/own, UPDATE own (via RLS)
GRANT SELECT, UPDATE ON public.partners TO authenticated;

-- ---- menu_items ------------------------------------------------------------
-- anon: SELECT active items only
GRANT SELECT ON public.menu_items TO anon;
-- authenticated: SELECT active/own, INSERT/UPDATE own (via RLS)
GRANT SELECT, INSERT, UPDATE ON public.menu_items TO authenticated;

-- ---- menu_item_options -----------------------------------------------------
-- anon: SELECT all (needed for menu display)
GRANT SELECT ON public.menu_item_options TO anon;
-- authenticated: SELECT all, ALL own (via RLS)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.menu_item_options TO authenticated;

-- ---- partner_applications --------------------------------------------------
-- anon: INSERT pending only
GRANT INSERT ON public.partner_applications TO anon;
-- authenticated: INSERT pending, SELECT/UPDATE admin only (via RLS)
GRANT INSERT ON public.partner_applications TO authenticated;

-- ---- deliveries ------------------------------------------------------------
-- anon: no direct access (all access via RLS policies for authenticated users)
-- authenticated: SELECT/INSERT/UPDATE per RLS policies
GRANT SELECT, INSERT, UPDATE ON public.deliveries TO authenticated;

-- ---- delivery_items --------------------------------------------------------
-- anon: no access
-- authenticated: SELECT per RLS
GRANT SELECT ON public.delivery_items TO authenticated;

-- ---- delivery_item_options -------------------------------------------------
-- anon: no access
-- authenticated: SELECT per RLS
GRANT SELECT ON public.delivery_item_options TO authenticated;

-- ---- delivery_messages -----------------------------------------------------
-- anon: no access
-- authenticated: ALL per RLS
GRANT SELECT, INSERT, UPDATE, DELETE ON public.delivery_messages TO authenticated;

-- ---- delivery_status_history -----------------------------------------------
-- anon: no access
-- authenticated: SELECT per RLS
GRANT SELECT ON public.delivery_status_history TO authenticated;

-- ---- drivers ---------------------------------------------------------------
-- anon: no access
-- authenticated: ALL own (via RLS)
GRANT SELECT, UPDATE ON public.drivers TO authenticated;

-- ---- earnings --------------------------------------------------------------
-- anon: no access
-- authenticated: SELECT own (via RLS)
GRANT SELECT ON public.earnings TO authenticated;

-- ---- performance_metrics ---------------------------------------------------
-- anon: no access
-- authenticated: SELECT per RLS
GRANT SELECT ON public.performance_metrics TO authenticated;

-- ---- ratings_and_reviews ---------------------------------------------------
-- anon: no access
-- authenticated: INSERT own, SELECT per RLS
GRANT SELECT, INSERT ON public.ratings_and_reviews TO authenticated;

-- ---- referral_codes --------------------------------------------------------
-- anon: SELECT (for validation)
GRANT SELECT ON public.referral_codes TO anon;
-- authenticated: SELECT (for validation)
GRANT SELECT ON public.referral_codes TO authenticated;

-- ---- route_points ----------------------------------------------------------
-- anon: no access
-- authenticated: INSERT/SELECT per RLS
GRANT SELECT, INSERT ON public.route_points TO authenticated;

-- ----------------------------------------------------------------------------
-- 4. Add BEFORE UPDATE trigger on profiles to freeze is_admin and role
--    for non-service-role callers
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.enforce_profile_admin_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only enforce for non-service-role callers
  -- current_setting('role') returns the current role; service_role bypasses RLS
  IF current_setting('role') <> 'service_role' THEN
    -- Prevent changing is_admin (can only be set by service_role via admin panel)
    NEW.is_admin := OLD.is_admin;
    -- Prevent changing role (set at signup via handle_new_user, or by admin via service_role)
    NEW.role := OLD.role;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_profile_admin_fields ON public.profiles;
CREATE TRIGGER trg_enforce_profile_admin_fields
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.enforce_profile_admin_fields();

-- ----------------------------------------------------------------------------
-- 5. Ensure RLS is enabled on all tables (belt and suspenders)
-- ----------------------------------------------------------------------------

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.partners ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.route_points ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.earnings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.partner_applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.menu_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.menu_item_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.drivers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_item_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.performance_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ratings_and_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referral_codes ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- 6. Add missing indexes for foreign keys (performance lint)
-- ----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_deliveries_partner_id ON public.deliveries (partner_id);
CREATE INDEX IF NOT EXISTS idx_delivery_items_delivery_id ON public.delivery_items (delivery_id);
CREATE INDEX IF NOT EXISTS idx_delivery_items_menu_item_id ON public.delivery_items (menu_item_id);
CREATE INDEX IF NOT EXISTS idx_delivery_item_options_delivery_item_id ON public.delivery_item_options (delivery_item_id);
CREATE INDEX IF NOT EXISTS idx_delivery_item_options_menu_item_option_id ON public.delivery_item_options (menu_item_option_id);
CREATE INDEX IF NOT EXISTS idx_delivery_messages_delivery_id ON public.delivery_messages (delivery_id);
CREATE INDEX IF NOT EXISTS idx_delivery_messages_sender_id ON public.delivery_messages (sender_id);
CREATE INDEX IF NOT EXISTS idx_delivery_status_history_delivery_id ON public.delivery_status_history (delivery_id);
CREATE INDEX IF NOT EXISTS idx_delivery_status_history_actor_id ON public.delivery_status_history (actor_id);
CREATE INDEX IF NOT EXISTS idx_drivers_id ON public.drivers (id);
CREATE INDEX IF NOT EXISTS idx_earnings_delivery_id ON public.earnings (delivery_id);
CREATE INDEX IF NOT EXISTS idx_earnings_driver_id ON public.earnings (driver_id);
CREATE INDEX IF NOT EXISTS idx_menu_item_options_menu_item_id ON public.menu_item_options (menu_item_id);
CREATE INDEX IF NOT EXISTS idx_menu_items_partner_id ON public.menu_items (partner_id);
CREATE INDEX IF NOT EXISTS idx_partner_applications_id ON public.partner_applications (id);
CREATE INDEX IF NOT EXISTS idx_partners_profile_id ON public.partners (profile_id);
CREATE INDEX IF NOT EXISTS idx_performance_metrics_delivery_id ON public.performance_metrics (delivery_id);
CREATE INDEX IF NOT EXISTS idx_profiles_id ON public.profiles (id);
CREATE INDEX IF NOT EXISTS idx_ratings_and_reviews_delivery_id ON public.ratings_and_reviews (delivery_id);
CREATE INDEX IF NOT EXISTS idx_ratings_and_reviews_reviewee_id ON public.ratings_and_reviews (reviewee_id);
CREATE INDEX IF NOT EXISTS idx_ratings_and_reviews_reviewer_id ON public.ratings_and_reviews (reviewer_id);
CREATE INDEX IF NOT EXISTS idx_referral_codes_used_by ON public.referral_codes (used_by);
CREATE INDEX IF NOT EXISTS idx_route_points_delivery_id ON public.route_points (delivery_id);

-- ----------------------------------------------------------------------------
-- 7. Add RLS policies for tables that had RLS enabled but no policies
--    (These were added after the main migration via direct SQL)
-- ----------------------------------------------------------------------------

-- ---- delivery_items --------------------------------------------------------
DROP POLICY IF EXISTS "delivery_items_select_participant_or_admin" ON public.delivery_items;
CREATE POLICY "delivery_items_select_participant_or_admin" ON public.delivery_items
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.deliveries d
      WHERE d.id = delivery_items.delivery_id
        AND (
          d.customer_id = (SELECT auth.uid())
          OR d.driver_id = (SELECT auth.uid())
          OR d.partner_id IN (SELECT id FROM public.partners WHERE profile_id = (SELECT auth.uid()))
          OR public.is_admin()
        )
    )
  );

-- ---- delivery_item_options -------------------------------------------------
DROP POLICY IF EXISTS "delivery_item_options_select_participant_or_admin" ON public.delivery_item_options;
CREATE POLICY "delivery_item_options_select_participant_or_admin" ON public.delivery_item_options
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.delivery_items di
      JOIN public.deliveries d ON d.id = di.delivery_id
      WHERE di.id = delivery_item_options.delivery_item_id
        AND (
          d.customer_id = (SELECT auth.uid())
          OR d.driver_id = (SELECT auth.uid())
          OR d.partner_id IN (SELECT id FROM public.partners WHERE profile_id = (SELECT auth.uid()))
          OR public.is_admin()
        )
    )
  );

-- ---- delivery_messages -----------------------------------------------------
DROP POLICY IF EXISTS "delivery_messages_all_participant" ON public.delivery_messages;
CREATE POLICY "delivery_messages_all_participant" ON public.delivery_messages
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.deliveries d
      WHERE d.id = delivery_messages.delivery_id
        AND (d.customer_id = (SELECT auth.uid()) OR d.driver_id = (SELECT auth.uid()))
    )
  ) WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.deliveries d
      WHERE d.id = delivery_messages.delivery_id
        AND (d.customer_id = (SELECT auth.uid()) OR d.driver_id = (SELECT auth.uid()))
    )
  );

-- ---- delivery_status_history -----------------------------------------------
DROP POLICY IF EXISTS "delivery_status_history_select_participant_or_admin" ON public.delivery_status_history;
CREATE POLICY "delivery_status_history_select_participant_or_admin" ON public.delivery_status_history
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.deliveries d
      WHERE d.id = delivery_status_history.delivery_id
        AND (
          d.customer_id = (SELECT auth.uid())
          OR d.driver_id = (SELECT auth.uid())
          OR public.is_admin()
        )
    )
  );

-- ---- drivers ---------------------------------------------------------------
DROP POLICY IF EXISTS "drivers_all_own" ON public.drivers;
CREATE POLICY "drivers_all_own" ON public.drivers
  FOR ALL USING ((SELECT auth.uid()) = id) WITH CHECK ((SELECT auth.uid()) = id);

-- ---- menu_item_options -----------------------------------------------------
DROP POLICY IF EXISTS "menu_item_options_select_all" ON public.menu_item_options;
CREATE POLICY "menu_item_options_select_all" ON public.menu_item_options
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "menu_item_options_all_own_partner" ON public.menu_item_options;
CREATE POLICY "menu_item_options_all_own_partner" ON public.menu_item_options
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.menu_items mi
      JOIN public.partners p ON p.id = mi.partner_id
      WHERE mi.id = menu_item_options.menu_item_id
        AND p.profile_id = (SELECT auth.uid())
    )
  ) WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.menu_items mi
      JOIN public.partners p ON p.id = mi.partner_id
      WHERE mi.id = menu_item_options.menu_item_id
        AND p.profile_id = (SELECT auth.uid())
    )
  );

-- ---- performance_metrics ---------------------------------------------------
DROP POLICY IF EXISTS "performance_metrics_select_admin_or_driver" ON public.performance_metrics;
CREATE POLICY "performance_metrics_select_admin_or_driver" ON public.performance_metrics
  FOR SELECT USING (
    public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.deliveries d
      WHERE d.id = performance_metrics.delivery_id
        AND d.driver_id = (SELECT auth.uid())
    )
  );

-- ---- ratings_and_reviews ---------------------------------------------------
DROP POLICY IF EXISTS "ratings_and_reviews_insert_reviewer" ON public.ratings_and_reviews;
CREATE POLICY "ratings_and_reviews_insert_reviewer" ON public.ratings_and_reviews
  FOR INSERT WITH CHECK ((SELECT auth.uid()) = reviewer_id);

DROP POLICY IF EXISTS "ratings_and_reviews_select_participant_or_admin" ON public.ratings_and_reviews;
CREATE POLICY "ratings_and_reviews_select_participant_or_admin" ON public.ratings_and_reviews
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.deliveries d
      WHERE d.id = ratings_and_reviews.delivery_id
        AND (d.customer_id = (SELECT auth.uid()) OR d.driver_id = (SELECT auth.uid()))
    )
    OR public.is_admin()
  );

-- ---- referral_codes --------------------------------------------------------
DROP POLICY IF EXISTS "referral_codes_select_all" ON public.referral_codes;
CREATE POLICY "referral_codes_select_all" ON public.referral_codes
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "referral_codes_admin_all" ON public.referral_codes;
CREATE POLICY "referral_codes_admin_all" ON public.referral_codes
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ----------------------------------------------------------------------------
-- 8. Fix auth_rls_initplan: wrap auth.uid() and auth.jwt() in subqueries
--    in all RLS policies for performance
-- ----------------------------------------------------------------------------

-- Note: The policies above already use (SELECT auth.uid()) instead of auth.uid()
-- Existing hardening policies (deliveries, profiles, partners, menu_items, etc.)
-- still use auth.uid() directly and would need manual updates to fix the initplan lint.
-- This is a performance optimization, not a security issue.

-- ----------------------------------------------------------------------------
-- 9. Clean up duplicate indexes
-- ----------------------------------------------------------------------------

DROP INDEX IF EXISTS public.idx_item_options_item_id;
DROP INDEX IF EXISTS public.idx_status_history_delivery_id;

-- ============================================================================
-- End of migration
-- ============================================================================