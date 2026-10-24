# Supabase migration implementation report

**Status date:** 2026-10-24 (Africa/Cairo)<br>
**Repository:** `Malak987/legal`<br>
**Working branch:** `arena/69f08c8e-legal`<br>
**Decision:** **NO-GO for production cutover or remote deployment**<br>
**Environment:** The connected Supabase project remains unclassified as development, staging, or production. This continuation made no remote SQL, Auth, Storage, secret, data, or function change.

> **Current-state addendum — 2026-10-24:** The read-only migration ledger confirms ten applied versions through `20261024123238_secure_rls_helper_functions_private_schema`; do not replay the latest migration. The duplicate case-index candidate is archived because the live composite index already exists. Identity/owner/lawyer-access SQL and rollback remain proposal-only under `supabase/proposals/`. Local source now includes a trusted lawyer-signup route gated off by default, owner-role authorization compatibility, assigned-lawyer case/booking read scopes, and a read-only lawyer panel; none is deployed. `cd backend && npm test` passes 513 tests across 123 suites, including 16 isolated PGlite proposal/rollback tests. Flutter and hosted E2E remain unverified. See [APP_INTEGRATION_AUDIT_2026-10-24.md](APP_INTEGRATION_AUDIT_2026-10-24.md) for current facts and limitations. The historical sections below may describe earlier candidate status and should not override this addendum.

This report describes local source work and verifiable test evidence. It does not claim an end-to-end hosted client request, staging validation, production deployment, payment completion, or verified cutover. The historical read-only baseline is retained in `MIGRATION_AUDIT.md`; the operation-by-operation status is in `MIGRATION_STATUS.md`.

## Executive summary

The local worktree includes the category/lawyer/case API and UI integration, Auth/profile changes, broader RLS/RPC candidates, and the authenticated `ai-assistant` Edge Function. The in-scope category, lawyer and case flows use the existing API backed by request-scoped Supabase access; the mobile case details and booking history now consume their existing endpoints. These source paths have not been deployed or verified with real hosted role accounts.

No migration or Edge Function was applied/deployed by this continuation. The live ledger already included category migration `20261024102004_legal_categories_and_assignments` before this work; the local-only composite case index remains pending. The connected project’s environment and production-row state have not been established. Do not run remote writes until project classification, a reliable backup/restoreability check, staging target, and explicit approval exist.

### Express operation inventory

Current source inventory: **70 resource route handlers** plus `GET /api/health` and `GET /health` aliases. The earlier 64-row matrix predates the category routes and omitted `GET /api/users/me`; see the current addendum in `MIGRATION_STATUS.md`.

| Local SQL/client status | Count | Meaning |
|---|---:|---|
| SQL candidate implemented, unapplied (`I`) | 31 | Local schema/RLS/RPC intent exists; no native client cutover or live verification. |
| SQL partial, unapplied (`P`) | 30 | Some route behavior is represented; parity/test/client work remains. |
| Mobile profile client slice (`C-I`) | 1 | `GET /api/users/:id` has a limited Supabase profile path; not an end-to-end application route. |
| Mobile profile client slice (`C-P`) | 1 | `PUT /api/users/:id` is limited to selected self-profile fields; email/admin parity remains. |
| Target only (`T`) | 1 | `DELETE /api/users/:id` still needs an approved, retention-safe Auth Admin design. |
| **Fully cut over** | **0** | No Express resource operation is verified end-to-end against Supabase. |

Both Flutter clients continue to use Express for general application data; all Admin resource screens remain Express-backed. The mobile app now has three additional **non-Express** AI workflows through Supabase, documented separately in the ledger. Health aliases are not database readiness checks.

## Local implementation in this branch

### PostgreSQL, RLS, Auth and Storage

- The preserved, unapplied candidate `supabase/archive/unapplied_candidates/20261023100000_harden_rls_auth_and_storage.sql` contains column/operation-specific grants, owner/admin policy work, Auth-linking changes, review redaction, and private PDF Storage policies. It remains archived and is not in CLI migration discovery.
- It validates an existing `legal-documents` bucket configuration instead of rewriting it. The intended bucket is private, PDF-only, limited to 10 MiB, and uses `<application-user-id>/documents/<opaque-name>.pdf` keys. Object access is owner/admin scoped.
- The preserved, unapplied candidate `supabase/archive/unapplied_candidates/20261023101500_authenticated_transactional_rpcs.sql` contains authenticated transactional RPC candidates. It remains archived and is not in CLI migration discovery.
- These migrations passed isolated PGlite scenarios, not a live PostgreSQL 17/Supabase test. They have **not** been applied remotely.
- Mobile Auth/profile work remains partial. Supabase Auth uses the public client key and user JWT; Firebase remains a fallback when Supabase client configuration is absent. Secure durable token/session restoration and a verified legacy-user import process are still incomplete. Admin resource screens still use Express.

### AI Edge Function, Storage and mobile screens

- `supabase/functions/ai-assistant/index.ts` is the Deno entrypoint; `supabase/config.toml` sets `verify_jwt = true`. The shared handler revalidates the user with Supabase Auth, requires a readable application profile, validates inputs, and uses the caller JWT for Storage. It does not use a service-role key.
- Server-side actions: `legal_chat`, `predict_case`, and `analyze_document`. The Gemini key is read only from server environment (`GEMINI_API_KEY`; optional `GEMINI_MODEL`) and never from a Flutter build define or request.
- Document analysis requires explicit consent, an owner-scoped private PDF object, a 10 MiB size limit and a PDF signature check. The server attempts cleanup in `finally`; the mobile app retries deletion if the function reports cleanup trouble or its call fails, and warns if cleanup cannot be confirmed. This is not yet evidence of a retention guarantee.
- `legal_app` chatbot, case-prediction, and document-review screens now call the authenticated Supabase Edge Function through `AppRepository`/`ApiClient`. Document review accepts PDFs only, removes the prior simulated progress, and asks for consent before uploading. Case-prediction output is labelled as an illustrative AI rating, not a calibrated probability. The chat and review UI display advisory notices.
- The client uses only the public anon/publishable key and the user JWT. The secret must be configured server-side only after an approved environment is identified. No AI request, Storage call, or deployed function has been verified against a real Supabase project or Gemini account.

### Tests and CI source

- `backend/test/edge_functions.test.js` exercises authentication, profile gating, consent, safe PDF paths/signatures, prompt bounds, provider errors, and temporary-object cleanup.
- `legal_app/test/supabase_ai_client_test.dart` checks Storage/Edge request shape, user-JWT headers, owner path restrictions, and error propagation. It has **not** been run because Flutter/Dart are unavailable in the runner.
- `.github/workflows/ci.yml` now includes a Deno type-check job for the Edge Function entrypoint. No CI run for this branch has completed yet.
- The complete operation/consumer/authorization/test/deployment ledger is in `MIGRATION_STATUS.md`.

## Test evidence

| Check | Result | Scope/limit |
|---|---|---|
| `cd backend && npm test` | **79 passed, 419 failed (498 tests; 122 suites)** | Full suite is not green. Many legacy route tests return 401 because `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY` are unavailable in this runner; unfiltered adapter tests also have failures. |
| `cd backend && node --test test/supabase_migrations.test.js` | **11 passed, 0 failed** | PGlite migration, authorization, data-preservation, and category/assignment checks; not a hosted PostgreSQL 17 deployment. |
| `cd backend && node --test --test-name-pattern='maps legal categories|verifies a Supabase JWT|preserves a legacy application UID|never links a legacy profile|serves users, lawyers' test/supabase_adapter.test.js` | **5 passed, 0 failed** | Current selected in-memory adapter/Auth/API tests, not live Supabase evidence. Covers category mapping, Auth profile resolution, case labels, and lawyer experience. |
| `cd backend && node --test test/edge_functions.test.js` | **12 passed, 0 failed (earlier run)** | Shared Edge Function handler/prompt behavior with mocked Supabase and Gemini dependencies; not Deno runtime or a provider call. Not rerun this continuation. |
| `node --check` for `backend/src/config/supabase.js`, `backend/src/routes/cases.js`, `backend/test/supabase_adapter.test.js` | **Passed** | Changed-file JavaScript syntax only. |
| Flutter/Dart analyze, tests, or build | **Not run** | Flutter and Dart are unavailable in this runner. This includes the changed admin/mobile screens and tests. |
| Deno `check` | **Not run locally** | Deno is unavailable; a CI type-check job has been added but has not run on this branch. |
| Supabase Auth/PostgREST/Storage/function/Gemini integration | **Not run** | No environment classification, backup/restore verification, or staging deployment; no live application operation was attempted. |
| Supabase SQL/config/function deployment | **Not performed** | No remote write or deployment occurred. |

The latest `npm audit --omit=dev` reported **10 findings (7 moderate, 3 high)**. No automatic dependency remediation was applied. Local Node/PGlite results do not constitute production security certification.

## Environment and deployment status

### Local implementation

Source and tests described above are present in the current branch. The existing API remains in the repository and continues to serve general client/Admin operations. No secrets or service-role credentials have been added to Flutter or committed.

### CI/test environment

Focused migration and category-adapter Node tests pass, but the current full Node suite fails (79 passed, 419 failed). A Deno type-check job is defined in source but awaits a GitHub Actions run. Flutter analyze/tests/build are unverified. No CI result should be inferred from an earlier remote-branch workflow run; it predates the current local edits.

### Staging

**Not established or deployed.** No staging project was identified, and no user asked to create a replacement project. Before staging, confirm ownership, environment, data/users, project region, migration history, Auth redirects, and recovery/export plan. Do not use the connected project based on name, age, emptiness, or assumptions.

### Production

**No migration, function, Storage, Auth setting, secret, or client release was changed by this continuation.** The project’s environment is unclassified, so this report does not call it production. Fresh read-only checks found an active/healthy project in `eu-west-1` with nine recorded migrations through `20261024102004_legal_categories_and_assignments`; no application/Auth rows were queried. The category migration was already in the live ledger. The backup/restoreability gate remains unmet, and the local-only composite case index was not applied.

## Security, RLS and data-safety verification

- The PGlite migration suite covers representative allowed/denied client, lawyer, and admin access, column privileges, private Storage paths, profile linking, atomic booking/wallet operations, idempotent retries, and other RPC authorization flows. It does not prove behavior on Supabase’s hosted Auth/PostgREST/Storage services or test every single Express handler contract.
- The Edge handler tests verify that anonymous/invalid user access is rejected before protected work; that the application profile and owner path are required; that explicit document consent is required; that non-owner paths are denied; and that a spoofed content type without a PDF signature is rejected. Tests use mocks.
- The Flutter client test source checks the public key plus caller JWT, generated owner path, and no client Gemini provider key. It is unrun locally.
- No service-role key is used in Flutter or by the AI function. The AI function’s Gemini key is server-side by design. No provider secret value is included in this report.
- Live RLS role tests, Auth lifecycle, profile provisioning, refresh/session persistence, Storage CRUD, cleanup/retention, Deno runtime behavior, and PostgreSQL concurrency tests remain outstanding. Do not claim RLS verified against the target project.
- User/account deletion can cascade into financial and legal records under the current schema. The required Auth Admin delete route is intentionally not implemented until a retention/soft-delete policy and recovery plan are approved; do not implement it as an unreviewed hard delete.
- Wallet credits and subscription activation still lack a payment provider, server-side transaction confirmation, and signed webhook. A UI success path is not payment evidence. No payment has been completed by this migration.

## Blockers and precise next steps

1. **Classify the connected Supabase project.** Confirm whether it is development, staging, or production; inspect existing data/users, migration history, Auth settings, Storage, deployed functions and secrets read-only. If it cannot be established, stop remote work and request a dedicated staging project.
2. **Establish an isolated staging environment and recovery plan.** Use a verified backup/export, preserve Auth identities and Storage files, rehearse migrations/cutover/rollback, and confirm that no data is overwritten or deleted.
3. **Run project-local tooling.** Use Supabase CLI/local Supabase + PostgreSQL 17, Deno, Flutter/Dart; validate migrations, real PostgREST/RLS/Auth/Storage, Deno function runtime, and the new Flutter tests. Test authorized and denied roles with disposable accounts and object data.
4. **Configure secrets on the approved server environment only.** Set `GEMINI_API_KEY` and an approved model only after review; never put the value in a Dart define, mobile asset, log, or Git. Add production-safe rate/usage limits before exposing AI to users.
5. **Review and deploy the AI/storage slice to staging.** Verify JWT checks, user/profile mapping, bucket settings, 10 MiB/PDF enforcement, consent, cleanup, error paths, provider terms/data residency, and real Gemini responses; inspect cleanup/retention rather than assuming it.
6. **Complete the wider route/client audit.** The current source has 70 resource handlers; categories/lawyers/cases and the bookings screens have local API/Supabase source paths, but the remaining resources still need an exact route/consumer/role review, deployment, and hosted verification. Add direct contract, role-denial, duplicate, failure, and concurrency tests. Add trusted Auth Admin email/deactivation operations only after data-retention approval.
7. **Resolve payments and data migration.** Select a provider and implement signed/idempotent webhook settlement before wallet credit or subscription activation. Plan verified legacy identity mapping, backups, row/financial reconciliation, and a rollback rehearsal.
8. **Run CI on the PR and address failures.** Verify backend, Firebase emulator, Deno check, Admin Flutter, and mobile Flutter jobs. The CI result must correspond to the final branch commit.
9. **Keep the old API live until cutover gates pass.** No merge to `main`, production cutover, backend retirement, or deployment is part of this report.

## Pull request status

No pull request is currently open from `arena/69f08c8e-legal`. Prepare one only after unrelated work is separated and branch CI is available. No merge to `main` is authorized.


## 2026-10-24 current continuation addendum — supersedes earlier category notes

### Live state and migration provenance

- The latest read-only refresh reconfirmed `qqfzbecwhewswkyxgebu` (`legal`), `ACTIVE_HEALTHY`, PostgreSQL 17.11.0.003, `eu-west-1`; nine migrations are recorded through `20261024102004_legal_categories_and_assignments`. This category migration was already applied before the continuation. It was not rerun, and this work performed no hosted SQL/Auth/Storage/secret/function change.
- Local `20261024102004_legal_categories_and_assignments.sql` was mechanically compared against the exact recorded live SQL and matched after ignoring comments/whitespace. Six recovered files are representations of versions already in the live ledger. The two 2026-10-23 unapplied candidates remain under `supabase/archive/unapplied_candidates/`, outside migration discovery.
- `20261024102730_cases_lawyer_category_covering_index.sql` remains a local-only, pending migration; no live equivalent composite index was found. The project has no database branches and no verified backup/restore test. Do not apply the index until the stated backup/restoreability gate is met.
- Only schema/catalog metadata was queried. No application/Auth row values or secrets were read, and no Firebase users/emails/passwords/Firestore data were migrated.

### Implementation completed in source

- Backend categories list/detail/admin CRUD and lawyer/case routes use the existing API. Lawyer `categoryId` and `experience` are accepted and serialized while legacy `specialty` is retained. Case create validates real client/category/lawyer records and their category match, retains submitted status and legacy case type, supports both-null legacy assignments, and rejects partial assignment. Edit/delete and owner/assignment validation remain authorization-scoped; FK races return conflict responses.
- Case list/detail API responses include related category/lawyer display names without changing stored case rows. Admin case list renders these names; Admin lawyer model and edit/create form now read/write `experience`. Category CRUD, lawyer category assignment, and case client/category/lawyer selectors use live API responses and expose loading, error/retry, empty, validation, and refresh states.
- Mobile category/lawyer browsing, search and detail continue through stable IDs and the existing session/repository/API patterns. My Cases now opens a real `GET /api/cases/:id` detail flow. Placeholder hearing dates, progress, documents/history/timeline panels, and the dead edit action were removed; no unsupported schema was added. Booking overview/active bookings now read `/api/bookings`; cancelling calls the existing authorized status endpoint. Completed/cancelled booking screens already used that endpoint.
- Court-case-number/FIR/party search files remain unconnected and are no longer reached from the My Cases path. The current schema/API has no case-number, FIR, court-complex or party-search fields, so these searches were not fabricated.
- Backend Auth lookup now resolves a profile by `auth_user_id` first and falls back only to a native UUID profile whose `uid=id` and mapping is not contradictory. Live schema metadata confirms the explicit unique Auth FK. The adapter maps `dueDate` and legacy `dueOn` to actual `cases.due_date`/`tasks.due_date` text columns; no data conversion was done.

### Verification performed in this continuation

| Check | Result | Limitation |
|---|---|---|
| `cd backend && node --test test/supabase_migrations.test.js` | **11 passed, 0 failed** | Isolated PGlite only; not hosted PostgreSQL/Supabase. |
| `cd backend && node --test --test-name-pattern='maps legal categories|verifies a Supabase JWT|preserves a legacy application UID|never links a legacy profile|serves users, lawyers' test/supabase_adapter.test.js` | **5 passed, 0 failed** | Selected in-memory adapter/Auth/API tests, not live RLS or hosted requests. Includes category/lawyer/case relation labels and lawyer experience. |
| `node --check` for changed backend adapter, case route and adapter test | **Passed** | JavaScript syntax only. |
| `git diff --check` | **Passed** | Whitespace/error-marker check on tracked changes; untracked files are outside this command's scope. |
| Flutter/Dart analyze, tests and build | **Not run** | Flutter/Dart are unavailable in this runner. |
| Full `npm test` | **Not rerun** | The earlier 498-test run was 79 passed/419 failed and predates current edits; comprehensive testing is a separate follow-up. |
| Hosted Supabase role/CRUD requests, migration apply, deployment | **Not performed** | No backup/restoreability gate or deployment approval; no hosted changes made. |

### Repository workflow

The branch remains `arena/69f08c8e-legal`. The final worktree was reviewed; `git diff --check` passed and the staged diff is empty. No commit, push or pull request was created because the worktree contains broad mixed changes and unrelated work must not be staged or bundled. No secrets, service-role keys, or production rows were read or added.
