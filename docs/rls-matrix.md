# RLS Policy Matrix

Generated from live Supabase policies (2026-09-30). This matrix shows what each role can do on each table.

## Legend
- ✅ = Allowed by RLS policy
- ❌ = Denied by RLS policy
- 🔑 = Requires `service_role` (bypasses RLS)
- N/A = Not applicable

## Tables

### `profiles` (PII, admin flag, role)
| Operation | anon | authenticated (customer) | authenticated (driver) | authenticated (partner) | authenticated (admin) | service_role |
|-----------|------|--------------------------|------------------------|------------------------|----------------------|--------------|
| SELECT own | ❌ | ✅ | ✅ | ✅ | ✅ | 🔑 |
| SELECT other | ❌ | ❌ | ❌ | ❌ | ✅ | 🔑 |
| INSERT | ❌ | ❌* | ❌* | ❌* | ❌* | 🔑 |
| UPDATE own (non-admin fields) | ❌ | ✅ | ✅ | ✅ | ✅ | 🔑 |
| UPDATE `is_admin` | ❌ | ❌ | ❌ | ❌ | ❌ | 🔑 |
| UPDATE `role` | ❌ | ❌ | ❌ | ❌ | ❌ | 🔑 |

*Profiles created by `handle_new_user` trigger on `auth.users` (runs as trigger owner)

### `partners` (restaurant businesses)
| Operation | anon | authenticated (customer) | authenticated (driver) | authenticated (partner owner) | authenticated (other partner) | authenticated (admin) | service_role |
|-----------|------|--------------------------|------------------------|------------------------------|------------------------------|----------------------|--------------|
| SELECT approved | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 🔑 |
| SELECT own (unapproved) | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | 🔑 |
| INSERT | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | 🔑 |
| UPDATE own (editable fields) | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | 🔑 |
| UPDATE `approved`/`founding_merchant`/etc | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | 🔑 |

### `menu_items`
| Operation | anon | authenticated (customer) | authenticated (driver) | authenticated (partner owner) | authenticated (other partner) | authenticated (admin) | service_role |
|-----------|------|--------------------------|------------------------|------------------------------|------------------------------|----------------------|--------------|
| SELECT active | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 🔑 |
| SELECT own (inactive) | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | 🔑 |
| INSERT | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | 🔑 |
| UPDATE own | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | 🔑 |

### `menu_item_options`
| Operation | anon | authenticated (customer) | authenticated (driver) | authenticated (partner owner) | authenticated (other partner) | authenticated (admin) | service_role |
|-----------|------|--------------------------|------------------------|------------------------------|------------------------------|----------------------|--------------|
| SELECT | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 🔑 |
| INSERT/UPDATE/DELETE own | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | 🔑 |

### `partner_applications`
| Operation | anon | authenticated (customer) | authenticated (driver) | authenticated (partner) | authenticated (admin) | service_role |
|-----------|------|--------------------------|------------------------|------------------------|----------------------|--------------|
| INSERT (status='pending') | ✅ | ✅ | ✅ | ✅ | ✅ | 🔑 |
| SELECT | ❌ | ❌ | ❌ | ❌ | ✅ | 🔑 |
| UPDATE | ❌ | ❌ | ❌ | ❌ | ✅ | 🔑 |

### `deliveries` (core table)
| Operation | anon | authenticated (customer) | authenticated (driver, unapproved) | authenticated (driver, approved) | authenticated (partner) | authenticated (admin) | service_role |
|-----------|------|--------------------------|-----------------------------------|--------------------------------|------------------------|----------------------|--------------|
| SELECT own (customer) | ❌ | ✅ | ❌ | ❌ | ✅* | ✅ | 🔑 |
| SELECT own (driver) | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | 🔑 |
| SELECT pending (driver) | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | 🔑 |
| SELECT partner's | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | 🔑 |
| INSERT (customer) | ❌ | ✅ | ❌ | ❌ | ✅ | ✅ | 🔑 |
| INSERT (partner) | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | 🔑 |
| UPDATE own (customer: pending→cancelled) | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | 🔑 |
| UPDATE own (driver: claim→pickup→deliver) | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | 🔑 |
| UPDATE `distance_miles`, pricing | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | 🔑 |
| UPDATE `is_admin`/`role` | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | 🔑 |

*Partner sees deliveries where they are the partner

### `delivery_items` / `delivery_item_options` / `delivery_messages` / `delivery_status_history`
| Operation | anon | authenticated (participant) | authenticated (non-participant) | authenticated (admin) | service_role |
|-----------|------|---------------------------|--------------------------------|----------------------|--------------|
| SELECT | ❌ | ✅ | ❌ | ✅ | 🔑 |
| INSERT (messages) | ❌ | ✅ | ❌ | ✅ | 🔑 |

### `drivers`
| Operation | anon | authenticated (customer) | authenticated (driver, unapproved) | authenticated (driver, approved) | authenticated (admin) | service_role |
|-----------|------|--------------------------|-----------------------------------|--------------------------------|----------------------|--------------|
| SELECT own | ❌ | ❌ | ✅ | ✅ | ✅ | 🔑 |
| UPDATE own (is_online, vehicle_type) | ❌ | ❌ | ✅ | ✅ | ✅ | 🔑 |
| UPDATE `approved` | ❌ | ❌ | ❌ | ❌ | ❌ | 🔑 |

### `earnings`
| Operation | anon | authenticated (driver) | authenticated (admin) | service_role |
|-----------|------|------------------------|----------------------|--------------|
| SELECT own | ❌ | ✅ | ✅ | 🔑 |
| INSERT/UPDATE | ❌ | ❌ | ❌ | 🔑 |

### `route_points`
| Operation | anon | authenticated (driver, assigned) | authenticated (customer/partner) | authenticated (admin) | service_role |
|-----------|------|--------------------------------|--------------------------------|----------------------|--------------|
| INSERT | ❌ | ✅ | ❌ | ✅ | 🔑 |
| SELECT | ❌ | ✅ | ✅* | ✅ | 🔑 |

*Customer/partner can see route points for their deliveries

### `performance_metrics`
| Operation | anon | authenticated (driver, assigned) | authenticated (admin) | service_role |
|-----------|------|--------------------------------|----------------------|--------------|
| SELECT | ❌ | ✅ | ✅ | 🔑 |

### `ratings_and_reviews`
| Operation | anon | authenticated (participant) | authenticated (admin) | service_role |
|-----------|------|---------------------------|----------------------|--------------|
| INSERT (as reviewer) | ❌ | ✅ | ✅ | 🔑 |
| SELECT | ❌ | ✅ | ✅ | 🔑 |

### `referral_codes`
| Operation | anon | authenticated | authenticated (admin) | service_role |
|-----------|------|---------------|----------------------|--------------|
| SELECT | ❌ | ❌ | ❌ | 🔑 |
| INSERT/UPDATE/DELETE | ❌ | ❌ | ✅ | 🔑 |
| **Validate code** | Via RPC `check_referral_code` (D workstream) | | | |

## Trust-Column Freeze Triggers

These columns are frozen for non-`service_role` callers:

| Table | Frozen Columns | Trigger |
|-------|----------------|---------|
| `profiles` | `is_admin`, `role` | `trg_enforce_profile_admin_fields` |
| `drivers` | `approved` | `trg_enforce_driver_admin_fields` |
| `partners` | `approved`, `founding_merchant`, `onboarding_fee_paid`, `joined_during_pilot`, `profile_id` | `trg_enforce_partner_admin_fields` |
| `referral_codes` | `is_active`, `used_by`, `used_at` | `trg_enforce_referral_code_admin_fields` |
| `partner_applications` | `status` | `trg_enforce_partner_application_admin_fields` |

## Function Grants (Private Schema)

| Function | anon | authenticated | service_role | postgres |
|----------|------|---------------|--------------|----------|
| `private.is_admin()` | ❌ | ✅ | ✅ | ✅ |
| `private.current_role_is()` | ❌ | ✅ | ✅ | ✅ |
| `private.get_my_role()` | ❌ | ✅ | ✅ | ✅ |
| `private.check_user_role()` | ❌ | ✅ | ✅ | ✅ |
| `private.enforce_*_admin_fields()` | ❌ | ✅ | ✅ | ✅ |

## Security Advisor Status (2026-09-30)

| Lint | Status |
|------|--------|
| `function_search_path_mutable` | ✅ Fixed (all SECURITY DEFINER functions have `SET search_path = public, private`) |
| `anon_security_definer_function_executable` | ✅ Fixed (all helpers moved to `private` schema, EXECUTE revoked from `anon`) |
| `authenticated_security_definer_function_executable` | ✅ Fixed |
| `auth_leaked_password_protection` | ⚠️ Auth config (enable in Supabase dashboard) |
| `rls_enabled_no_policy` | ✅ Fixed (all 17 tables have policies) |

## Performance Advisor Status (2026-09-30)

| Lint | Status |
|------|--------|
| `auth_rls_initplan` | ✅ Fixed (all policies use `(SELECT auth.uid())` subquery) |
| `unused_index` | ℹ️ Info only (27 indexes unused - normal for new DB) |
| `multiple_permissive_policies` | ✅ Fixed (consolidated `menu_item_options` and `referral_codes` policies) |
| `duplicate_index` | ✅ Fixed (dropped `idx_item_options_item_id`, `idx_status_history_delivery_id`) |
| `unindexed_foreign_keys` | ✅ Fixed (23 indexes added) |

## Notes

1. **Referral code validation** is intentionally not exposed to `anon`/`authenticated`. Client apps should call `check_referral_code(p_code)` RPC (Edge Function, IP-throttled) which returns boolean only.

2. **Pricing integrity**: `distance_miles`, `zone_assigned`, `fee_charged`, `driver_payout`, `platform_cut` are frozen by `enforce_delivery_pricing` trigger. Only `service_role` (via `create_delivery` Edge Function) can set them.

3. **State machine** for delivery status is enforced by `deliveries_update_participant_or_admin` WITH CHECK clause. Full state machine with `delivery_status_history` logging is part of E workstream.

4. **Real-time**: All tables are in `supabase_realtime` publication. Client channels should filter by `event = 'UPDATE'` and relevant IDs.