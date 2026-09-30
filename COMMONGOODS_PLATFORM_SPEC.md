# CommonGoods Platform Spec: Tunable, Data-Rich, Audit-Ready

From: Claude (mentor). To: the coding agent. Supersedes any hardcoded constants in the repo. Keep this file out of the public repo (it documents internals); Tyler holds it.

Tyler's directive: no hardcoded values, every variable tunable so algorithms can be tested and fine-tuned, maximum data collected, drivers get verifiable mileage reports for tax deductions, and no corners cut.

## 0. Principles

1. **Nothing magic.** Every rate, threshold, timeout, weight, radius, percentage, copy string and feature switch lives in the config system. Code contains structure, never numbers that a business decision could change.
2. **Reproducible decisions.** Every quote, payout, offer and dispatch decision stores its inputs, the algorithm version, and the config snapshot it used. Given a decision row, anyone can recompute it.
3. **Append-only history.** Config changes, mileage entries, events and ledger entries are never updated or deleted. Corrections are new rows that reference the old ones.
4. **Collect first, analyze later.** Instrument now; you cannot recover data you did not record. But collect deliberately: every field has a purpose, a retention rule and an access rule (section 6).
5. **Pure, testable algorithms.** Pricing and dispatch are pure functions (inputs in, breakdown out) with golden-file and property tests, run identically in production, tests and the simulator.

## 1. Config platform

### 1.1 Tables

- `config_registry` (one row per parameter): `key` (e.g. `pricing.base_fee`), `type`, `json_schema`, `unit`, `default_value`, `min`, `max`, `category`, `description`, `risk_level` (low/medium/high), `requires_approval` bool. Validate values against the schema with `pg_jsonschema` (available on Supabase).
- `config_values` (append-only): `id`, `key`, `scope_type` (`global | zone | partner | driver | customer | cohort | experiment_arm`), `scope_id`, `value jsonb`, `effective_from`, `effective_to`, `status` (`draft | scheduled | active | superseded | rolled_back`), `created_by`, `reason` (required), `approved_by`, `governance_proposal_id` (nullable, reserved for member votes), `created_at`.
- `config_snapshots`: `id`, `hash`, `resolved jsonb`, `created_at`. Deduplicated by hash. Every priced or dispatched delivery references one.
- `config_audit`: who changed what, old value, new value, reason, IP/app. Trigger-written.

### 1.2 Resolution

`resolve_config(key, ctx jsonb, at timestamptz)` returns the most specific active value: `experiment_arm > driver/customer/partner > cohort > zone > global > registry default`. Ties break on latest `effective_from`. `resolve_all(ctx, at)` returns the full resolved set and its snapshot ID. Cache in the app (fetch at launch + TTL from config), cache server-side per request. Rollback is a new row, never an edit.

### 1.3 Guardrails (enforced in the database, not the UI)

- Range checks from the registry.
- Cross-parameter constraints table (e.g. `driver_payout_min_per_mile <= pricing.per_mile`, `platform_cut_pct <= X`, `cancel.comp.* <= driver_payout`).
- Max change per publish for high-risk keys (e.g. no more than 20% relative move without `approved_by`).
- Scheduled activation, so changes can be timed for off-peak.
- An "impact preview" function: given a proposed change, recompute the last N days of deliveries under it and show the delta in customer price, driver pay and platform cut.

### 1.4 Starter parameter inventory (agent: create all of these in a seed migration; add more as you find hardcoded values)

- **Pricing:** `pricing.strategy` (algorithm version, see 2), `base_fee`, `per_mile`, `per_minute`, `min_fee`, `max_fee`, `zone.<n>.fee`, `distance_bands`, `demand_multiplier.{min,max,curve}`, `peak_hours`, `weather_surcharge`, `tip.presets`, `fee_rounding`.
- **Driver pay:** `pay.strategy`, `payout_pct_or_per_mile`, `min_payout`, `pay_floor_per_hour`, `wait_pay_per_minute`, `wait_pay_grace_minutes`, `bonus.rules`.
- **Platform/co-op:** `platform_cut_pct` (by zone, driver tier), `patronage_reserve_pct`.
- **Cancellation (replaces the earlier hardcoded proposal):** `cancel.free_stages` (default `[pending, claimed]`), `cancel.comp.en_route`, `cancel.comp.in_progress`, `cancel.customer_fee.*`, `cancel.lockout_after_status`.
- **Dispatch:** `dispatch.strategy`, `offer_mode` (broadcast / sequential / tiered), `offer_ttl_seconds`, `search_radius_miles`, `radius_expansion_steps`, `ranking_weights` (distance, rating, acceptance, idle time), `max_concurrent_offers`, `reoffer_delay_seconds`, `stale_claim_timeout_minutes`.
- **Geo/service:** zone polygons (a table, not constants), `service_hours`, `max_distance_miles`, `holiday_calendar`.
- **Limits:** `max_active_jobs_per_driver`, `max_orders_per_customer_per_hour`, `referral_code_length`, `referral_ttl_days`.
- **Telemetry:** `gps.sample_interval_s`, `gps.distance_filter_m`, `gps.accuracy_threshold_m`, `gps.upload_batch_size`, `gps.idle_sampling_multiplier`, `retention.*` (per table).
- **Tax/mileage:** date-effective rates live in their own table (section 5.4), not in `config_values`.
- **Feature flags:** `flag.<name>` with scope and rollout percent.
- **UX copy:** notification text, error messages, terms version.

### 1.5 Client and code rules

- A typed config client (`lib/config.ts`) generated from the registry. No `process.env` or literals for business values.
- CI check that fails on numeric literals in `lib/pricing*`, `lib/dispatch*` and screens (allow lists for layout constants only), and a generated `docs/config-registry.md`.
- Existing offenders to remove now: `lib/zones.ts` (rates, `IRS_RATE = 0.67`, cut percentages), the duplicated SQL `zone_pricing`, and any timeouts or radii in screens.

## 2. Algorithms as versioned strategies

- `algorithm_versions` (`kind` = pricing | dispatch | pay, `name`, `version`, `status`, `code_ref`, `description`). Config keys choose which version runs and its parameters.
- Every strategy implements the same contract and returns a **full breakdown**, not a number:
  - pricing: `{customer_total, components[], platform_cut, driver_payout, inputs, algorithm_version, config_snapshot_id}`
  - dispatch: `{candidates[], scores[], chosen, reason, algorithm_version, config_snapshot_id}`
- Persist: `quotes` (what the customer saw), `pricing_decisions` (final), `dispatch_decisions`. Show the driver the same breakdown for the pay they see (the co-op transparency promise).
- Start with the current zone pricing as `pricing/zone_v1`, then add `pricing/distance_time_v1` (base + per-mile + per-minute + multiplier) so there is something to compare. Same for dispatch: `broadcast_v1` (today) and `nearest_first_v1`.
- Implementation: TypeScript in an Edge Function (or a shared package used by the app, function and simulator). Database triggers must only validate, never recompute with their own copy of the rules.
- Tests: golden JSON fixtures per strategy, property tests (payout <= fee, monotonic with distance, floors respected), snapshot of the breakdown for regression.

## 3. Experiments (honest version)

- Tables: `experiments`, `experiment_arms` (with config overrides), `assignments` (deterministic hash of unit ID + experiment key, sticky), `exposures` (logged when the arm actually affects a decision).
- Units: customer, driver, zone, or time window (switchback). Guardrail metrics per experiment (cancel rate, driver hourly pay, time-to-claim) with automatic stop conditions.
- **Volume caveat, tell Tyler plainly:** with a small local market, classic A/B tests will not reach significance for weeks or months. Prefer switchback tests (alternate config by time block), before/after with controls, within-driver comparisons, and simulation. Collect data from day one so power grows over time.
- **Ethics guardrail:** experiments on driver pay may only test arms at or above the configured pay floor, must be disclosed to members in the ToS/co-op charter, and are visible in the driver's own breakdown. Customer-price and dispatch experiments are freer. This matters for a driver-owned platform's credibility.

## 4. Data collection

### 4.1 Event log

`events` (append-only, partitioned by month): `id`, `occurred_at` (device), `received_at` (server), `actor_id`, `actor_type`, `session_id`, `device_id`, `app_version`, `os`, `entity_type`, `entity_id`, `name`, `props jsonb`, `config_snapshot_id`, `experiment_assignments jsonb`. Client SDK with an offline queue and idempotency keys. Server rejects unknown event names via a registry (`event_catalog` with schemas).

Minimum event catalog: app_open, screen_view, signup_step, login, quote_viewed, order_placed, order_edited, cancel_tapped, search_no_results, out_of_area, offer_shown, offer_viewed, offer_accepted, offer_declined (with reason), offer_expired, driver_online/offline, delivery_started, arrived_pickup, picked_up, arrived_dropoff, delivered, proof_captured, tip_added, rating_given, support_opened, permission_granted/denied, crash/error.

### 4.2 Domain tables (structured, queryable)

- **Delivery timeline:** one row per stage with timestamp: requested, offered, claimed, `started_at` (driver began driving), arrived_pickup, picked_up, arrived_dropoff, delivered, cancelled (with `cancel_stage`, `cancelled_by`, `reason_code`). Add the `en_route` state Tyler's cancellation rule requires.
- `dispatch_offers`: offer time, viewed time, response time and type, decline reason, latency, offered pay, driver distance to pickup, rank, alternatives shown, algorithm version. This is the key table for tuning dispatch.
- `driver_sessions`: online/offline intervals with start/end location and reason.
- `demand_misses`: requests that never got a driver, requests outside the zone or service hours, abandoned quotes.
- `quotes` vs actuals: quoted distance/duration/price vs actual distance/duration/paid, plus ETA error.
- `wait_times`: arrival at pickup to pick up (restaurant prep), arrival at dropoff to handoff.
- `cancellations`, `support_issues`, `ratings_and_reviews` (exists), `earnings`/`ledger` (append-only, Stripe IDs when payments land).
- Snapshot the config and algorithm version on every row that depends on them.

### 4.3 Derived metrics (views/materialized views, refreshed on schedule)

Acceptance rate, time-to-claim, time-to-deliver, ETA error, utilization (active time / online time), driver pay per active hour and per online hour, earnings per mile, cancellation rate by stage and reason, customer funnel (quote to order to delivered), repeat rate, demand and supply heatmaps by zone and hour, cohort retention, referral yield.

### 4.4 Tooling

Start with Postgres views plus Metabase (open source, self-hostable) or Supabase Studio dashboards. Add scheduled exports (CSV/Parquet) to storage for offline analysis. Add PostHog (open source) only if product analytics on the client becomes a bottleneck. Do not add a warehouse until volume demands it.

## 5. Location telemetry and mileage records

### 5.1 Capture (client)

- `expo-location` with background updates via `expo-task-manager`. Requires an EAS development/production build (not Expo Go), iOS "Always" permission with a clear purpose string, Android foreground-service notification, and a user-visible "on shift" indicator.
- Capture per point: lat, lng, accuracy, speed, heading, altitude, timestamp (device), provider, `is_mock_location`, battery level, charging state, activity type if available. Sampling is config-driven and adaptive (denser while on a job, sparse while idle, none when offline).
- On-device SQLite buffer, batch upload with idempotency keys, resumable after offline periods.
- Only record while the driver is on shift. Tell the driver exactly what is collected, on screen, before permission.

### 5.2 Storage and processing (server)

- `location_pings`: raw and immutable, partitioned by month, RLS: driver reads own, customer sees only the assigned driver's live position during an active delivery, admin gets aggregated access.
- A processing job builds `trip_segments`: types `online_idle`, `to_pickup`, `to_dropoff`, `return`; start/end times and places; distance computed two ways (filtered haversine over points, and Mapbox Map Matching), both stored with a quality score, gap flags, and the method version. Keep raw plus derived so methods can be re-run when improved.

### 5.3 Mileage ledger (tamper-evident)

- `vehicles`: driver, year/make/model, placed-in-service date, `deduction_method` (standard/actual), and odometer readings (start-of-year, end-of-year, optional photo).
- `mileage_entries` (append-only): driver, vehicle, date, start/end time, start/end place (address plus coordinates), miles, `category` (delivery, to-pickup, waiting/idle, deadhead, other-platform, personal), `business_purpose`, `source` (gps | manual | import), source segment IDs, `method_version`, `prev_hash`, `hash` (SHA-256 chain per driver). Driver edits (reclassify, add other-platform miles, annotate) create **amendment** rows referencing the original with a required reason. Originals are never changed.
- Anchoring: publish a daily digest (hash of the day's chain heads) to a public log or send the driver an email receipt, so the chain cannot be silently rewritten later.
- Retention: keep for at least 7 years (config `retention.mileage_years`), longer than the typical 3-year IRS window, unless the user asks for deletion where law allows.

### 5.4 Date-effective rates (do not hardcode)

`tax_mileage_rates`: `effective_from`, `effective_to`, `business_cents`, `medical_cents`, `charity_cents`, `source_url`, `notes`. **Rates change mid-year.** Seed (per IRS): 2024 = 67¢, 2025 = 70¢, 2026 = 72.5¢ for Jan 1 to Jun 30 and 76¢ from Jul 1 (source: https://www.irs.gov/tax-professionals/standard-mileage-rates). The report applies the rate in effect on each entry's date. The repo currently hardcodes 0.67, which is wrong for 2025 and 2026. An admin task, "check IRS rates", should be a recurring reminder.

### 5.5 The report: "Verified Mileage Log"

Contents (aligned with IRS recordkeeping for vehicle expenses, Pub. 463; verify current wording when implementing): driver and vehicle; period; one line per trip with date, start/end time, from/to, miles, business purpose, category; totals by category and by rate period; estimated deduction at the date-effective rate; annual total miles vs business miles (odometer reconciliation, business-use %); data-quality summary (GPS coverage %, gaps, manual entries, amendments listed); report ID, generation time, SHA-256 of the data, and an Ed25519 signature; a QR/URL `/verify/<report_id>` that confirms the hash without exposing personal data. Output as PDF and CSV. Add year-end earnings summary export.

**Wording caution (important):** call it a *verified, tamper-evident, contemporaneous mileage log*. There is no IRS "certification" for apps; do not say certified by or approved by the IRS. Include: "Not tax advice; which miles are deductible depends on your situation (commuting rules, multiple platforms, method election). Consult a tax professional." Category totals let the driver and their preparer decide. Include manual entry and import for miles driven on other platforms so the log is complete.

## 6. Privacy and governance

- Data classification per table (public, internal, personal, sensitive-location) with an access matrix. Precise location is sensitive: minimum retention needed, raw pings restricted to the driver and service role, admins see aggregates by default with an audited "break glass" path.
- User rights: export (JSON/CSV) and deletion flows in-app (also needed for App Store account-deletion rule). Deletion keeps anonymized aggregates and legally required ledger data.
- Consent screens, a real privacy policy, and ToS covering data use and experiments. Have counsel review before launch.
- Retention jobs driven by `retention.*` config.
- Security: no service-role key in the client, Edge Functions for anything privileged, rate limits, audit logging on config and admin actions.

## 7. Admin/ops console (control surface)

Build inside the app (admin mode) or a small web app:
1. **Config editor:** search by key/category, scope selector, validation errors, diff view, reason field, schedule, approve, rollback, impact preview.
2. **Experiments:** create, assign, monitor guardrails, stop.
3. **Live ops board:** active deliveries, unclaimed jobs with age, online drivers on a map, manual reassign/cancel.
4. **Metrics dashboards** (section 4.3) and CSV export.
5. **Mileage/report admin:** re-run processing, view data-quality flags, regenerate reports.
6. **Member governance hook:** `governance_proposal_id` on config changes, so later a vote can gate high-risk parameters.
Roles: `admin`, `operator`, `analyst` (read-only aggregates). Every action audited.

## 8. Simulator and backtesting

A `sim/` package that:
- generates synthetic demand and supply (seeded, configurable) to stress pricing and dispatch;
- replays recorded events/deliveries under an alternative config or strategy to estimate counterfactual price, pay, acceptance and time-to-claim (mark clearly as estimates; behavior changes are not modeled);
- runs as CI regression on golden scenarios so an algorithm change shows its effect in a PR.

## 9. Order of work

Prerequisite: the pending fixes from the last review (profile trigger, app-to-RPC migration, `get_available_jobs`, signup flow, real tests, repo hygiene) and the `en_route` state.

| Phase | Work | Done when |
|---|---|---|
| P1 | Config platform (1) + event log (4.1) + seed registry + typed client + remove hardcoded constants | zero business literals in pricing/dispatch code; config edited from SQL and read by app |
| P2 | Strategy framework (2), quotes/decisions tables, `create_delivery` Edge Function using config (this replaces workstream F's constants), `dispatch_offers`, delivery timeline | every delivery stores breakdown and snapshot; two pricing strategies switchable by config |
| P3 | Location capture + ingestion + trip segments (5.1, 5.2) | a test drive yields segments with both distance methods |
| P4 | Mileage ledger, rates table, vehicles, report + verify endpoint (5.3 to 5.5) | signed PDF/CSV reproduces from data, tamper test fails verification |
| P5 | Admin console (7), metrics views (4.3), Metabase | Tyler can change a parameter, preview impact, and see metrics without SQL |
| P6 | Experiments (3), simulator (8) | a switchback test and a simulated backtest run end to end |
| P7 | Payments/ledger and co-op models (design docs from the main brief) | design reviewed |

Reporting format is unchanged: files changed, evidence, surprises, questions (max 3).

## 10. Open decisions for Tyler

1. Starting cancellation compensation values (config, not code) and who pays them.
2. Pay floor per hour the platform guarantees, and whether experiments are allowed on driver pay at all.
3. Retention periods for raw location data.
4. Whether drivers can log other-platform miles in the app (recommended: yes).
5. iOS background location: needs Apple review justification and a build via EAS; plan for a first TestFlight cycle.