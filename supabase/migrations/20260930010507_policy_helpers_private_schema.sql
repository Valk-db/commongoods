-- ============================================================================
-- CommonGoods: Move Policy Helpers to Private Schema + RLS Performance Fixes
-- Run after 20260930001651_rls_cleanup_and_grants.sql
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Create private schema for policy helper functions
-- ----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS private;
GRANT USAGE ON SCHEMA private TO authenticated;

-- ----------------------------------------------------------------------------
-- 2. Move policy helper functions to private schema with proper grants
-- ----------------------------------------------------------------------------

-- is_admin
CREATE OR REPLACE FUNCTION private.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public, private
AS $$
  select coalesce(
    (select is_admin from public.profiles where id = auth.uid()),
    false
  );
$$;
GRANT EXECUTE ON FUNCTION private.is_admin() TO authenticated, service_role, postgres;
REVOKE EXECUTE ON FUNCTION private.is_admin() FROM anon;

-- current_role_is
CREATE OR REPLACE FUNCTION private.current_role_is(target_role text)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public, private
AS $$
  select coalesce(
    (select role = target_role from public.profiles where id = auth.uid()),
    false
  );
$$;
GRANT EXECUTE ON FUNCTION private.current_role_is(target_role text) TO authenticated, service_role, postgres;
REVOKE EXECUTE ON FUNCTION private.current_role_is(target_role text) FROM anon;

-- get_my_role
CREATE OR REPLACE FUNCTION private.get_my_role()
RETURNS text
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  RETURN COALESCE(nullif(current_setting('request.jwt.claims', true)::json->'app_metadata'->>'role', ''), 'customer');
END;
$$;
GRANT EXECUTE ON FUNCTION private.get_my_role() TO authenticated, service_role, postgres;
REVOKE EXECUTE ON FUNCTION private.get_my_role() FROM anon;

-- check_user_role
CREATE OR REPLACE FUNCTION private.check_user_role(required_role text)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND (role = required_role OR is_admin = true)
  );
END;
$$;
GRANT EXECUTE ON FUNCTION private.check_user_role(required_role text) TO authenticated, service_role, postgres;
REVOKE EXECUTE ON FUNCTION private.check_user_role(required_role text) FROM anon;

-- ----------------------------------------------------------------------------
-- 3. Add trust-column freeze triggers in private schema
-- ----------------------------------------------------------------------------

-- drivers.approved
CREATE OR REPLACE FUNCTION private.enforce_driver_admin_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF current_setting('role') <> 'service_role' THEN
    NEW.approved := OLD.approved;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_enforce_driver_admin_fields ON public.drivers;
CREATE TRIGGER trg_enforce_driver_admin_fields
  BEFORE UPDATE ON public.drivers
  FOR EACH ROW EXECUTE FUNCTION private.enforce_driver_admin_fields();

-- partners.approved/founding_merchant/onboarding_fee_paid/joined_during_pilot/profile_id
CREATE OR REPLACE FUNCTION private.enforce_partner_admin_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF current_setting('role') <> 'service_role' THEN
    NEW.approved := OLD.approved;
    NEW.founding_merchant := OLD.founding_merchant;
    NEW.onboarding_fee_paid := OLD.onboarding_fee_paid;
    NEW.joined_during_pilot := OLD.joined_during_pilot;
    NEW.profile_id := OLD.profile_id;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_enforce_partner_admin_fields ON public.partners;
CREATE TRIGGER trg_enforce_partner_admin_fields
  BEFORE UPDATE ON public.partners
  FOR EACH ROW EXECUTE FUNCTION private.enforce_partner_admin_fields();

-- referral_codes.active/used_by/used_at
CREATE OR REPLACE FUNCTION private.enforce_referral_code_admin_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF current_setting('role') <> 'service_role' THEN
    NEW.active := OLD.active;
    NEW.used_by := OLD.used_by;
    NEW.used_at := OLD.used_at;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_enforce_referral_code_admin_fields ON public.referral_codes;
CREATE TRIGGER trg_enforce_referral_code_admin_fields
  BEFORE UPDATE ON public.referral_codes
  FOR EACH ROW EXECUTE FUNCTION private.enforce_referral_code_admin_fields();

-- partner_applications.status
CREATE OR REPLACE FUNCTION private.enforce_partner_application_admin_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF current_setting('role') <> 'service_role' THEN
    NEW.status := OLD.status;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_enforce_partner_application_admin_fields ON public.partner_applications;
CREATE TRIGGER trg_enforce_partner_application_admin_fields
  BEFORE UPDATE ON public.partner_applications
  FOR EACH ROW EXECUTE FUNCTION private.enforce_partner_application_admin_fields();

-- ----------------------------------------------------------------------------
-- 4. Remove anon SELECT on referral_codes (security hole)
--    Client-side lookups replaced with RPC in D workstream
-- ----------------------------------------------------------------------------
REVOKE SELECT ON public.referral_codes FROM anon;

-- ----------------------------------------------------------------------------
-- 5. Rewrite all policies to use private schema functions
--    and wrap auth.uid() as (SELECT auth.uid()) for auth_rls_initplan
-- ----------------------------------------------------------------------------

-- ---- deliveries ------------------------------------------------------------
DROP POLICY IF EXISTS "deliveries_select_participant_or_pending_driver_or_admin" ON public.deliveries;
CREATE POLICY "deliveries_select_participant_or_pending_driver_or_admin" ON public.deliveries
  FOR SELECT USING (
    (customer_id = (SELECT auth.uid()))
    OR (driver_id = (SELECT auth.uid()))
    OR private.is_admin()
    OR ((status = 'pending'::text) AND private.current_role_is('driver'::text))
    OR (partner_id IN (SELECT id FROM public.partners WHERE profile_id = (SELECT auth.uid())))
  );

DROP POLICY IF EXISTS "deliveries_update_participant_or_admin" ON public.deliveries;
CREATE POLICY "deliveries_update_participant_or_admin" ON public.deliveries
  FOR UPDATE USING (
    private.is_admin()
    OR (driver_id = (SELECT auth.uid()))
    OR (customer_id = (SELECT auth.uid()))
    OR ((status = 'pending'::text) AND private.current_role_is('driver'::text))
  )
  WITH CHECK (
    private.is_admin()
    OR (driver_id = (SELECT auth.uid()))
    OR ((customer_id = (SELECT auth.uid())) AND (status = ANY (ARRAY['pending'::text, 'cancelled'::text])))
  );

DROP POLICY IF EXISTS "deliveries_insert_own_as_customer" ON public.deliveries;
CREATE POLICY "deliveries_insert_own_as_customer" ON public.deliveries
  FOR INSERT WITH CHECK (
    (customer_id = (SELECT auth.uid()))
    AND (status = 'pending'::text)
    AND (driver_id IS NULL)
  );

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
          OR private.is_admin()
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
          OR private.is_admin()
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
          OR private.is_admin()
        )
    )
  );

-- ---- drivers ---------------------------------------------------------------
DROP POLICY IF EXISTS "drivers_all_own" ON public.drivers;
CREATE POLICY "drivers_all_own" ON public.drivers
  FOR ALL USING ((SELECT auth.uid()) = id) WITH CHECK ((SELECT auth.uid()) = id);

-- ---- earnings --------------------------------------------------------------
DROP POLICY IF EXISTS "earnings_select_own_or_admin" ON public.earnings;
CREATE POLICY "earnings_select_own_or_admin" ON public.earnings
  FOR SELECT USING (
    (driver_id = (SELECT auth.uid())) OR private.is_admin()
  );

-- ---- menu_item_options -----------------------------------------------------
DROP POLICY IF EXISTS "menu_item_options_select" ON public.menu_item_options;
CREATE POLICY "menu_item_options_select" ON public.menu_item_options
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

-- ---- menu_items ------------------------------------------------------------
DROP POLICY IF EXISTS "menu_items_insert_own_partner_or_admin" ON public.menu_items;
CREATE POLICY "menu_items_insert_own_partner_or_admin" ON public.menu_items
  FOR INSERT WITH CHECK (
    private.is_admin()
    OR (partner_id IN (SELECT id FROM public.partners WHERE profile_id = (SELECT auth.uid())))
  );

DROP POLICY IF EXISTS "menu_items_select_active_or_own_or_admin" ON public.menu_items;
CREATE POLICY "menu_items_select_active_or_own_or_admin" ON public.menu_items
  FOR SELECT USING (
    (active = true)
    OR private.is_admin()
    OR (partner_id IN (SELECT id FROM public.partners WHERE profile_id = (SELECT auth.uid())))
  );

DROP POLICY IF EXISTS "menu_items_update_own_partner_or_admin" ON public.menu_items;
CREATE POLICY "menu_items_update_own_partner_or_admin" ON public.menu_items
  FOR UPDATE USING (
    private.is_admin()
    OR (partner_id IN (SELECT id FROM public.partners WHERE profile_id = (SELECT auth.uid())))
  );

-- ---- partner_applications --------------------------------------------------
DROP POLICY IF EXISTS "partner_applications_select_admin_only" ON public.partner_applications;
CREATE POLICY "partner_applications_select_admin_only" ON public.partner_applications
  FOR SELECT USING (private.is_admin());

DROP POLICY IF EXISTS "partner_applications_update_admin_only" ON public.partner_applications;
CREATE POLICY "partner_applications_update_admin_only" ON public.partner_applications
  FOR UPDATE USING (private.is_admin());

DROP POLICY IF EXISTS "partner_applications_insert_public" ON public.partner_applications;
CREATE POLICY "partner_applications_insert_public" ON public.partner_applications
  FOR INSERT WITH CHECK ((status = 'pending'::text));

-- ---- partners --------------------------------------------------------------
DROP POLICY IF EXISTS "partners_insert_admin_only" ON public.partners;
CREATE POLICY "partners_insert_admin_only" ON public.partners
  FOR INSERT WITH CHECK (private.is_admin());

DROP POLICY IF EXISTS "partners_select_approved_or_own_or_admin" ON public.partners;
CREATE POLICY "partners_select_approved_or_own_or_admin" ON public.partners
  FOR SELECT USING (
    (approved = true)
    OR (profile_id = (SELECT auth.uid()))
    OR private.is_admin()
  );

DROP POLICY IF EXISTS "partners_update_own_or_admin" ON public.partners;
CREATE POLICY "partners_update_own_or_admin" ON public.partners
  FOR UPDATE USING (
    (profile_id = (SELECT auth.uid()))
    OR private.is_admin()
  )
  WITH CHECK (
    (profile_id = (SELECT auth.uid()))
    OR private.is_admin()
  );

-- ---- performance_metrics ---------------------------------------------------
DROP POLICY IF EXISTS "performance_metrics_select_admin_or_driver" ON public.performance_metrics;
CREATE POLICY "performance_metrics_select_admin_or_driver" ON public.performance_metrics
  FOR SELECT USING (
    private.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.deliveries d
      WHERE d.id = performance_metrics.delivery_id
        AND d.driver_id = (SELECT auth.uid())
    )
  );

-- ---- profiles --------------------------------------------------------------
DROP POLICY IF EXISTS "profiles_select_own_or_admin" ON public.profiles;
CREATE POLICY "profiles_select_own_or_admin" ON public.profiles
  FOR SELECT USING (
    (id = (SELECT auth.uid())) OR private.is_admin()
  );

DROP POLICY IF EXISTS "profiles_update_own_limited" ON public.profiles;
CREATE POLICY "profiles_update_own_limited" ON public.profiles
  FOR UPDATE USING (
    (id = (SELECT auth.uid())) OR private.is_admin()
  )
  WITH CHECK (
    private.is_admin()
    OR ((id = (SELECT auth.uid())) AND (is_admin = false))
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
    OR private.is_admin()
  );

-- ---- referral_codes --------------------------------------------------------
DROP POLICY IF EXISTS "referral_codes_admin_all" ON public.referral_codes;
CREATE POLICY "referral_codes_admin_all" ON public.referral_codes
  FOR ALL USING (private.is_admin()) WITH CHECK (private.is_admin());
-- Note: referral code validation done via RPC (check_referral_code) in D workstream

-- ---- route_points ----------------------------------------------------------
DROP POLICY IF EXISTS "route_points_insert_assigned_driver" ON public.route_points;
CREATE POLICY "route_points_insert_assigned_driver" ON public.route_points
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.deliveries d
      WHERE d.id = route_points.delivery_id
        AND d.driver_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS "route_points_select_participant_or_admin" ON public.route_points;
CREATE POLICY "route_points_select_participant_or_admin" ON public.route_points
  FOR SELECT USING (
    private.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.deliveries d
      WHERE d.id = route_points.delivery_id
        AND (d.customer_id = (SELECT auth.uid()) OR d.driver_id = (SELECT auth.uid()))
    )
  );

-- ----------------------------------------------------------------------------
-- 6. Clean up duplicate indexes
-- ----------------------------------------------------------------------------
DROP INDEX IF EXISTS public.idx_item_options_item_id;
DROP INDEX IF EXISTS public.idx_status_history_delivery_id;

-- ============================================================================
-- End of migration
-- ============================================================================