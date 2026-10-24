# Supabase-native migration (implementation status)

> **Read-only live-state refresh — 2026-10-24:** Project `qqfzbecwhewswkyxgebu` reports `ACTIVE_HEALTHY` on PostgreSQL 17.11.0.003 in `eu-west-1`. The live ledger contains ten applied versions through `20261024123238_secure_rls_helper_functions_private_schema`. That last version was recovered locally from the ledger and must not be replayed. The identity/owner/lawyer-access SQL under `proposals/` is still only a proposal. The duplicate composite-index candidate `20261024102730` is archived outside active CLI migration discovery because live `cases_lawyer_category_idx` already covers `(lawyer_id, category_id)`. No hosted change was made in this continuation; no verified backup/restore test or database branch is available, and the target environment has not been independently classified as staging or production.

## Current state

The canonical `supabase/migrations/` directory contains ten SQL files and they correspond to the ten versions recorded in the live migration ledger: two baseline migrations, six recovered already-applied versions, `20261024102004_legal_categories_and_assignments.sql`, and `20261024123238_secure_rls_helper_functions_private_schema.sql`. The category SQL was mechanically compared to its exact live ledger statement (comments/whitespace ignored); the latest helper SQL was recovered from the ledger. Do not replay either. The duplicate `20261024102730_cases_lawyer_category_covering_index.sql` and the two earlier unapplied candidates remain in `archive/unapplied_candidates/`, outside CLI migration discovery. The new owner/lawyer-access proposal and its rollback are in `proposals/` and have not been applied. The environment remains unclassified as development, staging, or production, and the standing backup/restoreability gate blocks hosted writes.

The scoped category/lawyer/case source flows and Admin/mobile screens are integrated through the existing API/session patterns, with protected database calls using a verified Supabase JWT. This is source integration, not a hosted client/RLS verification or deployment. The same distinction applies to the AI Edge Function/Storage source: it has not been deployed.

The checked-in SQL integration suite (`backend/test/supabase_migrations.test.js`) uses PGlite to apply all migrations to an isolated in-memory PostgreSQL engine, seed fake Auth/Storage catalogs, and test grants, RLS, Auth linking, transactional RPCs, and role boundaries. The shared AI Edge Function handler has Node tests in `backend/test/edge_functions.test.js`; Flutter Storage/Edge HTTP client tests are in `legal_app/test/supabase_ai_client_test.dart`. These are isolated tests only: they do not connect to the configured project, verify Supabase JWT signatures, exercise live PostgREST/Storage/Auth, or replace a local Supabase/PostgreSQL 17 and concurrency test. CI now includes a Deno type-check job for the Edge Function entrypoint; that job has not yet run on this branch.

The mobile client has a partial Supabase Auth/profile path; its public client signup is now disabled by default, and profile updates omit role/email. Admin sign-in reads the profile through RLS-protected PostgREST. The chatbot, case-prediction, and document-review screens have local authenticated `ai-assistant` clients, but the live project has no deployed function or Storage bucket. These are source changes, not a live integration: general mobile data and all Admin resource screens continue through Express. Flutter/Dart and hosted Auth/PostgREST/Storage/Gemini tests were not run in this environment.

## Identity and roles — live state versus proposal

- **Live:** `public.users.role` is the application role source; the database check allows `client`, `lawyer`, and `admin`, not `owner`. The live `private.current_app_user_id()` falls back to the Auth UUID if no application profile exists. The live `auth.users` trigger links an unlinked profile by case-insensitive email without checking confirmation or an explicit legacy UID. Do not treat this live behavior as meeting the intended identity boundary.
- **Local app code:** the public mobile role selector is removed, role metadata is not sent, unknown/missing/non-client profiles close the client session, and client signup defaults off. The local backend verifies an explicit profile role and rejects missing/unknown roles instead of using `client` as a fallback. These source changes are not deployed.
- **Proposal only:** `proposals/20261024_identity_owner_lawyer_access.sql` makes missing-profile helpers return NULL, prioritizes explicit Auth UUID mappings, links legacy profiles only by a trusted UID plus confirmed matching email, maps public email/phone signup to `client` by default, and allows `lawyer` only through trusted server metadata. It preserves existing `admin` accounts, reserves a singleton `owner` for trusted provisioning, restricts client-owner policies, and adds assigned-lawyer reads for cases/bookings only. Its companion runbook/rollback are in the same directory. PGlite proposal and full-policy rollback checks pass locally; the proposal has not been applied.
- Do not create a public “make me owner/admin” endpoint. The live project has no `owner` role and no live `rpc_admin_set_user_role` function. The checked-in `provision:admin` npm script points to a missing `backend/scripts/provision_admin.js`; there is no provision script to use. Use only an approved, server-side or SQL Editor workflow after a reviewed schema change. Never trust browser role, email, user ID, or submitted profile data as proof of privilege.
- Firebase password hashes are not imported. Existing users need a verified account recovery/password-reset or re-registration flow. Do not automatically link a legacy identity based only on email.

## Transaction and authorization boundaries — current integration limits

- The live project has RLS enabled on 19 existing public tables. The exact live role/policy/function/grant summary and screen mapping are in [`APP_INTEGRATION_AUDIT_2026-10-24.md`](APP_INTEGRATION_AUDIT_2026-10-24.md). Public catalogue and protected app operations still need live client/JWT negative tests before any direct-client rollout.
- **Live RPCs:** the catalog currently exposes only `rpc_recalculate_lawyer_rating`, `rpc_reserve_booking_slots`, and `rpc_wallet_mutate`. Many local Express operations reference RPC names that are absent remotely; those UI actions are not verified end-to-end. No additional SQL function or model should be inferred from a route name.
- The local backend keeps protected caller data access on a request-scoped Supabase JWT/RLS path. `service_role` remains server-only during transition; it bypasses RLS by design and must never enter Flutter, browser code, public config, CI logs, or client requests.
- Wallet credits remain admin-only until a payment provider and verified webhook are implemented. The backend intentionally blocks subscription activation without a verified payment flow. A `Pending` subscription is not a purchase or an active entitlement.
- The local AI/Storage clients and `supabase/functions/` source are not deployed: the live project has no Edge Functions or bucket. The two older RLS/Storage candidates are archived and unapplied. Do not treat the intended `legal-documents` bucket, PDF limits, RLS path policies, or AI cleanup as live behavior. Never upload real client documents until an approved deployment and storage-retention test is complete.

## Isolated testing and migration review

### Automated PostgreSQL tests

```bash
cd backend
npm ci
npm test
```

The PGlite test applies every file under `supabase/migrations/` to a fresh isolated database. Its Auth and Storage schemas are test doubles. It intentionally strips only the `CREATE EXTENSION pgcrypto` statement because PGlite does not package contrib extensions; the PostgreSQL 17 target has built-in `gen_random_uuid()`.

### Supabase CLI / local stack

Use a disposable local Supabase stack or isolated non-production Supabase project for full Postgres 17, Auth, PostgREST, Storage, and parallel booking tests. Never run `supabase db reset` against a linked/shared/production database. For a local stack, verify the linked target is not the configured production project before any reset or seed command.

### Synthetic local seed

`cd backend && npm run seed:test` writes only the fixed synthetic fixtures in `backend/src/seed.js`. It is disabled for `NODE_ENV=production` and requires `LEGAL_ALLOW_TEST_SEED=true`, `SUPABASE_TEST_URL`, and `SUPABASE_TEST_SERVICE_ROLE_KEY`. The URL must use `http` or `https` and resolve syntactically to `localhost`, `127.0.0.1`, or `::1`; URL credentials, query parameters, and fragments are rejected. Supply the service-role key issued by the local Supabase stack through the process environment, never a hosted project's key. The script creates no Auth users or passwords; its placeholder emails use the reserved `.invalid` domain. Validation occurs before the Supabase client is created, and the seed never prints configured key values.

Before any remote push:

1. Obtain explicit approval for the environment and change window.
2. Take and verify a recoverable database backup/export; separately export Auth metadata and Storage objects if they exist. Do not export/import passwords or Firebase password hashes.
3. Inspect `supabase migration list` and the SQL diff. The read-only snapshot for this target recorded ten applied versions, and the ten active local migration files match those versions. Re-check the chosen environment and migration history before applying any reviewed pending migration; the owner/lawyer SQL under `proposals/` is not a versioned migration or deployment instruction.
4. Test on a disposable isolated project with controlled test accounts and synthetic fixtures (never production test users/data), RLS and function grants, Auth confirmation/reset, simultaneous reservations, wallet idempotency, Storage paths, and all existing data-shape checks.
5. Use the CLI dry-run where supported, then have a second reviewer approve the exact migration list before `supabase db push`.
6. After an approved push, verify migration history, grants, policies, triggers, RPC grants, bucket privacy, and representative role-scoped queries. Do not use a service key for client smoke tests.

No remote push/deploy is authorized by this implementation task; the connected project must remain unchanged until its environment is established, a safe staging path exists, and the client/migration gates pass.

### Edge Function local validation and approved staging deployment

- Node tests for the shared handler run with `cd backend && npm test`; CI also runs `deno check supabase/functions/ai-assistant/index.ts`. For local runtime testing, use a disposable Supabase stack and isolated test account/PDF; do not use a real legal document.
- Store `GEMINI_API_KEY` only in the approved function environment, outside Git and Flutter build configuration. The AI function uses the caller JWT for profile and Storage access and does not require a service-role key for those operations.
- Once a staging project is explicitly identified, reviewed, backed up where relevant, and approved, deploy only to that target and verify JWT rejection, caller profile mapping, PDF path/size/signature checks, consent, cleanup, provider failure behavior, and advisory output. Do not deploy to an unclassified or production project as a substitute for staging.
- No function deployment or Gemini/Storage call has been made from this branch.

## Backup, cutover, and rollback

- Preserve Firebase/Express service and data until both Flutter clients use Supabase Auth and the complete native route matrix is tested. This repository is not ready for traffic cutover.
- Before importing or changing production data, capture a read-only source export and a destination backup, compare row counts and financial totals, validate every foreign-key/identity mapping, and rehearse rollback on an isolated clone. Retain the original Firebase exports; never reset, truncate, overwrite, or drop production data as a migration shortcut.
- The recovered migration files under `supabase/migrations/` represent versions already applied to this project; do not replay them. The owner/lawyer proposal contains no intentional application-row backfill, but it changes future Auth-trigger behavior, role constraints, and SELECT visibility. The old status-normalization candidate is archived, not active. Reconcile every proposed behavior and its rollback before any approved deployment.
- Prefer a forward corrective migration for a schema/grant/policy issue. Do not blindly run a down migration that restores the audited insecure grants, and do not use `pg_dump --clean` as a restore command. If a data restore is required, pause writes, obtain owner approval, restore a verified pre-change backup/PITR snapshot into an isolated recovery target first, compare data, and follow the platform’s reviewed recovery procedure.
- A code rollback may restore the previous application release only while the old API/Auth path is still healthy. It does not authorize removing the new schema or overwriting new rows. Record and manually reconcile any writes made after cutover before deciding whether a database restore is necessary.

## Remaining external services and names (no values)

- Supabase client: `SUPABASE_URL`, `SUPABASE_ANON_KEY` (public key only).
- Trusted server/Edge Functions: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` (secret; server-side only).
- Gemini document review, legal chat, and case prediction require a server-side `GEMINI_API_KEY` (optionally `GEMINI_MODEL`). The local `supabase/functions/ai-assistant/` implementation reads those values server-side, verifies the caller JWT/profile, uses caller-scoped Storage, and returns advisory output. The function source is not deployed and the secret is not verified/configured in the target environment; the Flutter clients no longer embed or call Gemini directly.
- Payments need a chosen provider, server-side provider credentials, and a webhook-signature secret. No provider, webhook, checkout, or verified payment flow is implemented; do not treat wallet credits/subscription activation as payment success.
- Initial admin provisioning and production schema rollout require project-owner approval. No secret values are stored in this repository or in this document.
