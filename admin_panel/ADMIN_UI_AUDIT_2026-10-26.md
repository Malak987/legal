# Admin panel UI and functional completeness audit (historical snapshot)

> **Superseded on 2026-10-26.** The current `main` commit is `42e431ab60ab8846f4feeefeb11b684b5a5d45ef`; the fresh live audit confirms all 16 migration versions are applied and the relevant dashboard/lawyer/review/case RPCs exist. The prior migration-gap claims below describe an earlier state. See [`../CURRENT_STATE_AUDIT_2026-10-26.md`](../CURRENT_STATE_AUDIT_2026-10-26.md) for the current screen-to-data map and live blockers.

**Scope:** repo `Malak987/legal`, branch `main` @ `90bbda0` (nothing committed or pushed).

**Method:** every screen, dialog and widget under `admin_panel/lib` was read. Each field was traced as model → `api_service.dart` → PostgREST table/RPC → migration column/constraint/grant. No SQL was run against the remote project.

**Line references:** `file:line` points to the pre-fix file at HEAD, unless it says "(now)".

## Context: remote vs local schema

- The remote project has 11 migrations, through `20261025122424`.
- `20261025140000` through `144000` exist only locally and are not applied.
- All 16 RPCs the panel calls are defined only in those pending files:
  - `rpc_dashboard_stats`, `rpc_admin_set_user_role`, `rpc_admin_set_booking_status`, `rpc_admin_reschedule_booking`, `rpc_delete_booking`
  - `rpc_admin_review_moderate`, `rpc_admin_review_delete`, `rpc_subscription_cancel`, `rpc_subscription_delete`, `rpc_notification_update` (all in 142000)
  - `rpc_admin_case_update`, `rpc_lawyer_my_availability` (143000)
  - `rpc_admin_lawyers_page`, `rpc_admin_lawyer_get`, `rpc_admin_lawyer_save`, `rpc_admin_lawyer_delete` (144000)
- The same goes for the `public_reviews` view (140000).
- Until those migrations are deployed, the screens marked "pending" below fail at runtime with PostgREST 404 (PGRST202/PGRST205).
- There is also a live 42P17 on users UPDATE, which 140000 fixes.

---

## 1. Screen inventory

| # | Screen / component | Role | Data path | Works on live today? |
|---|---|---|---|---|
| 1 | Login (`login_screen.dart`, `auth_service.dart`) | all | Supabase Auth + `users` profile (admin/owner/lawyer only) | Yes. `owner` only exists after 141000 |
| 2 | Dashboard | admin/owner | `rpc_dashboard_stats` | No (142000) |
| 3 | Lawyers list + Lawyer dialog | admin/owner | `rpc_admin_lawyers_page` / `_save` / `_delete` | No (144000) |
| 4 | Categories list + dialog | admin/owner | `legal_categories` table | Yes. Slug comes from the client, until the 143000 trigger |
| 5 | Users table + Edit dialog | admin/owner | `users` table | List yes. Edit no (live 42P17, fixed in 140000) |
| 6 | Cases list + Case dialog + client picker | admin/owner | `cases` insert/delete, `rpc_admin_case_update` | List/delete yes. **Create is blocked**: its lawyer lookup needs `rpc_admin_lawyers_page`. Edit needs 143000 |
| 7 | Bookings | admin/owner | `bookings` select, `rpc_admin_set_booking_status`, `rpc_delete_booking` | List yes. Actions no (142000) |
| 8 | Reviews | admin/owner | `public_reviews` view, `rpc_admin_review_delete` | No (140000/142000) |
| 9 | Plans + Plan dialog | admin/owner | `plans` table | Yes |
| 10 | Subscriptions | admin/owner | `subscriptions` select, `rpc_subscription_cancel` | List yes. Cancel no (142000) |
| 11 | Notifications + dialog | admin/owner | `notifications` insert/delete, `rpc_notification_update` | Create/delete yes. Read toggle no (142000) |
| 12 | Chats (list + messages pane) | admin/owner | `chats`, `chat_messages` select | Yes |
| 13 | Lawyer: Overview / My Cases / My Bookings / My Availability | lawyer | `cases`/`bookings` with assigned-lawyer RLS (141000), `rpc_lawyer_my_availability` (143000) | No. Also needs `lawyers.user_id` to be set (finding L2) |
| – | `AppScaffold` (sidebar ≥900px, drawer below), `ClientPickerField`, `common.dart` | shared | – | – |

There are no hearings or documents screens, and no table backs them; see section 6.

---

## 2. Findings (Phase 2)

**Priority:**
- **P0:** blocks a core workflow.
- **P1:** data cannot be entered or is written wrong.
- **P2:** validation, UX or integrity risk.
- **P3:** polish.

### 2a. Confirmed defects

| ID | Screen | Field / action | Current behaviour + evidence | Expected | DB/API support | Pending migration? | P | Fix |
|---|---|---|---|---|---|---|---|---|
| C1 | Cases | Create case | Assignment is mandatory on create (`cases_screen.dart:443-450`). The lawyer list comes from `GET lawyers` → `rpc_admin_lawyers_page` (`api_service.dart:350-359`), which does not exist remotely, so no case can be created | Create works | RPC in 144000 | **Yes (144000)** | P0 | Deploy 140000–144000. No UI change |
| C2 | Cases | Edit case | `PUT cases/:id` → `rpc_admin_case_update` (`api_service.dart:256-261`): 404 remotely | Edit works | 143000 | **Yes** | P0 | Deploy |
| C3 | Cases | `caseType` on create | The type field is hidden for new cases (`:569-577`), but `'caseType': _type.text` sends `''` (`:465`). The mobile app shows `caseType` (`legal_app/.../cases.dart:109`), so new admin cases show no type | `case_type` = category name, as `rpc_admin_case_update` and `sync_legal_category_labels` already do | Column exists and is granted | No | P1 | **Fixed**: the selected category's name is sent |
| C4 | Cases | Title | Only an empty title is rejected (`:424`). The DB CHECK needs ≥2 characters and the RPC 2–200, so a raw 23514/`INVALID_CASE_TITLE` appears | Client-side check matches the DB | – | No | P2 | **Fixed**: ≥2 check, `maxLength` 200. Also client name 160, legacy type 120, description 4000 (RPC limits) |
| C5 | Cases | Due date | Free text, no picker or format (`:667`); the mobile app uses `yyyy-MM-dd` | Date picker | `due_date text` | No | P2 | **Fixed**: calendar button writes `yyyy-MM-dd`; field stays editable for legacy values |
| L1 | Lawyers | **Bio** | Column, model (`models.dart:37`) and RPC `p_bio` all exist, but the dialog has no Bio field and never sends `bio` (`lawyers_screen.dart:329-338`) | Editable bio | `lawyers.bio`, `rpc_admin_lawyer_save(p_bio)` | No (column exists) | P1 | **Fixed**: multiline Bio, max 4000 |
| L2 | Lawyers | **Linked lawyer account** (`user_id`) | The RPC supports `p_user_id` (lawyer role, unique link) and `_saveLawyer` forwards `userId` (`api_service.dart:458`), but the form cannot set it. Lawyer accounts therefore can never see their workspace (assigned cases/bookings RLS and availability match on `lawyers.user_id`) | Link/unlink a lawyer-role user | 144000 RPC | Yes, to save | P1 | **Fixed**: shows the current link, explicit Unlink, and a picker limited to `role=lawyer`. `userId` is sent only after an explicit pick or unlink (`''` stores NULL) |
| L3 | Lawyers | Category on edit | Edit offered "No category (legacy profile)" (`:421-423`). The RPC rejects a missing category (`CATEGORY_REQUIRED`), and `''` silently keeps the old one (`COALESCE(NULLIF(...), old)`) | Category always required | – | Yes | P2 | **Fixed**: required on create and edit |
| L4 | Lawyers | Hourly rate on edit | "Leave empty to keep" (`:319`). If the stored `price_value` is 0 (legacy default), the RPC raises `INVALID_LAWYER_PROFILE` | Rate required when none is stored | – | Yes | P2 | **Fixed** |
| L5 | Lawyers | Lengths/name | Only an empty name is rejected (`:288`); the RPC needs name 2–160, experience ≤120, price ≤80, location ≤200, image ≤500 | Match the RPC | – | Yes | P2 | **Fixed**: ≥2 name check plus `maxLength` on every field |
| P1 | Plans | **Color dropdown crash** | `initialValue: _color` with only 5 palette items (`plans_screen.dart:326-337`). The DB default `#3A86FF`, or any unlisted colour, makes the dropdown assert ("exactly one item"), so such plans cannot be edited | Edit any plan | – | No | P1 | **Fixed**: an unlisted stored colour is kept as "Current (#xxxxxx)" |
| P2 | Plans | **`price_value`** | Not in the model or form (`models.dart:304-342`). Admin and mobile both sort plans by `price_value.asc` (`api_service.dart:98`, `app_repository.dart:376`), so every admin plan stays at 0 | Editable numeric price | Column NUMERIC(12,2) ≥0; INSERT/UPDATE granted in 140000 | No | P1 | **Fixed**: model field, plus a validated form field (≥0, 2 decimals) |
| P3 | Plans | Title | Only an empty title is rejected; the CHECK needs ≥2 | – | – | No | P2 | **Fixed** |
| N1 | Notifications | **"Leave empty for all"** | The dialog promised a broadcast (`notifications_screen.dart:226-230`), but `notifications.user_id` is NOT NULL and there is no broadcast RPC, so the insert fails with 23502. It also used a raw user-ID text box | One recipient, chosen safely | Table insert | No | P1 | **Fixed**: recipient role plus `ClientPickerField` (required). The "for all" wording is removed; broadcast is a schema proposal (S8) |
| N2 | Notifications | Type | An empty type was sent as `''`, overriding the DB default `general` (`:195`) | Default applies | – | No | P2 | **Fixed**: omitted when empty |
| N3 | Notifications | Delete | Deleted immediately, without confirmation (`:61-70`) | Confirm | – | No | P2 | **Fixed** |
| B1 | Bookings | Status menu | "Mark Active/Completed/Cancelled" was offered for every booking (`bookings_screen.dart:160-171`). The RPC rejects changes out of Completed/Cancelled (`BOOKING_STATUS_IS_TERMINAL`) | Only valid transitions | 142000 | Yes | P2 | **Fixed**: terminal bookings get no status items; the current status is hidden; the label says "Confirmed", as stored |
| B2 | Bookings | Delete | No success feedback | Snackbar | – | No | P3 | **Fixed** |
| S1 | Subscriptions | Cancel | Irreversible cancel with no confirmation (`subscriptions_screen.dart` `_setStatus`) | Confirm | 142000 | Yes | P2 | **Fixed** |
| A1 | API adapter | `GET bookings/:id`, reschedule | `_one()` used `select=*` (`api_service.dart:553-558`). Pending 140000 grants bookings SELECT column-by-column (no `idempotency_key_hash`), so `*` would become 42501 | Explicit granted columns | – | Activates with 140000 | P2 | **Fixed**: bookings uses `_selectColumns('bookings')` |
| U1 | Users | Role chip | `owner` was coloured like `client` (`users_screen.dart:168-172`) | Distinct | – | – | P3 | **Fixed** |
| X1 | StatusChip | `Confirmed` | Fell through to the default colour (`common.dart:75-90`) | Success colour | – | – | P3 | **Fixed** |
| D1 | Dashboard | Layout | Chart and overview were a fixed `Row`, squeezed on narrow widths (`dashboard_screen.dart:103-171`) | Responsive | – | – | P3 | **Fixed**: stacks below 720px |

### 2b. Confirmed gaps not fixed in this pass (need design or moderate changes)

| ID | Screen | Gap + evidence | Support | Pending? | P | Recommendation |
|---|---|---|---|---|---|---|
| G1 | All lists | Every list fetches page 1, limit 100, and ignores `total`/`totalPages` (e.g. `cases_screen.dart:41-46`, `lawyers_screen.dart:31-37`). Rows beyond 100 are unreachable | `_tablePage` already returns total/totalPages | No | P2 | Shared pagination footer (page, total, next/prev) |
| G2 | All forms | Raw DB/RPC codes reach users (`INVALID_CASE_ASSIGNMENT`, `23505 duplicate key … legal_categories_name_lower_key`, `23503` FK on lawyer/plan/category delete). `_domainError` (`api_service.dart:844-865`) only applies to reschedule `row['error']` | Codes are available on `ApiException.code` | Partly | P2 | Central code→message map in `_decode`, e.g. "category already exists", "lawyer has cases/bookings", "plan has subscriptions" |
| G3 | Users | No role-change action, though `PUT users/:id/role` → `rpc_admin_set_user_role` exists (`api_service.dart:206-216`). Needed before L2 can link a new lawyer account | 142000 | Yes | P2 | Role menu (client/lawyer/admin) with confirmation; never assigns `owner` |
| G4 | Reviews | No moderation UI, though `PUT reviews/:id` → `rpc_admin_review_moderate` exists. The lawyer is never shown; only `lawyer_id` is available, and names are not resolved | 142000 | Yes | P2 | Moderate dialog (rating 1–5, comment ≤4000). Resolve lawyer names via `lawyers(id,name)` (granted columns). Keep `user_id` hidden |
| G5 | Bookings | Client not shown (only `user_id`); no search; reschedule RPC has no UI | `users` select / 142000 | Partly | P2 | Resolve client names; optional reschedule dialog |
| G6 | Subscriptions | Shows the raw `User: <id>`. `start_date`/`end_date` are not in the model | Columns exist | No | P3 | Resolve user name/email; add dates |
| G7 | Cases | No status/priority/lawyer/category filters in the UI, although `_casePage` supports them (`api_service.dart:362-375`) | Yes | No | P3 | Filter bar |
| G8 | Lawyers | Rating is admin-editable, but `trg_reviews_recalculate_lawyer_rating` (142000) overwrites it on any review change | – | Yes | P3 | Read-only, or label as override (tooltip added) |
| G9 | Lawyers | Changing a lawyer's category while cases reference (lawyer, old category) violates `cases_lawyer_category_fkey`, with a raw error | FK in 102004 | No | P2 | Pre-check assigned cases or map 23503 (see G2) |
| G10 | Chats | Fixed 340px list (`chats_screen.dart:46-48`) overflows on phones. The title shows only the first participant. The pane loads the oldest 100 messages (`api_service.dart:149-154`), and the selected chat is not highlighted | – | No | P3 | Responsive master/detail; newest-first window |
| G11 | Notifications | Recipient not shown in the list | `user_id` exists | No | P3 | Resolve recipient name |
| G12 | Arabic/RTL | No `flutter_localizations`, `supportedLocales` or `locale`. UI strings are English and layout is LTR only. Arabic data renders and can be typed, but aligns left | – | – | P2 | Add localization + `ar` locale with RTL (a dependency change, so out of scope for this pass) |
| G13 | Dashboard | `plans` count fetched but not shown; no pending-bookings metric (not returned by the RPC) | Partly | Yes | P3 | Show plans; extend the RPC if needed |

### 2c. Verified OK (no action)

- Categories: create, edit, delete, search, ≥2 and ≤120 name checks, Arabic names (random slug fallback). The 143000 trigger later replaces client slugs. The delete warning matches the FK RESTRICT.
- Case owner handling: legacy, non-client and missing owners are never silently reassigned. Assignment pair and category/lawyer consistency are enforced by the UI (lawyers filtered by category), the FK and the RPC.
- Users: email read-only (Auth-managed); only name/phone/address sent, matching the 140000 column grant.
- Loading, error (with Retry) and empty states exist on every list. Search is debounced on users, lawyers, categories and cases.
- Shell navigation is role-aware: lawyers get read-only workspace screens only. The sidebar becomes a drawer below 900px.

---

## 3. Implementation plan (Phase 3)

1. **Deploy blocker (no code):** apply 140000 → 144000 in order, after review. This unblocks C1, C2, the dashboard, lawyers, reviews and all RPC actions. Without it, L2–L5 and B1 cannot be exercised remotely.
2. **Data correctness (done in this pass):** C3, L1, L2, P1, P2, N1, N2, A1.
3. **Validation parity (done):** C4, L3–L5, P3. Client checks now mirror the CHECK constraints and RPC limits.
4. **Safety/UX (done):** C5, N3, B1, B2, S1, U1, X1, D1.
5. **Next, low/moderate risk, no schema change:**
   - G2 error mapping.
   - G1 pagination.
   - G3 role action (needed for an end-to-end lawyer onboarding).
   - G4 review moderation + lawyer names.
   - G5/G6/G11 name resolution.
6. **Later:** G12 localization/RTL; G10 chats responsiveness; G7/G13 filters and metrics.

---

## 4. Schema-change proposals (not implemented; no DB/API contract exists)

| ID | Requested capability | Today | Proposal |
|---|---|---|---|
| S1 | Case number | absent | `cases.case_number text`, unique per tenant, optional; add to RPC allow-list |
| S2 | Court | absent | `cases.court text` (or a `courts` lookup table) |
| S3 | Filing date | absent (`due_date` is text) | `cases.filing_date date`; consider migrating `due_date` to `date` |
| S4 | Next hearing date / hearings | No table. The mobile "case number / court" search screens are unbacked mockups (`legal_app/lib/views/cases/casenumber.dart`) | `case_hearings(id, case_id FK, hearing_at timestamptz, court, notes)` with owner/assigned-lawyer/admin RLS; derive "next hearing" |
| S5 | Case documents | Only the private bucket `legal-documents` (140000), path `<user-id>/documents/<name>.pdf`; no case link, no metadata table | `case_documents(id, case_id, object_path, uploaded_by, created_at)` + admin read RLS; the upload Edge Function records rows |
| S6 | User account status (active/suspended) | absent | `users.status` + RLS/Auth ban integration via an admin RPC |
| S7 | Lawyer email/phone | Not on `lawyers`; available only via the linked `users` row (L2) | Prefer showing the linked user's contact info; avoid duplicate columns |
| S8 | Notification broadcast | `user_id` NOT NULL | `rpc_admin_notify_role(p_role, title, content, type)` that inserts one row per recipient |
| S9 | Multiple categories per lawyer | Single `lawyers.category_id` (FK pair used by cases) | `lawyer_categories` join table; the cases FK would need redesign |
| S10 | Arabic + English category names | Single `name` | `name_ar`/`name_en` (or a translations table); the slug stays from the Latin name |

---

## 5. Files changed in this pass (local only, not committed)

- `lib/screens/cases_screen.dart`: C3, C4, C5.
- `lib/screens/lawyers_screen.dart`: L1–L5; rating tooltip (G8).
- `lib/screens/plans_screen.dart` and `lib/models/models.dart` (`Plan.priceValue`): P1–P3.
- `lib/screens/notifications_screen.dart`: N1–N3.
- `lib/screens/bookings_screen.dart`: B1, B2.
- `lib/screens/subscriptions_screen.dart`: S1.
- `lib/screens/users_screen.dart`: U1.
- `lib/widgets/common.dart`: X1.
- `lib/screens/dashboard_screen.dart`: D1.
- `lib/services/api_service.dart`: A1, plus the prior task's uncommitted changes (preserved).
- `test/admin_form_fixes_test.dart` (new, 8 tests); `test/cases_screen_test.dart` (+1 `caseType` assertion).

**Results:**
- `flutter test`: 70/70 passed (62 before, plus 8 new).
- `flutter analyze`: one pre-existing info (`use_null_aware_elements`, `api_service.dart:398`).
- `analysis_options.yaml` reverted after running.

---

## 6. Phase 2 — functional completion (2026-10-26, local only, not committed)

Baseline: `main` @ `90bbda0` plus the uncommitted Phase-1 changes (backed up
before editing to `/home/user/backups/phase1_tracked.patch` and
`phase1_untracked.tgz`). No SQL was executed against the remote project; no
migration was applied, pushed, repaired or marked as applied.

### 6a. Gaps closed

| Gap | Change |
|---|---|
| G1 pagination | New `lib/widgets/pagination.dart`: `paginatedOf`, `loadPaginated` (steps back to the last page if the current page became empty), `PaginationBar` ("Showing a–b of N", "Page x of y", previous/next, disabled with a spinner while loading) and `PagedFutureView` (first-load spinner, friendly error + retry, empty state, stale rows under a progress bar while the next page loads). Applied to users, lawyers, categories, cases, bookings, reviews, plans, subscriptions, notifications, chats and the lawyer workspace (cases, bookings, availability). Search and filter changes reset to page 1. A full page without an exact count is treated as "more may exist" (both in `paginatedOf` and `_tablePage`), so rows after 100 are never silently hidden. Chats now use `_tablePage` (Content-Range total) instead of a capped list. Lawyer overview counts use `total` instead of `items.length`. |
| G2 errors | New `lib/services/api_errors.dart`: `friendlyError` / `reportError` / `apiErrorDiagnostics`. Domain codes (all `RAISE … MESSAGE` codes from 140000–144000 and the booking `{error: CODE}` results), then PostgREST/PostgreSQL codes (PGRST202/42883 missing RPC, PGRST205/42P01 missing view, PGRST204/42703 missing column, 42501/PGRST30x permission/session, 42P17 policy, 23505 duplicate incl. categories, 23503 FK restriction naming the referencing records, 23514/23502/22001/22P02/22023 validation), then HTTP status. Text ends with `(ref: CODE)`; details, hint, SQL and constraint/key values are never shown. `ApiException.message/code/details/hint` are unchanged (contract tests still assert them) and `reportError` logs the full diagnostics in debug builds only. Every `'$e'` / `'${snapshot.error}'` in screens and the client picker now goes through it. |
| G3 role UI | Users → "Change role" (`UserRoleDialog`): only client / lawyer / admin, each with its effect explained, extra warning when granting or removing admin, confirm disabled until the role changes. Disabled for owner rows and for the signed-in user's own row. Calls `PUT users/:id/role` → `rpc_admin_set_user_role` only (no table write), then re-fetches the page. PGRST202/42883 → "needs rpc_admin_set_user_role (migration 20261025142000)… No change was made." |
| G4 review moderation | Reviews → "Moderate review" (`ReviewModerationDialog`): rating slider 1–5 in 0.5 steps, comment ≤ 4000 chars, only changed fields sent, save disabled until something changes. `rpc_admin_review_moderate` returns `to_jsonb(review)` incl. `user_id`; the adapter now strips `userId` from that response. The dialog states that the lawyer's stored rating is **not** recalculated (G8 remains). |
| Reschedule | Bookings → "Reschedule…" for non-terminal bookings only (`RescheduleBookingDialog`): date picker (today … +2 years), 24-hour `H:MM`/`HH:MM` validated (hour 0–23, minute 0–59, must end by midnight as the RPC requires), duration 1–12 h, same `lawyerId`. Server results (NO_AVAILABILITY, TIME_NOT_AVAILABLE, SLOT_TAKEN, TERMINAL_…, INVALID_…) map to friendly text. |
| G5/G6/G11 identity | Adapter-side best-effort lookups via permitted columns only: bookings / subscriptions / notifications gain `userName`/`userEmail` from `users(id,name,email)`; reviews gain `lawyerName` from `lawyers(id,name)`. Ids are validated (`^[A-Za-z0-9_-]{1,200}$`) and de-duplicated, the request is skipped when there are none, and a failed lookup (e.g. RLS) leaves the list usable with a fallback label. `reviews.user_id` is never requested or shown. Subscriptions also show start/end dates. |
| G7 case filters | Status, priority, category, lawyer (+ "Clear filters"), combined with search; every change resets to page 1. If the category or lawyer lookup fails (e.g. `rpc_admin_lawyers_page` not deployed) only that filter is disabled, with the reason as a tooltip. |
| Model fix | `Booking.fromJson` crashed when `hours` was missing (`(x ?? 1) is int ? x : …` returned null). Fixed. |

### 6b. Tests

`test/phase2_functional_test.dart` (30 tests): error mapping (duplicate
category, invalid assignment, FK restriction, missing RPC/view/column,
permission/validation, pass-through/fallback, diagnostics retain
code/details/hint); `paginatedOf`/`loadPaginated`; pagination footer
next/previous requests, search resets the page, friendly load error; case
filters combine with search, reset the page and degrade when the lawyer
lookup fails; role dialog (owner/self disabled, no owner option,
confirmation, PUT body, re-fetch, PGRST202 dependency message, adapter
refuses `owner` without a request); reschedule (validation, PUT body,
terminal bookings, SLOT_TAKEN mapping); moderation (`user_id` stripped,
only changed fields, save disabled); enrichment (users/lawyers lookups,
no reviewer identity, skipped for empty/unsafe ids, denied lookup, chats
paging).

Results: `flutter test` **100/100** (70 existing + 30 new);
`flutter analyze` 1 pre-existing info (`api_service.dart:410`);
backend `node --test test/*.test.js` 517/517.

### 6c. Remaining UI gaps

- Dropdown lookups (case dialog categories/lawyers, lawyer dialog
  categories, case filter options) still load at most 100 options. A
  searchable picker like `ClientPicker` is the follow-up.
- G8: no trigger or RPC recalculates `lawyers.rating` after a moderation or
  delete. Needs a schema proposal.
- G10: chats keep the fixed 340 px list (not responsive).
- G12: Arabic/RTL is a separate phase (no localization or dependency change
  was made).
- G13: dashboard metrics unchanged.
- Notification broadcast was not added (no reviewed contract).
- Lawyer workspace bookings do not show client identity (RLS may hide
  client profiles from lawyers; not requested).

### 6d. Needs migration deployment or manual approval

Until **20261025140000–20261025144000** are reviewed and deployed:
- Role change, reschedule and review moderation (all 142000 RPCs) show the
  dependency message.
- Case create/edit (C1/C2) and the lawyers list and lawyer filter
  (`rpc_admin_lawyers_page`, 144000) fail.
- Reviews (`public_reviews` view) fail.
- Authenticated users UPDATE keeps failing with 42P17 (fixed by 140000).

The local `20261025122424` reconciliation migration still needs review.
Nothing was committed, pushed or deployed.

## 7. UI/UX redesign and mobile responsiveness (2026-10-26, local only, not committed)

UI-only pass. No backend, database, API, auth, permission or business-rule
changes; no features removed; no mock data added to the app.

### 7.1 Root cause: "sidebar missing / navigation broken on mobile"

- **Primary.** Below 900 px the shell used a `Drawer`, but choosing a
  destination called `AdminNav.select` without closing the drawer. The page
  changed *behind* the scrim, so the drawer kept covering the screen and
  navigation looked broken. The old widget test hid this with a manual
  `Navigator.pop`.
- **Secondary.**
  - The Logout tile used `Colors.redAccent` for both background and text, so
    it rendered as an unlabeled red bar.
  - The page body was a nested `Scaffold` inside the shell.
  - Several layouts were fixed-width and overflowed or squeezed on phones:
    - 180 px KPI cards;
    - 30 px chart axis, so labels wrapped ("76/0");
    - `ListTile` trailing rows that crushed titles to one letter per line;
    - plan grid cards overflowing by 2.8 and 29 px;
    - users table cut off;
    - fixed 340 px chat list.
- The deployed site returned 404, so device- or browser-specific causes
  could not be checked against production.

### 7.2 Navigation behaviour now

There is one `Scaffold` (`AppScaffold`) with a custom header and three
layouts.

| Width | Navigation |
|---|---|
| < 600 px | Header menu button opens a `Drawer` (min(304 px, width − 56)). Choosing an item closes the drawer, then navigates. Scrim tap, system back and Escape dismiss it. |
| 600–1023 px | Collapsed icon rail with tooltips; the header menu button also opens the labelled drawer. |
| ≥ 1024 px | Persistent 264 px sidebar with a brand block, grouped sections (Legal · Clients & scheduling · Billing · Communication), and a restrained active state (subtle fill, gold indicator, bold label). It also has hover and focus states and a collapse toggle to the rail. |

- **On every layout:**
  - a visible "Sign out";
  - the page title and an account menu (name, email, role, Sign out) in the
    header.
- **At 1366×768 the whole sidebar fits without scrolling.** On shorter
  screens the list scrolls.
- **The lawyer workspace** uses the same shell, ungrouped.

### 7.3 Design system

- **`lib/config/theme.dart`**
  - `AppSpacing`, `AppRadius` and `AppBreakpoints` tokens.
  - Neutral palette and sidebar colours.
  - Status colours darkened for AA contrast on white:
    - danger `#B42318`
    - success `#067647`
    - warning `#B54708`
    - secondary/info `#1D5FBF`
    - accent → text-safe gold `#A16207`
  - The brand navy `#002366` is kept.
  - A full Material 3 `ThemeData`: text hierarchy, flat bordered cards,
    outlined inputs (label, focus, error, disabled, prefix/suffix colours),
    all button types with hover/pressed/focus overlays, dialog, popup/menu,
    tooltip, snackbar, chip, data table, checkbox/radio/switch, slider,
    progress, date/time picker, drawer and scrollbar themes.
  - `AppTheme.destructiveButtonStyle`.
  - Existing constant names are kept, so every screen still compiles.
  - Roboto only; no new dependencies.
- **`lib/widgets/common.dart`**
  - `StatCard` (fluid width).
  - `ResponsiveGrid`.
  - `StatusBadge`; `StatusChip`/`PriorityChip` now show a dot or icon plus a
    text label, so state is never colour-only.
  - `LoadingView`, `EmptyState` (title, description, action) and
    `ErrorBanner` (title).
  - `SearchField` with a clear button.
  - `FilterDropdown` (labelled; the key sits on the inner `DropdownButton`).
  - `ListToolbar`: inline on wide screens; on compact, two filters per row
    and the primary action below.
  - `SectionCard`, `InlineMessage`.
  - `RecordTile`: badges move under the text on narrow rows.
  - `RecordAvatar`, `RowAction` (actions with tooltips; destructive actions
    in red).
- **`lib/widgets/pagination.dart`:** restyled bar with bordered pager
  buttons and a short summary below 400 px. Keys, texts and logic are
  unchanged.

### 7.4 Screens

- **Dashboard**
  - Responsive grid of 8 KPI cards (4/2 columns). Plans and wallet balance
    come from the existing stats payload.
  - Cards navigate to their screens.
  - Bar chart: nice axis steps, compact labels, reserved width sized to the
    longest label, tooltips.
  - Status breakdown with counts and shares derived from the same numbers.
  - The existing quick actions are kept.
  - No invented metrics; there is no recent-activity endpoint, so none is
    shown.
- **Lists** (Lawyers, Categories, Cases, Bookings, Reviews, Subscriptions,
  Notifications, lawyer workspace cases, bookings and availability):
  - `ListToolbar` and `RecordTile`;
  - tooltips added to edit/delete icons;
  - Notifications show a Read/Unread badge.
- **Users:** a card list below 720 px; otherwise a full-width table in a
  card, with avatar initials, role badges with icons, and the same actions
  and keys.
- **Plans:** content-height cards in a `ResponsiveGrid`, which fixes the
  overflow. The plan colour is shown as a thin accent strip.
- **Chats:** master/detail. Both panes appear at ≥ 760 px; below that, one
  pane at a time with a back button. The back button is also shown during
  loading, error and empty states.
- **Dialogs:** themed (16 px radius, 16 px mobile inset, consistent actions).
  The 8 destructive confirmations use the filled-red style. Fields,
  validators and submitted values are unchanged.
- **Login:** restyled. The error box is now `InlineMessage` with the same
  text, and the password-visibility button has a tooltip.

### 7.5 Verification

- **`flutter test`:** 116/116 pass (100 existing plus 16 new in
  `test/responsive_ui_test.dart`). The new tests cover:
  - each of 320, 375, 430, 768, 1024, 1366 and 1440 px: all 11 admin
    destinations reachable, the drawer closes after every choice, the header
    title matches, the menu button and persistent nav appear only where
    expected, and no overflow;
  - the collapse/expand rail;
  - mobile Sign out;
  - Escape dismissing the drawer;
  - dashboard KPIs at 320 px;
  - component tests for badges, `SearchField` clear, `ListToolbar` at
    320 px, `RecordTile` narrow/wide and `ResponsiveGrid`.
- **`widget_test.dart`:** the lawyer-drawer test's manual
  `Navigator.pop(...)` was replaced with
  `expect(find.byType(Drawer), findsNothing)`.
- **`flutter analyze`:** only the pre-existing info at
  `api_service.dart:410`.
- **Backend:** 517/517 (no backend files changed).
- **Visual verification** used flutter_test screenshots, not a real
  browser. `flutter build web` exhausts the 2 GB sandbox.
  - A temporary harness rendered the real `AdminApp` with fake API data and
    real Roboto/Material Icons fonts.
  - 21 scenarios produced 83 screenshots with no overflow exceptions:
    navigation at all 7 widths; all lists at 320/375/768/1366; dialogs at
    375/1366; error and empty states; lawyer workspace; login.
  - The harness was removed from the repo afterwards.

### 7.6 Remaining issues

- **Not tested in a real browser or device:** browser zoom, iOS Safari
  viewport quirks and real-mouse hover were not exercised.
- **Arrow glyph in role descriptions:** the existing "Lawyers → Edit"
  copy uses a "→" that the test font lacks; browsers fall back to another
  font.
- **No new sorting:** tables gained no sorting (none existed and the
  API/pagination contract is unchanged).
- **Earlier gaps still open:** dropdown lookups are capped at 100, rating
  recalculation (G8) and dashboard metric definitions (G13) are unchanged,
  and RTL was intentionally not added.
