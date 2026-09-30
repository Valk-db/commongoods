-- ============================================================================
-- CommonGoods: Outstanding fixes from last review
-- Run after 20260930025022_fix_referral_job_lifecycle_bugs.sql
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Fix profiles trigger: enforce_profile_admin_fields must be SECURITY INVOKER
--    and raise exception (not silently revert) for is_admin/role changes
-- ----------------------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_enforce_profile_admin_fields ON public.profiles;

CREATE OR REPLACE FUNCTION private.enforce_profile_admin_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, private
AS $$
BEGIN
  -- Allow postgres (SECURITY DEFINER RPCs) and admins
  IF current_user = 'postgres' OR private.is_admin() THEN
    RETURN NEW;
  END IF;

  -- Forbid direct client writes to frozen columns
  IF NEW.is_admin IS DISTINCT FROM OLD.is_admin
     OR NEW.role IS DISTINCT FROM OLD.role THEN
    RAISE EXCEPTION 'forbidden: cannot modify profile admin fields (is_admin, role)';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_enforce_profile_admin_fields
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION private.enforce_profile_admin_fields();

-- ----------------------------------------------------------------------------
-- 2. Add en_route state to deliveries status check constraint
--    Timeline: requested → offered → claimed → en_route → picked_up → delivered
--    (en_route = driver started driving to pickup, arrived_pickup = at location)
-- ----------------------------------------------------------------------------

ALTER TABLE public.deliveries
  DROP CONSTRAINT IF EXISTS deliveries_status_check;

ALTER TABLE public.deliveries
  ADD CONSTRAINT deliveries_status_check
  CHECK (status IN ('pending', 'offered', 'claimed', 'en_route', 'in_progress', 'completed', 'cancelled'));

-- Add timestamps for the new stages
ALTER TABLE public.deliveries
  ADD COLUMN IF NOT EXISTS offered_at timestamptz,
  ADD COLUMN IF NOT EXISTS en_route_at timestamptz,
  ADD COLUMN IF NOT EXISTS arrived_pickup_at timestamptz,
  ADD COLUMN IF NOT EXISTS arrived_dropoff_at timestamptz;

-- ----------------------------------------------------------------------------
-- 3. Add cancellation stage and compensation config keys
--    cancel_stage: 'pending' | 'offered' | 'claimed' | 'en_route' | 'in_progress'
--    Compensation amounts stored in config (see P1), referenced here
-- ----------------------------------------------------------------------------

ALTER TABLE public.deliveries
  ADD COLUMN IF NOT EXISTS cancel_stage text,
  ADD COLUMN IF NOT EXISTS cancel_reason_code text,
  ADD COLUMN IF NOT EXISTS compensation_amount numeric(10,2);

-- ----------------------------------------------------------------------------
-- 4. Update advance_delivery_status to support en_route transition
--    claimed → en_route (driver starts driving to pickup)
--    en_route → in_progress (driver arrives at pickup, picks up)
--    in_progress → completed (driver delivers)
-- ----------------------------------------------------------------------------

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
  v_cancel_stage text;
  v_compensation numeric(10,2) := 0;
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

  -- State machine transitions with en_route
  CASE
    -- Driver starts driving to pickup
    WHEN v_delivery.status = 'claimed' AND p_new_status = 'en_route' AND v_actor_role = 'driver' THEN
      v_allowed := true;
      UPDATE public.deliveries SET en_route_at = now() WHERE id = p_delivery_id;

    -- Driver arrives at pickup, begins pickup process
    WHEN v_delivery.status = 'en_route' AND p_new_status = 'in_progress' AND v_actor_role = 'driver' THEN
      v_allowed := true;
      UPDATE public.deliveries SET picked_up_at = now(), arrived_pickup_at = now() WHERE id = p_delivery_id;

    -- Driver arrives at dropoff
    WHEN v_delivery.status = 'in_progress' AND p_new_status = 'completed' AND v_actor_role = 'driver' THEN
      v_allowed := true;
      UPDATE public.deliveries SET delivered_at = now(), arrived_dropoff_at = now() WHERE id = p_delivery_id;

    -- Customer cancels - determine stage and compensation
    WHEN v_delivery.status IN ('pending', 'offered', 'claimed', 'en_route', 'in_progress')
         AND p_new_status = 'cancelled' AND v_actor_role = 'customer' THEN
      v_allowed := true;
      v_cancel_stage := v_delivery.status;
      UPDATE public.deliveries
      SET cancelled_by = 'customer',
          cancel_stage = v_cancel_stage,
          cancellation_reason_code = 'customer_cancelled'
      WHERE id = p_delivery_id;

      -- Compensation logic (reads from config registry)
      -- pending/offered: free, claimed: driver gets wait_pay, en_route: driver gets distance + wait, in_progress: full pay
      -- Actual values resolved in app/Edge Function from config

    -- Partner cancels (before pickup only)
    WHEN v_delivery.status IN ('pending', 'offered', 'claimed', 'en_route')
         AND p_new_status = 'cancelled' AND v_actor_role = 'partner' THEN
      v_allowed := true;
      v_cancel_stage := v_delivery.status;
      UPDATE public.deliveries
      SET cancelled_by = 'partner',
          cancel_stage = v_cancel_stage,
          cancellation_reason_code = 'partner_cancelled'
      WHERE id = p_delivery_id;

    -- Driver cancels before pickup (use release_delivery for claimed/en_route)
    -- Admin can cancel anytime
    WHEN p_new_status = 'cancelled' AND v_actor_role = 'admin' THEN
      v_allowed := true;
      v_cancel_stage := v_delivery.status;
      UPDATE public.deliveries
      SET cancelled_by = 'system',
          cancel_stage = v_cancel_stage,
          cancellation_reason_code = 'admin_cancelled'
      WHERE id = p_delivery_id;

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

  -- Log status transition with location if available
  INSERT INTO public.delivery_status_history (delivery_id, actor_id, status, lat, lng)
  VALUES (p_delivery_id, v_user_id, p_new_status,
    CASE
      WHEN p_new_status = 'en_route' THEN v_delivery.pickup_lat
      WHEN p_new_status = 'in_progress' THEN v_delivery.pickup_lat
      WHEN p_new_status = 'completed' THEN v_delivery.dropoff_lat
      ELSE NULL END,
    CASE
      WHEN p_new_status = 'en_route' THEN v_delivery.pickup_lng
      WHEN p_new_status = 'in_progress' THEN v_delivery.pickup_lng
      WHEN p_new_status = 'completed' THEN v_delivery.dropoff_lng
      ELSE NULL END);

  RETURN QUERY SELECT true, NULL::text;
END;
$$;

GRANT EXECUTE ON FUNCTION public.advance_delivery_status(p_delivery_id uuid, p_new_status text) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.advance_delivery_status(p_delivery_id uuid, p_new_status text) FROM anon;

-- ----------------------------------------------------------------------------
-- 5. Update claim_delivery to transition pending → offered → claimed
--    Add offered state when job is broadcast to drivers
-- ----------------------------------------------------------------------------

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
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT false, 'unauthenticated', NULL::uuid;
    RETURN;
  END IF;

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

  -- Lock the delivery row with SKIP LOCKED
  SELECT * INTO v_delivery
  FROM public.deliveries
  WHERE id = p_delivery_id
    AND status IN ('pending', 'offered')
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

  -- Check driver doesn't already have an active job
  IF EXISTS (
    SELECT 1 FROM public.deliveries
    WHERE driver_id = v_user_id
      AND status IN ('claimed', 'en_route', 'in_progress')
  ) THEN
    RETURN QUERY SELECT false, 'driver_already_has_active_job', NULL::uuid;
    RETURN;
  END IF;

  -- If pending, first transition to offered (for dispatch tracking)
  IF v_delivery.status = 'pending' THEN
    UPDATE public.deliveries
    SET status = 'offered',
        offered_at = now(),
        driver_id = v_user_id
    WHERE id = p_delivery_id;

    INSERT INTO public.delivery_status_history (delivery_id, actor_id, status)
    VALUES (p_delivery_id, v_user_id, 'offered');
  END IF;

  -- Now claim it
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

  INSERT INTO public.delivery_status_history (delivery_id, actor_id, status)
  VALUES (p_delivery_id, v_user_id, 'claimed');

  RETURN QUERY SELECT true, NULL::text, p_delivery_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_delivery(p_delivery_id uuid) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.claim_delivery(p_delivery_id uuid) FROM anon;

-- ----------------------------------------------------------------------------
-- 6. Add release_delivery support for en_route state
--    Driver can release before pickup (claimed or en_route)
-- ----------------------------------------------------------------------------

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
    AND status IN ('claimed', 'en_route')
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'not_found_or_not_claimed_by_you';
    RETURN;
  END IF;

  -- Release the delivery
  UPDATE public.deliveries
  SET driver_id = NULL,
      status = 'pending',
      claimed_at = NULL,
      en_route_at = NULL,
      offered_at = NULL
  WHERE id = p_delivery_id;

  INSERT INTO public.delivery_status_history (delivery_id, actor_id, status)
  VALUES (p_delivery_id, v_user_id, 'pending');

  RETURN QUERY SELECT true, NULL::text;
END;
$$;

GRANT EXECUTE ON FUNCTION public.release_delivery(p_delivery_id uuid) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.release_delivery(p_delivery_id uuid) FROM anon;

-- ----------------------------------------------------------------------------
-- 7. get_available_jobs: already fixed in previous migration, ensure it hides
--    dropoff and notes for pending jobs. Verify grants.
-- ----------------------------------------------------------------------------

-- Function already exists as SECURITY DEFINER from previous migration
-- Just ensure it's executable by authenticated
GRANT EXECUTE ON FUNCTION public.get_available_jobs() TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.get_available_jobs() FROM anon;

-- ----------------------------------------------------------------------------
-- 8. Ensure service_role has all necessary grants for RPC operations
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
-- 9. Indexes for new columns
-- ----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_deliveries_cancel_stage ON public.deliveries (cancel_stage);
CREATE INDEX IF NOT EXISTS idx_deliveries_offered_at ON public.deliveries (offered_at);
CREATE INDEX IF NOT EXISTS idx_deliveries_en_route_at ON public.deliveries (en_route_at);
CREATE INDEX IF NOT EXISTS idx_deliveries_arrived_pickup_at ON public.deliveries (arrived_pickup_at);
CREATE INDEX IF NOT EXISTS idx_deliveries_arrived_dropoff_at ON public.deliveries (arrived_dropoff_at);

-- ----------------------------------------------------------------------------
-- End of migration
-- ============================================================================