-- ============================================================================
-- CommonGoods security hardening
-- Run this once in the Supabase SQL editor (or via `supabase db push`).
-- Safe to re-run: uses IF EXISTS / OR REPLACE / DROP POLICY IF EXISTS throughout.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Real admin flag, instead of a hardcoded email checked only in the app
-- ----------------------------------------------------------------------------
alter table public.profiles
  add column if not exists is_admin boolean not null default false;

-- Seed the existing admin. Update the email here if it's wrong, then re-run
-- just this block.
update public.profiles p
set is_admin = true
from auth.users u
where p.id = u.id
  and u.email = 'sivalkmedia@gmail.com';

-- Helper used inside policies below. SECURITY DEFINER + a pinned search_path
-- so it can read profiles regardless of the caller's own RLS visibility into
-- that table, without being hijackable via a hostile search_path.
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(
    (select is_admin from public.profiles where id = auth.uid()),
    false
  );
$$;

create or replace function public.current_role_is(target_role text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(
    (select role = target_role from public.profiles where id = auth.uid()),
    false
  );
$$;

-- ----------------------------------------------------------------------------
-- 2. Server-side pricing integrity for deliveries
--
-- Today the client (lib/zones.ts) computes distance/zone/fee/payout/cut from
-- Mapbox and the customer's app inserts those numbers directly. Nothing stops
-- a modified client from inserting fee_charged: 0.01, driver_payout: 999, etc.
-- This trigger recomputes zone/fee/payout/cut server-side from distance_miles
-- on every insert/update, so those four columns can never diverge from the
-- zone table below no matter what the client sends.
--
-- NOTE: this does not validate that distance_miles itself is the *real*
-- route distance — that still comes from the client's Mapbox call. Closing
-- that gap fully means moving the Mapbox call into a Supabase Edge Function
-- (using a server-side Mapbox token) that computes distance and inserts the
-- row with the service-role key, rather than letting the client insert
-- directly. Happy to build that Edge Function next if you want the full
-- fix — this migration is the immediately-deployable half of it.
-- ----------------------------------------------------------------------------
create or replace function public.zone_pricing(miles double precision)
returns table(zone integer, fee numeric, driver_payout numeric, platform_cut numeric)
language sql
immutable
as $$
  select
    case
      when miles <= 5  then 1
      when miles <= 10 then 2
      when miles <= 20 then 3
      else null
    end as zone,
    case
      when miles <= 5  then 8::numeric
      when miles <= 10 then 11::numeric
      when miles <= 20 then 15::numeric
      else null
    end as fee,
    case
      when miles <= 5  then 6.00::numeric
      when miles <= 10 then 8.25::numeric
      when miles <= 20 then 11.25::numeric
      else null
    end as driver_payout,
    case
      when miles <= 5  then 2.00::numeric
      when miles <= 10 then 2.75::numeric
      when miles <= 20 then 3.75::numeric
      else null
    end as platform_cut;
$$;

create or replace function public.enforce_delivery_pricing()
returns trigger
language plpgsql
as $$
declare
  pricing record;
begin
  -- Lock down everything that defines *what* the delivery is once it
  -- exists, unless an admin is making the change. Status, driver_id,
  -- timestamps, and notes remain freely updatable for the normal
  -- claim -> pickup -> deliver flow.
  if tg_op = 'UPDATE' and not public.is_admin() then
    new.customer_id      := old.customer_id;
    new.partner_id        := old.partner_id;
    new.category          := old.category;
    new.pickup_address     := old.pickup_address;
    new.pickup_lat        := old.pickup_lat;
    new.pickup_lng        := old.pickup_lng;
    new.dropoff_address    := old.dropoff_address;
    new.dropoff_lat       := old.dropoff_lat;
    new.dropoff_lng       := old.dropoff_lng;
    new.distance_miles     := old.distance_miles;
    new.requested_at      := old.requested_at;
  end if;

  -- Admins can hand-edit zone/fee/payout/cut directly (e.g. comping a
  -- delivery); everyone else gets it recomputed from distance_miles,
  -- full stop.
  if not public.is_admin() then
    select * into pricing from public.zone_pricing(new.distance_miles);
    if pricing.zone is null then
      raise exception 'OUTSIDE_SERVICE_AREA';
    end if;
    new.zone_assigned := pricing.zone;
    new.fee_charged   := pricing.fee;
    new.driver_payout := pricing.driver_payout;
    new.platform_cut  := pricing.platform_cut;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_delivery_pricing on public.deliveries;
create trigger trg_enforce_delivery_pricing
  before insert or update on public.deliveries
  for each row execute function public.enforce_delivery_pricing();

-- ----------------------------------------------------------------------------
-- 3. Row Level Security
-- ----------------------------------------------------------------------------
alter table public.profiles            enable row level security;
alter table public.partners            enable row level security;
alter table public.deliveries          enable row level security;
alter table public.route_points        enable row level security;
alter table public.earnings            enable row level security;
alter table public.partner_applications enable row level security;
alter table public.menu_items          enable row level security;

-- ---- profiles --------------------------------------------------------------
drop policy if exists "profiles_select_own_or_admin" on public.profiles;
create policy "profiles_select_own_or_admin" on public.profiles
  for select using (id = auth.uid() or public.is_admin());

drop policy if exists "profiles_update_own_limited" on public.profiles;
create policy "profiles_update_own_limited" on public.profiles
  for update using (id = auth.uid() or public.is_admin())
  with check (
    public.is_admin()
    -- non-admins can edit their own row but never grant themselves is_admin
    or (id = auth.uid() and is_admin = false)
  );

-- profile rows are created by your handle_new_user trigger on auth.users
-- (running as the trigger owner, not the end user), so no public insert
-- policy is needed here. If you insert profiles some other way, add one.

-- ---- partners ---------------------------------------------------------------
drop policy if exists "partners_select_approved_or_own_or_admin" on public.partners;
create policy "partners_select_approved_or_own_or_admin" on public.partners
  for select using (
    approved = true
    or profile_id = auth.uid()
    or public.is_admin()
  );

drop policy if exists "partners_insert_admin_only" on public.partners;
create policy "partners_insert_admin_only" on public.partners
  for insert with check (public.is_admin());

drop policy if exists "partners_update_own_or_admin" on public.partners;
create policy "partners_update_own_or_admin" on public.partners
  for update using (profile_id = auth.uid() or public.is_admin())
  with check (profile_id = auth.uid() or public.is_admin());

-- Partners can edit their own listing's editable fields (address, pickup
-- notes, POS system, etc.) but shouldn't be able to self-approve or hand
-- themselves founding-merchant/fee-paid status by crafting an update
-- payload. Lock those columns back to their stored value unless an admin
-- is making the change.
create or replace function public.enforce_partner_admin_fields()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'UPDATE' and not public.is_admin() then
    new.approved             := old.approved;
    new.founding_merchant    := old.founding_merchant;
    new.onboarding_fee_paid  := old.onboarding_fee_paid;
    new.joined_during_pilot  := old.joined_during_pilot;
    new.profile_id           := old.profile_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_partner_admin_fields on public.partners;
create trigger trg_enforce_partner_admin_fields
  before update on public.partners
  for each row execute function public.enforce_partner_admin_fields();

-- ---- deliveries ---------------------------------------------------------------
drop policy if exists "deliveries_select_participant_or_pending_driver_or_admin" on public.deliveries;
create policy "deliveries_select_participant_or_pending_driver_or_admin" on public.deliveries
  for select using (
    customer_id = auth.uid()
    or driver_id = auth.uid()
    or public.is_admin()
    or (status = 'pending' and public.current_role_is('driver'))
    or partner_id in (select id from public.partners where profile_id = auth.uid())
  );

drop policy if exists "deliveries_insert_own_as_customer" on public.deliveries;
create policy "deliveries_insert_own_as_customer" on public.deliveries
  for insert with check (
    customer_id = auth.uid()
    and status = 'pending'
    and driver_id is null
  );

drop policy if exists "deliveries_update_participant_or_admin" on public.deliveries;
create policy "deliveries_update_participant_or_admin" on public.deliveries
  for update using (
    public.is_admin()
    or driver_id = auth.uid()
    or customer_id = auth.uid()
    or (status = 'pending' and public.current_role_is('driver'))
  )
  with check (
    public.is_admin()
    or driver_id = auth.uid()
    or (customer_id = auth.uid() and status in ('pending', 'cancelled'))
  );

-- ---- route_points ---------------------------------------------------------------
drop policy if exists "route_points_select_participant_or_admin" on public.route_points;
create policy "route_points_select_participant_or_admin" on public.route_points
  for select using (
    public.is_admin()
    or exists (
      select 1 from public.deliveries d
      where d.id = route_points.delivery_id
        and (d.customer_id = auth.uid() or d.driver_id = auth.uid())
    )
  );

drop policy if exists "route_points_insert_assigned_driver" on public.route_points;
create policy "route_points_insert_assigned_driver" on public.route_points
  for insert with check (
    exists (
      select 1 from public.deliveries d
      where d.id = route_points.delivery_id
        and d.driver_id = auth.uid()
    )
  );

-- ---- earnings ---------------------------------------------------------------
drop policy if exists "earnings_select_own_or_admin" on public.earnings;
create policy "earnings_select_own_or_admin" on public.earnings
  for select using (driver_id = auth.uid() or public.is_admin());

-- earnings rows are written by your backend logic (e.g. a trigger when a
-- delivery completes, or an Edge Function), not directly by the client —
-- no insert/update policy is granted to regular users on purpose.

-- ---- partner_applications ---------------------------------------------------------------
drop policy if exists "partner_applications_insert_public" on public.partner_applications;
create policy "partner_applications_insert_public" on public.partner_applications
  for insert with check (status = 'pending');

drop policy if exists "partner_applications_select_admin_only" on public.partner_applications;
create policy "partner_applications_select_admin_only" on public.partner_applications
  for select using (public.is_admin());

drop policy if exists "partner_applications_update_admin_only" on public.partner_applications;
create policy "partner_applications_update_admin_only" on public.partner_applications
  for update using (public.is_admin());

-- ---- menu_items ---------------------------------------------------------------
drop policy if exists "menu_items_select_active_or_own_or_admin" on public.menu_items;
create policy "menu_items_select_active_or_own_or_admin" on public.menu_items
  for select using (
    active = true
    or public.is_admin()
    or partner_id in (select id from public.partners where profile_id = auth.uid())
  );

drop policy if exists "menu_items_insert_own_partner_or_admin" on public.menu_items;
create policy "menu_items_insert_own_partner_or_admin" on public.menu_items
  for insert with check (
    public.is_admin()
    or partner_id in (select id from public.partners where profile_id = auth.uid())
  );

drop policy if exists "menu_items_update_own_partner_or_admin" on public.menu_items;
create policy "menu_items_update_own_partner_or_admin" on public.menu_items
  for update using (
    public.is_admin()
    or partner_id in (select id from public.partners where profile_id = auth.uid())
  );