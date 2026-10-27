# Admin panel Supabase runtime errors — diagnosis (historical snapshot)

> **Superseded on 2026-10-26.** A fresh audit of `main` at `42e431ab60ab8846f4feeefeb11b684b5a5d45ef` and the connected project `qqfzbecwhewswkyxgebu` confirms all 16 repository migration versions are applied, including `20261025140000`–`20261025144000`. The `public_reviews` view and admin RPCs are present. Do not use the pending-migration conclusions below as current state; see [`CURRENT_STATE_AUDIT_2026-10-26.md`](CURRENT_STATE_AUDIT_2026-10-26.md).

Scope: three failures reported against `main` @ `90bbda0` ("update legal platform").
Connected project: `legal` (`qqfzbecwhewswkyxgebu`, PostgreSQL 17, eu-west-1).
Investigation was read-only: no remote writes, migrations, grant or RLS changes.

## Common root cause: the client was shipped ahead of the database

| | Version | Local file | Remote `schema_migrations` |
|---|---|---|---|
| 1–10 | `20261022174110` … `20261024123238` | yes | applied |
| 11 | `20261025122424_tighten_anon_grants_and_optimize_user_policies` | **missing from Git** (now reconciled) | applied |
| 12 | `20261025140000_supabase_security_storage` | yes | **not applied** |
| 13 | `20261025141000_identity_owner_lawyer_access` | yes | **not applied** |
| 14 | `20261025142000_authenticated_transactional_rpcs` | yes | **not applied** |
| 15 | `20261025143000_supabase_native_workflows` | yes | **not applied** |
| 16 | `20261025144000_admin_native_workflows` | yes | **not applied** |

Commit `90bbda0` partially applied a patch. It left many `*.rej` files and the stray
`01a17343-…patch`. The admin client in that patch targets objects created only by
migrations 12–16. None of the admin RPCs it calls exist remotely, including
`rpc_dashboard_stats`, `rpc_admin_lawyer_save` and `rpc_admin_review_moderate`.

**Parity check.** The live schema was compared read-only with a PGlite database built
from local versions 1–11:

- **Identical:** columns (162), RLS policies (58), relations (19), non-NOT-NULL
  constraints (93) and triggers. The one extra trigger is Supabase's own
  `realtime.subscription` trigger.
- **Function bodies:** all identical except `rpc_reserve_booking_slots`. The live copy has
  one extra comment line; the difference is comment-only.
- **Grants:** differ only because PGlite doesn't simulate Supabase default privileges.

## 1. `POST /rest/v1/rpc/rpc_admin_lawyers_page` → 404

- **Live response:** `PGRST202`, "Could not find the function
  public.rpc_admin_lawyers_page(p_category_id, p_is_popular, p_is_top, p_limit, p_page,
  p_search) in the schema cache".
- **Remote schema:** no function named `rpc_admin_lawyers_page` exists in any schema.
- **Client:** `ApiService._lawyerPage` sends exactly those six named arguments.
- **Defining migration:** `20261025144000` declares the same six names and types, grants
  `EXECUTE` to `authenticated` only, and rechecks `is_admin()`. The contract matches; the
  object simply has not been deployed.
- **Fix:** deploy the existing migrations. No client change and no new migration.

## 2. `POST /rest/v1/legal_categories?select=*` → 400

- **Remote table:** `slug text NOT NULL`, with no default and no `BEFORE INSERT` trigger.
  Constraints are `UNIQUE(slug)`, a unique index on `lower(name)`, and CHECKs requiring a
  name of 2–120 characters and a slug of 1–160. The INSERT policy requires `is_admin()`;
  a denial would return 401/403, not 400. The table currently has 0 rows.
- **Original patch client:** posted `{name}` only, relying on the slug trigger in unapplied
  `20261025143000`. On the live schema that is SQLSTATE `23502` (NOT NULL violation), which
  PostgREST returns as **400**. This is reproduced in the live-parity PGlite suite.
- **HEAD client:** always sends `{name, slug}`. A non-mutating anon probe showed PostgREST
  knows both columns (unknown columns return `PGRST204`/400). With 0 rows, HEAD's payload
  should not produce a 400.
- **Not confirmed:** the exact 400 body was not captured, and the deployed web build
  (`legal-102026.web.app/main.dart.js`) returns 404, so its payload can't be inspected.
  `23502` from a slug-less build is the only 400 path the evidence supports, but it remains
  a strong inference, not a confirmation.
- **Latent HEAD defect:** names with no ASCII letters or digits (for example Arabic) all
  received the slug `category`, so the second one would fail with 409 (`UNIQUE(slug)`).
- **Fix:**
  - The client now uses a random fallback slug for such names.
  - `ApiException` now keeps PostgREST's `code`/`details`/`hint`, so the next failure is
    fully diagnosable.
  - Once `20261025143000` is deployed, its trigger generates the slug server-side.

## 3. `GET /rest/v1/public_reviews?...` → 404

- **Live response:** `PGRST205`, "Could not find the table 'public.public_reviews' in the
  schema cache".
- **Remote schema:** only the `reviews` table exists (0 rows). Its SELECT policy is
  `USING (true)`.
- **Privacy gap today:** `anon` and `authenticated` currently hold SELECT on **every**
  `reviews` column, including `user_id`.
- **Defining migration:** `20261025140000` creates
  `public_reviews (id, user_name, lawyer_id, rating, comment, created_at, updated_at)` with
  `security_invoker`/`security_barrier`. It grants the view, and only those safe base
  columns, to `anon` and `authenticated`.
- **Client:** the select list matches the view exactly. The reviews screen never uses
  `userId`. The client contract is correct; the view is missing.
- **Why not point the client at `reviews`:** that would only work because of the
  over-broad live grant, and would stop being the privacy contract once 140000 is deployed.
- **Fix:** deploy the existing migrations. No client change.

## Related live defect found during reconciliation (not one of the three)

The Git-missing live migration `20261025122424` recreated `users_update_self_or_admin`.
Its `WITH CHECK` contains subqueries on `public.users` itself. As a result, every
authenticated PostgREST `UPDATE` on `public.users` currently fails with **`42P17` infinite
recursion** (HTTP 500).

- **Confirmed on live** with a non-executing `EXPLAIN` as `authenticated`.
- **Resolved by** `20261025140000`, which replaces that policy (verified in PGlite).

## Deployment (not performed)

1. **Back up first.** Take a backup or PITR point. Use a branch or staging project if your
   plan supports branching.
2. **Align history.** Commit the reconciled
   `20261025122424_tighten_anon_grants_and_optimize_user_policies.sql`. Its SQL is
   byte-identical to the live recorded statement (md5 `26c2eb70…`). `supabase db push`
   refuses to run while a remote version is missing locally. Do **not** re-run it.
3. **Check the migration list.** `supabase migration list` should show versions 1–11 on
   both sides and 12–16 local-only.
4. **Push.** Run `supabase db push --dry-run`, then `supabase db push`. This applies
   140000 → 144000 in order; each file is wrapped in `BEGIN … COMMIT`.
5. **Verify:**
   - `POST /rpc/rpc_admin_lawyers_page` and `GET /public_reviews` no longer return
     `PGRST202`/`PGRST205`.
   - Admin category creation works.
   - A profile `UPDATE` no longer returns `42P17`.

**Compatibility:** migrations 12–16 are broad security changes, not just these objects.
Among other things they:

- revoke direct `lawyers` writes,
- remove the `users` self-insert policy,
- hide `reviews.user_id`,
- narrow column grants.

Any older mobile or admin build that writes tables directly may break. Both HEAD clients
(`admin_panel`, and `legal_app`, which also reads `public_reviews`) are written for the
post-migration contract.
