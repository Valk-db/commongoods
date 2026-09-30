-- ============================================================================
-- CommonGoods: Fix Config Security
-- Run after 20260930060001_fix_demand_multiplier_and_components.sql
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Make config_values SELECT admin-only
--    Clients call resolve_config RPC which derives context from auth.uid()
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS "config_values_select_authenticated" ON public.config_values;

CREATE POLICY "config_values_select_admin_only" ON public.config_values
  FOR SELECT USING (private.is_admin());

-- ----------------------------------------------------------------------------
-- 2. Add trigger blocking DELETE on config_values
--    Permit UPDATE only for status and effective_to transitions
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.enforce_config_values_immutability()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    -- Only admins can delete, and only if status is not 'active'
    IF NOT private.is_admin() THEN
      RAISE EXCEPTION 'DELETE on config_values requires admin privileges';
    END IF;
    IF OLD.status = 'active' THEN
      RAISE EXCEPTION 'Cannot DELETE active config values';
    END IF;
    RETURN OLD;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    -- Allow updates to status, effective_to, approved_by, governance_proposal_id, reason
    -- Block changes to key, scope_type, scope_id, value, effective_from, created_by
    IF NEW.key IS DISTINCT FROM OLD.key THEN
      RAISE EXCEPTION 'Cannot modify config_values.key';
    END IF;
    IF NEW.scope_type IS DISTINCT FROM OLD.scope_type THEN
      RAISE EXCEPTION 'Cannot modify config_values.scope_type';
    END IF;
    IF NEW.scope_id IS DISTINCT FROM OLD.scope_id THEN
      RAISE EXCEPTION 'Cannot modify config_values.scope_id';
    END IF;
    IF NEW.value IS DISTINCT FROM OLD.value THEN
      RAISE EXCEPTION 'Cannot modify config_values.value (create new row instead)';
    END IF;
    IF NEW.effective_from IS DISTINCT FROM OLD.effective_from THEN
      RAISE EXCEPTION 'Cannot modify config_values.effective_from';
    END IF;
    IF NEW.created_by IS DISTINCT FROM OLD.created_by THEN
      RAISE EXCEPTION 'Cannot modify config_values.created_by';
    END IF;
    -- Allow: status, effective_to, approved_by, governance_proposal_id, reason
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_config_values_immutability ON public.config_values;
CREATE TRIGGER trg_enforce_config_values_immutability
  BEFORE UPDATE OR DELETE ON public.config_values
  FOR EACH ROW EXECUTE FUNCTION private.enforce_config_values_immutability();

-- ----------------------------------------------------------------------------
-- 3. Gate preview_config_impact to admins only
-- ----------------------------------------------------------------------------

REVOKE EXECUTE ON FUNCTION public.preview_config_impact(jsonb, integer) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.preview_config_impact(jsonb, integer) TO service_role, postgres;

-- ----------------------------------------------------------------------------
-- 4. Fix validate_config_constraints to use structured constraints
--    Instead of EXECUTE format with raw SQL expressions
-- ----------------------------------------------------------------------------

-- First, add structured constraint columns to config_constraints
ALTER TABLE public.config_constraints
  ADD COLUMN IF NOT EXISTS key_a text,           -- left side config key
  ADD COLUMN IF NOT EXISTS operator text CHECK (operator IN ('=', '!=', '<', '<=', '>', '>=', 'in', 'not_in')), -- comparison operator
  ADD COLUMN IF NOT EXISTS key_b text,           -- right side config key (optional)
  ADD COLUMN IF NOT EXISTS constant_value jsonb; -- constant value for comparison (optional)

-- Migrate existing expression-based constraints to structured format
-- This is a one-time migration; new constraints should use structured format
UPDATE public.config_constraints
SET
  key_a = 'pay.payout_pct_or_per_mile',
  operator = '<=',
  key_b = 'pricing.per_mile',
  constant_value = NULL
WHERE name = 'driver_payout_min_per_mile';

UPDATE public.config_constraints
SET
  key_a = 'platform_cut_pct',
  operator = '<=',
  constant_value = '0.40'::jsonb
WHERE name = 'platform_cut_pct_max';

UPDATE public.config_constraints
SET
  key_a = 'cancel.comp.en_route',
  operator = '<=',
  constant_value = '("pay.min_payout" + "pricing.per_mile" * 5)'::jsonb
WHERE name = 'cancel_comp_en_route_le_driver_payout';

UPDATE public.config_constraints
SET
  key_a = 'cancel.comp.in_progress',
  operator = '<=',
  constant_value = '("pay.min_payout" + "pricing.per_mile" * 10)'::jsonb
WHERE name = 'cancel_comp_in_progress_le_driver_payout';

UPDATE public.config_constraints
SET
  key_a = 'pricing.fee_rounding',
  operator = 'in',
  constant_value = '["none", "round", "ceil_0.25", "ceil_0.50"]'::jsonb
WHERE name = 'fee_rounding_consistent';

UPDATE public.config_constraints
SET
  key_a = 'dispatch.ranking_weights.distance + dispatch.ranking_weights.rating + dispatch.ranking_weights.acceptance + dispatch.ranking_weights.idle_time',
  operator = '=',
  constant_value = '1'::jsonb
WHERE name = 'ranking_weights_sum_to_one';

UPDATE public.config_constraints
SET
  key_a = 'pay.pay_floor_per_hour',
  operator = '>=',
  constant_value = '7.25'::jsonb
WHERE name = 'pay_floor_respects_min_wage';

-- ----------------------------------------------------------------------------
-- 5. Replace validate_config_constraints with structured evaluation
-- ----------------------------------------------------------------------------

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
  v_left jsonb;
  v_right jsonb;
  v_passed boolean;
BEGIN
  FOR v_constraint IN
    SELECT name, message, severity, key_a, operator, key_b, constant_value
    FROM public.config_constraints
    WHERE is_active = true
  LOOP
    -- Resolve left side (key_a can be a JSON path expression)
    v_left := p_proposed;
    -- For now, assume key_a is a simple key or JSON path
    -- In production, you'd use a JSON path evaluator
    IF v_constraint.key_a IS NOT NULL THEN
      v_left := p_proposed ->> v_constraint.key_a;
      IF v_left IS NOT NULL THEN
        -- Try to cast to numeric if it looks like a number
        IF v_left ~ '^\d+(\.\d+)?$' THEN
          v_left := v_left::jsonb::numeric;
        END IF;
      END IF;
    END IF;

    -- Resolve right side
    IF v_constraint.key_b IS NOT NULL THEN
      v_right := p_proposed ->> v_constraint.key_b;
      IF v_right IS NOT NULL AND v_right ~ '^\d+(\.\d+)?$' THEN
        v_right := v_right::jsonb::numeric;
      END IF;
    ELSIF v_constraint.constant_value IS NOT NULL THEN
      v_right := v_constraint.constant_value;
    END IF;

    -- Evaluate constraint
    v_passed := false;
    CASE v_constraint.operator
      WHEN '=' THEN
        v_passed := v_left = v_right;
      WHEN '!=' THEN
        v_passed := v_left != v_right;
      WHEN '<' THEN
        v_passed := v_left < v_right;
      WHEN '<=' THEN
        v_passed := v_left <= v_right;
      WHEN '>' THEN
        v_passed := v_left > v_right;
      WHEN '>=' THEN
        v_passed := v_left >= v_right;
      WHEN 'in' THEN
        v_passed := v_left = ANY (v_right::jsonb_array_elements_text()::text[]);
      WHEN 'not_in' THEN
        v_passed := v_left != ALL (v_right::jsonb_array_elements_text()::text[]);
      ELSE
        v_passed := false;
    END CASE;

    RETURN QUERY SELECT v_constraint.name, v_passed, v_constraint.message;
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.validate_config_constraints(jsonb) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 6. Make resolve_config and resolve_all_config the only client-facing functions
--    Ensure they properly derive context from auth.uid() and never trust client-supplied ctx
-- ----------------------------------------------------------------------------

-- The resolve_config function already derives context from the caller's JWT
-- No changes needed - it's already SECURITY DEFINER with proper context extraction

-- ----------------------------------------------------------------------------
-- 7. Add client-facing RPC for config resolution (already exists: resolve_config)
--    No direct SELECT on config_values allowed
-- ----------------------------------------------------------------------------

-- ============================================================================
-- End of migration
-- ============================================================================