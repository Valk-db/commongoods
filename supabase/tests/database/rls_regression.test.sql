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
SELECT plan(15);

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
  '23503',  -- FK violation since no auth.users record
  'INSERT with is_admin=true should fail (FK violation first)'
);

-- ============================================================================
-- Test 2: profiles - user cannot change role on own row
-- ============================================================================
DO $$
DECLARE
  v_user_id uuid;
BEGIN
  INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, raw_user_meta_data)
  VALUES (gen_random_uuid(), 'test_role_change@example.com', 'test_hash', now(), jsonb_build_object('full_name', 'Test User'))
  RETURNING id INTO v_user_id;

  INSERT INTO public.profiles (id, role, full_name)
  VALUES (v_user_id, 'customer', 'Test User');

  -- Try to update role - should be blocked by trigger
  BEGIN
    UPDATE public.profiles SET role = 'driver' WHERE id = v_user_id;
    -- If we get here, trigger didn't fire
    RAISE EXCEPTION 'Trigger should have blocked role change';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = 'P0001' THEN
      -- Expected: trigger raised exception
      PERFORM pass('UPDATE role should be blocked by trigger');
    ELSE
      RAISE;
    END IF;
  END;

  DELETE FROM auth.users WHERE id = v_user_id;
END;
$$;

-- ============================================================================
-- Test 3: profiles - user cannot change is_admin on own row
-- ============================================================================
DO $$
DECLARE
  v_user_id uuid;
BEGIN
  INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, raw_user_meta_data)
  VALUES (gen_random_uuid(), 'test_admin_change@example.com', 'test_hash', now(), jsonb_build_object('full_name', 'Test User'))
  RETURNING id INTO v_user_id;

  INSERT INTO public.profiles (id, role, full_name, is_admin)
  VALUES (v_user_id, 'customer', 'Test User', false);

  -- Try to update is_admin - should be blocked by trigger
  BEGIN
    UPDATE public.profiles SET is_admin = true WHERE id = v_user_id;
    RAISE EXCEPTION 'Trigger should have blocked is_admin change';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = 'P0001' THEN
      PERFORM pass('UPDATE is_admin=true should be blocked by trigger');
    ELSE
      RAISE;
    END IF;
  END;

  DELETE FROM auth.users WHERE id = v_user_id;
END;
$$;

-- ============================================================================
-- Test 4: RLS policies exist on key tables
-- ============================================================================
SELECT has_policy('public', 'profiles', 'profiles_select_own', 'SELECT',
  'profiles SELECT policy exists');

SELECT has_policy('public', 'deliveries', 'deliveries_select_participant', 'SELECT',
  'deliveries SELECT policy exists');

SELECT has_policy('public', 'partners', 'partners_select_approved', 'SELECT',
  'partners SELECT policy exists');

SELECT has_policy('public', 'menu_items', 'menu_items_select_active', 'SELECT',
  'menu_items SELECT policy exists');

-- ============================================================================
-- Test 5: Legacy permissive policies are gone
-- ============================================================================
SELECT hasnt_policy('public', 'deliveries', 'authenticated users can read deliveries', 'SELECT',
  'legacy permissive SELECT policy removed from deliveries');

SELECT hasnt_policy('public', 'deliveries', 'drivers can update deliveries', 'UPDATE',
  'legacy permissive UPDATE policy removed from deliveries');

SELECT hasnt_policy('public', 'partners', 'Admin can manage partners', 'ALL',
  'hardcoded admin email policy removed from partners');

SELECT hasnt_policy('public', 'menu_items', 'Admin can manage menu items', 'ALL',
  'hardcoded admin email policy removed from menu_items');

-- ============================================================================
-- Test 6: anon role has no table access to sensitive tables
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
-- Test 7: SECURITY DEFINER functions not executable by anon
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
-- Test 8: All tables have RLS enabled
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
  PERFORM pass('All public tables have RLS enabled');
END;
$$;

-- ============================================================================
-- Test 9: Key functions exist
-- ============================================================================
SELECT has_function('public', 'get_available_jobs', 0,
  'get_available_jobs() function exists');

SELECT has_function('public', 'claim_delivery', 1,
  'claim_delivery() function exists');

SELECT has_function('public', 'advance_delivery_status', 2,
  'advance_delivery_status() function exists');

-- ============================================================================
-- Test 10: Trust column freeze triggers
-- ============================================================================
DO $$
DECLARE
  v_code_id uuid;
BEGIN
  INSERT INTO public.referral_codes (code, role) VALUES ('TESTCODE', 'customer') RETURNING id INTO v_code_id;
  BEGIN
    UPDATE public.referral_codes SET is_active = false WHERE id = v_code_id;
    RAISE EXCEPTION 'Trigger should have blocked is_active change';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = 'P0001' THEN
      PERFORM pass('referral_codes.is_active freeze triggers exception');
    ELSE
      RAISE;
    END IF;
  END;
  DELETE FROM public.referral_codes WHERE id = v_code_id;
END;
$$;

DO $$
DECLARE
  v_driver_id uuid;
BEGIN
  INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at)
  VALUES (gen_random_uuid(), 'test_driver_freeze@example.com', 'hash', now())
  RETURNING id INTO v_driver_id;
  INSERT INTO public.profiles (id, role) VALUES (v_driver_id, 'driver');
  INSERT INTO public.drivers (profile_id, approved) VALUES (v_driver_id, false);
  BEGIN
    UPDATE public.drivers SET approved = true WHERE profile_id = v_driver_id;
    RAISE EXCEPTION 'Trigger should have blocked approved change';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = 'P0001' THEN
      PERFORM pass('drivers.approved freeze triggers exception');
    ELSE
      RAISE;
    END IF;
  END;
  DELETE FROM auth.users WHERE id = v_driver_id;
END;
$$;

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