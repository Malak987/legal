# Supabase-native migration audit

> **Historical baseline dated 2026-10-23.** Current project metadata, source/app inventory, grants/policies/RPC findings, verification results, and data-transfer status are in [FIRESTORE_TO_SUPABASE_INVENTORY_2026-10-24.md](FIRESTORE_TO_SUPABASE_INVENTORY_2026-10-24.md). In particular, do not use this baseline's live row/account claims, grant counts, or local test totals as current evidence.

**Audit date:** 2026-10-23
**Repository:** `Malak987/legal`
**Branch / inspected commit:** `arena/69f08c8e-legal` / `3f463ed`
**Target Supabase project:** `qqfzbecwhewswkyxgebu` (`eu-west-1`)
**Scope:** Phase 1 source, deployment, client, and remote-project audit before migration changes. This is a historical, read-only baseline; subsequent local code/migration work is not reflected here. The connected Supabase project was not classified as development, staging, or production, and no deployment target was inferred. For current source/test/deployment status, see `IMPLEMENTATION_REPORT.md` and `MIGRATION_STATUS.md`.

## Executive result

**The application has not completed its migration to Supabase.** Supabase PostgreSQL schema/RLS and three server-only RPCs exist, but neither Flutter client is currently using Supabase PostgreSQL as its general data API. Both still use the Express API URL for application data, and the deployed configuration routes that API through Firebase Hosting to a Firebase Cloud Function. The Express API has a Firestore fallback. Flutter also retains Firebase Auth fallbacks; the Admin panel retains a direct Cloud Firestore profile fallback.

The current Supabase RPCs are callable only by `service_role`, no Supabase Edge Functions or Storage buckets exist, and the remote database/Auth project has no application rows or Auth accounts. The actual database project is healthy and the two migrations are present, but that alone is not evidence of a completed client/runtime migration.

**This audit makes no persistent schema, data, auth-setting, secret, deployment, or Firebase changes.** Audit catalog checks were read-only. An earlier interrupted smoke-test CTE was aborted; a subsequent cleanup query using only `smoke-test-%` IDs reported zero affected rows. The remote database still verifies empty. There is no open pull request for this branch; PRs #1–#13 are merged into `main`.

## Git and pull-request inspection

- `git status`: clean working tree on `arena/69f08c8e-legal`.
- Current HEAD and `origin/arena/69f08c8e-legal`: `3f463ed` (`Improve ReviewsScreen scroll layout and test async drain loop`).
- `gh pr list --state open --head arena/69f08c8e-legal`: no PR.
- `gh pr list --state all --limit 100`: PRs #1–#13 are merged; the most recent is #13, which migrated the Express API to **Firebase Cloud Functions Gen 2**, not Supabase Edge Functions.
- No branch switch, reset, commit, push, merge, or deployment was performed in this audit.

## Current production/runtime request path

```text
Flutter mobile / Flutter Web admin
  ├─ Auth: Firebase Auth fallback, or hand-written Supabase Auth REST when an anon key is supplied
  └─ Application data: API_BASE_URL (defaults to https://legal-102026.web.app/api)
       └─ Firebase Hosting /api rewrite
            └─ backend/index.js -> Express on Firebase Cloud Functions Gen 2
                 ├─ Supabase service-role adapter, only when its server environment is configured
                 └─ otherwise Firebase Admin Auth + Cloud Firestore
```

The mobile `ApiClient.productionBaseUrl` and admin `AppConfig.apiBaseUrl` still point to `legal-102026.web.app/api`. `legal_app/main.dart` only selects its Supabase Auth gateway when `SUPABASE_ANON_KEY` is present; its `ApiClient` remains an HTTP client for the Express API. `admin_panel` has the same split: manual Supabase Auth/PostgREST profile lookup can be selected by a key, but `ApiService` remains Express HTTP and the Firebase Auth/Firestore fallback remains in the code. Neither app depends on `supabase_flutter`; there is no Supabase-native repository transport in the clients.

The server adapter in `backend/src/config/supabase.js` maps camelCase document names to PostgreSQL snake_case columns and uses a Supabase service-role client. `backend/src/config/firebase.js` selects this adapter only when both server-side Supabase URL and service key are configured; otherwise Firebase Admin/Firestore is selected. `firebase.json` still deploys `backend/` as Node 22 Cloud Functions and rewrites `/api/**` to it. The checked-in runtime examples contain placeholders only; `backend/.env` is absent. No Supabase Edge Function is currently deployed to replace this runtime.

## Complete Express endpoint inventory

`backend/src/routes/index.js` mounts 15 routers below `/api`. The Express app also exposes `/api/health` and `/health` (two aliases). The route inventory below reflects the inspected route code; it does not assume that a route is backed by Supabase in production.

| Resource | Express routes | Existing authorization and business rules | Supabase-native destination |
|---|---|---|---|
| Health | `GET /api/health`, `GET /health` | Unauthenticated process-level health response; does not check database readiness. | Supabase service health / app readiness probe; no Express dependency. |
| Lawyers | `GET /lawyers`, `GET /lawyers/:id`, `POST /lawyers`, `PUT /lawyers/:id`, `DELETE /lawyers/:id` | Public reads; admin-only writes. Search/filter/sort/pagination. Booking prices are derived from `priceValue`. | Public PostgREST reads under anon/authenticated policies; admin writes through authenticated RLS. |
| Users | `GET /users`, `POST /users/me`, `GET /users/:id`, `PUT /users/:id`, `PATCH /users/:id/role`, `DELETE /users/:id` | List/role/delete admin-only; self-or-admin profile read/update; profile provisioning takes token identity and assigns `client`; self cannot change role, UID, or sign-in email; delete also deletes Auth user; admin email update synchronizes Auth and profile. | Own profile through RLS; role changes through admin-checked RLS/RPC; Supabase Auth admin email update and delete require a trusted Edge Function. |
| Cases | `GET /cases`, `GET /cases/:id`, `POST /cases`, `PUT /cases/:id`, `DELETE /cases/:id` | Authenticated; owner or admin. Non-admin owner comes from verified identity. Admin can assign only an existing `client` or `lawyer`; status/priority defaults; partial updates preserve omitted fields; owner changes admin-only. | PostgREST with owner/admin RLS, constraints and input validation; no service-role client in Flutter. |
| Bookings | `GET /bookings`, `GET /bookings/:id`, `POST /bookings`, `PUT /bookings/:id`, `DELETE /bookings/:id` | Authenticated; list/details scoped to owner or admin. Create derives hourly price from lawyer, validates real date/time and advertised schedule, starts non-admin booking as `Pending`, and atomically reserves all consumed slots. Non-admin can cancel only; admin can alter state/reschedule and price is recomputed; cancel/delete release locks. | Authenticated PostgreSQL RPCs for create, reschedule, state changes, cancel/delete; database unique slot constraint and transactions are mandatory. Direct table writes are not safe. |
| Tasks | `GET /tasks`, `GET /tasks/:id`, `POST /tasks`, `PUT /tasks/:id`, `DELETE /tasks/:id` | Authenticated; owner or admin. Create owner from verified identity except admin; updates cannot reassign an owner for non-admin; partial updates preserve status/priority. | PostgREST with owner/admin RLS and consistent status constraints. |
| Wallet | `GET /wallet/:userId`, `POST /wallet/transactions` | Self/admin read. Amount >0, <=1,000,000, max two decimals; USD; only admin can credit, owner can debit own wallet; verify user exists; idempotency key binds user/type/amount; prevent overdraft and currency mixing; balance, ledger, idempotency atomic. Comments explicitly say a real top-up needs a verified payment-provider result/webhook, which is not implemented. | Authenticated wallet RPC for owner debit/admin credit and atomic ledger/idempotency; actual payment credits need an external provider webhook/Edge Function. No card/PayPal verification exists. |
| Reviews | `GET /reviews`, `GET /reviews/:id`, `POST /reviews`, `PUT /reviews/:id`, `DELETE /reviews/:id` | Public read strips author `userId`; one review per author/lawyer; author identity from verified token; admin-only moderation and delete. **The inspected route does not check for a qualifying completed booking**, despite the review workflow’s legal/business implications. | Public redacted view (do not expose `user_id`) plus authenticated RPC/constraint for submission; admin-only moderation. Qualification rule must be explicitly approved and enforced, not invented client-side. |
| Chats/messages | `GET /chats`, `GET /chats/:id`, `POST /chats`, `POST /chats/:id/messages`, `DELETE /chats/:id` | Authenticated; participant or admin access. Creator must be a participant unless admin; participants must be distinct; participant names and sender identity are resolved from trusted profiles/token; message write and chat summary update are currently separate writes; members/admin may delete per route helper. | RLS for participant reads; atomic create/send RPCs with participant/name/token checks. Realtime is not currently implemented; polling is the current UI behavior. |
| Plans | `GET /plans`, `GET /plans/:id`, `POST /plans`, `PUT /plans/:id`, `DELETE /plans/:id` | Public read; admin writes; search/sort/pagination. | PostgREST public reads and admin-only authenticated RLS writes. |
| Subscriptions | `GET /subscriptions`, `GET /subscriptions/:id`, `POST /subscriptions`, `PUT /subscriptions/:id`, `DELETE /subscriptions/:id` | Owner/admin reads. New owner subscription is always `Pending`, plan title derived from existing plan. Owner may cancel only; cannot alter plan or activate. Owner cannot hard-delete an Active record; admin can. | Authenticated RPC for insert/update/delete enforcing ownership, immutable plan data, and transitions; verified payment event is needed for paid activation. |
| Notifications | `GET /notifications/:userId`, `GET /notifications`, `POST /notifications`, `PUT /notifications/:id/read`, `PUT /notifications/:id`, `DELETE /notifications/:id` | Own/admin reads; all-users list and creation admin-only; owner can mark/edit/delete own notification, cannot transfer ownership; admin can manage. | RLS/column restrictions or narrow RPC for self read-state updates; admin-only creation and cross-user management. |
| Earnings | `GET /earnings/:userId` | The inspected middleware permits self or admin (it does not explicitly require lawyer); endpoint is read-only. | PostgREST with a deliberately approved lawyer/admin policy; data writes require a trusted settlement/booking workflow that is not present. |
| Availability | `GET /availability`, `GET /availability/:id`, `POST /availability`, `PUT /availability/:id`, `DELETE /availability/:id` | Public reads. Admin can manage all. Lawyer writes are checked in Express using `availability.lawyerId == req.user.uid`; ownership model is ambiguous because lawyer records also have a separate `user_id`. | Public read RLS plus owner-scoped lawyer RLS/RPC using `lawyers.user_id`; resolve and migrate the ownership contract before allowing direct writes. |
| Favorites | `GET /favorites/:userId`, `POST /favorites`, `DELETE /favorites/:id` | Self/admin list, add owner from verified token, duplicate add returns existing record, delete owner/admin. | PostgREST with owner RLS and existing `(user_id, lawyer_id)` uniqueness. |
| Dashboard | `GET /dashboard/stats` | Admin-only aggregate counts and wallet-balance sum. | Admin-checked PostgreSQL RPC; do not expose service-role credentials to browser. |

### Cross-cutting Express controls

- `authenticate`: validates a Firebase ID token or Supabase Auth access token through server adapter; resolves profile name/role from `public.users`/Firestore. Identity is token-derived; profile role is authoritative. The Supabase adapter uses server-side Auth admin functions where needed.
- `requireRole`, `requireSelfOrAdmin`, `ownerIdFor`, `isOwner`, `lockOwnerOnUpdate`: server-side role/ownership checks.
- `Joi` validation in `backend/src/utils/validators.js`; unknown body fields are stripped. `stateTransitions.js` limits booking/subscription states. `scheduling.js` and `bookingReservation.js` implement schedule validation and Firestore lock strategy.
- `helmet`, CORS allowlist, Express rate limit (100 requests / 15 minutes), 2 MiB JSON body limit, centralized not-found/error response handling.
- The current health handler only checks the HTTP layer, not Postgres/Auth.

## Existing database access and transaction behavior

`backend/src/config/supabase.js` maps 18 document-style collections to these PostgreSQL tables: `users`, `lawyers`, `cases`, `bookings`, `booking_slots`, `tasks`, `chats`, `chat_messages`, `reviews`, `favorites`, `wallets`, `wallet_transactions`, `wallet_idempotency`, `plans`, `subscriptions`, `notifications`, `earnings`, and `availability`.

The adapter has a material integrity gap: `runTransaction()` stages writes, then sends separate PostgREST requests and attempts compensating writes on error. It does **not** create a PostgreSQL transaction and cannot guarantee rollback/atomicity across requests. Its `batch()` is also sequential. The booking and wallet routes call this adapter, so those operations are not equivalent to Firestore transactions when the adapter is configured against Supabase. Only the three SQL RPCs below are truly transactional.

## Verified remote Supabase state

Read-only checks were made against `qqfzbecwhewswkyxgebu` using the Supabase connector and SQL catalog views:

- Project status `ACTIVE_HEALTHY`; checked `auth`, `db`, `rest`, and `storage` services are healthy. Earlier health check also reported `realtime`, pooler, Postgres user, and pgBouncer healthy.
- PostgreSQL 17.11, region `eu-west-1`.
- Migration history contains exactly:
  1. `20261022174110` — `initial_legal_schema_and_rls`
  2. `20261022174313` — `transactional_rpc_functions`
- Exactly the 18 expected public tables exist; all 18 have RLS enabled (none has `FORCE ROW LEVEL SECURITY`). Catalog query confirmed the live column lists. Notable mismatch: `public.lawyers` has no `experience` column although the mobile model reads `experience` and an earlier smoke insert that assumed it exists failed. The database table uses `user_id` to link a lawyer profile to a `users` row.
- 54 policies exist (the 18-table migration’s policy set). This count is not by itself proof that the policies implement every Express authorization rule.
- Three `SECURITY DEFINER` RPCs exist: `rpc_recalculate_lawyer_rating`, `rpc_reserve_booking_slots`, and `rpc_wallet_mutate`. Catalog grants confirmed `anon_can_exec=false`, `authenticated_can_exec=false`, `service_role_can_exec=true` for all three. Therefore Flutter clients cannot invoke the existing RPCs.
- Exact row counts checked in the earlier read-only pass were zero in all 18 public tables, `auth.users`, and the named application tables. The later `pg_stat_user_tables` estimates also show zero live tuples. This is an empty project, not a migrated production dataset.
- No Edge Functions were listed. `storage.buckets` has zero rows. The project custom-secret listing is empty. Email/password Auth is enabled, signup is allowed, email auto-confirm is disabled, JWT expiry is 3600 seconds, and refresh-token rotation is enabled.
- The RLS role helpers resolve a simulated, non-existent authenticated UUID to `current_app_user_id = auth.uid`, `current_app_user_role = NULL`, `is_admin = false`, and zero visible users. This was a read-only role-context check, not a test of a real client/lawyer/admin account.
- Catalog inspection also found `anon`, `authenticated`, and `service_role` granted all table privileges (including `TRUNCATE`, `INSERT`, `UPDATE`, `DELETE`, `TRIGGER`, and `REFERENCES`) on every public table. RLS still applies to normal PostgREST table DML, but `TRUNCATE` is not row-filtered; grants should be reduced to the exact required operations as part of a reviewed migration.
- Live constraints do not match all current Express contracts: `bookings_status_check` allows `Pending, Confirmed, Completed, Cancelled`, while Express/admin UI uses `Pending, Active, Completed, Cancelled`. `tasks_status_check` uses `Pending, In Progress, Completed`, while the backend task validator uses `To Do, In Progress, Done`. These contract mismatches must be reconciled before direct PostgREST use.
- The live `auth.users` trigger `trg_auth_users_link_migrated` fires **AFTER INSERT**, and the deployed `link_migrated_auth_user()` links a matching `public.users.email` without checking `email_confirmed_at`. Because project email auto-confirm is off, confirmation-sensitive identity linking needs review before signup is opened to imported profiles.
- A remote database read through the Supabase control-plane connector was verified. The sandbox itself blocks direct outbound requests to `*.supabase.co`; this means a local Flutter/HTTP end-to-end request cannot be claimed from this runner without an allowed network path. No client/API write was made in this audit.

## Feature inventory outside the Express route set

| Capability | Current implementation | Migration / production finding |
|---|---|---|
| Supabase Auth | Hand-written GoTrue REST in both Flutter apps if a publishable/anon key is passed at compile time. | Mobile token refresh is in-memory only; no session restoration/persistent token storage on app restart. Admin Supabase mode also stores only an in-memory session; `currentUser()` does not restore it and its Supabase auth-state stream is empty. |
| Firebase Auth / Firestore | Firebase SDK and fallback code remain in `legal_app`, `admin_panel`, backend config, `firebase.json`, `firestore.rules`, and emulator CI. Admin panel can read its profile directly from Firestore. | Firebase remains an active fallback/runtime path; removing it now would break builds/configurations and is premature until Supabase Auth/RLS replacement and data/identity cutover are tested. |
| File upload / document review | `legal_app/views/aidocumentsreview/aireview.dart` selects a local file, simulates a 0–100% upload, extracts PDF text locally, then calls Gemini directly. | Progress is explicitly simulated; no document is persisted, no Supabase Storage bucket exists, and no Storage policies exist. Not a real upload workflow. |
| AI chatbot / prediction / document analysis | Flutter calls Google Generative Language API directly. `AiConfig` accepts `GEMINI_API_KEY` as a Dart define; the key is extractable from a shipped client. | Third-party Gemini integration is real but the credential placement is not production-safe. Requires a Supabase Edge Function and server-side Gemini secret; the project has no function/secret configured. The model's generated outcome prediction must remain advisory, not an authoritative legal result. |
| Payments | Payment UI includes PayPal/card/cash selections and static amounts; no provider SDK, verification webhook, or settlement job found. Wallet route intentionally denies non-admin credit. | Real PayPal/card top-up and paid-subscription activation are not implemented. Supabase does not replace the payment processor. Require chosen provider credentials, server-side webhook signature verification, idempotency, and financial approval. |
| Schedules/background jobs/webhooks | No scheduled job, cron trigger, queue, or incoming payment webhook found in backend or Supabase. | Reminder seeds are static fixture data; no reminder delivery/settlement scheduler exists. |
| Other client screens | Lawyer directory/search, booking/calendar, cases list, favorites, chats, reviews, tasks, profile, wallet, subscription, and dashboard/admin resource screens have API/repository integration points. | Some navigation destinations are explicitly static or legacy: search result lawyer detail is a mock/no-op; tapping a live case opens a static status screen; legacy bookmark/cart/orders use `ProductData`; AI document upload is simulated. Must be classified/disabled or connected before claiming all screens are live. |

## Security and behavior gaps to resolve before client cutover

These are source/catalog findings, not a full exploit test:

1. **No native client transport or deployed Edge Functions.** Existing app data still depends on Firebase Hosting + Express. No Supabase API URL/key is required/selected by the current production build defaults.
2. **Fake transaction adapter.** The service-role PostgREST adapter cannot make a multi-request transaction. Booking slot creation, chat message plus chat summary, and rollback semantics must become single SQL transactions/RPCs.
3. **Over-broad table grants.** Revoke all blanket grants from `anon`/`authenticated`; grant only the minimum required for each table/view/function in addition to RLS.
4. **Role and row-scope holes in current policies:** availability write policy checks only `is_lawyer_or_admin()` and does not bind a lawyer to its own lawyer row; participant chat update policy allows participants to rewrite `participants`/display metadata; reviews allow author UPDATE/DELETE though the Express route makes moderation/deletion admin-only; subscription owner UPDATE policy checks only final `status='Cancelled'`, not immutable plan columns; review table SELECT exposes `user_id` to direct PostgREST queries whereas Express strips author IDs. Users self-update policy compares old `role`/`email` by subqueries against the same RLS table and needs execution testing/rewrite to avoid recursive/incorrect policy behavior.
5. **Booking/task status contract mismatch** between live CHECK constraints and backend/admin model (above). This will reject direct writes and likely admin state changes.
6. **Rating recomputation is not automatic.** A service-only recalc RPC exists, but no review trigger invokes it. No secure client-callable review submission function exists.
7. **Auth identity linking** is based on email at `auth.users` INSERT without a confirmed-email condition. Auth config requires confirmation, but the trigger runs before that confirmation. Add verified/controlled linking; do not grant role from client metadata.
8. **No real role accounts or rows to verify.** The empty project has no client, lawyer, or admin profile. Signup creates `client`; establishing the first admin requires a trusted out-of-band provisioning step (or an audited Edge Function), not client-provided role claims.
9. **Admin user deletion/email synchronization requires Auth Admin privileges.** Direct PostgREST cannot safely delete `auth.users` or update the Auth email; use a server-side Edge Function and project-managed server secret.
10. **Payment and document AI workflows have no secure external integration.** Do not claim a successful payment, subscription activation, upload, or AI-backed document processing until provider/storage/function credentials and workflows exist.

## Target migration map

- **Direct PostgREST under RLS:** public lawyer/availability/plan reads; own profile, cases, tasks, favorites, notifications and permitted read operations; admin resource CRUD where the RLS rule is simple and complete.
- **PostgreSQL RPCs (SECURITY DEFINER, fixed `search_path`, `auth.uid()`/database-role checks, explicit `REVOKE`/`GRANT`):** registration profile provisioning; booking create/cancel/reschedule/status/slot release; wallet debit and admin-credit ledger; subscription state transitions; review submission/rating update; chat create/send with atomic summary; dashboard aggregates; narrow notification updates. RPCs must derive caller identity and role themselves, not trust a client `user_id` or role.
- **Supabase Edge Functions:** Auth Admin operations (admin user email update/delete), Gemini proxy/document analysis, and chosen payment-provider create/verify/webhook handlers. The service-role key and provider credentials remain server-only.
- **Supabase Storage:** only if document review needs persistent file storage; create a private bucket with user-scoped paths, size/type limits, and RLS. Do not create a bucket or claim uploads until required and approved.
- **Remove Firebase Functions/Hosting/API and Firebase SDK fallbacks only after** both Flutter clients use Supabase Auth sessions and the final Supabase data/function contracts, all role boundaries pass tests, migration/import is separately backed up and validated, and an approved cutover/rollback plan exists.

## Verification labels for this audit

- **VERIFIED AGAINST THE REMOTE SUPABASE PROJECT:** project/service health, two migration-history rows, 18 live public tables/columns, RLS flags, policy/function grants, key/Edge/Storage inventory (without printing any key value), zero-row checks, auth config, constraints, trigger/function definitions, and read-only simulated-role helper evaluation.
- **VERIFIED LOCALLY:** repository branch/PR inventory, Express routes/middleware/adapter source, client endpoint/config source, tests and deployment configuration were inspected. Prior CI run `39833573065` passed the three then-current jobs; those results are not evidence of Supabase end-to-end behavior.
- **CODE-REVIEWED ONLY:** route behavior and current policies were compared; the unconfirmed-email link trigger, transaction adapter, client fallbacks, Gemini key boundary, fake upload, and contract mismatches require tests/fixes.
- **BLOCKED BY MISSING ACCESS OR CREDENTIALS:** local direct network access to Supabase is blocked; no build-time anon/publishable key is configured in the repository, no app Auth accounts exist, no Edge Functions or Storage buckets exist, and no external Gemini/payment credentials are configured here.
- **REQUIRES MANUAL TESTING:** Auth persistence/session refresh on iOS/Android/web; email-confirmation and password-reset flows; client/lawyer/admin RLS and UI workflows with designated accounts; real booking concurrency; payment-provider verification; Storage upload/download policy; admin Auth-user changes; and production hosting/cutover.

## Commands and test evidence

Commands run in this audit:

- `git status --short`, `git log -5 --oneline --decorate`, `gh pr list --state all --limit 100`: confirmed clean starting branch/commit, no open PR for this head, and merged PR history.
- Repository inspection with `find`, `grep`, and source reads under `backend/`, `legal_app/`, `admin_panel/`, `firebase.json`, `.github/workflows/`, and `supabase/`: endpoint, integration, client, schema, and deployment inventory above.
- Supabase connector `get_project_health`, `list_migrations`, `get_auth_config`, `list_edge_functions`, `list_secrets`, plus read-only catalog/row-count SQL: remote results above. The only simulated JWT check ran in a transaction with `SET LOCAL ROLE authenticated` and `ROLLBACK`; it read no account data and wrote nothing.
- `cd backend && npm ci && npm test`: **120 suites / 471 tests passed, 0 failed**. `npm ci` reported **9 dependency audit findings (7 moderate, 2 high)**; no automatic dependency remediation was applied.
- `gh run view 39833573065 --json ...`: run completed successfully at HEAD `3f463edf068536d4411225535418391c89e97ac1`. Mobile analyze/test, Admin analyze/test/Firebase Hosting web build, and Backend/Firebase Emulator E2E jobs all passed. These are existing CI results for the current commit, not Supabase end-to-end tests.
- `command -v flutter`, `command -v dart`, `command -v psql`, `command -v docker`: none of these local toolchains is installed in this runner; no local Flutter build, database emulator, or local Express server was started. No application client was run against the remote Supabase project.
- `git diff --check`: no whitespace errors in tracked diff; audit document is new/untracked at this point.

## Completion gate

Do not call the migration complete or remove backend code until: every route contract has a tested Supabase-native equivalent; each direct operation passes role-scoped RLS tests; privileged workflows use atomic RPC/Edge Functions; both apps default to Supabase Auth + PostgREST/functions with only public publishable/anon keys; no Firebase/Express URL/runtime dependency remains on production paths; Flutter builds/tests and Edge Function/database tests pass; and an approved backup/import/cutover/rollback and account-password transition plan is in place.

## Post-audit implementation work (2026-10-23)

The initial audit remains historical and its “no changes made” statement describes that audit phase. Subsequent implementation is tracked separately in `supabase/MIGRATION_STATUS.md` and `supabase/README.md`: two reviewed SQL migrations plus PGlite integration tests have been added; notification updates and booking deletes now have authenticated RPCs; backend Auth adapter email-only identity linking has been removed; the mobile Auth response parser no longer trusts client-editable `user_metadata.legacy_uid`, and mobile own-profile read/update plus Supabase signup now use PostgREST/RLS and the confirmed-user trigger when configured. These changes are not deployed. Both Flutter clients still use Express for remaining application data, and the migration is not complete.
