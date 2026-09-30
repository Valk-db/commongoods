# CommonGoods Database Schema

Generated from live Supabase project `egadbxrflihbelknvpxc` (PostgreSQL 17.6)

## Entity-Relationship Diagram

```
auth.users (Supabase Auth)
    │
    ├── 1:1 ── profiles
    │           │
    │           ├── 1:1 ── drivers (approved, is_online, vehicle_type)
    │           ├── 1:1 ── partners (profile_id, approved, business_name, lat/lng)
    │           │
    │           ├── 1:N ── deliveries (customer_id)
    │           ├── 1:N ── deliveries (driver_id)
    │           │
    │           ├── 1:N ── partner_applications (submitted by user)
    │           ├── 1:N ── referral_codes (used_by)
    │           ├── 1:N ── earnings (driver_id)
    │           ├── 1:N ── ratings_and_reviews (reviewer_id, reviewee_id)
    │           └── 1:N ── delivery_messages (sender_id)
    │
    ├── 1:N ── deliveries
    │           │
    │           ├── 1:N ── delivery_items
    │           │           └── 1:N ── delivery_item_options
    │           ├── 1:N ── delivery_messages
    │           ├── 1:N ── delivery_status_history
    │           ├── 1:N ── route_points
    │           ├── 1:N ── earnings
    │           ├── 1:N ── performance_metrics
    │           └── 1:N ── ratings_and_reviews
    │
    ├── 1:N ── partners
    │           │
    │           ├── 1:N ── menu_items
    │           │           └── 1:N ── menu_item_options
    │           └── 1:N ── deliveries (partner_id)
    │
    └── 1:N ── referral_codes (created by admin)

```

## Tables (17 public tables)

### Core Auth & Profiles

| Table | Columns | Description |
|-------|---------|-------------|
| `profiles` | `id` (PK, FK→auth.users), `role` (customer/driver/partner), `full_name`, `phone`, `created_at`, `is_admin`, `priority_score`, `lifetime_deliveries`, `cancellation_rate`, `historical_tip_ratio` | Extended user profile, frozen `is_admin`/`role` |
| `drivers` | `id` (PK, FK→profiles), `is_online`, `vehicle_type`, `approved`, `updated_at` | Driver-specific fields, frozen `approved` |
| `partners` | `id` (PK), `profile_id` (FK→profiles), `business_name`, `address`, `lat`, `lng`, `pickup_notes`, `pos_system`, `approved`, `created_at`, `founding_merchant`, `onboarding_fee_paid`, `joined_during_pilot`, `average_prep_time_minutes`, `merchant_priority_score` | Restaurant/business, frozen approval fields |

### Referral System

| Table | Columns | Description |
|-------|---------|-------------|
| `referral_codes` | `id` (PK), `code` (UK), `role` (driver/partner), `label`, `used_by` (FK→profiles), `used_at`, `expires_at`, `is_active`, `created_at` | One-time codes for driver/partner signup, frozen trust fields |
| `partner_applications` | `id` (PK), `business_name`, `contact_name`, `contact_email`, `contact_phone`, `address`, `pos_system`, `notes`, `status`, `submitted_at` | Pending partner applications, frozen `status` |

### Deliveries (Core)

| Table | Columns | Description |
|-------|---------|-------------|
| `deliveries` | `id` (PK), `customer_id`, `driver_id`, `partner_id`, `status` (pending/claimed/in_progress/completed/cancelled), `category`, `pickup_address`, `pickup_lat/lng`, `dropoff_address`, `dropoff_lat/lng`, `distance_miles`, `zone_assigned`, `fee_charged`, `driver_payout`, `platform_cut`, `estimated_duration_minutes`, `actual_duration_minutes`, `route_polyline`, `requested_at`, `claimed_at`, `picked_up_at`, `delivered_at`, `notes`, `ready_for_pickup_at`, `transport_type`, `base_fee_applied`, `per_mile_rate_applied`, `surge_multiplier_applied`, `tip_amount`, `driver_arrived_at_pickup_at`, `driver_arrived_at_dropoff_at`, `cancelled_by`, `cancellation_reason_code`, `dynamic_boost_incentive` | Core delivery job, pricing frozen by trigger |
| `delivery_items` | `id` (PK), `delivery_id` (FK), `menu_item_id` (FK), `quantity`, `price_at_purchase` | Order line items |
| `delivery_item_options` | `id` (PK), `delivery_item_id` (FK), `menu_item_option_id` (FK), `price_at_purchase` | Item option selections |
| `delivery_messages` | `id` (PK), `delivery_id` (FK), `sender_id` (FK→profiles), `message_text`, `created_at` | In-delivery chat |
| `delivery_status_history` | `id` (PK), `delivery_id` (FK), `actor_id` (FK→profiles), `status`, `lat`, `lng`, `changed_at` | Audit log of status transitions |
| `route_points` | `id` (PK), `delivery_id` (FK), `lat`, `lng`, `driver_speed`, `recorded_at` | GPS breadcrumbs |
| `earnings` | `id` (PK), `driver_id` (FK→profiles), `delivery_id` (FK), `amount`, `platform_cut`, `paid_out`, `created_at` | Driver payout ledger |
| `performance_metrics` | `delivery_id` (PK, FK), `estimated_prep_minutes`, `actual_prep_minutes`, `estimated_transit_minutes`, `actual_transit_minutes`, `driver_wait_at_merchant_minutes`, `prep_delay_minutes`, `transit_delay_minutes`, `had_interaction_issues` | Per-delivery analytics |

### Menu System

| Table | Columns | Description |
|-------|---------|-------------|
| `menu_items` | `id` (PK), `partner_id` (FK), `name`, `description`, `price`, `category`, `photo_url`, `active`, `created_at` | Restaurant menu items |
| `menu_item_options` | `id` (PK), `menu_item_id` (FK), `name`, `price_modifier`, `is_available` | Item customizations |

### Social

| Table | Columns | Description |
|-------|---------|-------------|
| `ratings_and_reviews` | `id` (PK), `delivery_id` (FK), `reviewer_id` (FK→profiles), `reviewee_id` (FK→profiles), `reviewee_type`, `rating_stars`, `tags`, `written_review`, `created_at` | Post-delivery ratings |

## Key Functions (Private Schema)

| Function | Purpose |
|----------|---------|
| `private.is_admin()` | Returns true if caller is admin |
| `private.current_role_is(role)` | Returns true if caller's role matches |
| `private.get_my_role()` | Returns caller's role from JWT |
| `private.check_user_role(role)` | Returns true if caller has role or is admin |
| `private.enforce_profile_admin_fields()` | Freezes `is_admin`/`role` on profiles |
| `private.enforce_driver_admin_fields()` | Freezes `approved` on drivers |
| `private.enforce_partner_admin_fields()` | Freezes approval fields on partners |
| `private.enforce_referral_code_admin_fields()` | Freezes trust fields on referral_codes |
| `private.enforce_partner_application_admin_fields()` | Freezes `status` on partner_applications |

## Pricing Functions (Public Schema)

| Function | Purpose |
|----------|---------|
| `public.zone_pricing(miles)` | Returns zone, fee, driver_payout, platform_cut |
| `public.enforce_delivery_pricing()` | Trigger: recomputes pricing on INSERT/UPDATE |
| `public.enforce_partner_admin_fields()` | Freezes partner admin fields |

## Triggers

| Trigger | Table | Event | Function |
|---------|-------|-------|----------|
| `trg_enforce_delivery_pricing` | deliveries | BEFORE INSERT/UPDATE | `public.enforce_delivery_pricing` |
| `trg_enforce_partner_admin_fields` | partners | BEFORE UPDATE | `public.enforce_partner_admin_fields` |
| `trg_enforce_profile_admin_fields` | profiles | BEFORE UPDATE | `private.enforce_profile_admin_fields` |
| `trg_enforce_driver_admin_fields` | drivers | BEFORE UPDATE | `private.enforce_driver_admin_fields` |
| `trg_enforce_referral_code_admin_fields` | referral_codes | BEFORE UPDATE | `private.enforce_referral_code_admin_fields` |
| `trg_enforce_partner_application_admin_fields` | partner_applications | BEFORE UPDATE | `private.enforce_partner_application_admin_fields` |
| `on_auth_user_created` | auth.users | AFTER INSERT | `public.handle_new_user` |

## Indexes (23 FK indexes + PKs)

All foreign keys have covering indexes. Notable:
- `deliveries`: `idx_deliveries_customer_id`, `idx_deliveries_driver_id`, `idx_deliveries_partner_id`
- `delivery_items`: `idx_delivery_items_delivery_id`, `idx_delivery_items_menu_item_id`
- `partners`: `idx_partners_profile_id`
- `drivers`: `idx_drivers_id` (PK)
- `earnings`: `idx_earnings_delivery_id`, `idx_earnings_driver_id`

## RLS Policies (3-4 per table)

All 17 tables have RLS enabled with restrictive policies. See `docs/rls-matrix.md` for full matrix.

## Migrations (Committed Order)

1. `20260630202036_remote_schema.sql` - Initial schema dump (7 tables)
2. `20260630203000_security_hardening.sql` - Hardening policies, pricing trigger, admin flag
3. `20260930001651_rls_cleanup_and_grants.sql` - Legacy policy removal, grant revocation, freeze triggers
4. `20260930010507_policy_helpers_private_schema.sql` - Private schema helpers, performance fixes, referral security

## Rebuild Instructions

```bash
# Local development
supabase start
supabase db reset  # Applies all migrations from scratch

# Verify
supabase test db  # Runs pgTAP tests in supabase/tests/

# Generate types
supabase gen types typescript --local > lib/supabase.types.ts
```