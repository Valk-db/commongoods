-- ============================================================================
-- CommonGoods RLS Regression Tests (pgTAP)
-- Run with: supabase test db
-- ============================================================================

-- Enable pgTAP extension
CREATE EXTENSION IF NOT EXISTS pgtap;

-- ----------------------------------------------------------------------------
-- Test Suite: RLS and Security
-- ----------------------------------------------------------------------------

-- Plan: 24 tests
SELECT plan(24);

-- ============================================================================
-- Test 1: profiles - FK violation when inserting without auth.users record
-- ============================================================================
DO $$
DECLARE
  v_error_code text;
BEGIN
  BEGIN
    INSERT INTO public.profiles (id, role, is_admin) VALUES (gen_random_uuid(), 'customer', true);
    RAISE EXCEPTION 'Expected FK violation';
  EXCEPTION WHEN foreign_key_violation THEN
    v_error_code := SQLSTATE;
  END;
  IF v_error_code = '23503' THEN
    PERFORM pass('INSERT with non-existent user_id should fail (FK violation)');
  ELSE
    PERFORM fail('Expected FK violation, got ' || v_error_code);
  END IF;
END;
$$;

-- ============================================================================
-- Test 2: profiles - user cannot change role on own row (trigger blocks)
-- ============================================================================
DO $$
DECLARE
  v_user_id uuid;
BEGIN
  INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, raw_user_meta_data)
  VALUES (gen_random_uuid(), 'test_role_change_' || gen_random_uuid() || '@example.com', 'test_hash', now(), jsonb_build_object('full_name', 'Test User'))
  RETURNING id INTO v_user_id;

  UPDATE public.profiles SET role = 'customer', full_name = 'Test User' WHERE id = v_user_id;

  BEGIN
    UPDATE public.profiles SET role = 'driver' WHERE id = v_user_id;
    PERFORM fail('Trigger should have blocked role change');
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = 'P0001' THEN
      PERFORM pass('UPDATE role should be blocked by trigger');
    ELSE
      PERFORM fail('Unexpected error: ' || SQLERRM);
    END IF;
  END;

  DELETE FROM auth.users WHERE id = v_user_id;
END;
$$;

-- ============================================================================
-- Test 3: profiles - user cannot change is_admin on own row (trigger blocks)
-- ============================================================================
DO $$
DECLARE
  v_user_id uuid;
BEGIN
  INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, raw_user_meta_data)
  VALUES (gen_random_uuid(), 'test_admin_change_' || gen_random_uuid() || '@example.com', 'test_hash', now(), jsonb_build_object('full_name', 'Test User'))
  RETURNING id INTO v_user_id;

  UPDATE public.profiles SET role = 'customer', full_name = 'Test User', is_admin = false WHERE id = v_user_id;

  BEGIN
    UPDATE public.profiles SET is_admin = true WHERE id = v_user_id;
    PERFORM fail('Trigger should have blocked is_admin change');
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = 'P0001' THEN
      PERFORM pass('UPDATE is_admin=true should be blocked by trigger');
    ELSE
      PERFORM fail('Unexpected error: ' || SQLERRM);
    END IF;
  END;

  DELETE FROM auth.users WHERE id = v_user_id;
END;
$$;

-- ============================================================================
-- Test 4-7: RLS policies exist on key tables
-- ============================================================================
SELECT pass('profiles SELECT policy exists')
WHERE EXISTS (
  SELECT 1 FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'profiles' AND policyname = 'profiles_select_own'
);

SELECT pass('deliveries SELECT policy exists')
WHERE EXISTS (
  SELECT 1 FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'deliveries' AND policyname = 'deliveries_select_participant'
);

SELECT pass('partners SELECT policy exists')
WHERE EXISTS (
  SELECT 1 FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'partners' AND policyname = 'partners_select_approved'
);

SELECT pass('menu_items SELECT policy exists')
WHERE EXISTS (
  SELECT 1 FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'menu_items' AND policyname = 'menu_items_select_active'
);

-- ============================================================================
-- Test 8-11: Legacy permissive policies are gone
-- ============================================================================
SELECT pass('legacy permissive SELECT policy removed from deliveries')
WHERE NOT EXISTS (
  SELECT 1 FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'deliveries' AND policyname = 'authenticated users can read deliveries'
);

SELECT pass('legacy permissive UPDATE policy removed from deliveries')
WHERE NOT EXISTS (
  SELECT 1 FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'deliveries' AND policyname = 'drivers can update deliveries'
);

SELECT pass('hardcoded admin email policy removed from partners')
WHERE NOT EXISTS (
  SELECT 1 FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'partners' AND policyname = 'Admin can manage partners'
);

SELECT pass('hardcoded admin email policy removed from menu_items')
WHERE NOT EXISTS (
  SELECT 1 FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'menu_items' AND policyname = 'Admin can manage menu items'
);

-- ============================================================================
-- Test 12-17: GRANTs to authenticated (RLS controls access, not GRANTs)
-- ============================================================================
SELECT pass('authenticated has GRANT SELECT on profiles')
WHERE EXISTS (
  SELECT 1 FROM information_schema.table_privileges
  WHERE grantee = 'authenticated' AND table_schema = 'public' AND table_name = 'profiles' AND privilege_type = 'SELECT'
);

SELECT pass('authenticated has GRANT SELECT on deliveries')
WHERE EXISTS (
  SELECT 1 FROM information_schema.table_privileges
  WHERE grantee = 'authenticated' AND table_schema = 'public' AND table_name = 'deliveries' AND privilege_type = 'SELECT'
);

SELECT pass('authenticated has GRANT SELECT on drivers')
WHERE EXISTS (
  SELECT 1 FROM information_schema.table_privileges
  WHERE grantee = 'authenticated' AND table_schema = 'public' AND table_name = 'drivers' AND privilege_type = 'SELECT'
);

SELECT pass('authenticated has GRANT SELECT on earnings')
WHERE EXISTS (
  SELECT 1 FROM information_schema.table_privileges
  WHERE grantee = 'authenticated' AND table_schema = 'public' AND table_name = 'earnings' AND privilege_type = 'SELECT'
);

SELECT pass('authenticated has GRANT SELECT on referral_codes')
WHERE EXISTS (
  SELECT 1 FROM information_schema.table_privileges
  WHERE grantee = 'authenticated' AND table_schema = 'public' AND table_name = 'referral_codes' AND privilege_type = 'SELECT'
);

SELECT pass('authenticated has GRANT SELECT on partner_applications')
WHERE EXISTS (
  SELECT 1 FROM information_schema.table_privileges
  WHERE grantee = 'authenticated' AND table_schema = 'public' AND table_name = 'partner_applications' AND privilege_type = 'SELECT'
);

-- ============================================================================
-- Test 18-21: SECURITY DEFINER functions not executable by anon
-- ============================================================================
SELECT pass('anon cannot EXECUTE is_admin()')
WHERE NOT EXISTS (
  SELECT 1 FROM information_schema.routine_privileges
  WHERE grantee = 'anon' AND routine_schema = 'public' AND routine_name = 'is_admin' AND privilege_type = 'EXECUTE'
);

SELECT pass('anon cannot EXECUTE current_role_is()')
WHERE NOT EXISTS (
  SELECT 1 FROM information_schema.routine_privileges
  WHERE grantee = 'anon' AND routine_schema = 'public' AND routine_name = 'current_role_is' AND privilege_type = 'EXECUTE'
);

SELECT pass('anon cannot EXECUTE get_my_role()')
WHERE NOT EXISTS (
  SELECT 1 FROM information_schema.routine_privileges
  WHERE grantee = 'anon' AND routine_schema = 'public' AND routine_name = 'get_my_role' AND privilege_type = 'EXECUTE'
);

SELECT pass('anon cannot EXECUTE check_user_role()')
WHERE NOT EXISTS (
  SELECT 1 FROM information_schema.routine_privileges
  WHERE grantee = 'anon' AND routine_schema = 'public' AND routine_name = 'check_user_role' AND privilege_type = 'EXECUTE'
);

-- ============================================================================
-- Test 22: All non-partitioned tables have RLS enabled
-- ============================================================================
DO $$
DECLARE
  tbl record;
  rls_enabled boolean;
  all_enabled boolean := true;
BEGIN
  FOR tbl IN
    SELECT c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'
      AND c.relname NOT LIKE 'events_%'
  LOOP
    SELECT relrowsecurity INTO rls_enabled
    FROM pg_class
    WHERE relname = tbl.relname AND relnamespace = 'public'::regnamespace;

    IF NOT rls_enabled THEN
      all_enabled := false;
      RAISE NOTICE 'Table % does not have RLS enabled', tbl.relname;
    END IF;
  END LOOP;

  IF all_enabled THEN
    PERFORM pass('All non-partitioned public tables have RLS enabled');
  ELSE
    PERFORM fail('Some tables missing RLS');
  END IF;
END;
$$;

-- ============================================================================
-- Test 23-24: Trust column freeze triggers
-- ============================================================================
DO $$
DECLARE
  v_code_id uuid;
BEGIN
  INSERT INTO public.referral_codes (code, role) VALUES ('TESTCODE_' || gen_random_uuid(), 'customer') RETURNING id INTO v_code_id;
  BEGIN
    UPDATE public.referral_codes SET is_active = false WHERE id = v_code_id;
    PERFORM fail('Trigger should have blocked is_active change');
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = 'P0001' THEN
      PERFORM pass('referral_codes.is_active freeze triggers exception');
    ELSE
      PERFORM fail('Unexpected error: ' || SQLERRM);
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
  DELETE FROM public.profiles WHERE id = v_driver_id;
  INSERT INTO public.profiles (id, role) VALUES (v_driver_id, 'driver');
  INSERT INTO public.drivers (id, approved) VALUES (v_driver_id, false);
  BEGIN
    UPDATE public.drivers SET approved = true WHERE id = v_driver_id;
    PERFORM fail('Trigger should have blocked approved change');
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = 'P0001' THEN
      PERFORM pass('drivers.approved freeze triggers exception');
    ELSE
      PERFORM fail('Unexpected error: ' || SQLERRM);
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