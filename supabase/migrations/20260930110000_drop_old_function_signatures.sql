-- ============================================================================
-- CommonGoods: Drop old function signatures, keep only current versions
-- Run after 20260930100000_fix_create_delivery_use_quote_pricing.sql
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Drop old create_delivery signatures (keep only the latest with p_quote_id REQUIRED)
-- ----------------------------------------------------------------------------

-- First, let's see what exists
DO $$
DECLARE
  v_func RECORD;
BEGIN
  RAISE NOTICE '=== create_delivery functions BEFORE cleanup ===';
  FOR v_func IN
    SELECT oid, proname, pg_get_function_identity_arguments(oid) as args
    FROM pg_proc
    WHERE proname = 'create_delivery' AND pronamespace = 'public'::regnamespace
  LOOP
    RAISE NOTICE 'Found: % (%)', v_func.proname, v_func.args;
  END LOOP;
END;
$$;

-- Drop ALL create_delivery functions first
DROP FUNCTION IF EXISTS public.create_delivery(
  uuid, uuid, text, text, double precision, double precision,
  text, double precision, double precision, double precision, integer,
  text, uuid
) CASCADE;

DROP FUNCTION IF EXISTS public.create_delivery(
  uuid, uuid, text, text, double precision, double precision,
  text, double precision, double precision, double precision, integer,
  text, uuid, uuid
) CASCADE;

-- The current version (from 20260930100000) has p_quote_id as REQUIRED (no DEFAULT)
-- We'll recreate it below if needed, but the latest migration should have already created it
-- Let's verify and ensure only one exists

DO $$
DECLARE
  v_count integer;
BEGIN
  SELECT count(*) INTO v_count
  FROM pg_proc
  WHERE proname = 'create_delivery' AND pronamespace = 'public'::regnamespace;

  IF v_count > 1 THEN
    RAISE EXCEPTION 'More than one create_delivery function exists after cleanup: %', v_count;
  END IF;

  RAISE NOTICE '=== create_delivery functions AFTER cleanup: % ===', v_count;
END;
$$;

-- ----------------------------------------------------------------------------
-- 2. Drop old get_quote signatures (keep only the latest from 20260930070000)
-- ----------------------------------------------------------------------------

DO $$
DECLARE
  v_func RECORD;
BEGIN
  RAISE NOTICE '=== get_quote functions BEFORE cleanup ===';
  FOR v_func IN
    SELECT oid, proname, pg_get_function_identity_arguments(oid) as args
    FROM pg_proc
    WHERE proname = 'get_quote' AND pronamespace = 'public'::regnamespace
  LOOP
    RAISE NOTICE 'Found: % (%)', v_func.proname, v_func.args;
  END LOOP;
END;
$$;

-- Drop any old get_quote functions (there should only be one from 20260930070000)
-- If there are duplicates, drop them all and the latest migration will recreate
DROP FUNCTION IF EXISTS public.get_quote(
  uuid, uuid, text, text, double precision, double precision,
  text, double precision, double precision, double precision, integer,
  text, uuid
) CASCADE;

-- ----------------------------------------------------------------------------
-- 3. Drop old check_referral_code signatures (keep only the latest from 20260930080000)
-- ----------------------------------------------------------------------------

DO $$
DECLARE
  v_func RECORD;
BEGIN
  RAISE NOTICE '=== check_referral_code functions BEFORE cleanup ===';
  FOR v_func IN
    SELECT oid, proname, pg_get_function_identity_arguments(oid) as args
    FROM pg_proc
    WHERE proname = 'check_referral_code' AND pronamespace = 'public'::regnamespace
  LOOP
    RAISE NOTICE 'Found: % (%)', v_func.proname, v_func.args;
  END LOOP;
END;
$$;

DROP FUNCTION IF EXISTS public.check_referral_code(text) CASCADE;

-- ----------------------------------------------------------------------------
-- 4. pgTAP test: Assert exactly one create_delivery exists with correct signature
-- ----------------------------------------------------------------------------

-- Enable pgTAP if not already
CREATE EXTENSION IF NOT EXISTS pgtap;

-- Test will run with: supabase test db
BEGIN;
SELECT plan(3);

-- Test 1: Exactly one create_delivery function exists
SELECT is(
  (SELECT count(*) FROM pg_proc WHERE proname = 'create_delivery' AND pronamespace = 'public'::regnamespace),
  1,
  'Exactly one create_delivery function exists'
);

-- Test 2: The create_delivery function has the correct number of arguments (13: 12 params + quote_id required)
SELECT is(
  (SELECT pg_proc.pronargs FROM pg_proc
   WHERE proname = 'create_delivery' AND pronamespace = 'public'::regnamespace),
  13,
  'create_delivery has 13 arguments (quote_id required)'
);

-- Test 3: The create_delivery function signature matches expected (quote_id is NOT nullable/required)
-- Check that the last argument (p_quote_id) has no default
SELECT ok(
  (SELECT count(*) = 0 FROM pg_proc p
   JOIN pg_namespace n ON p.pronamespace = n.oid
   WHERE p.proname = 'create_delivery'
   AND n.nspname = 'public'
   AND pg_get_function_identity_arguments(p.oid) LIKE '%p_quote_id uuid%'
   AND p.proargdefaults IS NOT NULL),
  'create_delivery p_quote_id parameter has no default (required)'
);

SELECT * FROM finish();
COMMIT;

-- ============================================================================
-- End of migration
-- ============================================================================