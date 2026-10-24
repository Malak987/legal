# App integration audit — Supabase, mobile, and admin

**Review date:** 2026-10-24 (Africa/Cairo)
**Scope:** read-only inspection of the connected Supabase project plus source review of `legal_app/`, `admin_panel/`, and the existing Express adapter. No production writes, Auth-setting changes, deployments, test data, or user-row reads were performed.

## Executive result

This is a **partial integration, not a completed cutover**. The project has an existing 19-table RLS schema and the apps contain Supabase Auth/profile code, a Supabase-backed Express adapter, partial direct PostgREST reads, and local AI/Storage function clients. Most app data screens still use the Express API. At the time of this audit, the panel lacked a lawyer workspace and registration path; later local source added a read-only lawyer panel and a server-side lawyer-signup endpoint gated off by default. Neither is deployed. Live Supabase still has only three RPC functions and no Edge Functions or Storage bucket, so several local sources reference services that remain unpublished.

Two current live identity gaps block safe public signup and complete fail-closed authorization:

1. `private.current_app_user_id()` falls back to `auth.uid()::text` without a matching `public.users` profile.
2. The `auth.users` insert trigger links an unlinked application profile by case-insensitive email alone, before it checks confirmation or an explicit legacy mapping.

The mobile client now fails closed on missing/unknown/non-client roles and **public client signup is disabled by default** pending the reviewed identity fix. The backend verifier no longer substitutes `client` for an absent/unknown database role. These are local code changes only; they do not alter production behavior.

## Live Supabase snapshot (read-only)

Project `qqfzbecwhewswkyxgebu` is `ACTIVE_HEALTHY` in `eu-west-1`, PostgreSQL `17.11.0.003`. The migration ledger contains these ten applied versions:

- `20261022174110_initial_legal_schema_and_rls`
- `20261022174313_transactional_rpc_functions`
- `20261024020757_conservative_live_security_hardening`
- `20261024021003_close_anon_internal_function_access`
- `20261024021013_restrict_rls_helper_function_execution`
- `20261024021402_add_missing_foreign_key_indexes`
- `20261024021409_tighten_availability_and_user_identity`
- `20261024021423_restrict_subscription_owner_updates`
- `20261024102004_legal_categories_and_assignments`
- `20261024123238_secure_rls_helper_functions_private_schema`

The exact SQL for the latest already-applied migration is now recovered locally at `supabase/migrations/20261024123238_secure_rls_helper_functions_private_schema.sql`. It was read from the migration ledger and **was not executed again**.

The live schema has 19 public tables, all with RLS enabled: `availability`, `booking_slots`, `bookings`, `cases`, `chat_messages`, `chats`, `earnings`, `favorites`, `lawyers`, `legal_categories`, `notifications`, `plans`, `reviews`, `subscriptions`, `tasks`, `users`, `wallet_idempotency`, `wallet_transactions`, and `wallets`. There are no public tables for case documents, hearings, or case history. No duplicate tables are proposed.

The live role check allows `client`, `lawyer`, and `admin`, but not `owner`. `authenticated` has UPDATE privilege on `users.role` and `users.auth_user_id`; the live `guard_user_identity_fields()` trigger currently blocks identity/role edits unless `public.is_admin()` returns true. The existing `admin` role is preserved as-is; it is not silently renamed to `owner`. The live RPC catalog contains only:

- `rpc_recalculate_lawyer_rating(text)`
- `rpc_reserve_booking_slots(...)`
- `rpc_wallet_mutate(...)`

The connected project returned no Edge Functions, Storage buckets, or Storage policies. Auth allows signup and requires email confirmation, but its current Site URL is `http://localhost:3000` and the redirect allow-list is empty. `anon` also has table-level SELECT privilege on `public.users`; that grant alone does not establish row visibility because RLS has no anonymous `users` policy. Realtime health metadata reported `db_connected=false`; this was not treated as proof of Realtime database connectivity.

The local index candidate `20261024102730_cases_lawyer_category_covering_index.sql` is not in the live migration ledger, and the live catalog already has `cases_lawyer_category_idx ON public.cases (lawyer_id, category_id)`. The duplicate candidate was preserved under `supabase/archive/unapplied_candidates/`, outside active CLI migration discovery; do not apply it.

## Identity and authorization findings

### Mobile client app

- `SignUpScreen` previously let the user choose `client` or `lawyer`; that selector is removed. The app has no public owner role path.
- Auth user metadata is display data only; the app no longer sends a `role` field. A compile-time `ENABLE_CLIENT_SIGNUP` flag defaults to `false`, and the registration button is disabled until the identity/profile flow is deployed and verified.
- `AppProfile` no longer treats a missing role as `client`. `AuthService.loadProfile()` accepts only an explicit `client` row in this client-only app, clears the Auth session on missing/unknown/non-client profile results, and never grants mobile access to a lawyer/admin account. A non-client profile returned after profile update also closes the session.
- The session uses the Supabase Auth refresh-token store. The profile read/update uses PostgREST only when Supabase URL and public key are configured; otherwise API calls require `API_BASE_URL`. Neither key nor API URL is populated by default.
- This does **not** fix the live database trigger. The `ENABLE_CLIENT_SIGNUP` guard is a source-level safety gate; the live project's public Auth signup setting remains enabled until an approved database/Auth change is made.

### Admin panel

- Login is Supabase Auth plus a direct RLS-scoped read of `public.users`; the stored role is checked strictly as `admin`. Missing/invalid/client/lawyer roles do not enter the admin shell. There is no public signup screen.
- There is no lawyer home/workspace in the panel, and no owner role support in the live database or app. Lawyer registration, lawyer-role routing, and owner-only provisioning are therefore **not complete**.
- The existing admin shell contains `Dashboard`, `Lawyers`, `Categories`, `Users`, `Cases`, `Bookings`, `Reviews`, `Plans`, `Subscriptions`, `Notifications`, and `Chats`. These screens use the existing `ApiService`/Express API, not direct PostgREST calls.

### Existing Express backend

- Protected routes verify Supabase Auth and create a request-scoped database client using the caller JWT, so PostgreSQL RLS remains in the authorization path. The process-wide service-role client remains server-side; this audit did not remove or deploy it.
- Local backend verification now rejects missing/unknown roles instead of using `role || 'client'`. The profile is read from `public.users`; role claims in Auth/user metadata do not supply the application role.
- The backend references a larger set of RPC names than the live catalog provides (including dashboard, booking mutation, case/task update, chat, favorites, reviews, notification, subscription, and role-change RPCs). Those RPC-dependent operations are not live-verified and will fail unless the matching reviewed functions are deployed. Ordinary reads/writes also remain subject to the live RLS policy and column grants.
- The existing Firebase/Firestore compatibility code and Express service remain in the repository. No service was disabled, deleted, or cut over.

## Screen/data-source matrix

| App/screens | Current source in local code | Observed live authorization/model fit | Result |
|---|---|---|---|
| Mobile signup/login/session/profile | Supabase Auth; profile via `ApiClient` PostgREST when configured | Live `users` role is authoritative; self-insert policy only permits `client`, but Auth trigger currently email-links legacy rows unsafely and does not create a new profile | **Partial / signup disabled by default** pending trigger and redirect approval |
| Mobile home, search, popular lawyers, lawyer detail | `AppRepository`; direct public PostgREST lawyer query only when `USE_SUPABASE_LAWYER_CATALOG=true`, otherwise Express | `lawyers` and `legal_categories` exist; public lawyer table SELECT is allowed; linked `user_id` is also selectable by `anon` under current grants | **Opt-in source only; default still Express** |
| Mobile categories | `GET /api/categories` through Express | `legal_categories` exists; backend uses caller JWT for protected writes | **Express-backed; not direct PostgREST** |
| Mobile favorites | Express by default; direct PostgREST opt-in `USE_SUPABASE_FAVORITES` | `favorites` exists and owner-scoped RLS exists, but `rpc_favorite_add` is not in the live RPC catalog | **Not safe to enable yet** |
| Mobile My Cases / case detail / case create | `GET/POST/PUT /api/cases` via Express | `cases` exists; client owner/admin policies exist. No lawyer-assigned SELECT policy, case history table, hearing table, document relation, or corresponding fields | **Partial; lawyers cannot access assigned cases; no fabricated history/hearings** |
| Mobile bookings / availability calendar | `/api/bookings`, `/api/availability` via Express | Existing `bookings`, `booking_slots`, and `availability` tables/policies exist. Live booking read policy is client-owner/admin, not assigned lawyer. Backend mutation RPC names exceed live RPC set | **Partial; lawyer appointment view/mutations not verified** |
| Mobile tasks, plans/subscriptions, notifications, wallet, earnings, reviews, chats | `AppRepository` API methods via Express | Corresponding existing tables/RLS exist. Wallet mutation RPC exists; many other RPCs referenced by routes are absent. No payment provider/webhook exists; activation must remain blocked | **Mixed; do not claim full CRUD parity** |
| Mobile AI chat, case prediction, PDF document review | Authenticated Edge Function client; PDF upload expects `document-upload`, `ai-assistant`, `legal-documents` bucket | No functions, bucket, or Storage policies are deployed | **Local source only; live requests/uploads not available** |
| Mobile court/FIR/party lookup and legacy cart/order-style screens | Existing legacy/static screen code | Current live schema has no court number/FIR/hearing/history/document model or product-order schema in the 19 tables | **Not connected to Supabase; do not treat as live legal case data** |
| Admin dashboard | `GET /api/dashboard/stats` via Express | Calls a dashboard RPC not present in live RPC catalog | **Blocked until backend/database parity is reviewed** |
| Admin lawyers/categories/users/cases | Express CRUD endpoints | Existing `lawyers`, `legal_categories`, `users`, `cases` tables are present; RLS/admin role boundaries exist. Some paths use missing RPCs or rely on backend-specific response enrichment | **Source-integrated through Express, not direct Supabase; live CRUD not tested** |
| Admin bookings/reviews/plans/subscriptions/notifications/chats | Express API | Tables exist; multiple mutation RPC names are absent remotely; no lawyer panel or owner role | **Partial / RPC parity gap** |

## Local changes and verification

- Added the exact local copy of the already-applied private-helper migration and archived the duplicate index candidate.
- Added a non-applied SQL proposal and exact rollback for missing-profile fail-closed helpers, explicit legacy linking, one-owner role support, and assigned-lawyer SELECT-only access to existing cases/bookings. See `supabase/proposals/20261024_identity_owner_lawyer_access.md`.
- Removed the mobile public role selector and role metadata, disabled client signup by default, and added fail-closed client-profile validation.
- Changed the backend Auth adapter to reject an unknown/missing profile role rather than defaulting to `client`; added adapter regression coverage.
- Current local verification: `cd backend && npm test` passes **513 tests across 123 suites**. `node --test test/supabase_migrations.test.js` passes **16/16**, including PGlite application of the proposal after all ten active migrations, confirmed/unconfirmed email and phone signup fixtures, Auth-UUID mapping, client/lawyer/owner policy boundaries, SECURITY DEFINER owner-guard checks, and a full before/after snapshot comparison of cases/bookings/booking_slots policies after rollback. These are synthetic local fixtures and PGlite only; they are not hosted PostgreSQL or Supabase Auth/PostgREST E2E evidence. Flutter/Dart are unavailable in this workspace, so Flutter tests were not run.
- No Flutter/Dart, Supabase CLI, Deno, `psql`, or Docker binaries are available here; Flutter tests/build and live E2E were not run. The backend Node suite is the only executable app suite in this environment.
- No production DDL/DML, Auth setting, Storage operation, function deployment, user-row read, or secret read/write was performed.
