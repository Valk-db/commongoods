-- ============================================================================
-- CommonGoods: Fix mileage rates - change to numeric(6,4) dollars per mile
-- Run after 20260930042507_p2_strategy_framework_create_delivery.sql
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Fix tax_mileage_rates table - change cents columns to dollars with 4 decimal precision
-- ----------------------------------------------------------------------------

-- Add new columns with correct type
ALTER TABLE public.tax_mileage_rates
  ADD COLUMN business_dollars numeric(6,4),
  ADD COLUMN medical_dollars numeric(6,4),
  ADD COLUMN charity_dollars numeric(6,4);

-- Migrate data: convert cents to dollars (divide by 100, or by 10000 for 2026 rates that were already * 100)
UPDATE public.tax_mileage_rates
SET
  business_dollars = CASE
    WHEN business_cents >= 1000 THEN business_cents / 10000.0  -- 2026 rates stored as cents*100
    ELSE business_cents / 100.0  -- 2024/2025 rates stored as cents
  END,
  medical_dollars = CASE
    WHEN medical_cents IS NOT NULL AND medical_cents >= 1000 THEN medical_cents / 10000.0
    WHEN medical_cents IS NOT NULL THEN medical_cents / 100.0
    ELSE NULL
  END,
  charity_dollars = CASE
    WHEN charity_cents IS NOT NULL AND charity_cents >= 1000 THEN charity_cents / 10000.0
    WHEN charity_cents IS NOT NULL THEN charity_cents / 100.0
    ELSE NULL
  END;

-- Drop old columns
ALTER TABLE public.tax_mileage_rates
  DROP COLUMN business_cents,
  DROP COLUMN medical_cents,
  DROP COLUMN charity_cents;

-- Rename new columns to original names
ALTER TABLE public.tax_mileage_rates
  RENAME COLUMN business_dollars TO business_cents;
ALTER TABLE public.tax_mileage_rates
  RENAME COLUMN medical_dollars TO medical_cents;
ALTER TABLE public.tax_mileage_rates
  RENAME COLUMN charity_dollars TO charity_cents;

-- Add CHECK constraints for reasonable ranges
ALTER TABLE public.tax_mileage_rates
  ADD CONSTRAINT tax_mileage_rates_business_check
  CHECK (business_cents >= 0.10 AND business_cents <= 2.00);

ALTER TABLE public.tax_mileage_rates
  ADD CONSTRAINT tax_mileage_rates_medical_check
  CHECK (medical_cents IS NULL OR (medical_cents >= 0.05 AND medical_cents <= 1.00));

ALTER TABLE public.tax_mileage_rates
  ADD CONSTRAINT tax_mileage_rates_charity_check
  CHECK (charity_cents IS NULL OR (charity_cents >= 0.05 AND charity_cents <= 1.00));

-- ----------------------------------------------------------------------------
-- 2. Reseed with correct IRS rates (dollars per mile, 4 decimal places)
--    Per IRS:
--    2024: business 0.67, medical 0.21, charity 0.14
--    2025: business 0.70, medical 0.21, charity 0.14
--    2026 H1 (Jan 1 - Jun 30): business 0.725, medical 0.205, charity 0.14
--    2026 H2 (Jul 1 - Dec 31): business 0.76, medical 0.235, charity 0.14
-- ----------------------------------------------------------------------------

-- Clear existing data
TRUNCATE public.tax_mileage_rates RESTART IDENTITY;

-- Insert correct rates
INSERT INTO public.tax_mileage_rates (effective_from, effective_to, business_cents, medical_cents, charity_cents, source_url, notes) VALUES
('2024-01-01', '2024-12-31', 0.6700, 0.2100, 0.1400, 'https://www.irs.gov/tax-professionals/standard-mileage-rates', '2024 rate'),
('2025-01-01', '2025-12-31', 0.7000, 0.2100, 0.1400, 'https://www.irs.gov/tax-professionals/standard-mileage-rates', '2025 rate'),
('2026-01-01', '2026-06-30', 0.7250, 0.2050, 0.1400, 'https://www.irs.gov/tax-professionals/standard-mileage-rates', '2026 H1 rate'),
('2026-07-01', '2026-12-31', 0.7600, 0.2350, 0.1400, 'https://www.irs.gov/tax-professionals/standard-mileage-rates', '2026 H2 rate');

-- ----------------------------------------------------------------------------
-- 3. Update get_mileage_rate function to return numeric(6,4) instead of integer
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_mileage_rate(p_date date)
RETURNS TABLE (
  business_cents numeric(6,4),
  medical_cents numeric(6,4),
  charity_cents numeric(6,4)
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
-- 4. Add unit test function for the 2026-06-30 / 2026-07-01 boundary
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.test_mileage_rate_boundary()
RETURNS TABLE (
  test_name text,
  passed boolean,
  message text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_h1_rate RECORD;
  v_h2_rate RECORD;
BEGIN
  -- Test 2026-06-30 returns H1 rate
  SELECT * INTO v_h1_rate FROM public.get_mileage_rate('2026-06-30');

  -- Test 2026-07-01 returns H2 rate
  SELECT * INTO v_h2_rate FROM public.get_mileage_rate('2026-07-01');

  -- Check H1 rates
  IF v_h1_rate.business_cents = 0.7250 AND v_h1_rate.medical_cents = 0.2050 AND v_h1_rate.charity_cents = 0.1400 THEN
    RETURN QUERY SELECT '2026-06-30 returns H1 rates'::text, true::boolean, 'Business: 0.7250, Medical: 0.2050, Charity: 0.1400'::text;
  ELSE
    RETURN QUERY SELECT '2026-06-30 returns H1 rates'::text, false::boolean, format('Expected business=0.7250 medical=0.2050 charity=0.1400, got business=%s medical=%s charity=%s', v_h1_rate.business_cents, v_h1_rate.medical_cents, v_h1_rate.charity_cents)::text;
  END IF;

  -- Check H2 rates
  IF v_h2_rate.business_cents = 0.7600 AND v_h2_rate.medical_cents = 0.2350 AND v_h2_rate.charity_cents = 0.1400 THEN
    RETURN QUERY SELECT '2026-07-01 returns H2 rates'::text, true::boolean, 'Business: 0.7600, Medical: 0.2350, Charity: 0.1400'::text;
  ELSE
    RETURN QUERY SELECT '2026-07-01 returns H2 rates'::text, false::boolean, format('Expected business=0.7600 medical=0.2350 charity=0.1400, got business=%s medical=%s charity=%s', v_h2_rate.business_cents, v_h2_rate.medical_cents, v_h2_rate.charity_cents)::text;
  END IF;

  -- Check they are different
  IF v_h1_rate.business_cents != v_h2_rate.business_cents THEN
    RETURN QUERY SELECT 'H1 and H2 business rates differ'::text, true::boolean, format('H1: %s, H2: %s', v_h1_rate.business_cents, v_h2_rate.business_cents)::text;
  ELSE
    RETURN QUERY SELECT 'H1 and H2 business rates differ'::text, false::boolean, 'H1 and H2 business rates are the same (should differ)'::text;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION private.test_mileage_rate_boundary() TO service_role;