# CommonGoods — Mentor Brief (v2)

From: Claude (mentor). To: the coding agent in Tyler's IDE.
Basis: the repository at `main` (`37925b9`) and nothing else. Every finding below is something you can confirm by reading the tree. Where I give a file and line range, go read it.

## 0. Operating stance

You own this codebase end to end: app, migrations, Edge Functions, CI, deploys, store metadata. Tyler wants results, not permission requests. Decide, implement, verify, and report.

- Run whatever commands you need: Supabase CLI, `gh`, `eas`, `psql`, `tsc`, tests, scripts. Apply migrations, deploy functions, and edit the database directly when the task calls for it.
- If a tool is missing or blocked, do not work around it silently. Install it. If you can't, tell Tyler exactly what to enable (see section 6) and continue with what you can do.
- Verify your own work. Every change needs a test or a reproduction that fails before and passes after.
- Secrets: never print them or commit them. If you find one, report the file and variable name.
- Tyler's preference: when giving him code, give complete files, not snippets or diffs. Keep reports concise and technical.

## 1. Findings from the repo (ordered by severity)

### 1.1 Committed secrets
`commongoods.zip` (756 KB, tracked in git) contains a `.env` holding a Supabase personal access token (`sbp_…`), a Mapbox **secret** token (`sk.…`), and the anon key. History is public, so these are burned: Tyler must rotate all of them. In the repo:
- delete the zip; add `*.zip` and `.env*` (keeping `!.env.example`) to `.gitignore`; add `.env.example` with names only;
- purge the zip from history (`git filter-repo --path commongoods.zip --invert-paths`, force-push; Tyler consents to this) and add gitleaks to CI;
- `lib/zones.ts`, `app/customer.tsx` and `app/admin.tsx` read `EXPO_PUBLIC_MAPBOX_TOKEN`. `EXPO_PUBLIC_*` values ship inside the app binary, so a secret `sk.` token there is exposed to every user. Use a URL-restricted public `pk.` token for map display and move Directions/geocoding server-side (1.5).

### 1.2 RLS: legacy policies coexist with the hardening policies
`supabase/migrations/20260630202036_remote_schema.sql` is a dump that contains **both** the original policies and the ones added by `…203000_security_hardening.sql`. Permissive policies are OR'd, so the originals still grant access:

| Legacy policy (in the dump) | Consequence |
|---|---|
| `profiles` "Users can update own profile" (`USING` only, no `WITH CHECK`, no column limit) | a user can set `is_admin = true` or change `role` on their own row |
| `deliveries` "authenticated users can read deliveries" (`USING (true)`) | every signed-in user reads every delivery, including addresses, coordinates and notes (Realtime too) |
| `deliveries` "drivers can update deliveries" (any authenticated user when `status='pending'`) | anyone, not just drivers, can claim or edit pending jobs |
| `deliveries` "Customers can create deliveries" / "customers can insert deliveries" (`customer_id = uid` only) | insert with arbitrary `status`, `driver_id`, prices |
| `partner_applications` "Anyone can submit partner application" (`CHECK (true)`) | insert with any `status` |
| `partners` / `menu_items` "Admin can manage …" | hardcoded admin email in policy SQL, duplicating `is_admin()` |

Also: `anon` and `authenticated` hold `GRANT ALL` on every public table and function (same dump, lines ~614–890), so RLS is the only barrier.

Work: query `pg_policies` on the live project, drop every legacy policy, revoke `anon` grants, and add a `BEFORE UPDATE` trigger on `profiles` that freezes `is_admin` and `role` for non-service callers. Add RLS regression tests that attempt each exploit as an ordinary user and assert failure; run them in CI.

### 1.3 Signup and role grants are client-controlled
`handle_new_user()` (dump lines 127–142) copies `raw_user_meta_data->>'role'` into `profiles.role`. `app/auth.tsx` lines ~106–113 pass `role: refRole` from the client, and lines ~64–89 validate the referral code client-side. Anyone can call `supabase.auth.signUp` directly with `role: 'driver'` and skip referrals entirely. Then `auth.tsx` ~125 deactivates the code in a second, unauthenticated-at-that-point request that can fail silently, so codes can be reused.

Fix: `handle_new_user` always creates `'customer'`. Add an RPC `redeem_referral_code(code)` that, atomically (`select … for update`), validates and consumes the code and creates the `drivers` / `partners` row with `approved` set per policy. Client never supplies a role.

### 1.4 Job lifecycle is unsafe and incomplete
- `app/driver.tsx` `handleClaim` guards with `.eq('status','pending')` client-side. Move claiming into an RPC `claim_delivery(id)` that locks the row, requires an approved driver, and is backed by a partial unique index allowing one active job (`claimed`/`in_progress`) per driver.
- Any driver can write `status='completed'` straight from `pending` because nothing enforces transitions. Add a state-machine trigger (`pending→claimed→in_progress→completed`, plus defined cancel paths) and stamp timestamps server-side.
- No way for a driver to release a claimed job, and customers can cancel after pickup (`deliveries_update_participant_or_admin` allows `cancelled` at any time).
- Drivers select `*` on all pending jobs, so they see dropoff addresses and notes before claiming. Serve a restricted `available_jobs` view (pickup, zone, pay, rough distance) and reveal the dropoff after claim.
- `driver.tsx` subscribes to `event:'*'` on the whole table and re-runs four queries on any change. Filter the channel and merge the queries. Earnings "today/this week" filter on `requested_at` instead of `delivered_at`.
- `route_points` and `earnings` tables exist but no code writes to either. GPS trail and payout ledger are both empty.

### 1.5 Pricing trust boundary
`enforce_delivery_pricing` (hardening migration) recomputes fee/payout/cut from `distance_miles`, which the client supplies from its own Mapbox call (`customer.tsx` ~239–258). A modified client can post `distance_miles: 0.1` for a 19-mile trip. Fix: an Edge Function `create_delivery` takes the two coordinates, calls Mapbox Directions with a server-held token, validates that the pickup matches the partner's stored lat/lng when `partner_id` is set, writes with the service role, and client `INSERT` on `deliveries` is revoked. Zones and rates should also live in a table, not in two duplicated places (`lib/zones.ts` and the SQL `zone_pricing`).

### 1.6 Schema drift
The app queries tables that no migration creates: `drivers` (`lib/appMode.ts:37`) and `referral_codes` (`app/auth.tsx:64,125`). Migrations define seven tables; the app depends on nine. There is no `items`/`subtotal`/`customer_notes` on `deliveries` and no order-line table, and `app/customer.tsx` is a pin-to-pin courier request with no menu browsing, so **the repo has no restaurant ordering flow** even though `menu_items` and partner menu editing exist. Run `supabase db pull`, commit the true schema, and treat migrations as the only way to change it from now on. Generate types with `supabase gen types typescript` and delete the hand-written `Delivery` type in `lib/supabase.ts`.

### 1.7 Known bugs and cleanup
- `lib/supabase.ts` uses a bare SecureStore adapter; Supabase sessions exceed the iOS Keychain value limit. Implement the standard `LargeSecureStore` (encryption key in SecureStore, ciphertext in AsyncStorage).
- Mapbox Geocoding v5 `mapbox.places` calls are duplicated in `customer.tsx` (lines ~46, 88) and `admin.tsx` (~34). Extract `lib/geocode.ts` on the Search Box API, ideally behind the Edge Function.
- `app/orders.tsx` chooses customer vs driver view from `profiles.role`; use `useAppMode().currentMode`. `appMode.ts` also decides eligibility from `drivers.approved` while RLS uses `profiles.role`; unify on the approval tables.
- `customer.tsx` (551 lines) and `admin.tsx` (449) need splitting into components and hooks. `driver-history.tsx` is a stub. `lib/zones.ts` hardcodes `IRS_RATE = 0.67` with a "2024" comment; source the current rate from config and check it.
- `README.md` is Expo boilerplate; `@expo/ngrok` is a runtime dependency; default template assets remain; no CI exists; no tests exist.
- `storage.ts` uploads to bucket `partner-photos`, but no storage policies are in the migrations. Define them (public read, owner-only write, size/MIME limits).
- App Store readiness: in-app account deletion, privacy policy and ToS URLs, and permission strings (location, camera) in `app.json`.

## 2. Product gaps (design, then build)

1. **Payments and ledger.** `fee_charged` is a number with no money movement. Design Stripe Connect Express for drivers with the platform cut as the application fee, tips, refunds, and an append-only `ledger` written by a completion trigger. `earnings` should derive from it.
2. **Cooperative structure in the data model.** Nothing represents membership, equity, votes or patronage. As written, this is a conventional marketplace at a 25% take (`platformCut` / `fee` = 2/8, 2.75/11, 3.75/15). Model `members`, `shares` (or equity ledger), `proposals`/`votes`, and an annual patronage calculation so the product matches the pitch.
3. **Proof of delivery**: dropoff photo or PIN, GPS breadcrumbs into `route_points`, dispute records.
4. **Driver push notifications** on new jobs (`expo-notifications` plus a database webhook to an Edge Function).
5. **Customer ordering from partner menus**: cart, order lines, partner accept/prepare/ready states. This is what the seeded partner/menu tables were built for.
6. Ratings, support/issue reporting, admin analytics (orders per week, claim time, on-time rate).
7. Gate-code feature (Tyler's separate idea): local-only storage per driver, geofenced reminder. Fits inside the driver dashboard.

## 3. Shoulders to stand on (verify each against the live source before adopting)

- **CoopCycle** (github.com/coopcycle): open-source delivery platform run by a federation of courier co-ops. Mine it for its data model, dispatch, and federation ideas. It is licensed under the "Coopyleft" license, so read the terms before copying code.
- **OpenCourier** (Platform Cooperativism Consortium, platform.coop): protocol for interoperable community-owned delivery platforms. Align order/courier schemas with it now.
- **Coopify / Cibus** (coopify.app): open-source platform-co-op infrastructure (AGPL, Rails) with a food delivery product. Their published fee claims are marketing until proven; useful for governance and bylaw templates.
- **The Drivers Cooperative / Driver Systems Inc.**: the largest driver-owned platform co-op in the US; publicly states a 15% commission for operating costs. Compare against CommonGoods' 25%.
- **Radish (Montreal)**: multistakeholder delivery co-op; read its ownership write-ups.
- **Supabase's own docs and examples** for RLS patterns, `LargeSecureStore`, Edge Functions and pgTAP tests. Use them rather than inventing patterns.

## 4. Workstreams

You may parallelize and reorder within the rules below. Do not start section 2 items until 1.1–1.6 are done.

| # | Workstream | Done when |
|---|---|---|
| A | Secrets and hygiene (1.1), CI (typecheck, lint, gitleaks, RLS tests), real README, AGENTS.md | history clean, CI green |
| B | Schema truth (1.6): `db pull`, commit, generate types | migrations reproduce live DB from scratch |
| C | RLS cleanup, grants, profile column freeze, tests (1.2) | every exploit test fails on the live project |
| D | Signup/referral RPC (1.3) | direct `signUp` with `role:'driver'` yields a customer |
| E | Job lifecycle: `claim_delivery`, `available_jobs`, state machine, release, Realtime filter (1.4) | two-device race test passes |
| F | `create_delivery` Edge Function, revoke client inserts, zones table (1.5) | tampered distance rejected |
| G | Known bugs and cleanup (1.7) | issues closed, files split |
| H | Payments and co-op model design docs (section 2.1, 2.2) | docs delivered to mentor for review |

## 5. Reporting

After each workstream send: (1) files changed, (2) test evidence, (3) surprises or blockers, (4) at most three questions for Tyler. Tyler reads this thread, so write for him too.

## 6. Tooling to enable if the agent lacks it

- **Supabase MCP server**: lets the agent inspect the live project, run SQL, apply migrations, deploy Edge Functions, read logs, and run advisors (security and performance linters). Enable this first; it covers workstreams B–F. Without it, use the Supabase CLI (`supabase login`, `supabase link`, `supabase db pull/push`, `supabase functions deploy`).
- **GitHub access**: `gh` CLI authenticated, or the GitHub MCP server, for CI runs, secrets, and history rewriting.
- **Expo plugin/skills**: `.claude/settings.json` already enables `expo@claude-plugins-official`. Also use EAS (`eas build`, `eas submit`) for cloud builds so no local native toolchain is needed.
- **Stripe MCP server / CLI**: enable before workstream H implementation.
- **A shell with `psql`, `git-filter-repo`, and gitleaks** for 1.1 and the RLS tests. If missing, install through the package manager.
- If a browser tool is available, use it to check dashboards (Mapbox token restrictions, Supabase auth settings).

If any step fails, send Tyler: the command, the exact error, and what you need him to enable or approve.