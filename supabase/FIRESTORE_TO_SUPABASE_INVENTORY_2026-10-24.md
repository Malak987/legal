# Firestore → Supabase/backend inventory

**Snapshot:** 2026-10-24 (Africa/Cairo)<br>
**Repository:** `Malak987/legal`, branch `arena/69f08c8e-legal`, HEAD `1e43a889f3a5e901599190f0a595806621b284ca`<br>
**Live Supabase project:** `qqfzbecwhewswkyxgebu` (PostgreSQL 17.11; project reported healthy)<br>
**Disposition:** read-only live inspection and local verification only. **No hosted migration, Auth change, Storage write, seed, or Firestore transfer was performed.** No verified restorable backup was available, so the requested hosted-change gate remains closed.

## 1. Scope and confidence

This is an inventory of the repository's source-supported Firestore/API contract, its current local Supabase implementation, and the live Supabase catalog. It is **not** a live Firestore document census: no Firestore connector/export was available, so live Firestore collections, document counts, actual per-document field presence, and source-to-target reconciliation remain unverified. Field names below come from `backend/src/config/supabase.js`, route validators/handlers, `backend/src/seed.js`, and Flutter call sites; they do not prove every stored Firestore document has every listed optional field.

Likewise, SQL catalog inspection establishes live schema/ACL/policy metadata, not that a Flutter screen can successfully complete a hosted Auth/PostgREST/Storage transaction. No production row-level data was used for the transfer audit. **One read-only catalog/aggregate query incidentally included `count(*)` over `public.users`; no individual row values were selected, and that aggregate was not retained or used as a transfer assertion.**

## 2. Live deployment state and migration gate

### Live migration history

The connected project reports these eight applied migrations, in order:

1. `20261022174110 initial_legal_schema_and_rls`
2. `20261022174313 transactional_rpc_functions`
3. `20261024020757 conservative_live_security_hardening`
4. `20261024021003 close_anon_internal_function_access`
5. `20261024021013 restrict_rls_helper_function_execution`
6. `20261024021402 add_missing_foreign_key_indexes`
7. `20261024021409 tighten_availability_and_user_identity`
8. `20261024021423 restrict_subscription_owner_updates`

The repository has four local SQL files: the first two baseline versions above and two later candidates:

- `supabase/migrations/20261023100000_harden_rls_auth_and_storage.sql`
- `supabase/migrations/20261023101500_authenticated_transactional_rpcs.sql`

The two candidates are **not applied**. They predate the latest six remote migration versions and their PGlite fixture is explicitly a synthetic initial local snapshot, not a mirror of the current live catalog. Reconcile missing remote migration source/history and rebase/review any candidate changes before attempting a deploy; do not replay these files blindly over the live project.

No reliable backup/restore path was available through the connected tools. Accordingly, no remote project changes were attempted. The live Auth configuration remains unchanged: email sign-up enabled, confirmation required, unverified sign-in disabled, `site_url` is `http://localhost:3000`, and the redirect allow-list is empty.

### Live catalog summary

- 18 `public` tables; 153 columns; 18 primary keys; 23 foreign keys; 35 check constraints; 7 unique constraints; 70 indexes.
- RLS is enabled on all 18 tables, but is **not forced** on them.
- 54 public-schema RLS policies, 11 public functions and 16 public triggers.
- Table privileges are broad: `anon` has `SELECT` on all 18 public tables; `authenticated` has `SELECT/INSERT/UPDATE/DELETE` on all 18; `service_role` has full table privileges. `anon` and `authenticated` do not have table-level `TRUNCATE`, `REFERENCES`, or `TRIGGER` privileges. RLS and column grants still affect actual requests; hosted JWT role-boundary behavior was not exercised.
- Storage has 0 buckets, 0 objects, and 0 Storage policies. The catalog nevertheless reports table-level `anon` and `authenticated` `INSERT/SELECT/UPDATE/DELETE` grants on `storage.buckets`, `storage.objects`, and `storage.buckets_analytics`; this is not a tested Storage API boundary and does not establish that a file is publicly accessible.
- No Edge Functions are deployed.

## 3. Source collection/field map

“Firestore fields” here means repository-supported property names and shapes. `backend/src/config/supabase.js` maps camelCase document keys to snake_case columns and maps nested `chats/{chatId}/messages` to `chat_messages`. `bookingSlots` and `wallet_idempotency` are backend-internal reservation/idempotency records, not ordinary user-facing screens.

| Firestore logical path / source-known fields | Supabase table / live status | Application use in source |
|---|---|---|
| `users/{uid}` — `uid`, optional `authUserId`, `name`, `email`, `phone`, `role`, `avatar`, `address`, `createdAt`, `updatedAt` | `public.users`; Auth link is nullable `auth_user_id`; current role/identity checks and FK exist. | Both apps use profile/auth flows. Admin user management is through Express in the panel; mobile profile access can use Supabase when configured. |
| `lawyers/{id}` — optional `userId`, `name`, `specialty`, optional `experience`, `price`, `priceValue`, `image`, `rating`, `location`, `bio`, `isPopular`, `isTop`, timestamps | `public.lawyers`; current live table has no `experience`; `specialty` remains free text; `user_id` nullable/FK. | Legal catalogue/detail screens use the repository; direct PostgREST is behind default-off `USE_SUPABASE_LAWYER_CATALOG`. Admin lawyer CRUD uses Express. |
| `cases/{id}` — `userId`, `title`, `description`, `clientName`, `caseType`, `priority`, `status`, `dueDate`, timestamps | `public.cases`; `case_type`/`due_date` remain text; nullable owner FK to `users`. No lawyer assignment, category FK, hearings, document relation, or history relation. | Legal case list uses the API; case-detail/hearing presentation is not backed by normalized hearing records. Admin case list/create/edit/delete uses Express and selects a client owner, not lawyer assignment. |
| `availability/{id}` — `lawyerId`, `lawyerName`, `date`, `slots` (source array of times), timestamps | `public.availability`; `slots jsonb`; FK to lawyer. Date check validates `YYYY-MM-DD` shape only. | Legal booking calendar reads availability through the API. No availability CRUD screen was found in the Admin panel. |
| `bookings/{id}` — `userId`, `lawyerId`, `lawyerName`, `date`, `time`, `hours`, `totalPrice`, `status`, optional `slotKeys`, timestamps | `public.bookings`; FK to user/lawyer; slot reservation table is separate. Live table has no `idempotency_key_hash`. | Legal calendar creates bookings; history/order screens list and cancel; Admin panel lists/deletes bookings. |
| Internal `bookingSlots/{id}` — `lawyerId`, `date`, minute-of-day `slot`, `bookingId`, `userId`, `createdAt` | `public.booking_slots`; FKs to booking/lawyer/user, unique `(lawyer_id,date,slot)`. | Server-side booking/reservation machinery only; no direct Flutter CRUD. |
| `chats/{chatId}` — `participants[]`, `participantNames` map, `lastMessage`, timestamps | `public.chats`; participants stored as `text[]`, names as `jsonb`; no normalized participant table/FKs for each participant. | Legal chat list/detail/send and Admin chat list/detail use API routes. |
| `chats/{chatId}/messages/{messageId}` — `senderId`, `senderName`, `text`, `createdAt` | `public.chat_messages`; FKs to chat and sender user. | Legal and Admin chat/message panes use the Express API; current production Realtime behavior was not verified. |
| `favorites/{id}` — `userId`, `lawyerId`, `createdAt` | `public.favorites`; user/lawyer FKs and unique `(user_id,lawyer_id)`. | Legal favorites and lawyer-detail save action; direct PostgREST/RPC is behind default-off `USE_SUPABASE_FAVORITES`. Not an Admin feature. |
| `reviews/{id}` — `userId`, `userName`, `lawyerId`, `rating`, `comment`, timestamps | `public.reviews`; user/lawyer FKs, unique author/lawyer pair, rating check. Current raw table SELECT is public under broad table SELECT grants. | Legal review list/submit uses the API; Admin review moderation/deletion uses Express. Candidate `public_reviews` view is not live. |
| `tasks/{id}` — `userId`, `title`, `description`, `dueDate`, `priority`, `status`, timestamps | `public.tasks`; owner FK. Live status check currently permits only `Pending`, `In Progress`, `Completed`; Express validator also permits `Cancelled`. | Legal tasks list/create/update/delete uses API. Admin panel has no task screen. POST forwards the complete validated payload; the submitted initial `status` is retained. |
| `plans/{id}` — `title`, `price`, `priceValue`, `color`, `features[]`, `isPopular`, timestamps | `public.plans`; `features jsonb`; public SELECT, admin mutation policy. | Legal subscription screen reads plans; Admin panel manages plans through Express. |
| `subscriptions/{id}` — `userId`, `planId`, `planTitle`, `status`, `startDate`, `endDate`, timestamps | `public.subscriptions`; user/plan FKs; `end_date` nullable. Status check: `Pending`, `Active`, `Cancelled`, `Expired`. | Legal subscription screen creates/cancels via API; Admin panel lists/updates status via Express. No verified billing/payment workflow. |
| `notifications/{id}` — `userId`, `title`, `content`, `type`, `icon`, `read`, timestamps | `public.notifications`; owner FK. | Legal notifications list/delete uses API; Admin panel creates/deletes notifications through Express. |
| `wallets/{userId}` — `userId`, `balance`, `currency`, timestamps | `public.wallets`; user FK; `id=user_id` check and unique `user_id`. | Legal wallet/balance screens use API. No Admin wallet UI found. |
| `wallet_transactions/{id}` — `userId`, `type`, `amount`, `description`, `balance`, `currency`, optional `idempotencyKeyHash`, timestamps | `public.wallet_transactions`; user FK; nullable `idempotency_key_hash`; live amount check is `0 < amount <= 100000`. Express accepts up to 1,000,000, a live schema/API mismatch. | Legal transactions/top-up flow uses API; no Admin transaction screen found. A client-supplied credit is not proof of payment. |
| Internal `wallet_idempotency/{deterministic-id}` — `userId`, `type`, `amount`, `currency`, `balance`, `transaction`, `createdAt` | `public.wallet_idempotency`; user FK; owner/admin SELECT policy; protected writes are server-side. | Internal backend wallet idempotency only; not a screen collection. |
| `earnings/{userId}` — `userId`, `balance`, `totalEarnings`, `breakdown` map, timestamps | `public.earnings`; user FK, `id=user_id` check, unique owner. | Legal earnings/detail screens use API. Admin panel has no earnings screen. |
| No repository-supported normalized category collection | No `categories` table. Lawyer `specialty` and case `case_type` are text, not FK-backed taxonomies. | Legal UI has category/filter choices; Admin case editor uses free-text/type inputs. Do not infer relational category IDs. |
| No `caseHearings`, `caseDocuments`, or `caseHistory` collection contract found | No hearing/document/history tables or case relations in live schema. | Hearing-date UI includes static date content; AI document review uses a temporary upload workflow, not a case-document archive. |
| No standalone upload collection or live Storage bucket | Avatar/lawyer `image` values are string fields; no live bucket or file objects. Candidate bucket `legal-documents` is unapplied. | Legal AI document review can call local-source Edge Function/Storage code when configured; no Admin upload workflow. |

## 4. Exact live public columns

`NULL` below means the column is nullable; other listed columns are `NOT NULL` in the live catalog. Types are live PostgreSQL types.

```text
availability:          id text, lawyer_id text, lawyer_name text, date text, slots jsonb, created_at timestamptz, updated_at timestamptz
booking_slots:          id text, lawyer_id text, date text, slot integer, booking_id text, user_id text, created_at timestamptz
bookings:               id text, user_id text, lawyer_id text, lawyer_name text, date text, time text, hours integer, total_price numeric, status text, slot_keys text[], created_at timestamptz, updated_at timestamptz
cases:                  id text, user_id text NULL, title text, description text, client_name text, case_type text, priority text, status text, due_date text, created_at timestamptz, updated_at timestamptz
chat_messages:          id text, chat_id text, sender_id text, sender_name text, text text, created_at timestamptz
chats:                  id text, participants text[], participant_names jsonb, last_message text, created_at timestamptz, updated_at timestamptz
earnings:               id text, user_id text, balance numeric, total_earnings numeric, breakdown jsonb, created_at timestamptz, updated_at timestamptz
favorites:              id text, user_id text, lawyer_id text, created_at timestamptz
lawyers:                id text, user_id text NULL, name text, specialty text, price text, price_value numeric, image text, rating numeric, location text, bio text, is_popular boolean, is_top boolean, created_at timestamptz, updated_at timestamptz
notifications:          id text, user_id text, title text, content text, type text, icon text, read boolean, created_at timestamptz, updated_at timestamptz
plans:                  id text, title text, price text, price_value numeric, color text, features jsonb, is_popular boolean, created_at timestamptz, updated_at timestamptz
reviews:                id text, user_id text, user_name text, lawyer_id text, rating numeric, comment text, created_at timestamptz, updated_at timestamptz
subscriptions:          id text, user_id text, plan_id text, plan_title text, status text, start_date timestamptz, end_date timestamptz NULL, created_at timestamptz, updated_at timestamptz
tasks:                  id text, user_id text, title text, description text, due_date text, priority text, status text, created_at timestamptz, updated_at timestamptz
users:                  id text, uid text, auth_user_id uuid NULL, name text, email text, phone text, role text, avatar text, address text, created_at timestamptz, updated_at timestamptz
wallet_idempotency:     id text, user_id text, type text, amount numeric, currency text, balance numeric, transaction jsonb, created_at timestamptz
wallet_transactions:    id text, user_id text, type text, amount numeric, description text, balance numeric, currency text, idempotency_key_hash text NULL, created_at timestamptz, updated_at timestamptz
wallets:                id text, user_id text, balance numeric, currency text, created_at timestamptz, updated_at timestamptz
```

### Live relationship and constraint inventory

- **Primary keys:** `id` on each of the 18 tables.
- **Foreign keys (23):** `availability.lawyer_id → lawyers.id` (`CASCADE`); `booking_slots.booking_id → bookings.id`, `lawyer_id → lawyers.id`, `user_id → users.id` (all `CASCADE`); `bookings.lawyer_id → lawyers.id` (`RESTRICT`), `user_id → users.id` (`CASCADE`); `cases.user_id → users.id` (`SET NULL`); `chat_messages.chat_id → chats.id` and `sender_id → users.id` (`CASCADE`); `earnings.user_id → users.id` (`CASCADE`); `favorites.lawyer_id → lawyers.id` and `user_id → users.id` (`CASCADE`); `lawyers.user_id → users.id` (`SET NULL`); `notifications.user_id → users.id` (`CASCADE`); `reviews.lawyer_id → lawyers.id` and `user_id → users.id` (`CASCADE`); `subscriptions.plan_id → plans.id` (`RESTRICT`) and `user_id → users.id` (`CASCADE`); `tasks.user_id → users.id` (`CASCADE`); `users.auth_user_id → auth.users.id` (`SET NULL`); and `user_id → users.id` (`CASCADE`) on `wallet_idempotency`, `wallet_transactions`, and `wallets`.
- **Unique constraints (7):** `booking_slots(lawyer_id,date,slot)`; `earnings(user_id)`; `favorites(user_id,lawyer_id)`; `reviews(user_id,lawyer_id)`; `users(auth_user_id)`; `users(uid)`; `wallets(user_id)`.
- **Check constraints (35), grouped by behavior:** date-shape checks on `availability`, `booking_slots`, and `bookings`; booking slot range, hours, status, and nonnegative total; case title/priority/status; non-empty message text and at least two chat participants; `earnings.user_id=id`; lawyer name/price/rating; notification title; plan title/price; review rating; subscription status; task title/priority/status; user name/role/`uid=id`; positive wallet-idempotency amount, nonnegative balance, credit/debit type; transaction amount/balance/type; and wallet nonnegative balance/`user_id=id`. The date regex validates only string shape, not a real calendar date. Live `wallet_transactions` caps a transaction at 100,000 while the Express wallet handler allows up to 1,000,000. Live tasks reject `Cancelled` even though the Express validator accepts it.
- **Index note:** three live indexes include the recently added FK indexes `idx_booking_slots_user_id`, `idx_lawyers_user_id`, and `idx_subscriptions_plan_id`; total public indexes: 70.

## 5. RLS, functions, triggers, and current privacy/authorization concerns

All 18 public tables have RLS enabled. Live table grants are broad, so the policies—not absence of table DML grants—are the row boundary. Relevant live policy patterns include public SELECT for `availability`, `lawyers`, `plans`, and `reviews`; owner/admin scopes for user-owned cases/tasks/bookings/messages/favorites/wallet data; admin-only direct booking/booking-slot writes; owner/lawyer/admin availability writes; participant-scoped chat/message access; and owner-created subscriptions restricted to `Pending` with owner cancellation-only updates plus admin management.

Specific issues to resolve and test before opening the tables to client traffic:

- Public raw `lawyers` and `reviews` SELECT is combined with table-wide SELECT grants, so `user_id` is selectable from those rows. Current live schema has no `public_reviews` redaction view and no confirmed column-level safeguard for those fields.
- `wallet_transactions` and `wallet_idempotency` owner/admin SELECT policies expose entire rows to the owner, including the wallet transaction idempotency hash and the stored idempotency transaction JSON. Review whether these columns belong in a client response.
- Chat participant membership is stored in an editable `text[]`; the live table/policies are not a normalized participant relation and this participant-array boundary has not had a hosted negative-test pass.
- Reviews currently have owner update/delete policy paths; compare this with the Admin-only moderation behavior in the source before client cutover.
- There are 11 current public functions. Exact live list: `current_app_user_id()`, `current_app_user_role()`, `guard_subscription_owner_update()`, `guard_user_identity_fields()`, `is_admin()`, `is_lawyer_or_admin()`, `link_migrated_auth_user()`, `rpc_recalculate_lawyer_rating(text)`, `rpc_reserve_booking_slots(...)`, `rpc_wallet_mutate(...)`, and `set_updated_at()`.
- The three current `rpc_*` operations (`rpc_recalculate_lawyer_rating`, `rpc_reserve_booking_slots`, `rpc_wallet_mutate`) are `SECURITY DEFINER` and executable by `service_role` only, not `anon` or `authenticated`. Authenticated execution is granted to the four role/identity helper functions `current_app_user_id`, `current_app_user_role`, `is_admin`, and `is_lawyer_or_admin`; `anon` cannot execute any of the 11 listed functions. Trigger/helper execution settings use `search_path=pg_catalog, public`.
- Current public triggers: `set_updated_at` triggers on availability, bookings, cases, chats, earnings, lawyers, notifications, plans, reviews, subscriptions, tasks, users, wallet_transactions, and wallets; plus `guard_subscription_owner_update_trigger` and `guard_user_identity_fields_trigger`.
- The current full function catalog resolves the earlier targeted RPC-query discrepancy: the live project has the three legacy service-role RPCs above, but **not** the caller-authenticated booking/chat/case/task/subscription/review/favorite/user-role/dashboard RPC set in the local candidate migration.

The live trigger for user identity fields and the subscription update guard are present. No Auth/JWT role, PostgREST column exposure, Storage API, RPC invocation, or concurrent booking/wallet call was tested against hosted credentials.

## 6. Express endpoint inventory and RPC equivalence

There are **64** resource handlers in `backend/src/routes/*.js`, plus `GET /api/health` and `GET /health`. The route prefix is `/api`:

| Resource | Existing Express methods | Main source behavior / authorization |
|---|---|---|
| `lawyers` | `GET /`, `GET /:id`, `POST /`, `PUT /:id`, `DELETE /:id` | Public catalogue/detail; admin mutation. |
| `users` | `GET /`, `POST /me`, `GET /:id`, `PUT /:id`, `PATCH /:id/role`, `DELETE /:id` | Admin list/role/delete; self profile; Supabase email-change/account-delete path intentionally guarded pending trusted Auth Admin lifecycle. |
| `cases` | `GET /`, `GET /:id`, `POST /`, `PUT /:id`, `DELETE /:id` | Authenticated owner/admin boundaries; no source-supported hearing/document/history relations. |
| `bookings` | `GET /`, `GET /:id`, `POST /`, `PUT /:id`, `DELETE /:id` | Owner/admin; create validates availability/rate and reserves slots atomically in the server adapter; client cancellation/admin status or reschedule. |
| `availability` | `GET /`, `GET /:id`, `POST /`, `PUT /:id`, `DELETE /:id` | Public reads; lawyer owner/admin mutation. |
| `tasks` | `GET /`, `GET /:id`, `POST /`, `PUT /:id`, `DELETE /:id` | Owner/admin. The validated full POST object is persisted, including an explicitly submitted initial status. |
| `chats` | `GET /`, `GET /:id`, `POST /`, `POST /:id/messages`, `DELETE /:id` | Participants/admin; sender identity is derived from verified auth. |
| `reviews` | `GET /`, `GET /:id`, `POST /`, `PUT /:id`, `DELETE /:id` | Public read; one review per user/lawyer; moderation is admin in Express. |
| `favorites` | `GET /:userId`, `POST /`, `DELETE /:id` | Owner/admin. |
| `plans` | `GET /`, `GET /:id`, `POST /`, `PUT /:id`, `DELETE /:id` | Public read; admin mutation. |
| `subscriptions` | `GET /`, `GET /:id`, `POST /`, `PUT /:id`, `DELETE /:id` | Owner/admin; new subscription is `Pending`; activation is not proof of payment. |
| `notifications` | `GET /:userId`, `GET /`, `POST /`, `PUT /:id/read`, `PUT /:id`, `DELETE /:id` | Owner reads/updates; admin broadcast/list/content management. |
| `earnings` | `GET /:userId` | Self/admin read. |
| `wallet` | `GET /:userId`, `POST /transactions` | Owner/admin reads; user debit/admin credit; idempotency and server-side wallet transaction. Credit remains untrusted without payment-provider verification. |
| `dashboard` | `GET /stats` | Admin reporting aggregate. |

### Live RPC names versus local candidates

The live catalog is not equivalent to the application route set. Current authenticated clients cannot invoke the three live `rpc_*` functions; they are service-role-only. The checked-out route adapter calls candidate RPC names such as `rpc_create_booking`, `rpc_chat_send_message`, `rpc_task_update`, and `rpc_admin_set_user_role`; a broad current-live catalog query confirms these are not currently deployed.

The two **unapplied** SQL candidates provide authenticated transactional operations for booking create/cancel/status/reschedule/delete; wallet mutation; chat create/send; case/task updates and case assignment; notification update; subscription create/cancel/delete; review submit/moderate/delete; favorite add; user role update; and admin dashboard stats. They also add scheduling/locking helpers and rating recalculation logic. Their local tests are not live verification. No Edge Functions are deployed; local-source `ai-assistant` and `document-upload` are not current remote RPC/endpoint equivalents.

## 7. `admin_panel` and `legal_app` source call-site usage

This table describes current repository call sites, not runtime analytics or verified production use.

| Feature | `legal_app` | `admin_panel` | Supabase end-to-end status |
|---|---|---|---|
| Auth/profile/roles | Optional Firebase or handwritten Supabase Auth gateway; Supabase profile read/update code exists. | Optional Firebase or Supabase Auth; Supabase mode reads a profile from PostgREST. Role comes from `public.users`. | Partial. Both Supabase sessions/tokens are memory-only; app reload does not restore a Supabase session. Admin `restore()` sees no current user in Supabase mode. Signup/profile confirmation and Admin user lifecycle need coordinated Auth work. |
| Lawyers/categories | Home, popular, search, detail, availability and favorite screens call the repository. Public direct PostgREST catalogue is guarded by default-off flag and requests `experience`, missing live. No normalized categories. | Lawyer list/create/edit/delete uses Express. | Partial/local candidate only; keep direct catalogue flag off until schema and hosted RLS are verified. |
| Cases/hearings/documents/history | Case list is API-backed; hearing UI is static. AI document review is a temporary PDF/Edge workflow, not a case-document archive. | Case list/create/edit/delete and client picker use Express; no lawyer assignment UI. | Core case record exists; hearing/document/history relations are missing, not “migrated” by the `cases` table. |
| Bookings/availability | Calendar reads availability/bookings and creates booking through Express; order history screens fetch/cancel bookings. | Booking list/delete through Express; no availability editor. | Tables exist. Authenticated RPC replacement is local-only; no hosted booking/RLS/concurrency verification. |
| Chat/notifications | Chat list/detail/send and notifications list/delete use Express. | Chat list/detail and notifications create/delete use Express. | Tables exist; normalized chat participants/realtime are missing; authenticated RPC candidates unapplied. |
| Plans/subscriptions | Plan/subscription screen calls repository routes; create/cancel is API-backed. | Plan CRUD and subscription list/status update use Express. | Tables exist; no billing provider/webhook and no payment-backed activation. |
| Wallet/transactions/earnings | Wallet, top-up, transaction history, and earnings screens call API routes. | No wallet/earnings screen found. | Tables/routes exist; no hosted wallet RPC, real payment verification, or financial-history lifecycle test. |
| Reviews/favorites/tasks | Review read/submit, favorite read/add/remove, and task CRUD call repository methods. | Review moderation/delete uses Express; no favorites/tasks UI. | Partial source paths; only catalogue/favorites have opt-in direct PostgREST slices; their live prerequisites are absent/unverified. |
| Admin reporting | No admin dashboard feature. | Dashboard calls `GET /api/dashboard/stats` through `ApiService`. | Still Express-backed; local `rpc_dashboard_stats()` is not live. |
| Uploads/AI | Calls local-source `document-upload` and `ai-assistant` functions when Supabase is configured; uses server-only trusted Storage upload code. | No corresponding screen. | Not usable against the current project: Storage bucket/policies are absent and no Edge Functions are deployed. |

Both app configs default `SUPABASE_ANON_KEY` to empty and retain Firebase/Express fallbacks; both API clients default to the Firebase Hosting backend URL. The Admin panel's Supabase profile read does not move Admin CRUD off Express. The legal app has no direct `cloud_firestore` calls in `lib/`, but Firebase Auth and its Express/Firebase backend remain active compatibility paths. Do not remove Firebase Auth, Firestore backend, or Express before replacements are deployed and verified.

## 8. Source-supported gaps and local migration candidates

The current schema is not a complete domain model for every screen. No normalized categories/specialties, hearings, case documents/history, or chat-participant relation is supported by the current source contract. Do not invent those foreign keys or declare static UI data migrated. Subscription activation remains blocked on a verified billing flow. Wallet credits remain privileged and need a payment-provider webhook; do not treat a client top-up action as proof of payment. Upload retention/deletion needs a product/legal policy.

The existing local candidates are intended to address only source-supported gaps and boundaries:

- `20261023100000_harden_rls_auth_and_storage.sql`: column/RLS and Auth-profile hardening, missing `lawyers.experience` and `bookings.idempotency_key_hash`, task status check expansion to include the API-supported `Cancelled`, review redaction view, and private `legal-documents` Storage policies/bucket contract.
- `20261023101500_authenticated_transactional_rpcs.sql`: server-checked authenticated transactional operations listed above, including atomic booking/wallet/chat flows and admin reporting/role operations; it also aligns the wallet transaction amount check with the Express ceiling of 1,000,000.

These are reviewable local candidates, **not applied migrations**. No new SQL migration was authored or applied in this inventory turn. Before deployment, reconcile them with the six missing live migration sources, current live definitions/policies/grants, API contracts, and backup/restore evidence. The candidate PGlite tests use a synthetic broad-grant initial snapshot and do not establish parity with these current live catalogs.

## 9. Firestore transfer status

- Repository search found no Firestore export/import/reconciliation implementation. `backend/src/seed.js` is a demo/test seed program, **not** a migration tool; it must not be run against production as a substitute.
- No Firestore export, Supabase import, document/row mapping run, ID reconciliation, Auth identity migration, or before/after count comparison was performed or verified.
- Preservation of IDs is represented in the adapter mapping/tests as a goal, not proof that any live records were transferred.
- **Transfer status: not started / unverified.** Do not describe this backend as Firestore-migrated.

## 10. Verification performed

- Read-only live Supabase health, Auth config, migration history, public schema/constraints/indexes, all public RLS policies, function execution ACLs, trigger catalog, table grants, Storage counts/grants, and Edge Function list were inspected. These are catalog checks, not application-level security tests.
- `backend` full suite: `npm test` — **505/505 passed, 124 suites, 0 failed** after correcting the stale Edge Function test mocks and rejecting empty sanitized user profile updates before writes.
- Targeted Supabase tests: `node --test test/supabase_migrations.test.js test/supabase_adapter.test.js` — **23/23 passed** (PGlite candidate-schema tests plus adapter tests; local only).
- Static checks: `node --check` over all `backend/src` and `backend/test` JavaScript files and the three shared Edge Function `.mjs` files — passed; `git diff --check` — passed.
- `npm ci` completed in `backend`; npm reported **10 dependency audit findings (7 moderate, 3 high)**. No dependency upgrades/audit remediation were attempted.
- Flutter/Dart, Deno, Supabase CLI, Docker and `psql` are unavailable in this environment. Flutter tests/analyzer, Deno checks, live PostgREST/Auth/Storage/RPC tests, and hosted PostgreSQL concurrency tests were not run.
- No remote migration or write occurred. The PGlite and mocked HTTP tests do not establish live-project parity or verification.

## 11. Worktree and changes recorded in this pass

- Current branch remains `arena/69f08c8e-legal` at HEAD `1e43a889f3a5e901599190f0a595806621b284ca`; no commit or push was made. The worktree has **72 modified tracked paths and 30 untracked files**, with nothing staged. It already contained broad local implementation work; no reset, clean, stash, or discard was used.
- Files touched in this inventory pass: `backend/src/routes/users.js` (reject an update whose profile fields were all stripped before issuing a no-op write); `backend/test/edge_functions.test.js` (mock the handler's current explicit `auth_user_id` then native-ID fallback lookup); `backend/test/supabase_migrations.test.js` (label the fixture/candidate suite as local, not current-live parity); `supabase/FIRESTORE_TO_SUPABASE_INVENTORY_2026-10-24.md` (this report); and current-state pointers/addenda in `supabase/MIGRATION_STATUS.md`, `supabase/README.md`, `supabase/MIGRATION_AUDIT.md`, and `supabase/FINAL_IMPLEMENTATION_REPORT.md`.
- No SQL migration was created, edited, or applied in this pass. The two local candidate migrations remain unapplied; the two baseline migration files are historical source for the already-reported live baseline. The complete current path list is available from `git status --short`; unrelated existing work was not staged or committed.

## 12. Remaining work before either app can use Supabase end-to-end

1. Obtain and verify a restorable backup, then reconcile the current eight live migration records with source-controlled SQL; do not use blind migration push.
2. Review and apply only the reconciled migrations through an approved change process; verify the live migration ledger and exact definitions afterward.
3. Complete Supabase Auth persistence/refresh/recovery and profile/role lifecycle in both Flutter apps; coordinate signup, email confirmation/change, identity linking, Admin bootstrap, role changes, deletion/retention, and Firebase identity coexistence. Do not cut over Auth alone.
4. Run hosted positive/negative JWT tests for every table and column, including public lawyer/review data, owner isolation, chat participant mutation, wallet/idempotency fields, subscription owner transitions, Storage path ownership, Edge Function authorization, and all RPC ACLs.
5. Keep `USE_SUPABASE_LAWYER_CATALOG` and `USE_SUPABASE_FAVORITES` disabled until the missing live columns/functions and privacy boundaries are deployed and hosted-tested. Wire all other domain routes away from Express one feature at a time only after route/RPC behavior matches.
6. Agree and implement normalized category, hearing, document/archive, case-history, and chat-participant models only if product/source contracts authorize them; migrate static UI data only after that contract exists.
7. Implement and verify provider-backed subscription activation and wallet credits; define document retention and cleanup guarantees; provide trusted Auth Admin email/delete/deactivation operations.
8. Add/test hosted admin reporting and client flows, realtime/chat delivery if required, pagination/filter semantics, and production-like PostgreSQL 17 booking/wallet concurrency.
9. Run Flutter tests/analyzers and Deno checks in an environment with those SDKs, then perform staged dual-read/reconciliation of Firestore IDs/fields and records. Only retire Express/Firebase after all callers, fallbacks, identity workflows, and rollback paths are verified.

**Bottom line:** the repository contains a broad Supabase adapter and two substantial local candidate migrations, and the backend/local SQL test suites pass. The live project is not at parity with those candidates; most app features still use the Express/Firebase API, hosted Storage/Edge Functions are absent, and Firestore transfer is unverified. The work is therefore an inventory plus local verification—not a completed migration or cutover.
