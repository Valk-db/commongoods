-- ============================================================================
-- CommonGoods: Update check_referral_code to return role and error details
-- Run after 20260930070001_update_create_delivery_quote_id.sql
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Update check_referral_code to return structured result with role
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.check_referral_code(p_code text)
RETURNS TABLE (
  success boolean,
  role text,
  error text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_code RECORD;
BEGIN
  -- Normalize code
  p_code := trim(upper(p_code));

  SELECT * INTO v_code
  FROM public.referral_codes
  WHERE code = p_code;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, NULL::text, 'invalid_code'::text;
    RETURN;
  END IF;

  IF NOT v_code.is_active THEN
    RETURN QUERY SELECT false, NULL::text, 'code_inactive'::text;
    RETURN;
  END IF;

  IF v_code.expires_at IS NOT NULL AND v_code.expires_at < now() THEN
    RETURN QUERY SELECT false, NULL::text, 'code_expired'::text;
    RETURN;
  END IF;

  IF v_code.used_by IS NOT NULL THEN
    RETURN QUERY SELECT false, NULL::text, 'code_already_used'::text;
    RETURN;
  END IF;

  -- Return success with role
  RETURN QUERY SELECT true, v_code.role, NULL::text;
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_referral_code(p_code text) TO authenticated, anon, service_role;

-- ============================================================================
-- End of migration
-- ============================================================================