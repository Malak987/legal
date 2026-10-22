# Legal Services Platform

A legal-services platform built on Firebase (`legal-102026`) with three parts:

| Part | Path | What it is |
|------|------|------------|
| Cloud API | `backend/` | Node.js 22 + Express REST API deployed on **Firebase Cloud Functions (Gen 2)** (`us-central1`) behind **Firebase Hosting** (`https://legal-102026.web.app/api`) |
| Admin console | `admin_panel/` | Flutter Web admin app deployed on **Firebase Hosting** (`https://legal-102026.web.app`) |
| Mobile app | `legal_app/` | Flutter client for clients and lawyers, talking directly to `https://legal-102026.web.app/api` |

Firebase Authentication owns credentials. Cloud Firestore owns data. **Every
business read and write goes through the API** — the mobile app has no Firestore
client dependency at all, and the admin console uses the Firestore SDK for
exactly one document (`users/{own uid}` to check its role). Neither the mobile
app nor the web admin console depends on a developer laptop running a local
Node.js server.

---

## 1. Architecture

```
legal_app (Android / iOS) ───────────┐
                                     │ HTTPS + Firebase ID token
                                     ▼
                         https://legal-102026.web.app/api/**
                                     │
                        Firebase Hosting Rewrite (`/api{,/**}`)
                                     │
                                     ▼
admin_panel (Flutter Web) ──► Cloud Functions Gen 2: `api` (us-central1, Node 22)
        │                            │ Managed Google Cloud ADC (no key file)
        │                            ▼
        └─ reads users/{own uid} ──► Cloud Firestore + Firebase Auth (`legal-102026`)
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

## 2. Data model: Firebase Authentication vs. `users/{uid}`

- **Firebase Authentication** holds the *credential*: email, password hash, `uid`.
- **Cloud Firestore `users/{uid}`** holds the *profile*: `name`, `email`, `phone`, `address`, `role`. The document ID is always the Firebase `uid`.

```
sign-up:  Firebase signUp ──► POST /api/users/me ──► users/{uid} (role: client)
                    │                    │
                    │                    └─ on failure: delete the account just created
                    └─ token carries uid + email; the body carries only `name`
```

Roles: **`client`, `lawyer`, `admin`**. Self-service registration always produces
`client`; `role` is stripped from every self-service payload. Promotion is
`PATCH /api/users/:id/role` (admin-only).

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
   npm test                        # 461 unit + contract tests, 0 failures
   cd ..
   ```
   > **No `serviceAccount.json` or `.env` is needed for deployment.** Cloud Functions Gen 2 uses Google Cloud's managed runtime service account automatically, and production CORS defaults to `https://legal-102026.web.app` and `https://legal-102026.firebaseapp.com`. If you later attach a custom domain to Firebase Hosting, copy `backend/functions-config/.env.example` to `backend/functions-config/.env.legal-102026` and add that domain to `CORS_ORIGINS`.

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

**Seeding safeguard:** `SEED_ON_START` is hard-disabled in Cloud Functions and in `NODE_ENV=production`. Never run `npm run seed` against production Firestore. For local emulator seeding only, `npm run seed` requires explicit >=12-character environment variables (`SEED_ADMIN_PASSWORD`, `SEED_CLIENT_PASSWORD`, `SEED_LAWYER_PASSWORD`) with no hardcoded defaults.

---

## 5. API Reference

All responses use `{ success, message, data }`. Lists use `{ items, total, page, limit, totalPages }` inside `data`. Protected routes require `Authorization: Bearer <Firebase ID token>`.

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
| POST | `/api/users/me` | Provisions caller's `users/{uid}` profile (`role: "client"`). **201** created, **409** already exists, **401** invalid/missing token |
| GET | `/api/users/:id` | Self or admin |
| PUT | `/api/users/:id` | Self or admin (`role`, `email`, `uid` protected against non-admin mutation) |
| GET | `/api/users` | Admin (`?role=&search=&page=&limit=`) |
| PATCH | `/api/users/:id/role` | Admin (`{ role: "client" \| "lawyer" \| "admin" }`) |
| DELETE | `/api/users/:id` | Admin |

### Authenticated Resources

Each of `cases`, `bookings`, `tasks`, `subscriptions` supports `GET /`, `GET /:id`, `POST /`, `PUT /:id`, `DELETE /:id` scoped to `req.user.uid` (or all records for `admin`). Additional routes cover `/api/favorites`, `/api/wallet`, `/api/chats` + `/api/chats/:id/messages`, `/api/notifications`, `/api/earnings`, `/api/dashboard/stats`, and `POST /api/reviews`.

---

## 6. Running the Tests

```bash
cd backend     && npm test                     # 461 unit + Cloud Functions contract tests
cd admin_panel && flutter analyze && flutter test && flutter build web
cd legal_app   && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test
```

---

## 7. Security Notes

- **Identity & Roles:** Verified exclusively via Firebase Admin `verifyIdToken()`; `role` is stripped from self-service payloads.
- **Firestore Rules (`firestore.rules`):** Client SDK can only read `users/{own uid}`; all business reads/writes go through the Cloud Functions Admin SDK.
- **Secrets Hygiene:** `.env*`, `functions-config/.env*`, and `serviceAccount*.json` are ignored in both `.gitignore` and `firebase.json` `functions[0].ignore`. Production Cloud Functions uses managed ADC credentials with zero private key files.

---

## 8. Known Limitations

- **Web and iOS Firebase options in `legal_app/lib/config/firebase_options.dart`** remain placeholders (Android is configured for `legal-102026`; run `flutterfire configure --project=legal-102026` before shipping iOS/web builds of `legal_app`).
- **AI screens in `legal_app`** require `--dart-define=GEMINI_API_KEY=...` (or a server-side proxy endpoint before public store release).
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
