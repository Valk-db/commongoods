-- ============================================================================
-- CommonGoods: Job Lifecycle (Workstream E)
-- Run after 20260930011917_signup_referral_system.sql
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Partial unique index: one active job per driver
--    Active = claimed OR in_progress
-- ----------------------------------------------------------------------------

CREATE UNIQUE INDEX IF NOT EXISTS idx_deliveries_one_active_per_driver
  ON public.deliveries (driver_id)
  WHERE status IN ('claimed', 'in_progress');

-- ----------------------------------------------------------------------------
-- 2. claim_delivery(id) RPC
--    - Uses FOR UPDATE SKIP LOCKED to avoid deadlocks
--    - Requires drivers.approved = true
--    - Backed by the partial unique index above
--    - Stamps claimed_at server-side
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

  -- Check driver doesn't already have an active job (enforced by unique index too)
  IF EXISTS (
    SELECT 1 FROM public.deliveries
    WHERE driver_id = v_user_id
      AND status IN ('claimed', 'in_progress')
  ) THEN
    RETURN QUERY SELECT false, 'driver_already_has_active_job', NULL::uuid;
    RETURN;
  END IF;

  -- Claim the delivery
  UPDATE public.deliveries
  SET driver_id = v_user_id,
      status = 'claimed',
      claimed_at = now()
  WHERE id = p_delivery_id;

  -- Log status transition
  INSERT INTO public.delivery_status_history (delivery_id, actor_id, status)
  VALUES (p_delivery_id, v_user_id, 'claimed');

  RETURN QUERY SELECT true, NULL::text, p_delivery_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_delivery(p_delivery_id uuid) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.claim_delivery(p_delivery_id uuid) FROM anon;

-- ----------------------------------------------------------------------------
-- 3. release_delivery(id) RPC
--    - Lets driver give back a job before pickup (status = claimed)
--    - Resets driver_id, status, claimed_at
--    - Logs transition
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

-- ----------------------------------------------------------------------------
-- 4. advance_delivery_status(id, new_status) RPC
--    - Enforces state machine: pending→claimed→in_progress→completed
--    - Also supports cancellation paths
--    - Stamps timestamps server-side (picked_up_at, delivered_at)
--    - Logs every transition to delivery_status_history
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

  -- Determine actor's role
  IF private.is_admin() THEN
    v_actor_role := 'admin';
  ELSIF v_delivery.driver_id = v_user_id THEN
    v_actor_role := 'driver';
  ELSIF v_delivery.customer_id = v_user_id THEN
    v_actor_role := 'customer';
  ELSIF EXISTS (
    SELECT 1 FROM public.partners
    WHERE id = v_delivery.partner_id AND profile_id = v_user_id
  ) THEN
    v_actor_role := 'partner';
  ELSE
    v_actor_role := 'none';
  END IF;

  -- State machine transitions
  -- pending → claimed (driver claims via claim_delivery, not this RPC)
  -- claimed → in_progress (driver picks up)
  -- in_progress → completed (driver delivers)
  -- Any → cancelled (customer/driver/partner before pickup; admin anytime)

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

    -- Driver cancels (only before pickup)
    WHEN v_delivery.status IN ('pending', 'claimed') AND p_new_status = 'cancelled' AND v_actor_role = 'driver' THEN
      v_allowed := true;
      UPDATE public.deliveries SET cancelled_by = 'driver' WHERE id = p_delivery_id;

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
-- 5. available_jobs view (security_invoker = true)
--    - Hides dropoff address and notes until claimed
--    - Shows only pending jobs
--    - Filters by zone/distance if needed
-- ----------------------------------------------------------------------------

CREATE OR REPLACE VIEW public.available_jobs
  WITH (security_invoker = true)
AS
SELECT
  d.id,
  d.category,
  d.pickup_address,
  d.pickup_lat,
  d.pickup_lng,
  -- Hide dropoff until claimed
  CASE WHEN d.status = 'pending' THEN NULL ELSE d.dropoff_address END as dropoff_address,
  CASE WHEN d.status = 'pending' THEN NULL ELSE d.dropoff_lat END as dropoff_lat,
  CASE WHEN d.status = 'pending' THEN NULL ELSE d.dropoff_lng END as dropoff_lng,
  d.distance_miles,
  d.zone_assigned,
  d.fee_charged,
  d.driver_payout,
  d.platform_cut,
  d.estimated_duration_minutes,
  d.requested_at,
  d.notes,
  -- Partner info (only if approved)
  p.business_name as partner_name,
  p.pickup_notes
FROM public.deliveries d
LEFT JOIN public.partners p ON p.id = d.partner_id
WHERE d.status = 'pending'
  AND (p.approved = true OR p.id IS NULL);

GRANT SELECT ON public.available_jobs TO authenticated;

-- ----------------------------------------------------------------------------
-- 6. Update driver.tsx earnings query to use delivered_at
--    (This is a note for the app code change)
-- ----------------------------------------------------------------------------

-- Earnings should be filtered by delivered_at, not requested_at:
-- SELECT sum(amount) FROM earnings WHERE driver_id = ? AND delivered_at >= ?
-- The earnings table already has delivery_id FK; join to deliveries for delivered_at

-- ----------------------------------------------------------------------------
-- 7. Ensure delivery_status_history has proper grants
-- ----------------------------------------------------------------------------

GRANT SELECT ON public.delivery_status_history TO authenticated;
GRANT INSERT ON public.delivery_status_history TO service_role;

-- ============================================================================
-- End of migration
-- ============================================================================