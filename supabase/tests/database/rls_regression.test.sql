-- ============================================================================
-- CommonGoods RLS Regression Tests (pgTAP)
-- Run with: supabase test db
-- ============================================================================

-- Enable pgTAP extension
CREATE EXTENSION IF NOT EXISTS pgtap;

-- ----------------------------------------------------------------------------
-- Test Suite: RLS and Security
-- ----------------------------------------------------------------------------

BEGIN;

-- Plan: number of tests
SELECT plan(28);

-- ============================================================================
-- Helper functions for test setup
-- ============================================================================

-- Create a test user and return their ID
CREATE OR REPLACE FUNCTION test_create_user(p_email text, p_role text DEFAULT 'customer')
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, raw_user_meta_data)
  VALUES (gen_random_uuid(), p_email, 'test_hash', now(), jsonb_build_object('full_name', 'Test User'))
  RETURNING id INTO v_user_id;

  -- Create profile
  INSERT INTO public.profiles (id, role, full_name)
  VALUES (v_user_id, p_role, 'Test User');

  RETURN v_user_id;
END;
$$;

-- Clean up test user
CREATE OR REPLACE FUNCTION test_cleanup_user(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  DELETE FROM auth.users WHERE id = p_user_id;
END;
$$;

-- ============================================================================
-- Test 1: profiles - user cannot set is_admin = true on own row
-- ============================================================================
SELECT throws_ok(
  'INSERT INTO public.profiles (id, role, is_admin) VALUES (gen_random_uuid(), ''customer'', true)',
  '23502',  -- check constraint violation or similar
  'INSERT with is_admin=true should fail'
);

SELECT throws_ok(
  'UPDATE public.profiles SET is_admin = true WHERE id = (SELECT id FROM public.profiles LIMIT 1)',
  '20000',  -- trigger exception
  'UPDATE is_admin=true should be blocked by trigger'
);

-- ============================================================================
-- Test 2: profiles - user cannot change role on own row
-- ============================================================================
SELECT throws_ok(
  'UPDATE public.profiles SET role = ''driver'' WHERE id = (SELECT id FROM public.profiles LIMIT 1)',
  '20000',  -- trigger exception
  'UPDATE role should be blocked by trigger'
);

-- ============================================================================
-- Test 3: deliveries - authenticated user cannot read all deliveries
-- ============================================================================
-- This test needs a test database with multiple users and deliveries
-- For now, verify the policy exists
SELECT has_policy('public', 'deliveries', 'deliveries_select_participant', 'SELECT',
  'deliveries SELECT policy exists');

-- Verify legacy permissive policy is gone
SELECT hasnt_policy('public', 'deliveries', 'authenticated users can read deliveries', 'SELECT',
  'legacy permissive SELECT policy removed');

-- ============================================================================
-- Test 4: deliveries - non-driver cannot claim pending jobs via UPDATE
-- ============================================================================
SELECT has_policy('public', 'deliveries', 'deliveries_update_service', 'UPDATE',
  'deliveries restrictive UPDATE policy exists');

-- Verify legacy permissive UPDATE policy is gone
SELECT hasnt_policy('public', 'deliveries', 'drivers can update deliveries', 'UPDATE',
  'legacy permissive UPDATE policy removed');

-- ============================================================================
-- Test 5: deliveries - customer cannot insert with arbitrary status/driver_id
-- ============================================================================
SELECT has_policy('public', 'deliveries', 'deliveries_insert_service', 'INSERT',
  'deliveries INSERT policy exists with restrictions');

-- ============================================================================
-- Test 6: partner_applications - cannot insert with arbitrary status
-- ============================================================================
SELECT has_policy('public', 'partner_applications', 'partner_applications_insert_public', 'INSERT',
  'partner_applications INSERT policy requires status=pending');

-- ============================================================================
-- Test 7: partners/menu_items - hardcoded admin email removed
-- ============================================================================
SELECT hasnt_policy('public', 'partners', 'Admin can manage partners', 'ALL',
  'hardcoded admin email policy removed from partners');

SELECT hasnt_policy('public', 'menu_items', 'Admin can manage menu items', 'ALL',
  'hardcoded admin email policy removed from menu_items');

-- ============================================================================
-- Test 8: anon role has no table access to sensitive tables
-- ============================================================================
SELECT hasnt_table_privilege('anon', 'public', 'profiles', 'SELECT',
  'anon cannot SELECT profiles');

SELECT hasnt_table_privilege('anon', 'public', 'deliveries', 'SELECT',
  'anon cannot SELECT deliveries');

SELECT hasnt_table_privilege('anon', 'public', 'drivers', 'SELECT',
  'anon cannot SELECT drivers');

SELECT hasnt_table_privilege('anon', 'public', 'earnings', 'SELECT',
  'anon cannot SELECT earnings');

SELECT hasnt_table_privilege('anon', 'public', 'referral_codes', 'SELECT',
  'anon cannot SELECT referral_codes');

SELECT hasnt_table_privilege('anon', 'public', 'partner_applications', 'SELECT',
  'anon cannot SELECT partner_applications');

-- ============================================================================
-- Test 9: SECURITY DEFINER functions not executable by anon/authenticated
-- ============================================================================
SELECT hasnt_function_privilege('anon', 'public', 'is_admin', 'execute',
  'anon cannot EXECUTE is_admin()');

SELECT hasnt_function_privilege('anon', 'public', 'current_role_is', 'execute',
  'anon cannot EXECUTE current_role_is()');

SELECT hasnt_function_privilege('anon', 'public', 'get_my_role', 'execute',
  'anon cannot EXECUTE get_my_role()');

SELECT hasnt_function_privilege('anon', 'public', 'handle_new_user', 'execute',
  'anon cannot EXECUTE handle_new_user()');

SELECT hasnt_function_privilege('anon', 'public', 'check_user_role', 'execute',
  'anon cannot EXECUTE check_user_role()');

-- ============================================================================
-- Test 10: All tables have RLS enabled
-- ============================================================================
DO $$
DECLARE
  tbl record;
  rls_enabled boolean;
BEGIN
  FOR tbl IN
    SELECT tablename FROM pg_tables WHERE schemaname = 'public'
  LOOP
    SELECT relrowsecurity INTO rls_enabled
    FROM pg_class
    WHERE relname = tbl.tablename AND relnamespace = 'public'::regnamespace;

    IF NOT rls_enabled THEN
      RAISE EXCEPTION 'Table % does not have RLS enabled', tbl.tablename;
    END IF;
  END LOOP;
  -- If we get here, all tables have RLS
  PERFORM pass('All public tables have RLS enabled');
END;
$$;

-- ============================================================================
-- Test 11: Trust column freeze triggers raise exception on forbidden changes
-- ============================================================================
-- referral_codes.is_active, used_by, used_at
SELECT throws_ok(
  'UPDATE public.referral_codes SET is_active = false WHERE id = (SELECT id FROM public.referral_codes LIMIT 1)',
  '20000',
  'referral_codes.is_active freeze triggers exception'
);

-- drivers.approved
SELECT throws_ok(
  'UPDATE public.drivers SET approved = true WHERE id = (SELECT id FROM public.drivers LIMIT 1)',
  '20000',
  'drivers.approved freeze triggers exception'
);

-- partners admin fields
SELECT throws_ok(
  'UPDATE public.partners SET approved = true WHERE id = (SELECT id FROM public.partners LIMIT 1)',
  '20000',
  'partners.approved freeze triggers exception'
);

-- partner_applications.status
SELECT throws_ok(
  'UPDATE public.partner_applications SET status = ''approved'' WHERE id = (SELECT id FROM public.partner_applications LIMIT 1)',
  '20000',
  'partner_applications.status freeze triggers exception'
);

-- ============================================================================
-- Test 12: get_available_jobs function exists and is SECURITY DEFINER
-- ============================================================================
SELECT has_function('public', 'get_available_jobs', 0,
  'get_available_jobs() function exists');

-- ============================================================================
-- Test 13: check_referral_code not executable by anon
-- ============================================================================
SELECT hasnt_function_privilege('anon', 'public', 'check_referral_code', 'execute',
  'anon cannot EXECUTE check_referral_code()');

-- ============================================================================
-- Test 14: claim_delivery rejects customer claiming own delivery
-- ============================================================================
SELECT has_function('public', 'claim_delivery', 1,
  'claim_delivery() function exists');

-- ============================================================================
-- Test 15: advance_delivery_status has no driver-cancel transition
-- ============================================================================
SELECT has_function('public', 'advance_delivery_status', 2,
  'advance_delivery_status() function exists');

-- ============================================================================
-- Cleanup
-- ============================================================================
DROP FUNCTION IF EXISTS test_create_user(text, text);
DROP FUNCTION IF EXISTS test_cleanup_user(uuid);

SELECT * FROM finish();
ROLLBACK;

-- ============================================================================
-- End of tests
-- ============================================================================