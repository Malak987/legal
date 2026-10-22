# 🏛️ Legal Services App — Backend, Database & Admin Panel

This folder contains everything needed to run the Legal Services application with a
real database and an admin dashboard.

```
تطبيق/
├── legal_app/                 → The Flutter mobile app (connected to the API)
├── backend/                   → REST API server (Node.js + Express + Cloud Firestore)
└── admin_panel/               → Admin dashboard (Flutter Web)
```

---

## 1. Architecture

```
  Flutter Mobile App  ──┐
  (Firebase Auth)       │   Authorization: Bearer <Firebase ID Token>
                        ├──►  REST API (backend:5000)  ──►  Cloud Firestore
  Flutter Web Admin  ───┘
```

- **Firebase Authentication** — sign in / sign up for both the app and the admin panel.
- **Cloud Firestore** — the database (collections listed below).
- **Backend (Express)** — a REST API in front of Firestore that validates every request,
  enforces roles, and serves both clients.
- **Admin panel (Flutter Web)** — manages users, lawyers, cases, bookings, reviews,
  plans, notifications and chats.

---

## 2. Firestore collections

| Collection              | Purpose                                          |
|-------------------------|--------------------------------------------------|
| `users`                 | App users (client / lawyer / admin) with roles   |
| `lawyers`               | Lawyers & services (price, specialty, rating...)  |
| `cases`                 | Legal cases / matters                             |
| `tasks`                 | Case-related tasks with priority & status         |
| `bookings`              | Appointments (Pending / Active / Completed / Cancelled) |
| `reviews`               | Client reviews with ratings                       |
| `plans`                 | Subscription plans (Basic / Silver / Premium)     |
| `subscriptions`         | Active user subscriptions                         |
| `notifications`         | Notifications sent to users                       |
| `chats` (+`messages`)   | Conversations between users                       |
| `wallets`               | Wallet balances                                   |
| `wallet_transactions`   | Wallet credit/debit history                       |
| `earnings`              | Earnings overview per user                        |
| `availability`          | Lawyers' available slots by date                  |
| `favorites`             | Favorite lawyers per user                         |

---

## 3. Setup

### Step A — Firebase console

1. Create (or open) your Firebase project.
2. **Authentication** → Sign-in method → enable **Email/Password**.
3. **Firestore Database** → create in production mode.
4. **Project Settings → General → Your apps** → register a **Web app**.
5. **Project Settings → Service accounts** → **Generate new private key** and save the
   downloaded JSON.

### Step B — Backend

```powershell
cd backend
npm install
Copy-Item .env.example .env         # then edit if needed
# Put the downloaded service-account JSON here:
#   backend/serviceAccount.json
npm run seed                        # creates sample data + the admin account
npm start                           # http://localhost:5000
```

Check it is alive: <http://localhost:5000/api/health>

The seed creates the sample accounts (admin, client, lawyer). Their passwords
come from the environment and are never stored in this repository:

```powershell
$env:SEED_ADMIN_PASSWORD  = "<choose one>"
$env:SEED_CLIENT_PASSWORD = "<choose one>"
$env:SEED_LAWYER_PASSWORD = "<choose one>"
npm run seed
```

Each value must be at least 12 characters. If any of them is missing the seed
stops before writing anything and names the variables it needs. See
`backend/.env.example` for the variable names.

### Step C — Fill in the Firebase options

Two files contain placeholders — replace the values with your project's `firebaseConfig`:

| File                                                   | Used by          |
|--------------------------------------------------------|------------------|
| `backend/serviceAccount.json`                          | backend          |
| `admin_panel/lib/config/firebase_options.dart`         | admin panel      |
| `legal_app/lib/config/firebase_options.dart`            | mobile app      |

Both `firebase_options.dart` files must point to the **same** Firebase project.

### Step D — Run the admin panel

```powershell
cd admin_panel
flutter pub get
flutter run -d chrome
```

Sign in with `admin@legalapp.com` and the password you supplied in `SEED_ADMIN_PASSWORD`.

> If the admin panel's API base URL needs changing (e.g. deployed backend):
> `flutter run -d chrome --dart-define=API_BASE_URL=https://your-domain.com/api`

### Step E — Run the mobile app

```powershell
cd legal_app
flutter pub get
flutter run
```

The app picks a default base URL per platform, and `--dart-define=API_BASE_URL`
always overrides it:

| Target | Without `--dart-define` | Notes |
|--------|------------------------|-------|
| Android emulator | `http://10.0.2.2:5000/api` | `10.0.2.2` is the emulator's alias for your computer. `localhost` would be the emulated device itself. |
| Web (`flutter run -d chrome`), Linux/Windows/macOS desktop, iOS simulator | `http://localhost:5000/api` | The backend must be running on the same machine. |
| Physical Android/iOS device | **must** be set | No default can reach your computer; pass its LAN IP. |

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:5000/api
```

For a physical device the phone and the computer must be on the same network, the
backend must listen on `0.0.0.0` (not only `127.0.0.1`), and port 5000 must be
allowed through the firewall. The Android manifest already permits cleartext
HTTP for local development.

> Registration and sign-in need **real** Firebase options. `legal_app` currently
> ships working `android` values only; the `web` and `ios` blocks are still
> placeholders, so `Firebase.initializeApp` fails there and authentication
> reports "authentication is not configured for this build".

---

## 4. API reference

Base URL: `http://localhost:5000/api`
All protected routes require `Authorization: Bearer <Firebase ID Token>`.

### Public

| Method | Path                  | Description                |
|--------|-----------------------|----------------------------|
| GET    | `/health`             | Service status             |

### Lawyers

| Method | Path                  | Description                       |
|--------|-----------------------|-----------------------------------|
| GET    | `/lawyers`            | List (supports `search`, `isPopular`, `isTop`, paging) |
| GET    | `/lawyers/:id`        | Single lawyer                    |
| POST   | `/lawyers`            | Create *(admin/lawyer)*           |
| PUT    | `/lawyers/:id`        | Update *(admin/lawyer)*           |
| DELETE | `/lawyers/:id`        | Delete *(admin)*                  |

### Cases / Tasks / Bookings / Subscriptions

Standard CRUD under `/cases`, `/tasks`, `/bookings`, `/subscriptions`.
Non-admins can only access their own records.

### Registration and profiles

Registration is split in two so the password never reaches this backend:
the Firebase client SDK creates the Authentication account, then the app calls
the route below to create the matching Firestore document.

| Method | Path             | Description                                                        |
|--------|------------------|--------------------------------------------------------------------|
| POST   | `/users/me`      | Provision the caller's own `users/{uid}` profile. Authenticated. Body: `{ name, phone?, avatar?, address? }`. `uid` and `email` come from the verified ID token; `role` is always `client`. Answers `409` when a profile already exists. |

Roles are never granted here: an administrator promotes a user with
`PATCH /users/:id/role`.

#### Sign-up sequence (one flow, no password on the wire)

1. `createUserWithEmailAndPassword` on the Firebase **client** SDK. Firebase
   owns the credential and the uid; the password never leaves the device.
2. `POST /api/users/me` with the fresh ID token and `{ name }`. The backend
   writes `users/{uid}` with `role: 'client'`, taking the uid and the email from
   the verified token. A `role` or `email` sent in the body is stripped.
3. Only when both steps succeed does the app load the profile and show the Home
   screen. A failed registration never navigates to Home.

If step 2 fails, the app deletes **the account created by that attempt** so no
half-registered user is left behind (an Auth account without a profile cannot
hold a role and is invisible to the admin panel). The rollback is deliberately
scoped: a pre-existing account — created by hand in the Firebase console, or by
an earlier attempt — is never deleted.

Sign-in reuses the same provisioning route. When an account authenticates but
has no profile (a legacy or console-created user), the app calls
`POST /api/users/me` once with a name derived from the email, which yields an
ordinary `client` profile. An existing profile is never rewritten: the route
answers `409` and the stored document — including a `lawyer` or `admin` role —
is read back untouched.

#### Firebase Auth accounts vs `users/{uid}` profiles

These are two different things and the app treats them as such:

| | Firebase Authentication | Firestore `users/{uid}` |
|---|---|---|
| Created by | the client SDK on sign-up | `POST /api/users/me` |
| Holds | email, password hash, uid, disabled flag | `name`, `phone`, `address`, `avatar`, `role`, `email` |
| Joined by | the document id **is** the Auth uid | |
| Admin list shows | nothing | every profile document |

A signed-in Firebase user is therefore *not* automatically a client with a
profile, and the admin Users list only reflects provisioning. That is why the
app provisions before entering protected screens.

Trusted fields — writable by no client, whatever the app sends:

- `role` is set by the server (`client` on provisioning) and only changes via
  the admin-only `PATCH /users/:id/role`.
- `uid` is the verified token's uid; it is never read from a request body.
- `email` is taken from the token on provisioning; a non-admin change through
  `PUT /users/:id` is rejected.

The Flutter app never treats "authenticated" as "administrator": the only
admin signal it uses is a profile whose `role` is exactly `admin`, and no screen
was wired to admin-only backend routes in this phase.

### Users (admin)

| Method | Path                  | Description                                    |
|--------|-----------------------|------------------------------------------------|
| GET    | `/users`              | List (supports `search`, `role`, paging) *(admin)* |
| GET    | `/users/:id`          | Single profile *(self or admin)*               |
| PUT    | `/users/:id`          | Update profile; `role` is stripped *(self or admin)* |
| PATCH  | `/users/:id/role`     | `{ role }` *(admin)*                           |
| DELETE | `/users/:id`          | Delete profile + Auth account *(admin)*        |

### Wallet

| Method | Path                          | Description                     |
|--------|-------------------------------|---------------------------------|
| GET    | `/wallet/:userId`             | Balance + recent transactions   |
| POST   | `/wallet/transactions`        | `{ userId, type, amount, description }` |

### Chats / Notifications / Reviews / Plans / Availability / Favorites / Earnings

See `backend/src/routes/` — each file is a self-contained, documented router.

### Dashboard

| Method | Path               | Description                       |
|--------|--------------------|-----------------------------------|
| GET    | `/dashboard/stats` | Aggregate metrics *(admin only)*  |

---

## 5. Running the tests

**Backend** (Node's built-in runner, in-memory Firebase doubles — no project,
no credentials, no writes):

```bash
cd backend
npm ci
npm test
```

Single suite: `node --test test/profile_security.test.js`.

| Suite | Covers |
|-------|--------|
| `test/registration.test.js` | profile provisioning contract, duplicate/overwrite rules, admin-list visibility after provisioning |
| `test/profile_security.test.js` | role escalation attempts, malformed/legacy profile documents, admin-only routes, token-vs-body precedence |

**Flutter** (requires a Flutter SDK; there is no local SDK in the environment
this phase was developed in, so these run in CI only):

```bash
cd legal_app
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings   # compile gate
flutter test
dart format --output=none --show=changed lib test      # report only
```

The `Mobile app (analyze + test)` job in `.github/workflows/ci.yml` runs exactly
these on every push and pull request. Analysis is a *compile* gate: errors fail
the job, pre-existing info/warning lints are printed but do not. Formatting is
reported, never gated, because most of the app predates `dart format`.

| Test | Covers |
|------|--------|
| `test/api_client_test.dart` | base-URL selection, bearer header, envelope unwrapping, 401 refresh retry, non-JSON and error responses, provisioning 409 fallback, no `role` in update bodies |
| `test/auth_lifecycle_test.dart` | registration/provisioning/rollback scoping, legacy-profile provisioning, sign-in failures, session restoration, sign-out, routing gate |
| `test/widget_test.dart` | the auth boundary: no protected UI while resolving, auth flow when signed out, signed-in shell, sign-out |

All Flutter tests use fakes (`test/support/fakes.dart`) and a `MockClient`; they
never touch a live Firebase project.

---

## 6. Security notes

- Passwords are handled by Firebase Authentication (never stored in Firestore).
- The API verifies the ID token on every protected request and checks the user's role.
- Firestore should stay in **production mode** (rules locked down) since all access goes
  through the backend / authenticated clients.
- Change `ADMIN_JWT_SECRET`, and never deploy with a seed password you have used anywhere else.

---

## 7. Known limitations

Honest list of what this phase did **not** finish, so nothing here looks live
when it is not:

- **Firebase options**: only the Android block in `legal_app/lib/config/firebase_options.dart`
  holds real values. Web and iOS still have placeholders, so
  `Firebase.initializeApp` fails there and the app reports "authentication is
  not configured for this build". Sign-up/sign-in work on Android only.
- **Screens still showing sample data**: case status detail
  (`views/cases/casedashboard.dart`), lawyer detail (`views/home/details.dart`),
  edit-profile, address book, orders and most drawer destinations. The list
  screens for cases, favorites and lawyers now read the backend; the detail
  screens they open do not.
- **Writes left unwired**: creating cases/bookings/favorites from the UI is not
  connected. `AppRepository` already has the methods, but no screen calls them.
- **Bookings, wallet, chat, reviews, earnings** are out of scope for this phase.
- **Flutter verification**: no Flutter SDK is available in the development
  environment (the SDK download host is blocked), so `flutter analyze` and
  `flutter test` have never run locally. They are wired into CI
  (`.github/workflows/ci.yml`, job `legal-app`) and that is the first place the
  app's analysis and tests execute. The backend suite *was* run locally and
  passes.
- **No request-level retry/backoff**: `ApiClient` retries once after a forced
  token refresh (401) and gives every attempt a 20 s deadline, but a transient
  5xx is surfaced to the user rather than retried automatically.
- **A revoked session is reported, not force-ended.** If Firebase rejects a
  token even after a forced refresh, the screen shows the error; the app does
  not sign itself out automatically, because no flow has demonstrated that
  failure yet and an automatic sign-out on any 401 would also fire for
  authorization mistakes.
- **`PUT /users/:id` requires `name` and `email`** even for a partial update,
  because `userSchema` marks them required. The app sends both (the stored
  email unchanged); a future schema split would make partial updates natural.

---

## 8. Deploying

**Backend** — deploy anywhere that runs Node (Render, Railway, Fly.io, VPS). Set the
`SERVICE_ACCOUNT_PATH`, CORS origins, and `NODE_ENV=production`.

**Admin panel** — build for web and host the output on any static host:

```powershell
cd admin_panel
flutter build web --dart-define=API_BASE_URL=https://api.your-domain.com/api
# publish build/web
```

**Mobile app** — build with `flutter build apk` / `flutter build ipa`, passing the same
`--dart-define=API_BASE_URL`.