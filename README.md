# Legal Services Platform

> **Branch status (2026-10-24):** This repository retains the legacy Firebase/Firestore/Express services and deployment configuration; no cutover or production decommission was performed. The local backend now has a fail-closed lawyer-signup endpoint (disabled by default), verified owner-role compatibility, and assigned-lawyer case/booking read scopes; the admin panel has a separate read-only lawyer workspace. Most app data screens remain Express-backed. The read-only Supabase ledger has ten applied versions through `20261024123238`; identity/owner/lawyer access SQL remains proposal-only, mobile client signup remains disabled by default, and no hosted change/deployment/data transfer was made. Backend tests pass (514 tests / 123 suites); Flutter and hosted E2E remain unverified. See [`supabase/APP_INTEGRATION_AUDIT_2026-10-24.md`](supabase/APP_INTEGRATION_AUDIT_2026-10-24.md), [`supabase/MIGRATION_STATUS.md`](supabase/MIGRATION_STATUS.md), and [`supabase/IMPLEMENTATION_REPORT.md`](supabase/IMPLEMENTATION_REPORT.md) for detail.

A legal-services platform in an explicit Firebase-to-Supabase transition, with the legacy Firebase deployment configuration retained and Supabase-backed API flows being integrated:

| Part | Path | What it is |
|------|------|------------|
| Cloud API | `backend/` | Node.js 22 + Express REST API deployed on **Firebase Cloud Functions (Gen 2)** (`us-central1`) behind **Firebase Hosting** (`https://legal-102026.web.app/api`) |
| Admin console | `admin_panel/` | Flutter Web admin app deployed on **Firebase Hosting** (`https://legal-102026.web.app`) |
| Mobile app | `legal_app/` | Flutter client for clients and lawyers, talking directly to `https://legal-102026.web.app/api` |

The legacy Firebase Auth/Firestore path remains in the repository and is not
removed or represented as cut over. Current Supabase-backed routes authenticate
Supabase access tokens and use request-scoped PostgREST under RLS. This source
integration is incomplete and has not been deployed; verify each workflow and
target environment before relying on it. The Flutter applications continue to
use the API for business data rather than carrying a service-role credential.

---

## 1. Architecture

```
legal_app (Android / iOS) ───────────┐
                                     │ HTTPS + Supabase access token
                                     ▼
                         https://legal-102026.web.app/api/**
                                     │
                        Firebase Hosting Rewrite (`/api{,/**}`)
                                     │  (legacy deployment configuration retained)
                                     ▼
admin_panel (Flutter Web) ──► Cloud Functions Gen 2: `api` (us-central1, Node 22)
                                      │
                                      ├─ verifies Supabase Auth / application profile
                                      └─ request-scoped PostgREST ──► Supabase RLS/PostgreSQL

Legacy Firebase Auth/Firestore code and rules remain in the repository; this diagram
is not a claim that the hosted API or clients have completed a production cutover.
```

Single backend source of truth (no duplicated codebase):

- `backend/index.js` — Cloud Functions Gen 2 HTTPS export (`export const api = onRequest(..., app)` in `us-central1`).
- `backend/src/app.js` — Shared Express app (`createApp()`): proxy-aware rate limiter, dynamic CORS allowlist (`https://legal-102026.web.app` & `https://legal-102026.firebaseapp.com`), Cloud Functions pre-buffered `rawBody` / 2 MiB JSON handler, lightweight `/api/health` readiness endpoint, double-`/api/api/...` `404` guard, and API routers.
- `backend/src/index.js` — Optional standalone local dev HTTP entry point (`npm run dev`).
- `backend/src/config/firebase.js` — Initializes `firebase-admin` automatically via Google Cloud Application Default Credentials in Cloud Functions / Cloud Run / Emulators, with optional fallback to an untracked `backend/serviceAccount.json` for offline local standalone runs.
- `backend/src/routes/*.js` — Resource routers mounted under `/api` (Hosting rewrite) and `/` (direct `cloudfunctions.net` invocation).
- `backend/src/middleware/auth.js` — Firebase ID token verification and authorization helpers (`requireRole`, `requireSelfOrAdmin`, `ownerIdFor`, `isOwner`, `lockOwnerOnUpdate`).
- `firebase.json` & `.firebaserc` — Root Firebase configuration binding project `legal-102026`, `firestore.rules`, Cloud Functions Gen 2 (`source: "backend"`, `configDir: "backend/functions-config"`), Firebase Hosting (`public: "admin_panel/build/web"` with `/api{,/**}` -> `api` rewrite before SPA `** -> /index.html`), and local Firebase Emulator ports.

---

## 2. Identity and profile lifecycle during the transition

- The legacy Firebase Auth/Firestore path and deployment files remain present; they are not a promise that the Supabase migration or traffic cutover is complete.
- In the Supabase-backed API path, Supabase Auth verifies credentials and `public.users` is the intended application profile/role source for RLS. The live database still has an Auth-UUID fallback when no profile exists and an email-only legacy profile-link trigger; the current live behavior does **not** meet the intended fail-closed identity boundary.
- Local mobile code removes the public role selector, ignores client role metadata, closes sessions for missing/unknown/non-client profiles, and disables public client signup by default. The backend rejects a missing/unsupported profile role. These are source-only protections; the live Auth project still has signup enabled and the reviewed trigger/owner migration has not been applied.
- `POST /api/users/me` remains non-mutating. Sign-in email changes must use Supabase Auth's verified email-change flow; the ordinary profile route must not write `email`, role, UID, or Auth linkage fields.

Live roles are **`client`, `lawyer`, `admin`**; `owner` is not supported by the live role constraint and no owner was created. Do not convert existing `admin` accounts or allow public self-registration to grant `lawyer`, `admin`, or `owner`. The identity/owner/lawyer-access SQL and owner runbook are proposal-only in `supabase/proposals/`; role changes require a reviewed trusted process, not a client payload.

Collections: `users`, `lawyers`, `cases`, `bookings`, `bookingSlots`, `tasks`,
`chats` (+ `messages` subcollection), `reviews`, `favorites`, `wallet`,
`transactions`, `idempotency`, `plans`, `subscriptions`, `notifications`,
`availability`, `earnings`.

---

## 3. Production Deployment (Firebase Cloud Functions Gen 2 + Firebase Hosting)

### Step A — Prerequisites (Account & Billing Verification)

1. **Firebase / Google Cloud Blaze Plan**: Deploying Cloud Functions (2nd gen) requires the Firebase **Blaze (pay-as-you-go)** plan on project `legal-102026` so Google Cloud can enable **Cloud Functions API**, **Cloud Build API**, **Cloud Run Admin API**, and **Artifact Registry API**. Configure a budget alert in Google Cloud Billing if desired.
2. **Authenticate Firebase CLI** on your machine:
   ```bash
   npm install -g firebase-tools
   firebase login
   firebase projects:list          # confirm `legal-102026` is visible
   ```
3. **Install backend dependencies**:
   ```bash
   cd backend
   npm ci
   npm test                        # 514 tests across 123 suites, 0 failures (verified 2026-10-24)
   cd ..
   ```
   > No `serviceAccount.json` is needed for Cloud Functions Gen 2; Firebase supplies the Google runtime identity. The Supabase-backed API also requires runtime `SUPABASE_URL` and public `SUPABASE_ANON_KEY` values plus `SUPABASE_SERVICE_ROLE_KEY` stored as a Firebase Secret (declared by `backend/index.js`). Do not commit any secret or pass the service-role key to Flutter/web. The example configuration documents these names and optional CORS origins; they were not provisioned in this local-only compatibility change.

### Step B — Deploy Firestore Rules, Cloud Functions API, and Hosting

Run from the repository root (`/path/to/legal`):

```bash
# 1. Deploy Firestore security rules
firebase deploy --only firestore:rules --project legal-102026

# 2. Deploy the Express API as 2nd-gen Cloud Function `api` (us-central1, Node 22)
firebase deploy --only functions --project legal-102026

# 3. Build `admin_panel` web app (runs automatically via predeploy hook) & deploy Hosting + `/api/**` rewrite
firebase deploy --only hosting --project legal-102026
```

### Step C — Verify Live Deployment

```bash
# 1. Public health probe via Firebase Hosting rewrite (must return HTTP 200 JSON)
curl -i https://legal-102026.web.app/api/health

# 2. Double-prefix sanity check (must return HTTP 404 JSON)
curl -i https://legal-102026.web.app/api/api/health

# 3. Public data route check (must return HTTP 200 JSON envelope)
curl -sS https://legal-102026.web.app/api/lawyers | head -c 400

# 4. Protected route check without token (must return HTTP 401 JSON)
curl -i -X POST https://legal-102026.web.app/api/users/me \
  -H "Content-Type: application/json" \
  -d '{"name":"Test"}'
```

### Step D — Build Production Mobile App (`legal_app`)

Both `legal_app` and `admin_panel` already default to `https://legal-102026.web.app/api` out of the box — no `--dart-define` flag is needed unless pointing to a staging/custom domain:

```bash
cd legal_app
flutter pub get
flutter build apk --release
```

---

## 4. Local Development with Firebase Emulators

To develop offline without touching production Firestore or Auth:

```bash
# Terminal 1 (from repo root — starts Auth:9099, Firestore:8080, Functions:5001, Hosting:5000)
firebase emulators:start --project legal-102026 --only auth,firestore,functions,hosting

# Run automated end-to-end emulator tests
firebase emulators:exec --project legal-102026 --only auth,firestore,functions,hosting \
  "RUN_FIRESTORE_E2E=1 npm --prefix backend run test:emulator"
```

Point clients at the local emulator only when explicitly desired:

| Client | Local Emulator Command | Production Default (no flags needed) |
|--------|------------------------|--------------------------------------|
| Admin Web (`admin_panel`) | `flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:5000/api` | `https://legal-102026.web.app/api` |
| Mobile Android Emulator (`legal_app`) | `flutter run --dart-define=USE_LOCAL_EMULATOR=true` | `https://legal-102026.web.app/api` |
| Mobile iOS Simulator / Desktop (`legal_app`) | `flutter run --dart-define=USE_LOCAL_EMULATOR=true` | `https://legal-102026.web.app/api` |
| Custom API override | `flutter run --dart-define=API_BASE_URL=https://custom.example.com/api` | `https://legal-102026.web.app/api` |

**Synthetic test seed (Supabase only):** From `backend/`, `npm run seed:test` is for an isolated local Supabase stack only; it refuses `NODE_ENV=production`, requires `LEGAL_ALLOW_TEST_SEED=true`, and accepts only a loopback `SUPABASE_TEST_URL` plus the local stack's `SUPABASE_TEST_SERVICE_ROLE_KEY`. The seed uses synthetic records with `.invalid` email addresses, creates no Auth users or passwords, and is not the Firebase Emulator seeder. Never point it at a hosted project or use a production key. See [`supabase/README.md`](supabase/README.md#synthetic-local-seed) for the full guard contract.

---

## 5. API Reference

All responses use `{ success, message, data }`. Lists use `{ items, total, page, limit, totalPages }` inside `data`. Supabase-backed protected routes require `Authorization: Bearer <verified Supabase access token>`.

### Public

| Method | Path | Notes |
|--------|------|-------|
| GET | `/api/health` | Lightweight readiness probe (`{ success: true, status: "ok", timestamp }`) — exposes zero secrets or DB internals |
| GET | `/api/lawyers`, `/api/lawyers/:id` | `?search=&isPopular=&isTop=&page=&limit=` — searches name, specialty, location; sorted by rating |
| GET | `/api/availability`, `/api/availability/:id` | `?lawyerId=&page=&limit=` |
| GET | `/api/plans`, `/api/plans/:id` | Subscription plans |
| GET | `/api/reviews`, `/api/reviews/:id` | Author IDs stripped from public payload |

### Registration & Profiles

| Method | Path | Notes |
|--------|------|-------|
| POST | `/api/users/me` | Non-mutating compatibility endpoint; returns **409** because profile creation is managed by the confirmed Supabase Auth lifecycle; **401** for invalid/missing token |
| GET | `/api/users/me` | Reads the caller's linked profile; **404** until the Auth trigger provisions it |
| GET | `/api/users/:id` | Self or admin |
| PUT | `/api/users/:id` | Self or admin for editable profile fields; role/UID/Auth linkage are server-managed, and email changes require Supabase Auth's verified flow |
| GET | `/api/users` | Admin (`?role=&search=&page=&limit=`) |
| PATCH | `/api/users/:id/role` | Existing admin only (`{ role: "client" \| "lawyer" \| "admin" }`) |
| DELETE | `/api/users/:id` | Disabled with **403** pending an approved data-retention workflow |

### Authenticated Resources

The resource routes enforce field- and role-specific ownership rules; an administrator is not an automatic bypass for every operation. In particular, subscription creation remains Pending, paid activation/expiry and plan changes are unavailable without a verified billing workflow, and Active subscription history cannot be deleted even by an administrator. Other routes cover `/api/favorites`, `/api/wallet`, `/api/chats` + `/api/chats/:id/messages`, `/api/notifications`, `/api/earnings`, `/api/dashboard/stats`, and `POST /api/reviews`.

---

## 6. Running the Tests

```bash
cd backend     && npm test                     # verified locally after the deployment fix
cd admin_panel && flutter pub get && flutter analyze && flutter test
cd admin_panel && node scripts/build_web.mjs    # requires public SUPABASE_ANON_KEY in environment
cd legal_app   && flutter pub get && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test
```

---

## 7. Security Notes

- **Identity & Roles:** Firebase Admin verifies Firebase sessions on the legacy Express path. When configured, Supabase Auth issues the JWT used by RLS-protected PostgREST and authenticated Edge Functions; application roles remain server/database-authoritative.
- **Firestore Rules (`firestore.rules`):** These rules apply only to the legacy Firebase path. Supabase access is governed separately by versioned RLS, grants, and RPCs under `supabase/`.
- **Secrets Hygiene:** `.env*`, `functions-config/.env*`, and `serviceAccount*.json` are ignored by Git/Firebase packaging. The Supabase service-role key and AI provider key are server-only and must never enter Flutter builds. See `supabase/IMPLEMENTATION_REPORT.md` for current implementation/deployment status.

---

## 8. Known Limitations

- **Web and iOS Firebase options in `legal_app/lib/config/firebase_options.dart`** remain placeholders (Android is configured for `legal-102026`; run `flutterfire configure --project=legal-102026` before shipping iOS/web builds of `legal_app`).
- **AI screens in `legal_app`** use the authenticated Supabase `ai-assistant` Edge Function; the function must be deployed and configured with a server-side `GEMINI_API_KEY`. Flutter no longer reads or embeds a Gemini key. The current function/Storage implementation is local-only and has not been deployed or live-tested; see `supabase/IMPLEMENTATION_REPORT.md` before enabling the feature.
- **`LegalServicesAppDoc/`** is an unmaintained historical archive excluded from root Dart analysis via `analysis_options.yaml`.

---

## 9. Troubleshooting `flutter analyze` / Dart Analysis Server Crashes (Separate from Backend)

If `flutter analyze` or VS Code's Dart Analysis Server previously crashed on Linux, note that **this is purely a local Dart tooling/workspace issue and completely independent of backend hosting**:

1. **Repository causes (already fixed in git)**:
   - Removed the duplicate case-colliding directory `legal_app/lib/views/settings/Views/` (`Views/` vs `views/`), which caused infinite file-watcher invalidation loops when checked out onto case-insensitive `exfat`/`ntfs` drives mounted on Linux.
   - Fixed 62 over-deep relative imports (`../../../../consts/...`) across 18 files in `legal_app/lib/` that escaped outside `legal_app/lib/` into parent folders.
   - Purged `__MACOSX/` binary `._*.dart` AppleDouble files, `.DS_Store`, and `~$*.docx` lock files, and added root `analysis_options.yaml` so opening the monorepo root in an IDE does not scan the broken historical snapshot under `LegalServicesAppDoc/`.
2. **Local Fedora / Linux host cleanup after pulling**:
   - Move or clone the repo onto your native Linux `ext4`/`btrfs` home partition with an ASCII path (for example `~/projects/legal`) instead of an external `exfat`/`ntfs` mount path with spaces/non-ASCII segments.
   - Clear stale Dart Analysis Server caches once before re-opening VS Code:
     ```bash
     rm -rf ~/.dartServer
     cd ~/projects/legal/legal_app && flutter clean && flutter pub get
     cd ~/projects/legal/admin_panel && flutter clean && flutter pub get
     ```
