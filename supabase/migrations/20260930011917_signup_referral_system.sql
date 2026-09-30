-- ============================================================================
-- CommonGoods: Signup & Referral System (Workstream D)
-- Run after 20260930010507_policy_helpers_private_schema.sql
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Fix handle_new_user: always create 'customer', ignore client-supplied role
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  referral_code_text text;
  referral_role text;
BEGIN
  -- ALWAYS create customer; role upgrade happens via redeem_referral_code
  INSERT INTO public.profiles (id, role, full_name)
  VALUES (
    NEW.id,
    'customer',  -- hardcoded, never from raw_user_meta_data
    NEW.raw_user_meta_data->>'full_name'
  );

  -- If a referral code was provided in metadata, store it for later redemption
  -- (The actual redemption happens via redeem_referral_code RPC after signup)
  referral_code_text := NEW.raw_user_meta_data->>'referral_code';
  IF referral_code_text IS NOT NULL AND referral_code_text <> '' THEN
    -- Store the code in the user's profile for post-signup redemption
    -- We'll use a separate column or a temp table; for now, log it
    RAISE NOTICE 'User % provided referral code: %', NEW.id, referral_code_text;
  END IF;

  RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------------------
-- 2. referral_redemptions audit table
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.referral_redemptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  referral_code_id uuid NOT NULL REFERENCES public.referral_codes(id) ON DELETE CASCADE,
  redeemed_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  redeemed_at timestamptz NOT NULL DEFAULT now(),
  role text NOT NULL CHECK (role IN ('driver', 'partner')),
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.referral_redemptions ENABLE ROW LEVEL SECURITY;

-- Only admins and the redeeming user can see their own redemptions
CREATE POLICY "referral_redemptions_select_own_or_admin" ON public.referral_redemptions
  FOR SELECT USING (
    redeemed_by = (SELECT auth.uid())
    OR private.is_admin()
  );

-- Only service_role (via RPC) can insert
GRANT SELECT ON public.referral_redemptions TO authenticated;
GRANT INSERT ON public.referral_redemptions TO service_role;

-- ----------------------------------------------------------------------------
-- 3. redeem_referral_code(p_code) RPC
--    - Uses FOR UPDATE to lock the code row
--    - Validates: active, not expired, uses remaining
--    - Consumes code and creates drivers/partners row in same transaction
--    - Returns the created profile ID and role
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
BEGIN
  -- Caller must be authenticated
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT NULL::uuid, NULL::text, false, 'unauthenticated'::text;
    RETURN;
  END IF;

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
    ON CONFLICT (id) DO UPDATE SET approved = false; -- ensure not approved yet
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

GRANT EXECUTE ON FUNCTION public.redeem_referral_code(p_code text) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.redeem_referral_code(p_code text) FROM anon;

-- ----------------------------------------------------------------------------
-- 4. check_referral_code(p_code) - for pre-signup screen
--    Returns only boolean (valid/available), no sensitive info
--    Throttled via Edge Function keyed on IP (implemented separately)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.check_referral_code(p_code text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_code RECORD;
BEGIN
  SELECT * INTO v_code
  FROM public.referral_codes
  WHERE code = p_code;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF NOT v_code.is_active THEN
    RETURN false;
  END IF;

  IF v_code.expires_at IS NOT NULL AND v_code.expires_at < now() THEN
    RETURN false;
  END IF;

  IF v_code.used_by IS NOT NULL THEN
    RETURN false;
  END IF;

  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_referral_code(p_code text) TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- 5. Ensure referral_codes table has proper grants (anon lost SELECT in C)
--    check_referral_code is the only way for anon/authenticated to validate
-- ----------------------------------------------------------------------------

-- Already handled: anon has no SELECT, authenticated has SELECT
-- check_referral_code is callable by both

-- ----------------------------------------------------------------------------
-- 6. Verify handle_new_user trigger on auth.users
-- ----------------------------------------------------------------------------

-- Trigger already exists from initial schema; function is replaced above
-- No action needed

-- ============================================================================
-- End of migration
-- ============================================================================