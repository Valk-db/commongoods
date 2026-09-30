-- ============================================================================
-- CommonGoods: Events Default Partition and pg_cron Setup
-- Run after 20260930080000_update_check_referral_code.sql
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Add default partition to catch any rows outside defined ranges
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.events_default
  PARTITION OF public.events
  DEFAULT;

CREATE INDEX IF NOT EXISTS events_default_actor_id_idx ON public.events_default (actor_id);
CREATE INDEX IF NOT EXISTS events_default_entity_idx ON public.events_default (entity_type, entity_id);
CREATE INDEX IF NOT EXISTS events_default_name_idx ON public.events_default (name);
CREATE INDEX IF NOT EXISTS events_default_received_idx ON public.events_default (received_at);
CREATE INDEX IF NOT EXISTS events_default_idempotency_idx ON public.events_default (idempotency_key);

-- ----------------------------------------------------------------------------
-- 2. Add audience field to event_catalog for access control
-- ----------------------------------------------------------------------------

ALTER TABLE public.event_catalog
  ADD COLUMN IF NOT EXISTS audience text NOT NULL DEFAULT 'all'
    CHECK (audience IN ('all', 'customer', 'driver', 'partner', 'admin', 'system'));

-- Update existing events to have appropriate audience
UPDATE public.event_catalog SET audience = 'driver'
WHERE name IN ('offer_shown', 'offer_viewed', 'offer_accepted', 'offer_declined', 'offer_expired',
               'driver_online', 'driver_offline');

UPDATE public.event_catalog SET audience = 'customer'
WHERE name IN ('quote_viewed', 'order_placed', 'order_edited', 'cancel_tapped',
               'search_no_results', 'out_of_area', 'tip_added', 'rating_given', 'support_opened');

UPDATE public.event_catalog SET audience = 'partner'
WHERE name IN ('delivery_started', 'arrived_pickup', 'picked_up', 'arrived_dropoff',
               'delivered', 'proof_captured');

UPDATE public.event_catalog SET audience = 'admin'
WHERE name IN ('crash', 'error', 'permission_granted', 'permission_denied');

-- ----------------------------------------------------------------------------
-- 3. Add pg_cron job to create next month's partition
-- ----------------------------------------------------------------------------

-- Enable pg_cron extension if not already enabled
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Function to create next month's partition
CREATE OR REPLACE FUNCTION public.create_next_events_partition()
RETURNS void
LANGUAGE plpgsql
SET search_path = public, private
AS $$
DECLARE
  v_start date := date_trunc('month', (now() + interval '1 month'))::date;
  v_end date := v_start + interval '1 month';
  v_partition_name text;
  v_default_exists boolean;
BEGIN
  v_partition_name := 'events_' || to_char(v_start, 'YYYY_MM');

  -- Check if partition already exists
  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = v_partition_name AND n.nspname = 'public'
  ) THEN
    RAISE NOTICE 'Partition % already exists', v_partition_name;
    RETURN;
  END IF;

  -- Check if default partition exists and detach it
  SELECT EXISTS (
    SELECT 1 FROM pg_inherits i
    JOIN pg_class c ON c.oid = i.inhrelid
    JOIN pg_class p ON p.oid = i.inhparent
    WHERE p.relname = 'events' AND c.relname = 'events_default'
  ) INTO v_default_exists;

  IF v_default_exists THEN
    ALTER TABLE public.events DETACH PARTITION public.events_default;
  END IF;

  -- Create the new partition
  EXECUTE format(
    'CREATE TABLE %I PARTITION OF public.events
     FOR VALUES FROM (%L) TO (%L)',
    v_partition_name, v_start, v_end
  );

  -- Create indexes on the new partition
  EXECUTE format('CREATE INDEX IF NOT EXISTS %I_actor_id_idx ON %I (actor_id)', v_partition_name, v_partition_name);
  EXECUTE format('CREATE INDEX IF NOT EXISTS %I_entity_idx ON %I (entity_type, entity_id)', v_partition_name, v_partition_name);
  EXECUTE format('CREATE INDEX IF NOT EXISTS %I_name_idx ON %I (name)', v_partition_name, v_partition_name);
  EXECUTE format('CREATE INDEX IF NOT EXISTS %I_received_idx ON %I (received_at)', v_partition_name, v_partition_name);
  EXECUTE format('CREATE INDEX IF NOT EXISTS %I_idempotency_idx ON %I (idempotency_key)', v_partition_name, v_partition_name);

  -- Reattach default partition
  IF v_default_exists THEN
    ALTER TABLE public.events ATTACH PARTITION public.events_default DEFAULT;
  END IF;

  RAISE NOTICE 'Created partition % for range % to %', v_partition_name, v_start, v_end;
END;
$$;

-- Schedule the partition creation job to run on the 1st of each month at 00:05 UTC
SELECT cron.schedule(
  'create-monthly-events-partition',
  '5 0 1 * *',  -- 00:05 on the 1st of every month
  $$SELECT public.create_next_events_partition();$$
);

-- ----------------------------------------------------------------------------
-- 4. Grant execute permission on the partition function
-- ----------------------------------------------------------------------------

GRANT EXECUTE ON FUNCTION public.create_next_events_partition() TO service_role, postgres;

-- ============================================================================
-- End of migration
-- ============================================================================