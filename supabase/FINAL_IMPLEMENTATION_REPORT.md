# Final Supabase Implementation & Readiness Report

> **Historical snapshot (2026-10-23), superseded for current-state facts by [FIRESTORE_TO_SUPABASE_INVENTORY_2026-10-24.md](FIRESTORE_TO_SUPABASE_INVENTORY_2026-10-24.md).** The current read-only live catalog, migration history, grant/function findings, full backend test results, Firestore transfer status, and deployment gate are recorded in that newer inventory. Do not treat this dated report's earlier catalog counts, migration list, or test counts as current.

**Evidence date:** 2026-10-23 (Africa/Cairo)<br>
**Live Supabase catalog inspection:** 2026-10-23 15:36:49–15:52:43.751402 UTC (read-only)<br>
**Repository:** `Malak987/legal`<br>
**Branch:** `arena/69f08c8e-legal` (Arena status: active)<br>
**Observed local HEAD / common base:** `1e43a889f3a5e901599190f0a595806621b284ca`<br>
**Live remote branch tip:** `3f463edf068536d4411225535418391c89e97ac1`<br>
**Review status:** **BLOCKED** — ancestry is known, but the dirty worktree has not been reconciled with the four-commit remote tip (16 divergent remote-touched paths and 17 local-only paths).<br>
**Deployment decision:** **NO-GO** for production migration, deployment, or traffic cutover.

> This is still a dirty, uncommitted worktree. A separate bare clone confirmed the common base and remote ancestry without changing this checkout; no reconciliation, commit, push, PR, rebase, merge, reset, or discard was performed. Supabase metadata/catalog calls and SQL were read-only; no live migration, DDL/DML, data edit, Auth/Storage setting change, secret change, or function deployment occurred. No application-row contents were selected. The local PGlite/Node tests do not prove hosted Supabase behavior.

## 1. Executive summary

- The checkout is shallow at `1e43a889f3a5e901599190f0a595806621b284ca`. A separate read-only bare clone and a fresh `git ls-remote` established that this exact commit is the common base and remote `arena/69f08c8e-legal` is four commits ahead (`3f463edf068536d4411225535418391c89e97ac1`); `main` remains at the base. This corrects the earlier API comparison response that showed `merge_base=null`. The branch is still **not reconciled** because overlapping local/remote contents diverge and local-only work must be preserved.
- The four remote commits are `ea56d0caa8c63b7b1e6ae30d49e636c9be77c003`, `88f139e70700d573549d6a37ce3ef38635f8145f`, `a1507b05d00f0dd1dc90832fe79ac78a498a6193`, and `3f463edf068536d4411225535418391c89e97ac1`. They are not in this checkout's `HEAD`; no PR exists.
- The source tree contains four Supabase migration files. Remote history confirms only the first two baseline migrations; the local RLS-hardening and authenticated-RPC migrations are unapplied.
- The read-only remote audit reconfirmed 18 public tables, 153 columns, 83 constraints, 67 indexes, 54 public RLS policies, and broad effective grants: `anon`, `authenticated`, and `service_role` each have all seven table privileges (SELECT/INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER) on every public table. RLS is enabled but not forced. Raw `reviews.user_id`, `lawyers.user_id`, and protected `users` fields are publicly readable/updatable under these grants. Six `SECURITY DEFINER` helpers/trigger functions are executable by PUBLIC, anon, authenticated, and service_role; three business RPCs remain service_role-only. Storage has no bucket or policies and zero objects; eight Storage relations have RLS enabled, none forced. The new inspection also confirmed three unindexed FKs and eight baseline SELECT policy overlaps.
- The two local, unapplied candidate migrations close major authorization gaps, but they do **not** resolve every new performance/compatibility finding: they add no indexes for the three unindexed FKs, retain the `plans` ALL-policy/SELECT-policy overlap, and leave repeated auth-helper calls in `users` RLS predicates. The private `legal-documents` bucket design is grounded in the existing consent-gated flow, but its PDF MIME restriction trusts the declared content type; actual `%PDF-` signature validation happens only when the Edge Function analyzes an object. Nothing was deployed.
- The owner-reported Security/Performance Advisor findings (three unindexed FKs, repeated auth-related RLS evaluation on `users`, and multiple permissive policies) are not independently retrievable through the available connector tools; catalog inspection directly confirmed the FK gaps and policy overlaps, and the local policy source shows the repeated helper evaluations. Treat Advisor wording/severity as user-supplied, not as a newly fetched Advisor export.
- The repository has **64 Express resource handlers** plus two health aliases. By client/runtime cutover status, **0 are fully migrated and remotely verified, 8 are partial local client paths, and 56 remain legacy-dependent**. SQL source for an operation is not equivalent to a client cutover; both rollout flags remain disabled.
- Fresh local verification passed: after restoring the absent `node_modules` with `npm ci`, `npm test` passed (**501 tests, 124 suites**) and the PGlite migration/RLS suite passed (**10/10**, including the verified remote-baseline mirror). `npm ci` reported 9 audit findings (7 moderate, 2 high); no dependency fix was applied. Flutter/Dart, Deno, Supabase CLI, Docker, and `psql` remain unavailable, so no hosted-equivalent PostgreSQL 17/Auth/PostgREST/Storage E2E test ran. The latest GitHub CI is green only on remote SHA `3f463edf...`, not this dirty worktree.
- **No Supabase changes are deployed remotely.** Project `qqfzbecwhewswkyxgebu` is `ACTIVE_HEALTHY` in `eu-west-1`, PostgreSQL 17.11.0.003; no environment classification is exposed, and no write authorization was given. Review status is **BLOCKED**; production readiness is **NO-GO**.

## 2. Git, PR, and CI evidence

### Git state

| Item | Observed value |
|---|---|
| Current branch | `arena/69f08c8e-legal` |
| Local HEAD | `1e43a889f3a5e901599190f0a595806621b284ca` (`Merge pull request #13 ...`) |
| Repository depth | Shallow; `.git/shallow` contains the local HEAD only, and `git log --oneline --decorate -12` shows that one commit |
| Live remote feature tip | `3f463edf068536d4411225535418391c89e97ac1` (`git ls-remote origin`; also GitHub API) |
| Ancestry comparison | Fresh `git ls-remote` shows `main=1e43a889...` and `arena/69f08c8e-legal=3f463edf...`. A separate bare clone gives `git merge-base 1e43... 3f463... = 1e43...` and `git rev-list --left-right --count = 0 4`. This corrects the earlier GitHub compare API `merge_base=null` response; the common base is now verified, but the dirty tree is still not reconciled. |
| Staging | 0 staged paths (`git diff --cached --stat` empty) |
| Unstaged tracked changes | 58 paths; `git diff --stat`: 9,276 insertions, 5,515 deletions (untracked files are not included in this statistic) |
| Untracked files | 25 files; `git status --short` collapses the untracked `supabase/` directory, while `git ls-files --others --exclude-standard` enumerates all 25 |
| New local implementation commits | None visible on the current local branch; the implementation remains in the worktree |
| Push / PR | No push. `gh pr list --state all --head arena/69f08c8e-legal` returned `[]`; no PR exists |

The four remote commits are:

1. `ea56d0caa8c63b7b1e6ae30d49e636c9be77c003`
2. `88f139e70700d573549d6a37ce3ef38635f8145f`
3. `a1507b05d00f0dd1dc90832fe79ac78a498a6193`
4. `3f463edf068536d4411225535418391c89e97ac1`

They are present on the **live remote feature branch**, but not in this checkout’s `HEAD`. `git ls-remote` reverified the tip during this pass. A separate bare clone (outside the repository) established the exact common base; the prior compare API `merge_base=null` is not relied on. Read-only tree comparison: the four remote commits touch 50 paths; 34 have identical current-worktree content and 16 differ. Among the 83 backed-up changed/untracked local paths, 34 match remote-tip content, 32 differ, and 17 are absent from the remote tip. The divergences remain unresolved; I did not reconcile because doing so in this dirty checkout could overwrite or misattribute preserved work. No reset, clean, stash, checkout, merge, rebase, or commit was performed.

**Remote-touched paths whose local content differs (16):**

```text
.github/workflows/ci.yml
backend/package-lock.json
backend/package.json
backend/src/config/supabase.js
backend/test/supabase_adapter.test.js
legal_app/lib/config/supabase_config.dart
legal_app/lib/main.dart
legal_app/lib/services/app_repository.dart
legal_app/lib/services/auth_service.dart
legal_app/lib/views/home/details.dart
legal_app/lib/views/home/homescreen.dart
legal_app/lib/views/popularlawyers/popularlawyers.dart
legal_app/lib/views/search/search_screen.dart
legal_app/test/auth_lifecycle_test.dart
supabase/README.md
supabase/migrations/20261022174110_initial_legal_schema_and_rls.sql
```

**Backed-up local-only paths absent from the remote tip (17):**

```text
backend/test/edge_functions.test.js
backend/test/supabase_migrations.test.js
legal_app/lib/models/paginated_result.dart
legal_app/test/lawyer_catalogue_screen_test.dart
legal_app/test/supabase_ai_client_test.dart
legal_app/test/supabase_favorites_test.dart
legal_app/test/supabase_lawyer_catalog_test.dart
supabase/FINAL_IMPLEMENTATION_REPORT.md
supabase/IMPLEMENTATION_REPORT.md
supabase/MIGRATION_AUDIT.md
supabase/MIGRATION_STATUS.md
supabase/config.toml
supabase/functions/_shared/ai_assistant_handler.mjs
supabase/functions/_shared/ai_assistant_logic.mjs
supabase/functions/ai-assistant/index.ts
supabase/migrations/20261023100000_harden_rls_auth_and_storage.sql
supabase/migrations/20261023101500_authenticated_transactional_rpcs.sql
```

### Current worktree paths

**58 modified tracked files, all unstaged:**

```text
.github/workflows/ci.yml
README.md
admin_panel/lib/config/app_config.dart
admin_panel/lib/main.dart
admin_panel/lib/screens/users_screen.dart
admin_panel/lib/services/auth_service.dart
admin_panel/test/app_config_test.dart
admin_panel/test/auth_provider_test.dart
backend/.env.example
backend/functions-config/.env.example
backend/package-lock.json
backend/package.json
backend/src/config/env.js
backend/src/config/firebase.js
backend/src/routes/tasks.js
backend/src/seed.js
backend/src/utils/validators.js
backend/test/cases.test.js
backend/test/ownership.test.js
legal_app/lib/commonwidgets/product_card.dart
legal_app/lib/config/ai_config.dart
legal_app/lib/main.dart
legal_app/lib/models/app_profile.dart
legal_app/lib/models/product_model.dart
legal_app/lib/services/api_client.dart
legal_app/lib/services/app_repository.dart
legal_app/lib/services/auth_service.dart
legal_app/lib/state/session_controller.dart
legal_app/lib/views/aicasepredictiontool/aicaseprditionaitool.dart
legal_app/lib/views/aidocumentsreview/aireview.dart
legal_app/lib/views/booking/booking.dart
legal_app/lib/views/chatbot/chatbot.dart
legal_app/lib/views/earnings/earningdetails.dart
legal_app/lib/views/earnings/earnings.dart
legal_app/lib/views/favorites/favorite_screen.dart
legal_app/lib/views/home/details.dart
legal_app/lib/views/home/homescreen.dart
legal_app/lib/views/messages/chat_screen.dart
legal_app/lib/views/messages/chatdetailsscreen.dart
legal_app/lib/views/order/OrdersHistory/cancelled_orders.dart
legal_app/lib/views/order/OrdersHistory/completed_orders.dart
legal_app/lib/views/popularlawyers/popularlawyers.dart
legal_app/lib/views/profile/ManageAddress/address_book_screeen.dart
legal_app/lib/views/profile/past_orders.dart
legal_app/lib/views/reviews/reviews.dart
legal_app/lib/views/reviews/writereview.dart
legal_app/lib/views/search/search_screen.dart
legal_app/lib/views/settings/views/notifications.dart
legal_app/lib/views/subscription/subscription.dart
legal_app/lib/views/tasks/tasks.dart
legal_app/lib/views/transactions/transactions.dart
legal_app/lib/views/wallet/toppup.dart
legal_app/lib/views/wallet/wallet_screen.dart
legal_app/lib/views/wallet/walletscreen.dart
legal_app/lib/widgets/h.dart
legal_app/test/api_client_test.dart
legal_app/test/auth_lifecycle_test.dart
legal_app/test/support/fakes.dart
```

**25 untracked files:**

```text
backend/src/config/supabase.js
backend/test/edge_functions.test.js
backend/test/supabase_adapter.test.js
backend/test/supabase_migrations.test.js
legal_app/lib/config/supabase_config.dart
legal_app/lib/models/paginated_result.dart
legal_app/lib/views/wallet/transactions.dart
legal_app/test/connected_screens_test.dart
legal_app/test/lawyer_catalogue_screen_test.dart
legal_app/test/supabase_ai_client_test.dart
legal_app/test/supabase_favorites_test.dart
legal_app/test/supabase_lawyer_catalog_test.dart
supabase/FINAL_IMPLEMENTATION_REPORT.md
supabase/IMPLEMENTATION_REPORT.md
supabase/MIGRATION_AUDIT.md
supabase/MIGRATION_STATUS.md
supabase/README.md
supabase/config.toml
supabase/functions/_shared/ai_assistant_handler.mjs
supabase/functions/_shared/ai_assistant_logic.mjs
supabase/functions/ai-assistant/index.ts
supabase/migrations/20261022174110_initial_legal_schema_and_rls.sql
supabase/migrations/20261022174313_transactional_rpc_functions.sql
supabase/migrations/20261023100000_harden_rls_auth_and_storage.sql
supabase/migrations/20261023101500_authenticated_transactional_rpcs.sql
```

The current status is **not committed or pushed**. This report is itself an untracked file. The current checkout has no remote-tracking ref for the feature branch; its tip was queried without updating local refs.

### GitHub CI

Latest run for the remote feature branch: [CI run 39833573065](https://github.com/Malak987/legal/actions/runs/39833573065), **success**, push event, SHA `3f463edf068536d4411225535418391c89e97ac1` (2026-10-22). The backend + Firebase Emulator job, Admin Flutter analyze/test/web build job, and mobile Flutter analyze/test job all passed. Job links: [backend](https://github.com/Malak987/legal/actions/runs/39833573065/job/120015888847), [Admin](https://github.com/Malak987/legal/actions/runs/39833573065/job/120015888748), [mobile](https://github.com/Malak987/legal/actions/runs/39833573065/job/120015888379). Earlier runs on the three preceding commits failed; the run on `3f463edf...` is the later green run.

This CI run does **not** test the current dirty worktree. In particular, the local modified `.github/workflows/ci.yml` includes a Supabase Edge/Deno job not present in the recorded successful run. No current-worktree commit or PR exists for CI to test.

## 3. Supabase source and remote deployment state

### Local migration inventory

| Migration | Local source purpose | Remote history |
|---|---|---|
| `20261022174110_initial_legal_schema_and_rls.sql` | Baseline tables, constraints, indexes, RLS and policies | Listed remotely as applied |
| `20261022174313_transactional_rpc_functions.sql` | Baseline RPC functions | Listed remotely as applied |
| `20261023100000_harden_rls_auth_and_storage.sql` | Least-privilege grants, hardened RLS/identity, review redaction, compatibility columns/status values, validated private PDF bucket and owner-scoped Storage policies | **Not listed; unapplied** |
| `20261023101500_authenticated_transactional_rpcs.sql` | Authenticated transactional business/admin RPCs; authenticated wallet self-debit only; removes client subscription activation; least-privilege function EXECUTE grants | **Not listed; unapplied** |

The hardening migration adds compatibility status labels without rewriting booking/task rows; adds `lawyers.experience` and `bookings.idempotency_key`; prevents email-only legacy account linking; provisions profiles only after email confirmation; pins reviewed function search paths; makes `set_updated_at` invoker-rights; narrows direct table/column grants; closes chat membership, notification-content, and availability owner gaps; and exposes public reviews through a security-invoker view without reviewer IDs. The existing consent-gated PDF upload/delete and AI review flow demonstrates the Storage requirement; the migration would create/validate a private `legal-documents` bucket (10 MiB, `application/pdf` allowed-MIME metadata) plus owner-path policies, with no client update/upsert or direct bucket-table grants. This does **not** validate file bytes at upload: the client checks only non-empty/size and declares `application/pdf`; the Edge Function checks the `%PDF-` signature when analysis is requested. The RPC migration keeps booking/wallet mutations transactional, allows authenticated wallet self-debits but no credits, makes case-owner checks NULL-safe, limits notification owners to changing `read`, removes authenticated paid-subscription activation, and prevents deletion of Active subscriptions. These are **local source changes only**, not remote deployment evidence.

### Current remote project — read-only observations (reverified 2026-10-23 15:36:49–15:52:43.751402 UTC)

Project `legal`, ref `qqfzbecwhewswkyxgebu`, region `eu-west-1`, PostgreSQL `17.11.0.003`; project and Auth/DB/REST/Storage services report `ACTIVE_HEALTHY`. The health response also reports Realtime `ACTIVE_HEALTHY` while `db_connected=false` and `replication_connected=false`; record that as a separate Realtime operational caveat. The project metadata exposes no environment classification. It remains **unclassified and unauthorized for migration or deployment**.

- **Applied migrations:** only `20261022174110 initial_legal_schema_and_rls` and `20261022174313 transactional_rpc_functions`. No later migration was applied.
- **Catalog:** 18 public base tables, 153 columns, 83 constraints, 67 indexes and 54 public policies. RLS is enabled on all 18 tables; `FORCE ROW LEVEL SECURITY` is enabled on none. `anon`/`authenticated` have `rolbypassrls=false`; `service_role` has `rolbypassrls=true` and is not a superuser. The remote `lawyers` table lacks `experience`; `bookings` lacks `idempotency_key`; `public.public_reviews` does not exist.
- **Public table grants:** direct `has_table_privilege` checks show all seven privileges—`SELECT`, `INSERT`, `UPDATE`, `DELETE`, `REFERENCES`, `TRIGGER`, and `TRUNCATE`—true for `anon`, `authenticated`, and `service_role` on **each of all 18 public tables**. Separate column checks confirm anon/authenticated can select `reviews.user_id` and `lawyers.user_id`; anon/authenticated can select `users.email`; and authenticated can update `users.role`, `email`, `uid`, and `auth_user_id`. RLS does not restrict `TRUNCATE`; this is a high-priority authorization defect. No destructive request was attempted.
- **Policies:** all 54 rows from `pg_policies` were enumerated and reviewed. The table-by-table inventory and the local disposition follow. The raw reviews table contains `user_id`; the redacted view is absent. RLS does not remove broad grants or constrain `TRUNCATE`.

| Table | Remote policies (`policy (command)`) | Review / local disposition |
|---|---|---|
| `availability` | `availability_select_public (SELECT)`; `availability_write_lawyer_or_admin (ALL)` | **Gap:** write policy checks the caller's `lawyer` role, not ownership of `lawyers.user_id`. Candidate replaces it with owner-bound insert/update/delete policies. |
| `booking_slots` | `booking_slots_select_owner_or_admin (SELECT)`; `booking_slots_write_admin_only (ALL)` | Owner/admin reads; table writes should stay within atomic booking RPCs. Candidate removes direct writes. |
| `bookings` | `bookings_select_owner_or_admin (SELECT)`; `bookings_write_admin_only (ALL)` | Owner/admin reads; admin-only direct write policy does not encode scheduling/price invariants. Candidate routes mutations through checked RPCs. |
| `cases` | `cases_delete_owner_or_admin (DELETE)`; `cases_insert_owner_or_admin (INSERT)`; `cases_select_owner_or_admin (SELECT)`; `cases_update_owner_or_admin (UPDATE)` | Owner row scope is present. Candidate narrows writable columns and makes RPC owner checks NULL-safe; admin owner assignment is validated. |
| `chat_messages` | `chat_messages_delete_admin_only (DELETE)`; `chat_messages_insert_participant_or_admin (INSERT)`; `chat_messages_select_participant_or_admin (SELECT)` | Participant reads/inserts are scoped, but direct inserts can forge display fields and separate chat-summary writes are non-atomic. Candidate uses send/create RPCs and removes direct writes. |
| `chats` | `chats_delete_admin_only (DELETE)`; `chats_insert_participant_or_admin (INSERT)`; `chats_select_participant_or_admin (SELECT)`; `chats_update_participant_or_admin (UPDATE)` | **Gap:** any participant can rewrite `participants`/membership metadata. Candidate removes direct insert/update and uses checked RPCs; participant/admin deletion remains scoped. |
| `earnings` | `earnings_select_lawyer_owner_or_admin (SELECT)`; `earnings_write_admin_only (ALL)` | The read predicate excludes a client who owns an earnings row, unlike the Express self/admin route. Candidate uses owner-or-admin reads and no client writes. |
| `favorites` | `favorites_delete_owner_or_admin (DELETE)`; `favorites_insert_owner_or_admin (INSERT)`; `favorites_select_owner_or_admin (SELECT)` | Owner/admin scope and unique-pair intent are sound; candidate keeps the row boundary with minimal grants and idempotent add RPC. |
| `lawyers` | `lawyers_delete_admin_only (DELETE)`; `lawyers_insert_admin_only (INSERT)`; `lawyers_select_public (SELECT)`; `lawyers_update_admin_only (UPDATE)` | Public RLS is intentional, but broad SELECT grants expose `user_id`. Candidate grants public-safe columns only. |
| `notifications` | `notifications_delete_owner_or_admin (DELETE)`; `notifications_insert_admin_only (INSERT)`; `notifications_select_owner_or_admin (SELECT)`; `notifications_update_owner_or_admin (UPDATE)` | Owner scope blocks recipient reassignment, but broad column grants allow content/type edits. Candidate limits owners to `read`; admin edits use the checked RPC. |
| `plans` | `plans_select_public (SELECT)`; `plans_write_admin_only (ALL)` | Public read/admin write boundary is retained with limited client columns and RLS. |
| `reviews` | `reviews_delete_owner_or_admin (DELETE)`; `reviews_insert_owner_or_admin (INSERT)`; `reviews_select_public (SELECT)`; `reviews_update_owner_or_admin (UPDATE)` | **Gaps:** `user_id` is publicly readable and authors can edit/delete despite Express admin-only moderation. Candidate exposes a safe security-invoker view and removes direct write policies/grants. |
| `subscriptions` | `subscriptions_delete_admin_only (DELETE)`; `subscriptions_insert_owner_pending_or_admin (INSERT)`; `subscriptions_select_owner_or_admin (SELECT)`; `subscriptions_update_owner_cancel_or_admin (UPDATE)` | **Gap:** owner may change plan/term data while setting final status to `Cancelled`; admin may directly delete Active rows. Candidate uses checked RPCs, removes direct writes, and rejects Active deletion for every role. |
| `tasks` | `tasks_delete_owner_or_admin (DELETE)`; `tasks_insert_owner_or_admin (INSERT)`; `tasks_select_owner_or_admin (SELECT)`; `tasks_update_owner_or_admin (UPDATE)` | Owner scope is present but direct writes do not enforce state transitions/column limits. Candidate narrows columns and uses the status RPC. |
| `users` | `users_delete_admin_only (DELETE)`; `users_insert_self_client_or_admin (INSERT)`; `users_select_self_or_admin (SELECT)`; `users_update_self_or_admin (UPDATE)` | **Gap:** broad UPDATE grants permit changing `uid`/`auth_user_id`; the policy checks role/email but not Auth mapping. Candidate removes client direct INSERT and grants self-update only for `name`, `phone`, `avatar`, `address`; role/email/UID/Auth linkage are server-managed. |
| `wallet_idempotency` | `wallet_idempotency_select_owner_or_admin (SELECT)`; `wallet_idempotency_write_admin_only (ALL)` | Direct writes could bypass idempotency invariants. Candidate removes client access and keeps ledger/idempotency mutation inside the wallet RPC. |
| `wallet_transactions` | `wallet_tx_select_owner_or_admin (SELECT)`; `wallet_tx_write_admin_only (ALL)` | Direct writes could forge ledger entries. Candidate grants owner/admin read only; writes are transactional. |
| `wallets` | `wallets_select_owner_or_admin (SELECT)`; `wallets_write_admin_only (ALL)` | Direct balance writes could bypass debit/credit checks. Candidate grants owner/admin read only; balance changes use the constrained RPC. |

### Security/Performance Advisor reconciliation

The connector exposes project health, catalog SQL, migration history, Auth config, functions, and secrets, but not the hosted Security/Performance Advisor finding list. The three FK findings and policy overlap can be independently cross-checked in `pg_catalog`; the Advisor wording/severity remains owner-supplied evidence.

- The live catalog has exactly three FK columns without a valid, non-partial leading B-tree index: `booking_slots.user_id` (`booking_slots_user_id_fkey`), `lawyers.user_id` (`lawyers_user_id_fkey`), and `subscriptions.plan_id` (`subscriptions_plan_id_fkey`). Neither candidate migration adds these indexes. They are performance—not row-authorization—gaps, but should be addressed after table-size/lock planning; do not build production indexes during this review.
- There are eight current `authenticated` SELECT overlaps caused by an `ALL` policy plus a SELECT policy: `availability`, `booking_slots`, `bookings`, `earnings`, `plans`, `wallet_idempotency`, `wallet_transactions`, and `wallets`. The hardening migration drops/splits seven of those `ALL` policies; `plans_write_admin_only (ALL)` remains alongside `plans_select_public (SELECT)`, so one overlap remains. Split the plan admin policy into INSERT/UPDATE/DELETE before claiming all Advisor warnings are resolved.
- Current `users_select_self_or_admin` and `users_update_self_or_admin` invoke `current_app_user_id()`/`is_admin()` and `auth.uid()` in row predicates; the hardening migration recreates UPDATE but does not wrap stable helper calls in initplan-style scalar subqueries, and it leaves SELECT policy unchanged. The repeated-auth RLS performance finding may therefore remain; recheck the plan and Advisor after any policy optimization.

The candidate hardening migration leaves RLS enabled (and does not claim `FORCE RLS` protects `service_role`, which has `BYPASSRLS`). It replaces the 54 baseline public-table policies with 38 reviewed policies; the PGlite test asserts every policy name/command, each table's count, and relevant allow/deny boundaries. The safe public-review view intentionally retains `user_name` as the existing display field while withholding `user_id`; if product policy requires anonymous reviews, remove that display field too before rollout. Table/column/function grants are reduced because RLS alone cannot constrain `TRUNCATE`, `REFERENCES`, or `TRIGGER` privileges.
- **Remote public functions/triggers:** the live catalog returned nine public functions, all owned by `postgres`, all `SECURITY DEFINER`, all with `search_path=public`. The six `current_app_user_id`, `current_app_user_role`, `is_admin`, `is_lawyer_or_admin`, `link_migrated_auth_user`, and `set_updated_at` have explicit/default ACL entries making EXECUTE available to `PUBLIC`, `anon`, `authenticated`, and `service_role`. The three baseline business RPCs (`rpc_recalculate_lawyer_rating(text)`, `rpc_reserve_booking_slots(...)`, and `rpc_wallet_mutate(...)`) are executable by `postgres` and `service_role`, not anon/authenticated. The complete definitions/ACLs were read from `pg_proc`; no DDL was run. Fourteen public `trg_*_updated_at` triggers invoke the SECURITY DEFINER `set_updated_at()`; `trg_auth_users_link_migrated` is the only Auth trigger, is `AFTER INSERT`, and calls the email-only linker. There is no review-rating trigger. The local candidate pins paths, makes `set_updated_at` invoker-rights, grants RLS helper execution only to authenticated sessions that need those checks, revokes direct execution of trigger-only helpers, and updates the Auth trigger to run on confirmation as well as insert.
- **Auth/profile linking:** remote `current_app_user_id()` falls back to `auth.uid()::text` when no application profile is linked. `auth.users` has an `AFTER INSERT` trigger `trg_auth_users_link_migrated` calling `link_migrated_auth_user()`, which links an unlinked `public.users` row by case-insensitive email. The observed function does not require confirmed email or explicit verified legacy mapping.
- **Auth configuration:** Site URL `http://localhost:3000`; redirect URI allow-list empty; signup enabled; email authentication enabled with `mailer_autoconfirm=false`; phone authentication disabled; JWT lifetime 3,600 seconds; refresh-token rotation enabled with 10-second reuse interval. These settings are not approved production redirect configuration.
- **Storage:** no buckets, no `pg_policies` rows in schema `storage`, and `storage.objects` count is zero (count only; no object contents or paths read). RLS is enabled on eight `storage` relations and forced on none. `anon` and `authenticated` have SELECT/INSERT/UPDATE/DELETE on `storage.objects`, `storage.buckets`, and `storage.buckets_analytics`; they have SELECT only on `buckets_vectors`, `s3_multipart_uploads`, `s3_multipart_uploads_parts`, and `vector_indexes`, and no table privileges on `storage.migrations`. `service_role` has all seven table privileges on `objects`, `buckets`, `buckets_analytics`, and both multipart tables; SELECT only on `buckets_vectors`/`vector_indexes`; none on `migrations`. RLS currently denies ordinary API-role row access where no policy exists, but broad grants remain and Storage API behavior was not exercised. `storage` schema USAGE is true and CREATE false for anon/authenticated/service_role. The candidate creates/validates a private `legal-documents` bucket and owner-path SELECT/INSERT/DELETE policies; none is deployed. The candidate does not modify internal `buckets_analytics`/multipart/vector relations; review their internal grants with Storage compatibility tests before any broader revoke.
- **Edge Functions/secrets:** the deployed function list is empty; the project secret list is empty. No secret values were requested. The local `supabase/config.toml` sets `verify_jwt=true`, but that file is not evidence of remote deployment. No `GEMINI_API_KEY` is configured in the project secret inventory.

All remote inspection was read-only: project/migration/config/function/secret list calls and SQL catalog/`SELECT` queries. **No remote migrations, schema changes, data changes, Storage/Auth setting changes, function deployments, or secret updates occurred.**

## 4. Express operation inventory and cutover counts

The route count is from `rg -n -o "router\\.(get|post|put|patch|delete)\\s*\\(" backend/src/routes/*.js`: **64 resource handlers**. `/api/health` and `/health` are two additional aliases outside the count. “Partial” below means a conditional local Supabase client path exists, but a legacy fallback/other legacy consumer remains and hosted verification is absent. “Legacy-dependent” means the active clients still depend on Express for that operation; local SQL/RPC source alone does not change this status.

| # | Express resource operation | Current client/runtime disposition |
|---:|---|---|
| 1 | `GET /api/availability?lawyerId=` | Legacy-dependent |
| 2 | `GET /api/availability/:id` | Legacy-dependent |
| 3 | `POST /api/availability` | Legacy-dependent |
| 4 | `PUT /api/availability/:id` | Legacy-dependent |
| 5 | `DELETE /api/availability/:id` | Legacy-dependent |
| 6 | `GET /api/bookings?userId=&status=&lawyerId=` | Legacy-dependent |
| 7 | `GET /api/bookings/:id` | Legacy-dependent |
| 8 | `POST /api/bookings` | Legacy-dependent |
| 9 | `PUT /api/bookings/:id` | Legacy-dependent |
| 10 | `DELETE /api/bookings/:id` | Legacy-dependent |
| 11 | `GET /api/cases?userId=&status=&priority=&search=` | Legacy-dependent |
| 12 | `GET /api/cases/:id` | Legacy-dependent |
| 13 | `POST /api/cases` | Legacy-dependent |
| 14 | `PUT /api/cases/:id` | Legacy-dependent |
| 15 | `DELETE /api/cases/:id` | Legacy-dependent |
| 16 | `GET /api/chats?userId=` | Legacy-dependent |
| 17 | `GET /api/chats/:id` | Legacy-dependent |
| 18 | `POST /api/chats` | Legacy-dependent |
| 19 | `POST /api/chats/:id/messages` | Legacy-dependent |
| 20 | `DELETE /api/chats/:id` | Legacy-dependent |
| 21 | `GET /api/dashboard/stats` | Legacy-dependent |
| 22 | `GET /api/earnings/:userId` | Legacy-dependent |
| 23 | `GET /api/favorites/:userId` | Partial: default-off Supabase favorites path |
| 24 | `POST /api/favorites` | Partial: default-off authenticated RPC path |
| 25 | `DELETE /api/favorites/:id` | Partial: default-off RLS-scoped PostgREST path |
| 26 | `GET /api/lawyers?search=&isPopular=&isTop=&page=&limit=` | Partial: default-off anonymous paged catalogue path |
| 27 | `GET /api/lawyers/:id` | Partial: default-off anonymous public detail path |
| 28 | `POST /api/lawyers` | Legacy-dependent (Admin remains Express) |
| 29 | `PUT /api/lawyers/:id` | Legacy-dependent (Admin remains Express) |
| 30 | `DELETE /api/lawyers/:id` | Legacy-dependent (Admin remains Express) |
| 31 | `GET /api/notifications/:userId` | Legacy-dependent |
| 32 | `GET /api/notifications` | Legacy-dependent |
| 33 | `POST /api/notifications` | Legacy-dependent |
| 34 | `PUT /api/notifications/:id/read` | Legacy-dependent |
| 35 | `PUT /api/notifications/:id` | Legacy-dependent |
| 36 | `DELETE /api/notifications/:id` | Legacy-dependent |
| 37 | `GET /api/plans` | Legacy-dependent |
| 38 | `GET /api/plans/:id` | Legacy-dependent |
| 39 | `POST /api/plans` | Legacy-dependent |
| 40 | `PUT /api/plans/:id` | Legacy-dependent |
| 41 | `DELETE /api/plans/:id` | Legacy-dependent |
| 42 | `GET /api/reviews?lawyerId=&userId=` | Legacy-dependent |
| 43 | `GET /api/reviews/:id` | Legacy-dependent |
| 44 | `POST /api/reviews` | Legacy-dependent |
| 45 | `PUT /api/reviews/:id` | Legacy-dependent |
| 46 | `DELETE /api/reviews/:id` | Legacy-dependent |
| 47 | `GET /api/subscriptions?userId=&status=` | Legacy-dependent |
| 48 | `GET /api/subscriptions/:id` | Legacy-dependent |
| 49 | `POST /api/subscriptions` | Legacy-dependent |
| 50 | `PUT /api/subscriptions/:id` | Legacy-dependent |
| 51 | `DELETE /api/subscriptions/:id` | Legacy-dependent |
| 52 | `GET /api/tasks?userId=&status=&priority=` | Legacy-dependent |
| 53 | `GET /api/tasks/:id` | Legacy-dependent |
| 54 | `POST /api/tasks` | Legacy-dependent |
| 55 | `PUT /api/tasks/:id` | Legacy-dependent |
| 56 | `DELETE /api/tasks/:id` | Legacy-dependent |
| 57 | `GET /api/users?search=&role=&page=&limit=` | Legacy-dependent (Admin user list remains Express) |
| 58 | `POST /api/users/me` | Partial: Supabase Auth profile-trigger path in configured mode; Firebase/Express compatibility remains |
| 59 | `GET /api/users/:id` | Partial: Supabase profile reads in configured mode; Express/Admin consumers remain |
| 60 | `PUT /api/users/:id` | Partial: mobile self-profile PostgREST path in configured mode; Admin/legacy consumers remain |
| 61 | `PATCH /api/users/:id/role` | Legacy-dependent (no Admin RPC callsite) |
| 62 | `DELETE /api/users/:id` | Legacy-dependent; trusted Auth Admin function not implemented/deployed |
| 63 | `GET /api/wallet/:userId` | Legacy-dependent |
| 64 | `POST /api/wallet/transactions` | Legacy-dependent; no payment-provider-confirmed credit path |

**Totals:** 0 fully migrated and remotely verified; 8 partial local client paths (#23–27 and #58–60); 56 legacy-dependent operations. All 64 Express handlers remain in `backend/src/routes/*.js`; none has been removed or retired. These totals describe client/runtime cutover, not the number of local SQL candidates. `supabase/MIGRATION_STATUS.md` contains the route-by-route local SQL/authorization ledger.

### Evidence for the eight partial operations

| Operation(s) | Implemented in local source | Locally tested | CI-tested for this worktree | Applied remotely | Hosted end-to-end |
|---|---|---|---|---|---|
| #23–25 favorites | Yes: `ApiClient` constructor flag/getter and authenticated PostgREST list/delete plus `rpc_favorite_add` in `legal_app/lib/services/api_client.dart` and `app_repository.dart`; default-off `USE_SUPABASE_FAVORITES`; Favorite and detail screens use the repository | PGlite owner isolation/add/delete assertions pass. HTTP-mock assertions are in `legal_app/test/supabase_favorites_test.dart` but Flutter was unavailable, so they were not run | No; latest green run is on older SHA `3f463edf...` | No; migration `20261023101500` absent remotely | No |
| #26–27 lawyer catalogue | Yes: paged anonymous PostgREST, allowlisted columns excluding `user_id`, search/filter/detail, loading/error/retry/load-more UI and default-off `USE_SUPABASE_LAWYER_CATALOG` | PGlite migration/RLS tests pass. Flutter HTTP/widget tests are present but were not run | No for current worktree | No; hardening migration absent. Remote lacks `lawyers.experience`, which the explicit allowlist requests | No |
| #58–60 profile provision/read/update | Yes: Supabase Auth profile-trigger contract and mobile PostgREST profile reads/limited updates in configured mode; legacy fallback remains | PGlite Auth/profile/role migration tests pass. Flutter auth/API tests were not run | No for current worktree | No; remote has the older email-match trigger and no local hardening migration | No |

For all eight, “implemented in source” does not mean deployed or safe to enable against the current unclassified project. The two catalogue/favorites flags are false by default; profile mode is controlled by Supabase configuration and still lacks hosted verification.

## 5. Mobile, Admin, backend, Storage, and external integrations

### Mobile app (`legal_app`)

- Source supports Supabase Auth when configured, otherwise Firebase Auth compatibility. The Supabase Auth/profile path holds session/token state in memory; durable restore/refresh lifecycle is incomplete.
- The lawyer catalogue code now has a typed page-result model, API error categories, anonymous list/detail access, public-column allowlisting (excludes lawyer `user_id`), UI search/filters/pagination, loading/empty/error/retry states, and tests. It remains default-off; no Flutter analysis/test/build ran. The observed remote schema mismatch (`experience` absent) is a further blocker.
- Favorites code uses the authenticated user JWT and public anon key, omits caller-supplied `user_id`, calls the owner-derived/idempotent `rpc_favorite_add`, and deletes under RLS. Admin integration is not applicable to this per-user feature. It remains default-off and has no hosted verification.
- Most non-profile, non-favorites and non-catalogue operations still go through the legacy Express API whose default base is Firebase Hosting. Reviews, availability, booking, chat, tasks, wallet, subscriptions, etc. remain Express-dependent.
- Mobile client configuration contains only a public Supabase anon/publishable-key input; no Supabase service-role or Gemini key was found in the mobile tree. Firebase client API-key strings are present in normal Firebase app configuration; they are client identifiers, not Supabase service-role credentials.

### Admin dashboard (`admin_panel`)

- Admin source supports Supabase Auth and a direct RLS profile read when the public Supabase configuration is supplied, with Firebase fallback. Session/token state is in memory; durable restoration is not verified.
- Admin resource management remains Express-backed. `admin_panel/lib/screens/users_screen.dart` calls the legacy `ApiService` for listing/deleting/editing users; lawyer and other Admin resource screens likewise have no completed PostgREST/RPC cutover. The default Admin API remains Express.
- A prior GitHub CI run on `3f463edf...` passed Admin analyze, tests, and `flutter build web`; none of those checks was run on this current dirty worktree.

### Storage requirement and candidate behavior

- Storage use is demonstrated, not speculative: `legal_app/lib/views/aidocumentsreview/aireview.dart` gates PDF submission on user consent; `legal_app/lib/services/app_repository.dart` and `api_client.dart` upload/read/delete through the private `legal-documents` path; the local `ai-assistant` Edge Function consumes the caller-authorized object.
- The existing upload method rejects empty/over-10-MiB byte arrays, uses the user's JWT, generates an owner-scoped key, declares `Content-Type: application/pdf`, and sets `x-upsert: false`; it does **not** inspect PDF signature bytes. The candidate therefore grants authenticated `storage.objects` SELECT/INSERT/DELETE, not UPDATE, and does not expose `storage.buckets` directly. The migration would create the private bucket if absent, preserve any existing configuration, validate it, and add exact owner/admin path policies. It does not deploy an Edge Function.
- `file_size_limit=10485760` is the server-side Storage size cap. `allowed_mime_types=['application/pdf']` restricts the declared MIME type; it is not a byte-signature check. The local Edge handler checks the `%PDF-` header after download and attempts deletion in `finally` (reporting cleanup failure), but only when analysis is requested; it is not a full PDF parser or malware scanner. A direct/malicious client can send arbitrary bytes labeled `application/pdf` and leave an unanalysed private object. If strict PDF-only storage is required, validate bytes on a trusted upload path or otherwise prevent direct object writes; a client-side signature check alone is bypassable.
- This is source/catalog/PGlite evidence only. PGlite exercises grants and policy predicates, not the hosted Storage service's connection-role behavior. Before any staging/prod rollout, test upload, download, delete, actual MIME/size enforcement, rejected upsert, cross-owner access, cleanup behavior, and existing-bucket mismatch against the actual Storage API. No bucket was created in the connected project.

### Backend, AI, and secrets

- The 64 Express handlers remain active in source. Backend configuration supports a server-side Supabase adapter using `SUPABASE_SERVICE_ROLE_KEY`; the local candidate therefore retains only SELECT/INSERT/UPDATE/DELETE for `service_role` across its 18 mapped app tables (the current generic adapter supports CRUD for those tables), while revoking `TRUNCATE`/`REFERENCES`/`TRIGGER` and wallet-RPC execution. `service_role` still bypasses RLS and its key must remain server-only; Express route authorization is still essential. No deployed backend environment/secret value was inspected.
- Local `supabase/functions/ai-assistant/index.ts` uses the caller JWT/public anon key for profile and Storage access and reads `GEMINI_API_KEY` only via Deno environment. `supabase/config.toml` sets `verify_jwt=true`. Source/Node handler tests exist, but the remote project has no deployed function and no listed secrets; no Gemini call or live JWT test occurred.
- `.env` filename inspection found only `.env.example` files, not local `.env` files. The Supabase secret-list API returned empty. No service-role credential was found in mobile/Admin source. No secret values were requested or printed.
- The payment/checkout UI has no verified external payment-provider authorization, signed webhook, or provider-confirmed settlement. Wallet credits and paid subscription entitlements must not be inferred from UI state.
- A fresh `npm ci` audit reported 9 findings across 287 installed packages: 2 high, 7 moderate, 0 critical. No automatic upgrade was performed.

### Candidate migration line-by-line review and caller census

Reviewed the full local candidate files (`20261023100000_harden_rls_auth_and_storage.sql`, 503 lines; `20261023101500_authenticated_transactional_rpcs.sql`, 1,223 lines) against the re-read PG17 catalog, baseline migrations, tests, and source callers. Exact SHA-256 values are recorded in §6. The currently observed constraint names/signatures match the candidate's `ALTER FUNCTION`/`DROP CONSTRAINT` targets. Current bookings/tasks CHECKs are expanded by the candidate (old allowed values retained); the wallet amount cap is relaxed from 100,000 to 1,000,000, so those changes do not require rewriting existing rows. No application rows were read to check values.

- Migration 1's auth mapping requires `email_confirmed_at`, exact legacy ID, a trusted `raw_app_meta_data` marker, and an unlinked profile; it ignores user-editable `raw_user_meta_data.legacy_uid`, creates ordinary confirmed users as `client`, removes subject fallback, and narrows client grants. Its `public_reviews` security-invoker view and column grants hide raw `user_id`. The existing Storage bucket columns/types/defaults support the proposed insert; no bucket exists. `VALIDATE CONSTRAINT` can scan/lock tables, and the partial unique booking index is built non-concurrently inside the migration transaction; check table size/lock window before any deployment. The migration's Storage MIME allowlist checks declared metadata, not bytes.
- Migration 2 pins every new `SECURITY DEFINER` function to `pg_catalog,public,pg_temp`, derives row ownership from `auth.uid()` through the profile helper, checks admin actions in function bodies, revokes PUBLIC/anon execution, and grants client-callable functions only to `authenticated`. Booking price is derived from the lawyer row; slot conflicts use the unique `(lawyer_id,date,slot)` key; wallet operations permit only the caller's own debit (no credit); paid subscription activation is not implemented; active subscriptions cannot be deleted. Existing service-only RPCs for rating/slot reservation remain service-role-only, but the migration changes the existing `rpc_wallet_mutate` ACL from service-only to authenticated self-debit. No repo callsite for that legacy RPC was found; external/deployed callers are not knowable from this repository and must be checked before rollout.
- Booking RPCs validate published availability but do not lock the matching availability rows. A concurrent lawyer availability edit/delete can race the check; the slot uniqueness key prevents duplicate reservations but does not prevent booking against a just-withdrawn schedule. Add a row/version lock or explicitly accept and test the behavior before enabling booking RPCs. `rpc_admin_set_booking_status` accepts the four values permitted by the current Express booking validator; legacy `Confirmed` rows remain valid in the database but cannot be newly set by that RPC.
- Runtime source scan found exactly one RPC callsite: `legal_app/lib/services/app_repository.dart:717` invokes `rpc_favorite_add`. No runtime callsite was found for the other new RPCs or baseline `rpc_recalculate_lawyer_rating`, `rpc_reserve_booking_slots`, or `rpc_wallet_mutate` in backend, mobile, Admin, or Edge Function source. This is repository evidence only, not proof that no external consumer exists. Both rollout flags remain `false`.

## 6. Verification results

| Check | Actual result | Scope/limitation |
|---|---|---|
| `cd backend && node --test --test-reporter=spec test/supabase_migrations.test.js` | **10 passed, 0 failed** | PGlite 0.5.11 reproduces the verified baseline mirror and applies local candidates; asserts 38-policy inventory, grants/RLS, confirmed/verified Auth linking, ownership (including NULL owner), redacted reviews, Storage policy predicates, wallet authorization, and subscription safeguards. PGlite embeds PostgreSQL **18.6** on WASM, not the project's PostgreSQL 17.11.0.003. |
| `cd backend && npm test` (after `npm ci`) | **501 passed, 0 failed; 124 suites** | Node tests, mocks, and PGlite; simulated error-path logs are expected. No request was made to the connected project. `npm ci` restored missing dependencies; `backend/package-lock.json` remained byte-identical to the prior full recovery snapshot. |
| `node --check backend/test/supabase_migrations.test.js`; `node --check supabase/functions/_shared/ai_assistant_handler.mjs`; `node --check supabase/functions/_shared/ai_assistant_logic.mjs`; `git diff --check`; UTF-8/final-newline/trailing-whitespace scan | **Passed** | Static syntax/whitespace only; PGlite parsed/applied both candidate migrations. `git diff --check` covers tracked diffs; the explicit file scan also covered untracked candidate/report files. |
| Latest GitHub CI: [run 39833573065](https://github.com/Malak987/legal/actions/runs/39833573065), SHA `3f463edf...` | **Success**: backend + Firebase Emulator E2E, Admin analyze/test/web build, mobile analyze/test | Runs on the remote commit, not this local dirty checkout; no Supabase hosted integration |
| `flutter analyze`, `flutter test`, `dart format` locally | **Not run**; `flutter` and `dart` are unavailable | Includes both mobile and Admin Flutter checks |
| `deno check supabase/functions/ai-assistant/index.ts` locally | **Not run**; `deno` unavailable | Local workflow job is uncommitted and absent from the latest recorded CI run |
| Supabase CLI / local Supabase / `psql` / Docker | **Not run**; tools unavailable | PGlite is not Supabase/PostgreSQL 17/Auth/PostgREST/Storage |
| Hosted Supabase Auth/PostgREST/RLS/Storage/Edge integration | **Not run** | No approved environment, no deployed local migrations/function/bucket, no end-to-end test account flow |
| Project data or destructive checks | No application-row contents selected; no writes or destructive calls | Every remote SQL statement executed in this task was a catalog query or `SELECT`; the only live data aggregates were `COUNT(*)` on Storage buckets and objects, both zero. |

**PGlite limitations:** the test harness creates stub `auth.uid()`/roles and a minimal synthetic `storage` schema rather than using GoTrue or the Storage service; it does not test actual JWT verification, PostgREST request planning/role switching, Storage content-type/size enforcement or object bytes, hosted policy installation, database extension packaging, or independent hosted concurrent sessions. It embeds PostgreSQL 18.6 on WASM rather than the target PostgreSQL 17.11.0.003. These tests show local SQL behavior in that harness only; they are not hosted E2E or deployment evidence.

The successful CI run is useful evidence for the **older remote SHA only**. No test result in this report proves the current worktree’s Flutter code compiles or that remote Supabase accepts these client requests.

### Migration and test fingerprints (SHA-256)

| Local file | Lines | SHA-256 |
|---|---:|---|
| `supabase/migrations/20261022174110_initial_legal_schema_and_rls.sql` (baseline; local comment differs from remote-tip copy) | 1,033 | `05875dc95ce09b4f88184e0270e6e33ecf4b51c7a3842cccb15cb62fb32ecbfd` |
| `supabase/migrations/20261022174313_transactional_rpc_functions.sql` (baseline) | 221 | `14021737775a2dcd8d56f43a1a94f754d64f9c25bb1818ae187691dcd30da453` |
| `supabase/migrations/20261023100000_harden_rls_auth_and_storage.sql` (candidate; unapplied) | 503 | `1273f0626e8f980e2b2b20ec0d36904e914247f8cee5408713d8a20e0e6c25f1` |
| `supabase/migrations/20261023101500_authenticated_transactional_rpcs.sql` (candidate; unapplied) | 1,223 | `e3ea096970584bab8618afdbcf73c9b99023e970b1a54a56558daf5ad7f3190e` |
| `backend/test/supabase_migrations.test.js` | 1,854 | `64adc035e1f8e459eda1ac38997c6b9461ee24386632e82670d7b8cfad9f9177` |
| `backend/test/edge_functions.test.js` | 313 | `8cf5e2afdf71e23f442694c5b27480318fc161cc42edf2a4d22f60c9e55953a8` |

The report's own fingerprint and current working-tree state are recorded in the separate backup manifest, avoiding a self-referential hash.

## 7. Security findings, blockers, and remaining actions

### Blocking findings

1. **Unclassified remote environment and no authorization**: no migrations or deployment may be performed until the owner identifies the target and approves the change scope/window.
2. **Critical least-privilege gap remains remote**: all seven table privileges, including `TRUNCATE`, are granted to `anon` and `authenticated` on all 18 public tables; service role has them too. RLS does not constrain `TRUNCATE`.
3. **Public reviewer identity exposure remains live**: raw `reviews` is publicly selectable with `user_id`; the locally added security-invoker redacted view is absent remotely.
4. **Unsafe identity mapping/helpers remain live**: the remote Auth trigger links by email without confirmed/verified legacy mapping; `current_app_user_id()` falls back to JWT subject; helper/trigger functions are broadly executable. The local candidate replaces these behaviors, but is unapplied.
5. **Storage is not provisioned remotely**: no bucket, no Storage policies, and zero objects; `objects`, `buckets`, and `buckets_analytics` have broad API-role DML grants but RLS currently has no policies. The local candidate's size cap and declared MIME allowlist do not validate PDF bytes at upload. PGlite does not establish Storage API connection-role behavior or content enforcement.
6. **Remote schema is behind client/migration expectations**: `lawyers.experience` and `bookings.idempotency_key` are absent; remote migration history has not advanced.
7. **No production Auth redirect setup**: localhost Site URL and empty redirect allow-list require owner-approved configuration.
8. **Client/route parity is incomplete**: 8 partial paths only; 56 routes remain Express-dependent; Admin resource integrations remain legacy; all 64 handlers still exist.
9. **No current-worktree CI/Flutter verification or hosted Supabase E2E**; the latest green CI tests another SHA.
10. **No payment-provider confirmation/webhook** and **9 npm audit findings**, including 2 high.
11. **Git is not reconciled**: the shallow local checkout is at the verified common base and the remote tip is four commits ahead; 16 remote-touched paths diverge and 17 local-only paths must be preserved. There is no PR; work is uncommitted and unpushed. No safe merge/commit plan was executed.
12. **Candidate performance/compatibility gaps remain**: the three unindexed FKs are not indexed; seven of eight baseline permissive-policy overlaps are removed but `plans` remains; auth-helper evaluations in `users` policies remain unoptimized; booking RPCs can race availability edits; and direct Storage writes can spoof PDF MIME. The Security Advisor findings therefore cannot be claimed fully resolved by these migrations.

### Exact next actions

1. Keep this branch/worktree preserved. The full checksum-verified backup is `/home/user/legal-recovery-20261023-security-aKxYQK`; its original `local-remediation-final/` snapshot remains intact. The original full manifest (104 entries), original local-remediation subset (4 entries), and this report/candidate/test update manifest (7 entries) all verified. The update is preserved in `/home/user/legal-recovery-20261023-security-aKxYQK/verification-update-20261023/`. Before any later Git operation that could change the worktree, capture the exact current status/branch/log/diff/staged/untracked state and verify the outside backup again. Reconcile the four live remote commits only after reviewing the 16 divergent paths and preserving the 17 local-only paths; do not reset, discard, blind-stash, overwrite, or force history. The current status is not safely reconciled.
2. Obtain written environment classification and authorization for project `qqfzbecwhewswkyxgebu`; otherwise stop. Use only an already-existing, explicitly approved isolated test environment if available; do not create a new project, branch, paid service, or infrastructure.
3. Rehearse both unapplied migrations only on an already-approved isolated PostgreSQL 17/Supabase-compatible target or an existing local environment. Include grant revocation, raw-review redaction, confirmed/verified Auth linking, `legal-documents` bucket and actual Storage API behavior, RLS/function ACLs, statuses, rollback, identity recovery, table locks, and constraint validation. PGlite cannot validate hosted Storage/Auth/PostgREST behavior. Do not apply to the connected project.
4. Before PR review, decide and test an approved follow-up for the three FK indexes, the remaining `plans` policy overlap, `users` helper initplans, booking availability locking, and trusted PDF-byte validation. Do not claim current candidate files resolve those findings.
5. Configure approved Auth URLs/redirects and validate confirmed sign-up, explicit legacy linking, session persistence/refresh, and least-privilege roles on disposable test users. If no approved test environment exists, retain this as a blocker.
6. If an existing approved staging target is available, test private Storage and the JWT-verified Edge Function there; set Gemini credentials only in that target's server-side secret store. Run positive and negative live Auth/PostgREST/Storage/Edge tests. Do not create a production bucket during this task.
7. Complete the remaining mobile and Admin resource migrations or explicitly retain Express. Do not remove endpoints or call any route cut over until every consumer is moved and hosted replacement/rollback is validated. Keep `USE_SUPABASE_LAWYER_CATALOG` and `USE_SUPABASE_FAVORITES` disabled until that verification.
8. Add a real payment provider with signed server-side confirmation/webhooks before any wallet credit or paid entitlement is represented as successful. Review and resolve npm audit findings.
9. Only after safe reconciliation, commit intended changes to `arena/69f08c8e-legal`, run CI on that exact commit (including Flutter mobile/Admin and Deno), push only that branch, and open a review PR. Do not merge automatically.

### Rollback and preservation guidance

- Each candidate migration is wrapped in `BEGIN`/`COMMIT`, so a statement failure during that migration should roll back that migration transaction. There are no down-migration scripts; a successful commit is not automatically reversible.
- Keep the rollout flags disabled and Express paths active. If staging reveals a problem, stop/avoid the new client path and prepare a reviewed **forward corrective migration**. Do not restore the unsafe baseline grants/policies blindly, drop tables, or delete application rows. Use an approved pre-deployment backup for disaster recovery, not as a substitute for policy review.
- The Auth trigger may create profiles only for future confirmed signups; rollback must not delete those Auth users or linked profiles. Any identity repair requires verified UID/email reconciliation and an audited mapping—never an email-only relink.
- The candidate bucket is private and created only if absent. If rollback is ever considered, preserve objects and metadata first; do not drop a bucket containing user documents or overwrite an existing bucket configuration. No bucket was created in the connected project.
- The candidate migrations do not rewrite booking/task records or financial rows. Do not reverse wallet/subscription data during a schema rollback; financial state must be reconciled from trusted ledgers/provider events.

## 8. Final decision

**Review status: BLOCKED. Deployment decision: NO-GO.** The two candidate migrations remain local and unapplied. Fresh tests pass (10/10 PGlite migration/RLS checks; 501/501 backend tests), but PGlite 0.5.11 embeds PostgreSQL 18.6 and is not the project's PostgreSQL 17.11/Supabase Auth/PostgREST/Storage; no hosted end-to-end test ran. The live project still has broad public-table grants, unsafe email-only Auth linking, raw reviewer IDs, no Storage bucket/policies, and the recorded performance gaps. Candidate follow-up remains necessary for the three FK indexes, one remaining policy overlap, repeated auth-helper calls, booking availability races, and PDF byte validation. The local checkout is shallow and dirty at the verified common base; the remote feature branch is four commits ahead, with 16 divergent remote-touched paths and 17 local-only paths. No PR, commit, push, or live write occurred. Fifty-six Express operations remain legacy-dependent, eight paths are partial/default-off, and no rollout flag was enabled. Do not deploy, create a production bucket, push, or open a PR until safe history reconciliation, candidate fixes, compatibility validation on an existing approved target, and explicit authorization are complete.
