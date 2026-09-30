-- ============================================================================
-- CommonGoods: Fix Pricing Bypass - Remove Client INSERT on Deliveries
-- Run after 20260930053357_fix_pricing_sql_functions.sql
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Drop the legacy client INSERT policy that allows bypassing pricing
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS "deliveries_insert_own_as_customer" ON public.deliveries;
DROP POLICY IF EXISTS "Customers can create deliveries" ON public.deliveries;
DROP POLICY IF EXISTS "customers can insert deliveries" ON public.deliveries;
DROP POLICY IF EXISTS "Customers or Partners can create a delivery" ON public.deliveries;

-- ----------------------------------------------------------------------------
-- 2. Revoke GRANT INSERT on deliveries from authenticated (and anon)
--    Only service_role should be able to insert deliveries (via create_delivery RPC)
-- ----------------------------------------------------------------------------

REVOKE INSERT ON public.deliveries FROM authenticated;
REVOKE INSERT ON public.deliveries FROM anon;

-- Grant INSERT only to service_role
GRANT INSERT ON public.deliveries TO service_role;

-- ----------------------------------------------------------------------------
-- 3. Ensure the create_delivery RPC is executable only by service_role
-- ----------------------------------------------------------------------------

REVOKE EXECUTE ON FUNCTION public.create_delivery(
  uuid, uuid, text, text, double precision, double precision,
  text, double precision, double precision, double precision, integer,
  text, uuid
) FROM anon, authenticated;

GRANT EXECUTE ON FUNCTION public.create_delivery(
  uuid, uuid, text, text, double precision, double precision,
  text, double precision, double precision, double precision, integer,
  text, uuid
) TO service_role;

-- ----------------------------------------------------------------------------
-- 4. Also revoke execute on zone_pricing from anon/authenticated
--    (clients should not compute pricing)
-- ----------------------------------------------------------------------------

REVOKE EXECUTE ON FUNCTION public.zone_pricing(double precision) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.zone_pricing(double precision) TO service_role;

-- ============================================================================
-- End of migration
-- ============================================================================