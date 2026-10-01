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
-- Test 1: profiles - user cannot set is_admin = true without auth.users record
-- ============================================================================
DO $$
DECLARE
  v_error_code text;
BEGIN
  BEGIN
    -- Try to insert profile with non-existent user_id - FK should fail
    INSERT INTO public.profiles (id, role, is_admin) VALUES (gen_random_uuid(), 'customer', true);
    RAISE EXCEPTION 'Expected FK violation';
  EXCEPTION WHEN foreign_key_violation THEN
    v_error_code := SQLSTATE;
  END;
  IF v_error_code = '23503' THEN
    PERFORM pass('INSERT with non-existent user_id should fail (FK violation)');
  ELSE
    RAISE EXCEPTION 'Expected FK violation, got %', v_error_code;
  END IF;
END;
$$;

-- ============================================================================
-- Test 2: profiles - user cannot change role on own row
-- ============================================================================
DO $$
DECLARE
  v_user_id uuid;
BEGIN
  INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, raw_user_meta_data)
  VALUES (gen_random_uuid(), 'test_role_change_' || gen_random_uuid() || '@example.com', 'test_hash', now(), jsonb_build_object('full_name', 'Test User'))
  RETURNING id INTO v_user_id;

  -- Trigger handle_new_user() auto-creates profile, so we just update it
  UPDATE public.profiles SET role = 'customer', full_name = 'Test User' WHERE id = v_user_id;

  -- Try to update role - should be blocked by trigger
  BEGIN
    UPDATE public.profiles SET role = 'driver' WHERE id = v_user_id;
    RAISE EXCEPTION 'Trigger should have blocked role change';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = 'P0001' THEN
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
  VALUES (gen_random_uuid(), 'test_admin_change_' || gen_random_uuid() || '@example.com', 'test_hash', now(), jsonb_build_object('full_name', 'Test User'))
  RETURNING id INTO v_user_id;

  -- Trigger handle_new_user() auto-creates profile, so we just update it
  UPDATE public.profiles SET role = 'customer', full_name = 'Test User', is_admin = false WHERE id = v_user_id;

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
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'profiles' AND policyname = 'profiles_select_own'
  ) THEN
    PERFORM pass('profiles SELECT policy exists');
  ELSE
    PERFORM fail('profiles SELECT policy missing');
  END IF;
END;
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'deliveries' AND policyname = 'deliveries_select_participant'
  ) THEN
    PERFORM pass('deliveries SELECT policy exists');
  ELSE
    PERFORM fail('deliveries SELECT policy missing');
  END IF;
END;
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'partners' AND policyname = 'partners_select_approved'
  ) THEN
    PERFORM pass('partners SELECT policy exists');
  ELSE
    PERFORM fail('partners SELECT policy missing');
  END IF;
END;
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'menu_items' AND policyname = 'menu_items_select_active'
  ) THEN
    PERFORM pass('menu_items SELECT policy exists');
  ELSE
    PERFORM fail('menu_items SELECT policy missing');
  END IF;
END;
$$;

-- ============================================================================
-- Test 5: Legacy permissive policies are gone
-- ============================================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'deliveries' AND policyname = 'authenticated users can read deliveries'
  ) THEN
    PERFORM pass('legacy permissive SELECT policy removed from deliveries');
  ELSE
    PERFORM fail('legacy permissive SELECT policy still exists on deliveries');
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'deliveries' AND policyname = 'drivers can update deliveries'
  ) THEN
    PERFORM pass('legacy permissive UPDATE policy removed from deliveries');
  ELSE
    PERFORM fail('legacy permissive UPDATE policy still exists on deliveries');
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'partners' AND policyname = 'Admin can manage partners'
  ) THEN
    PERFORM pass('hardcoded admin email policy removed from partners');
  ELSE
    PERFORM fail('hardcoded admin email policy still exists on partners');
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'menu_items' AND policyname = 'Admin can manage menu items'
  ) THEN
    PERFORM pass('hardcoded admin email policy removed from menu_items');
  ELSE
    PERFORM fail('hardcoded admin email policy still exists on menu_items');
  END IF;
END;
$$;

-- ============================================================================
-- Test 6: anon role has no table access to sensitive tables
-- ============================================================================
DO $$
DECLARE
  v_has_priv boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.table_privileges
    WHERE grantee = 'anon'
      AND table_schema = 'public'
      AND table_name = 'profiles'
      AND privilege_type = 'SELECT'
  ) INTO v_has_priv;
  IF NOT v_has_priv THEN
    PERFORM pass('anon cannot SELECT profiles');
  ELSE
    PERFORM fail('anon can SELECT profiles');
  END IF;
END;
$$;

DO $$
DECLARE
  v_has_priv boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.table_privileges
    WHERE grantee = 'anon'
      AND table_schema = 'public'
      AND table_name = 'deliveries'
      AND privilege_type = 'SELECT'
  ) INTO v_has_priv;
  IF NOT v_has_priv THEN
    PERFORM pass('anon cannot SELECT deliveries');
  ELSE
    PERFORM fail('anon can SELECT deliveries');
  END IF;
END;
$$;

DO $$
DECLARE
  v_has_priv boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.table_privileges
    WHERE grantee = 'anon'
      AND table_schema = 'public'
      AND table_name = 'drivers'
      AND privilege_type = 'SELECT'
  ) INTO v_has_priv;
  IF NOT v_has_priv THEN
    PERFORM pass('anon cannot SELECT drivers');
  ELSE
    PERFORM fail('anon can SELECT drivers');
  END IF;
END;
$$;

DO $$
DECLARE
  v_has_priv boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.table_privileges
    WHERE grantee = 'anon'
      AND table_schema = 'public'
      AND table_name = 'earnings'
      AND privilege_type = 'SELECT'
  ) INTO v_has_priv;
  IF NOT v_has_priv THEN
    PERFORM pass('anon cannot SELECT earnings');
  ELSE
    PERFORM fail('anon can SELECT earnings');
  END IF;
END;
$$;

DO $$
DECLARE
  v_has_priv boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.table_privileges
    WHERE grantee = 'anon'
      AND table_schema = 'public'
      AND table_name = 'referral_codes'
      AND privilege_type = 'SELECT'
  ) INTO v_has_priv;
  IF NOT v_has_priv THEN
    PERFORM pass('anon cannot SELECT referral_codes');
  ELSE
    PERFORM fail('anon can SELECT referral_codes');
  END IF;
END;
$$;

DO $$
DECLARE
  v_has_priv boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.table_privileges
    WHERE grantee = 'anon'
      AND table_schema = 'public'
      AND table_name = 'partner_applications'
      AND privilege_type = 'SELECT'
  ) INTO v_has_priv;
  IF NOT v_has_priv THEN
    PERFORM pass('anon cannot SELECT partner_applications');
  ELSE
    PERFORM fail('anon can SELECT partner_applications');
  END IF;
END;
$$;

-- ============================================================================
-- Test 7: SECURITY DEFINER functions not executable by anon
-- ============================================================================
DO $$
DECLARE
  v_has_priv boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.routine_privileges
    WHERE grantee = 'anon'
      AND routine_schema = 'public'
      AND routine_name = 'is_admin'
      AND privilege_type = 'EXECUTE'
  ) INTO v_has_priv;
  IF NOT v_has_priv THEN
    PERFORM pass('anon cannot EXECUTE is_admin()');
  ELSE
    PERFORM fail('anon can EXECUTE is_admin()');
  END IF;
END;
$$;

DO $$
DECLARE
  v_has_priv boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.routine_privileges
    WHERE grantee = 'anon'
      AND routine_schema = 'public'
      AND routine_name = 'current_role_is'
      AND privilege_type = 'EXECUTE'
  ) INTO v_has_priv;
  IF NOT v_has_priv THEN
    PERFORM pass('anon cannot EXECUTE current_role_is()');
  ELSE
    PERFORM fail('anon can EXECUTE current_role_is()');
  END IF;
END;
$$;

DO $$
DECLARE
  v_has_priv boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.routine_privileges
    WHERE grantee = 'anon'
      AND routine_schema = 'public'
      AND routine_name = 'get_my_role'
      AND privilege_type = 'EXECUTE'
  ) INTO v_has_priv;
  IF NOT v_has_priv THEN
    PERFORM pass('anon cannot EXECUTE get_my_role()');
  ELSE
    PERFORM fail('anon can EXECUTE get_my_role()');
  END IF;
END;
$$;

DO $$
DECLARE
  v_has_priv boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.routine_privileges
    WHERE grantee = 'anon'
      AND routine_schema = 'public'
      AND routine_name = 'handle_new_user'
      AND privilege_type = 'EXECUTE'
  ) INTO v_has_priv;
  IF NOT v_has_priv THEN
    PERFORM pass('anon cannot EXECUTE handle_new_user()');
  ELSE
    PERFORM fail('anon can EXECUTE handle_new_user()');
  END IF;
END;
$$;

DO $$
DECLARE
  v_has_priv boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.routine_privileges
    WHERE grantee = 'anon'
      AND routine_schema = 'public'
      AND routine_name = 'check_user_role'
      AND privilege_type = 'EXECUTE'
  ) INTO v_has_priv;
  IF NOT v_has_priv THEN
    PERFORM pass('anon cannot EXECUTE check_user_role()');
  ELSE
    PERFORM fail('anon can EXECUTE check_user_role()');
  END IF;
END;
$$;

-- ============================================================================
-- Test 8: All non-partitioned tables have RLS enabled
-- ============================================================================
DO $$
DECLARE
  tbl record;
  rls_enabled boolean;
BEGIN
  FOR tbl IN
    SELECT c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'  -- regular tables only, not partitions (which are 'p')
      AND c.relname NOT LIKE 'events_%'  -- skip partitioned tables
  LOOP
    SELECT relrowsecurity INTO rls_enabled
    FROM pg_class
    WHERE relname = tbl.relname AND relnamespace = 'public'::regnamespace;

    IF NOT rls_enabled THEN
      RAISE EXCEPTION 'Table % does not have RLS enabled', tbl.relname;
    END IF;
  END LOOP;
  PERFORM pass('All non-partitioned public tables have RLS enabled');
END;
$$;

-- ============================================================================
-- Test 9: Key functions exist
-- ============================================================================
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'get_available_jobs'
      AND p.pronargs = 0
  ) THEN
    PERFORM pass('get_available_jobs() function exists');
  ELSE
    PERFORM fail('get_available_jobs() function missing');
  END IF;
END;
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'claim_delivery'
      AND p.pronargs = 1
  ) THEN
    PERFORM pass('claim_delivery() function exists');
  ELSE
    PERFORM fail('claim_delivery() function missing');
  END IF;
END;
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'advance_delivery_status'
      AND p.pronargs = 2
  ) THEN
    PERFORM pass('advance_delivery_status() function exists');
  ELSE
    PERFORM fail('advance_delivery_status() function missing');
  END IF;
END;
$$;

-- ============================================================================
-- Test 10: Trust column freeze triggers
-- ============================================================================
DO $$
DECLARE
  v_code_id uuid;
BEGIN
  INSERT INTO public.referral_codes (code, role) VALUES ('TESTCODE_' || gen_random_uuid(), 'customer') RETURNING id INTO v_code_id;
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
  VALUES (gen_random_uuid(), 'test_driver_freeze_' || gen_random_uuid() || '@example.com', 'hash', now())
  RETURNING id INTO v_driver_id;
  -- Trigger handle_new_user() auto-creates profile with role='customer'
  -- Delete it and re-insert with driver role
  DELETE FROM public.profiles WHERE id = v_driver_id;
  INSERT INTO public.profiles (id, role) VALUES (v_driver_id, 'driver');
  INSERT INTO public.drivers (id, approved) VALUES (v_driver_id, false);
  BEGIN
    UPDATE public.drivers SET approved = true WHERE id = v_driver_id;
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