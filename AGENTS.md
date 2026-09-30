# Agent Instructions for CommonGoods

This file contains instructions for AI agents working on the CommonGoods codebase.

## Project Overview

CommonGoods is a cooperative delivery platform (Expo + Supabase). Key architectural decisions:

- **Migrations are the source of truth** for the database schema. Never hand-edit types; run `supabase gen types typescript` after migrations.
- **RLS is the only access control**. All tables have RLS enabled. No `GRANT ALL` to `anon`/`authenticated`.
- **Client never computes pricing**. Distance and pricing happen in Edge Functions with server-held Mapbox token.
- **Multi-role app**: customer, driver, partner, admin. Mode switching via `lib/appMode.ts`.
- **Secrets**: Only public (`EXPO_PUBLIC_*`) vars in the app. Server secrets in Supabase Vault / Edge Function env.

## Workflow Rules

1. **Database changes**: Write a migration in `supabase/migrations/`, apply with `supabase db push`, then `supabase gen types typescript --linked > lib/supabase.types.ts`.
2. **Edge Functions**: Deploy with `supabase functions deploy <name> --project-ref <ref>`.
3. **Type safety**: Run `npx tsc --noEmit` before committing.
4. **Linting**: Run `npm run lint` before committing.
5. **Secrets**: Never commit `.env` or hardcoded secrets. Use `.env.example` for names only.
6. **CI**: GitHub Actions runs typecheck, lint, and gitleaks on every push/PR.

## Key Files

| File | Purpose |
|------|---------|
| `lib/supabase.ts` | Supabase client + shared types (keep in sync with generated types) |
| `lib/appMode.ts` | Role/mode switching, driver approval checks |
| `lib/zones.ts` | Zone pricing logic (mirrored in DB `zone_pricing` table) |
| `supabase/migrations/*.sql` | All schema changes |
| `app/_layout.tsx` | Root layout, auth provider, mode initialization |

## Common Tasks

### Add a migration
```bash
supabase migration new <name>
# edit the file
supabase db push
supabase gen types typescript --linked > lib/supabase.types.ts
```

### Deploy Edge Function
```bash
supabase functions deploy <name> --project-ref egadbxrflihbelknvpxc
```

### Pull remote schema (if drift suspected)
```bash
supabase db pull --schema public
# commit the new migration file
```

### Generate types
```bash
supabase gen types typescript --linked > lib/supabase.types.ts
```

## Security Checklist (every PR)

- [ ] No hardcoded secrets
- [ ] No `EXPO_PUBLIC_` secret tokens (Mapbox must be `pk.*`)
- [ ] RLS policies tested for new tables
- [ ] No `GRANT ALL` to `anon`/`authenticated`
- [ ] Client never writes `deliveries` directly (use `create_delivery` RPC/Edge Function)

## Known Issues (from mentor brief)

1. **RLS**: Legacy permissive policies still exist alongside hardening policies — must drop legacy.
2. **Signup**: Client controls `role` in `signUp` — must move to RPC.
3. **Job lifecycle**: No server-side claim/release/state-machine — add RPCs + triggers.
4. **Pricing**: Client sends `distance_miles` — move to Edge Function.
5. **Schema drift**: App queries `drivers`, `referral_codes` tables not in migrations.
6. **Types**: Hand-written `Delivery` type in `lib/supabase.ts` should be deleted after gen.
7. **Session storage**: `SecureStore` adapter hits iOS keychain limit — needs `LargeSecureStore`.

## Useful Commands

```bash
# Local dev
npm start

# Typecheck
npx tsc --noEmit

# Lint
npm run lint

# Supabase
supabase link --project-ref egadbxrflihbelknvpxc
supabase db push
supabase gen types typescript --linked > lib/supabase.types.ts
supabase functions deploy <name>
supabase db pull

# Gitleaks (local)
gitleaks detect --source . --verbose
```