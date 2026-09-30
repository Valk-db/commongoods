-- ============================================================================
-- CommonGoods: Fix referral redemption bugs, job lifecycle issues, and RLS bypasses
-- Run after 20260930020313_job_lifecycle.sql
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Fix referral_codes freeze trigger: column name is is_active not active
--    Change to SECURITY INVOKER, use current_user = 'postgres' for definer context
--    Raise exception instead of silently reverting
-- ----------------------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_enforce_referral_code_admin_fields ON public.referral_codes;

CREATE OR REPLACE FUNCTION private.enforce_referral_code_admin_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, private
AS $$
BEGIN
  -- Allow postgres (SECURITY DEFINER RPCs run as postgres) and admins
  IF current_user = 'postgres' OR private.is_admin() THEN
    RETURN NEW;
  END IF;

  -- Forbid any direct client writes to trust columns
  IF NEW.is_active IS DISTINCT FROM OLD.is_active
     OR NEW.used_by IS DISTINCT FROM OLD.used_by
     OR NEW.used_at IS DISTINCT FROM OLD.used_at THEN
    RAISE EXCEPTION 'forbidden: cannot modify referral code trust columns';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_enforce_referral_code_admin_fields
  BEFORE UPDATE ON public.referral_codes
  FOR EACH ROW EXECUTE FUNCTION private.enforce_referral_code_admin_fields();

-- ----------------------------------------------------------------------------
-- 2. Fix drivers.approved freeze trigger: SECURITY INVOKER, allow postgres + admin
-- ----------------------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_enforce_driver_admin_fields ON public.drivers;

CREATE OR REPLACE FUNCTION private.enforce_driver_admin_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, private
AS $$
BEGIN
  IF current_user = 'postgres' OR private.is_admin() THEN
    RETURN NEW;
  END IF;

  IF NEW.approved IS DISTINCT FROM OLD.approved THEN
    RAISE EXCEPTION 'forbidden: cannot modify driver approved status';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_enforce_driver_admin_fields
  BEFORE UPDATE ON public.drivers
  FOR EACH ROW EXECUTE FUNCTION private.enforce_driver_admin_fields();

-- ----------------------------------------------------------------------------
-- 3. Fix partners admin fields freeze trigger: SECURITY INVOKER, allow postgres + admin
-- ----------------------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_enforce_partner_admin_fields ON public.partners;

CREATE OR REPLACE FUNCTION private.enforce_partner_admin_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, private
AS $$
BEGIN
  IF current_user = 'postgres' OR private.is_admin() THEN
    RETURN NEW;
  END IF;

  IF NEW.approved IS DISTINCT FROM OLD.approved
     OR NEW.founding_merchant IS DISTINCT FROM OLD.founding_merchant
     OR NEW.onboarding_fee_paid IS DISTINCT FROM OLD.onboarding_fee_paid
     OR NEW.joined_during_pilot IS DISTINCT FROM OLD.joined_during_pilot
     OR NEW.profile_id IS DISTINCT FROM OLD.profile_id THEN
    RAISE EXCEPTION 'forbidden: cannot modify partner admin fields';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_enforce_partner_admin_fields
  BEFORE UPDATE ON public.partners
  FOR EACH ROW EXECUTE FUNCTION private.enforce_partner_admin_fields();

-- ----------------------------------------------------------------------------
-- 4. Fix partner_applications.status freeze trigger: SECURITY INVOKER
-- ----------------------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_enforce_partner_application_admin_fields ON public.partner_applications;

CREATE OR REPLACE FUNCTION private.enforce_partner_application_admin_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, private
AS $$
BEGIN
  IF current_user = 'postgres' OR private.is_admin() THEN
    RETURN NEW;
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION 'forbidden: cannot modify partner application status';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_enforce_partner_application_admin_fields
  BEFORE UPDATE ON public.partner_applications
  FOR EACH ROW EXECUTE FUNCTION private.enforce_partner_application_admin_fields();

-- ----------------------------------------------------------------------------
-- 5. Remove RAISE NOTICE from handle_new_user, validate+consume code in same txn
--    Also remove anon EXECUTE on check_referral_code
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  referral_code_text text;
  v_code RECORD;
  v_role text;
BEGIN
  -- ALWAYS create customer; role upgrade happens via redeem_referral_code
  INSERT INTO public.profiles (id, role, full_name)
  VALUES (
    NEW.id,
    'customer',  -- hardcoded, never from raw_user_meta_data
    NEW.raw_user_meta_data->>'full_name'
  );

  -- If a referral code was provided in metadata, validate and consume it NOW
  referral_code_text := NEW.raw_user_meta_data->>'referral_code';
  IF referral_code_text IS NOT NULL AND referral_code_text <> '' THEN
    -- Normalize code
    referral_code_text := trim(upper(referral_code_text));

    -- Lock the referral code row to prevent concurrent redemptions
    SELECT * INTO v_code
    FROM public.referral_codes
    WHERE code = referral_code_text
    FOR UPDATE;

    IF FOUND AND v_code.is_active
       AND (v_code.expires_at IS NULL OR v_code.expires_at > now())
       AND v_code.used_by IS NULL THEN

      v_role := v_code.role; -- 'driver' or 'partner'

      -- Mark code as used
      UPDATE public.referral_codes
      SET used_by = NEW.id,
          used_at = now(),
          is_active = false
      WHERE id = v_code.id;

      -- Create the role-specific row (drivers or partners)
      IF v_role = 'driver' THEN
        INSERT INTO public.drivers (id, is_online, approved)
        VALUES (NEW.id, false, false)
        ON CONFLICT (id) DO UPDATE SET approved = false;
      ELSIF v_role = 'partner' THEN
        UPDATE public.profiles
        SET role = 'partner'
        WHERE id = NEW.id;
      END IF;

      -- Audit the redemption
      INSERT INTO public.referral_redemptions (referral_code_id, redeemed_by, role)
      VALUES (v_code.id, NEW.id, v_role);

      -- Update profile role (customer -> driver/partner)
      UPDATE public.profiles
      SET role = v_role
      WHERE id = NEW.id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------------------
-- 6. Fix redeem_referral_code: only allow when profiles.role = 'customer'
--    Normalize p_code (trim, upper)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.redeem_referral_code(p_code text)
RETURNS TABLE (
  profile_id uuid,
  role text,
  success boolean,
  error text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_code RECORD;
  v_user_id uuid := auth.uid();
  v_role text;
  v_current_role text;
BEGIN
  -- Caller must be authenticated
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT NULL::uuid, NULL::text, false, 'unauthenticated'::text;
    RETURN;
  END IF;

  -- Only allow redemption if current role is customer
  SELECT role INTO v_current_role FROM public.profiles WHERE id = v_user_id;
  IF v_current_role IS NULL OR v_current_role <> 'customer' THEN
    RETURN QUERY SELECT NULL::uuid, NULL::text, false, 'not_eligible_for_redemption'::text;
    RETURN;
  END IF;

  -- Normalize code
  p_code := trim(upper(p_code));

  -- Lock the referral code row to prevent concurrent redemptions
  SELECT * INTO v_code
  FROM public.referral_codes
  WHERE code = p_code
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN QUERY SELECT NULL::uuid, NULL::text, false, 'invalid_code'::text;
    RETURN;
  END IF;

  -- Validate code
  IF NOT v_code.is_active THEN
    RETURN QUERY SELECT NULL::uuid, NULL::text, false, 'code_inactive'::text;
    RETURN;
  END IF;

  IF v_code.expires_at IS NOT NULL AND v_code.expires_at < now() THEN
    RETURN QUERY SELECT NULL::uuid, NULL::text, false, 'code_expired'::text;
    RETURN;
  END IF;

  IF v_code.used_by IS NOT NULL THEN
    RETURN QUERY SELECT NULL::uuid, NULL::text, false, 'code_already_used'::text;
    RETURN;
  END IF;

  v_role := v_code.role; -- 'driver' or 'partner'

  -- Mark code as used
  UPDATE public.referral_codes
  SET used_by = v_user_id,
      used_at = now(),
      is_active = false
  WHERE id = v_code.id;

  -- Create the role-specific row (drivers or partners)
  IF v_role = 'driver' THEN
    INSERT INTO public.drivers (id, is_online, approved)
    VALUES (v_user_id, false, false)
    ON CONFLICT (id) DO UPDATE SET approved = false;
  ELSIF v_role = 'partner' THEN
    -- Partner row will be created when they complete onboarding
    -- For now, just update profile role
    UPDATE public.profiles
    SET role = 'partner'
    WHERE id = v_user_id;
  END IF;

  -- Audit the redemption
  INSERT INTO public.referral_redemptions (referral_code_id, redeemed_by, role)
  VALUES (v_code.id, v_user_id, v_role);

  -- Update profile role (customer -> driver/partner)
  UPDATE public.profiles
  SET role = v_role
  WHERE id = v_user_id;

  RETURN QUERY SELECT v_user_id, v_role, true, NULL::text;
END;
$$;

-- Remove anon grant on check_referral_code (route through rate-limited Edge Function)
REVOKE EXECUTE ON FUNCTION public.check_referral_code(p_code text) FROM anon;

-- ----------------------------------------------------------------------------
-- 7. Revoke direct UPDATE on deliveries from authenticated users
--    All transitions must go through RPCs
-- ----------------------------------------------------------------------------

-- Drop the policy that lets any driver UPDATE pending rows
DROP POLICY IF EXISTS "deliveries_update_participant_or_admin" ON public.deliveries;

-- Create a restrictive UPDATE policy: only via RPC (service_role) or admin
-- Note: authenticated users can no longer UPDATE deliveries directly
CREATE POLICY "deliveries_update_via_rpc_only" ON public.deliveries
  FOR UPDATE USING (
    private.is_admin()
  )
  WITH CHECK (
    private.is_admin()
  );

-- Service role bypasses RLS, so it can UPDATE via RPCs
GRANT UPDATE ON public.deliveries TO service_role;

-- ----------------------------------------------------------------------------
-- 8. Tighten deliveries SELECT: remove pending access for role='driver'
--    Base access on drivers.approved instead
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS "deliveries_select_participant_or_pending_driver_or_admin" ON public.deliveries;

CREATE POLICY "deliveries_select_participant_or_approved_driver_or_admin" ON public.deliveries
  FOR SELECT USING (
    customer_id = (SELECT auth.uid())
    OR driver_id = (SELECT auth.uid())
    OR private.is_admin()
    OR (
      status = 'pending'
      AND EXISTS (
        SELECT 1 FROM public.drivers
        WHERE id = (SELECT auth.uid()) AND approved = true
      )
    )
    OR partner_id IN (SELECT id FROM public.partners WHERE profile_id = (SELECT auth.uid()))
  );

-- ----------------------------------------------------------------------------
-- 9. Replace available_jobs view with SECURITY DEFINER function
--    Checks drivers.approved internally, hides dropoff and notes
-- ----------------------------------------------------------------------------

DROP VIEW IF EXISTS public.available_jobs;

CREATE OR REPLACE FUNCTION public.get_available_jobs()
RETURNS TABLE (
  id uuid,
  category text,
  pickup_address text,
  pickup_lat double precision,
  pickup_lng double precision,
  dropoff_address text,
  dropoff_lat double precision,
  dropoff_lng double precision,
  distance_miles double precision,
  zone_assigned integer,
  fee_charged numeric,
  driver_payout numeric,
  platform_cut numeric,
  estimated_duration_minutes integer,
  requested_at timestamptz,
  partner_name text,
  pickup_notes text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_is_approved_driver boolean;
BEGIN
  -- Caller must be authenticated
  IF v_user_id IS NULL THEN
    RETURN;
  END IF;

  -- Check if user is an approved driver
  SELECT approved INTO v_is_approved_driver
  FROM public.drivers
  WHERE id = v_user_id;

  IF NOT v_is_approved_driver THEN
    RETURN;
  END IF;

  -- Return pending jobs with dropoff hidden and notes hidden
  RETURN QUERY
  SELECT
    d.id,
    d.category,
    d.pickup_address,
    d.pickup_lat,
    d.pickup_lng,
    NULL as dropoff_address,
    NULL as dropoff_lat,
    NULL as dropoff_lng,
    d.distance_miles,
    d.zone_assigned,
    d.fee_charged,
    d.driver_payout,
    d.platform_cut,
    d.estimated_duration_minutes,
    d.requested_at,
    p.business_name as partner_name,
    p.pickup_notes
  FROM public.deliveries d
  LEFT JOIN public.partners p ON p.id = d.partner_id
  WHERE d.status = 'pending'
    AND (p.approved = true OR p.id IS NULL);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_available_jobs() TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.get_available_jobs() FROM anon;

-- ----------------------------------------------------------------------------
-- 10. Fix job lifecycle RPCs
-- ----------------------------------------------------------------------------

-- claim_delivery: reject customer_id = v_user_id, catch unique_violation
CREATE OR REPLACE FUNCTION public.claim_delivery(p_delivery_id uuid)
RETURNS TABLE (
  success boolean,
  error text,
  delivery_id uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_delivery RECORD;
  v_user_id uuid := auth.uid();
  v_driver RECORD;
BEGIN
  -- Caller must be authenticated
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT false, 'unauthenticated', NULL::uuid;
    RETURN;
  END IF;

  -- Must be an approved driver
  SELECT * INTO v_driver
  FROM public.drivers
  WHERE id = v_user_id;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'not_a_driver', NULL::uuid;
    RETURN;
  END IF;

  IF NOT v_driver.approved THEN
    RETURN QUERY SELECT false, 'driver_not_approved', NULL::uuid;
    RETURN;
  END IF;

  -- Lock the delivery row with SKIP LOCKED to avoid contention
  SELECT * INTO v_delivery
  FROM public.deliveries
  WHERE id = p_delivery_id
    AND status = 'pending'
  FOR UPDATE SKIP LOCKED;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'not_available_or_already_claimed', NULL::uuid;
    RETURN;
  END IF;

  -- Reject if customer tries to claim their own delivery
  IF v_delivery.customer_id = v_user_id THEN
    RETURN QUERY SELECT false, 'cannot_claim_own_delivery', NULL::uuid;
    RETURN;
  END IF;

  -- Check driver doesn't already have an active job (enforced by unique index too)
  IF EXISTS (
    SELECT 1 FROM public.deliveries
    WHERE driver_id = v_user_id
      AND status IN ('claimed', 'in_progress')
  ) THEN
    RETURN QUERY SELECT false, 'driver_already_has_active_job', NULL::uuid;
    RETURN;
  END IF;

  -- Claim the delivery (unique index prevents race)
  BEGIN
    UPDATE public.deliveries
    SET driver_id = v_user_id,
        status = 'claimed',
        claimed_at = now()
    WHERE id = p_delivery_id;
  EXCEPTION WHEN unique_violation THEN
    RETURN QUERY SELECT false, 'driver_already_has_active_job', NULL::uuid;
    RETURN;
  END;

  -- Log status transition
  INSERT INTO public.delivery_status_history (delivery_id, actor_id, status)
  VALUES (p_delivery_id, v_user_id, 'claimed');

  RETURN QUERY SELECT true, NULL::text, p_delivery_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_delivery(p_delivery_id uuid) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.claim_delivery(p_delivery_id uuid) FROM anon;

-- release_delivery: unchanged (lets driver give back before pickup)
CREATE OR REPLACE FUNCTION public.release_delivery(p_delivery_id uuid)
RETURNS TABLE (
  success boolean,
  error text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_delivery RECORD;
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT false, 'unauthenticated';
    RETURN;
  END IF;

  SELECT * INTO v_delivery
  FROM public.deliveries
  WHERE id = p_delivery_id
    AND driver_id = v_user_id
    AND status = 'claimed'
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'not_found_or_not_claimed_by_you';
    RETURN;
  END IF;

  -- Release the delivery
  UPDATE public.deliveries
  SET driver_id = NULL,
      status = 'pending',
      claimed_at = NULL
  WHERE id = p_delivery_id;

  -- Log status transition
  INSERT INTO public.delivery_status_history (delivery_id, actor_id, status)
  VALUES (p_delivery_id, v_user_id, 'pending');

  RETURN QUERY SELECT true, NULL::text;
END;
$$;

GRANT EXECUTE ON FUNCTION public.release_delivery(p_delivery_id uuid) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.release_delivery(p_delivery_id uuid) FROM anon;

-- advance_delivery_status: remove driver-cancel arms, reorder role checks
CREATE OR REPLACE FUNCTION public.advance_delivery_status(
  p_delivery_id uuid,
  p_new_status text
)
RETURNS TABLE (
  success boolean,
  error text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_delivery RECORD;
  v_user_id uuid := auth.uid();
  v_allowed boolean := false;
  v_actor_role text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT false, 'unauthenticated';
    RETURN;
  END IF;

  SELECT * INTO v_delivery
  FROM public.deliveries
  WHERE id = p_delivery_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'delivery_not_found';
    RETURN;
  END IF;

  -- Determine actor's role (check driver FIRST before admin)
  IF v_delivery.driver_id = v_user_id THEN
    v_actor_role := 'driver';
  ELSIF v_delivery.customer_id = v_user_id THEN
    v_actor_role := 'customer';
  ELSIF EXISTS (
    SELECT 1 FROM public.partners
    WHERE id = v_delivery.partner_id AND profile_id = v_user_id
  ) THEN
    v_actor_role := 'partner';
  ELSIF private.is_admin() THEN
    v_actor_role := 'admin';
  ELSE
    v_actor_role := 'none';
  END IF;

  -- State machine transitions
  -- claimed → in_progress (driver picks up)
  -- in_progress → completed (driver delivers)
  -- Any → cancelled (customer/partner before pickup; admin anytime)
  -- NOTE: driver cancel removed - use release_delivery instead

  CASE
    -- Driver picks up
    WHEN v_delivery.status = 'claimed' AND p_new_status = 'in_progress' AND v_actor_role = 'driver' THEN
      v_allowed := true;
      UPDATE public.deliveries SET picked_up_at = now() WHERE id = p_delivery_id;

    -- Driver delivers
    WHEN v_delivery.status = 'in_progress' AND p_new_status = 'completed' AND v_actor_role = 'driver' THEN
      v_allowed := true;
      UPDATE public.deliveries SET delivered_at = now() WHERE id = p_delivery_id;

    -- Customer cancels (only before pickup)
    WHEN v_delivery.status IN ('pending', 'claimed') AND p_new_status = 'cancelled' AND v_actor_role = 'customer' THEN
      v_allowed := true;
      UPDATE public.deliveries SET cancelled_by = 'customer' WHERE id = p_delivery_id;

    -- Partner cancels (only before pickup)
    WHEN v_delivery.status IN ('pending', 'claimed') AND p_new_status = 'cancelled' AND v_actor_role = 'partner' THEN
      v_allowed := true;
      UPDATE public.deliveries SET cancelled_by = 'partner' WHERE id = p_delivery_id;

    -- Admin can cancel anytime
    WHEN p_new_status = 'cancelled' AND v_actor_role = 'admin' THEN
      v_allowed := true;
      UPDATE public.deliveries SET cancelled_by = 'system' WHERE id = p_delivery_id;

    ELSE
      v_allowed := false;
  END CASE;

  IF NOT v_allowed THEN
    RETURN QUERY SELECT false, 'invalid_transition_or_unauthorized';
    RETURN;
  END IF;

  -- Apply status change
  UPDATE public.deliveries
  SET status = p_new_status
  WHERE id = p_delivery_id;

  -- Log status transition
  INSERT INTO public.delivery_status_history (delivery_id, actor_id, status, lat, lng)
  VALUES (p_delivery_id, v_user_id, p_new_status,
    CASE WHEN p_new_status = 'in_progress' THEN v_delivery.pickup_lat
         WHEN p_new_status = 'completed' THEN v_delivery.dropoff_lat
         ELSE NULL END,
    CASE WHEN p_new_status = 'in_progress' THEN v_delivery.pickup_lng
         WHEN p_new_status = 'completed' THEN v_delivery.dropoff_lng
         ELSE NULL END);

  RETURN QUERY SELECT true, NULL::text;
END;
$$;

GRANT EXECUTE ON FUNCTION public.advance_delivery_status(p_delivery_id uuid, p_new_status text) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.advance_delivery_status(p_delivery_id uuid, p_new_status text) FROM anon;

-- ----------------------------------------------------------------------------
-- 11. Ensure proper grants on all tables for service_role (bypasses RLS)
-- ----------------------------------------------------------------------------

GRANT ALL ON public.deliveries TO service_role;
GRANT ALL ON public.drivers TO service_role;
GRANT ALL ON public.partners TO service_role;
GRANT ALL ON public.profiles TO service_role;
GRANT ALL ON public.referral_codes TO service_role;
GRANT ALL ON public.partner_applications TO service_role;
GRANT ALL ON public.earnings TO service_role;
GRANT ALL ON public.delivery_status_history TO service_role;
GRANT ALL ON public.menu_items TO service_role;
GRANT ALL ON public.menu_item_options TO service_role;
GRANT ALL ON public.delivery_items TO service_role;
GRANT ALL ON public.delivery_item_options TO service_role;
GRANT ALL ON public.delivery_messages TO service_role;
GRANT ALL ON public.route_points TO service_role;
GRANT ALL ON public.performance_metrics TO service_role;
GRANT ALL ON public.ratings_and_reviews TO service_role;

-- ----------------------------------------------------------------------------
-- End of migration
-- ============================================================================