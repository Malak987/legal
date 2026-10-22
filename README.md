# Legal Services Platform

A legal-services product with three parts:

| Part | Path | What it is |
|------|------|------------|
| API | `backend/` | Node.js + Express REST API over Firebase Firestore, authenticated with Firebase ID tokens |
| Admin console | `admin_panel/` | Flutter (web/desktop) admin app for users, lawyers, cases, bookings and the rest |
| Mobile app | `legal_app/` | Flutter client for clients and lawyers |

Firebase Authentication owns credentials. Firestore owns the data. **Every
business read and write goes through the API** — the mobile app has no Firestore
client dependency at all, and the admin console uses the Firestore SDK for
exactly one document (its own profile, to check its role). See section 7.

---

## 1. Architecture

```
legal_app (Flutter) ──┐
                      ├── HTTPS + Firebase ID token ──> backend (Express) ──> Firestore
admin_panel (Flutter) ┘                                   Firebase Admin SDK
        │
        └── Firestore SDK: reads ONLY users/{own uid} (role check) ──> Firestore
```

- `backend/src/index.js` — Express app: helmet, CORS allowlist, rate limit, routes, error handler.
- `backend/src/routes/*.js` — one router per resource, mounted under `/api`.
- `backend/src/middleware/auth.js` — token verification and the authorization helpers (`requireRole`, `requireSelfOrAdmin`, `ownerIdFor`, `isOwner`, `lockOwnerOnUpdate`).
- `backend/src/utils/validators.js` — Joi schemas; `validate(schema, body)` strips unknown keys, which is what makes `role`/`uid` injection impossible.
- `backend/src/utils/firestore.js` — the only module that touches collections (`listDocs`, `getDocById`, `createDoc`, `updateDoc`, `deleteDoc`).
- `legal_app/lib/state/session_controller.dart` — the single source of authentication truth for the mobile app (a `ChangeNotifier` behind `SessionScope`).
- `legal_app/lib/services/` — `api_client.dart` (transport), `auth_service.dart` (auth rules), `app_repository.dart` (collection reads/writes).

---

## 2. Data model: Firebase Authentication vs. `users/{uid}`

These are two different things and the distinction matters:

- **Firebase Authentication** holds the *credential*: email, password hash, uid.
  It is the only place a password exists.
- **Firestore `users/{uid}`** holds the *profile*: name, email, phone, address,
  `role`. The document id is always the Firebase uid.

An account can therefore authenticate and still have no profile (a uid created
by hand in the Firebase console, or by the old seed script). The app treats that
as recoverable rather than broken: `POST /api/users/me` creates the missing
document, with the uid and email taken from the **verified token**.

```
sign-up:  Firebase signUp ──► POST /api/users/me ──► users/{uid} (role: client)
                    │                    │
                    │                    └─ on failure: delete the account just created
                    └─ token carries uid + email; the body carries only `name`
```

Roles: **`client`, `lawyer`, `admin`** — three, no others. Self-service
registration always produces `client`; `role` is stripped from every
self-service payload, so a caller cannot promote themselves. Promotion is
`PATCH /api/users/:id/role`, admin-only.

Collections: `users`, `lawyers`, `cases`, `bookings`, `tasks`, `chats`
(+ `messages` subcollection), `reviews`, `favorites`, `wallet`,
`transactions`, `idempotency`, `plans`, `subscriptions`, `notifications`,
`availability`, `earnings`.

---

## 3. Setup

### Step A — Firebase project

1. Create the project, enable **Authentication → Email/Password**.
2. Create a **Firestore** database in **production mode**. Deploy the rules in
   `firestore.rules` (section 9) — do not run with test rules.
3. **Project settings → Service accounts → Generate new private key** and save
   the JSON as `backend/serviceAccount.json`. This file is a private key and is
   git-ignored. Never commit it, never paste it into an issue.
4. Register the Android app (`flutterfire configure`) for both Flutter apps.
   The committed `google-services.json` / `firebase_options.dart` files are
   project identifiers, not secrets, and are required for the build.

### Step B — Backend

```bash
cd backend
npm ci
cp .env.example .env          # then edit it
npm test                      # 451 tests, no Firebase project required
npm run dev                   # http://localhost:5000/api/health
```

The API needs nothing but the service account to start. There is no signing
secret to configure: authorization comes from the verified ID token plus the
`role` on the caller's profile document.

**Seeding (optional, never against production).** `npm run seed` creates demo
accounts and documents. It is *not* idempotent — every run adds another copy of
the demo data — and it refuses to start unless a password is supplied for each
account it creates:

```bash
SEED_ADMIN_PASSWORD=... SEED_CLIENT_PASSWORD=... SEED_LAWYER_PASSWORD=... npm run seed
```

Each value must be at least 12 characters and is never defaulted, printed or
committed; the variables are documented in `.env.example` and nowhere with a
value. `SEED_ON_START` stays `false`: turning it on re-seeds on every boot.

### Step C — Admin console

```bash
cd admin_panel
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:5000/api
```

The admin console refuses to continue unless the signed-in account's
`users/{uid}` document says `role: "admin"`.

### Step D — Mobile app

```bash
cd legal_app
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000/api
```

---

## 4. Choosing the API base URL

`ApiClient` resolves the base URL once, at compile time:

1. `--dart-define=API_BASE_URL=...` always wins.
2. Otherwise Android gets `http://10.0.2.2:5000/api` (the emulator's alias for
   the host machine's loopback).
3. Otherwise `http://localhost:5000/api`.

| Target | Command |
|--------|---------|
| Android emulator | `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000/api` |
| Physical Android device | `flutter run --dart-define=API_BASE_URL=http://<your-lan-ip>:5000/api` (backend must listen on `0.0.0.0`, port 5000 open) |
| Web / desktop / iOS simulator | `flutter run --dart-define=API_BASE_URL=http://localhost:5000/api` |

`localhost` inside an Android emulator is the *emulated device itself*, which is
why the emulator default is `10.0.2.2` and why a physical device needs the LAN
address.

**Cleartext HTTP is permitted only in debug and profile builds.** The release
manifest has no `usesCleartextTraffic`, so a release APK must point at an HTTPS
backend:

```bash
flutter build apk --dart-define=API_BASE_URL=https://api.example.com/api
```

---

## 5. API reference

All responses use `{ success, message, data }`. Lists use
`{ items, total, page, limit, totalPages }` inside `data`. Protected routes
require `Authorization: Bearer <Firebase ID token>`.

### Public

| Method | Path | Notes |
|--------|------|-------|
| GET | `/api/health` | Liveness |
| GET | `/api/lawyers` | `?search=&isPopular=&isTop=&page=&limit=` — searches name, specialty, location; sorted by rating |
| GET | `/api/lawyers/:id` | |
| GET | `/api/availability` | `?lawyerId=&page=&limit=` — one document per (lawyer, day), see [booking semantics](#8-booking-and-availability-semantics) |
| GET | `/api/availability/:id` | |
| GET | `/api/plans`, `/api/plans/:id` | Subscription plans |
| GET | `/api/reviews`, `/api/reviews/:id` | Author ids are stripped from the payload |

### Registration and profiles

| Method | Path | Notes |
|--------|------|-------|
| POST | `/api/users/me` | Provisions the caller's profile. `name` required (2–80 chars). uid and email come from the token; `role`/`uid` in the body are stripped. **201** created, **409** already exists (the existing document is never overwritten), **401** no/invalid token, unverified email allowed (this build has no verification flow) |
| GET | `/api/users/:id` | Self or admin |
| PUT | `/api/users/:id` | Self or admin. `name` + `email` required. Non-admins cannot change `email`, `role`, `uid` or `userId` |
| GET | `/api/users` | Admin. `?role=&search=&page=&limit=` |
| PATCH | `/api/users/:id/role` | Admin. Body `{ role: client\|lawyer\|admin }` |
| DELETE | `/api/users/:id` | Admin |

### Authenticated resources

Each of `cases`, `bookings`, `tasks`, `subscriptions` supports
`GET /`, `GET /:id`, `POST /`, `PUT /:id`, `DELETE /:id`. Non-admins are always
scoped to their own records; `userId` in a body cannot transfer ownership.

| Method | Path | Notes |
|--------|------|-------|
| GET | `/api/favorites/:userId`, POST `/api/favorites`, DELETE `/api/favorites/:id` | Self-scoped; the POST body has no `userId` — it comes from the token |
| GET | `/api/wallet/:userId` | Self or admin; balance + recent transactions |
| POST | `/api/wallet/transactions` | A user may **debit** their own wallet; only an admin may **credit** (there is no payment provider integration yet). Idempotent per `idempotencyKey` |
| GET/POST | `/api/chats` | `POST /api/chats/:id/messages`; participants only |
| GET | `/api/notifications/:userId` | Self or admin |
| GET/POST/PUT/DELETE | `/api/notifications` | Admin-only cross-user routes |
| GET | `/api/earnings/:userId` | Self or admin |
| GET | `/api/dashboard/stats` | Admin |
| POST | `/api/reviews` | One review per (author, lawyer); author comes from the token |

### Booking and availability semantics

An availability document is
`{ lawyerId, lawyerName, date: 'YYYY-MM-DD', slots: ['09:00', '10:30', ...] }`.
The collection is **not** enforced to one document per (lawyer, day): the
booking code reads every document for that pair and merges their slots, so
duplicates are harmless. A slot is a **start time only** — there is no end
time, no slot length and no timezone anywhere in the model, so `date` and
`time` are wall-clock values in the lawyer's local time and the server compares
them as strings. There is no past-date rule.

`POST /api/bookings` enforces, in this order:

1. the lawyer exists and has a numeric `priceValue` — otherwise **400**
   (`totalPrice` is computed as `priceValue × hours`, never taken from the
   body; an administrator may override it);
2. `date` is a real calendar date and `time` is a parseable clock time
   (`'09:00'`, `'9:00'`, `'9:00 am'` are accepted and stored as `HH:MM`);
3. `hours` is an integer from 1 to 12;
4. the (lawyer, date) pair has published availability — otherwise **400**;
5. the requested start is one of the advertised slots — otherwise **400**,
   with the offered slots in the message;
6. no blocking booking already covers the appointment. Every status blocks
   **except `Cancelled`**, which releases its slot (and `DELETE` releases too).
   `Completed` keeps its slot, because the appointment did happen.

An appointment occupies every advertised slot in `[start, start + hours)`.
Because the model has no closing time, a duration that runs past the last
published slot is accepted; the mobile UI is stricter and only offers a
duration while every hour it spans is published and free.

**Concurrency.** Firestore gives no phantom protection for queries, so a
"read the day, then write" check can be beaten by a second request. Instead each
(lawyer, day, slot) has a deterministic reservation document,
`bookingSlots/{sha256(lawyerId \0 date \0 minutes)}`, written **in the same
`db.runTransaction` as the booking**. Two requests for the same slot read the
same document, so at most one commits; the other gets **409**. A query-based
overlap check still runs inside the transaction as a backstop for legacy or
seeded bookings that predate the reservation documents. An administrator
rescheduling a booking (`PUT /api/bookings/:id`) re-reserves it in its own
transaction, ignoring its current locks and releasing the ones it no longer
needs.

Regression coverage lives in `backend/test/booking_availability.test.js`; the
atomicity test drives two `createReservedBooking` transactions in the same tick,
which is the only way to force the interleaving (see the notes in that file).

---

## 6. Running the tests

```bash
cd backend      && npm test                 # 451 tests, Node 22, in-memory Firestore double
cd admin_panel   && flutter analyze && flutter test
cd legal_app     && flutter analyze && flutter test
```

Backend tests never touch a real Firebase project: `backend/test/helpers/harness.js`
provides an in-memory Firestore double and a stubbed token verifier.

Notable suites:

| File | Covers |
|------|--------|
| `registration.test.js` | provisioning, 409 on duplicate, token-derived identity, no self-promotion |
| `profile_security.test.js` | role/uid injection, admin-only promotion, self-serve profile updates |
| `ownership.test.js`, `cases/…` | per-record ownership across resources |
| `chats_authorization.test.js`, `chats_identity.test.js` | participant-only access, identity spoofing |
| `wallet.test.js` | credits admin-only, insufficient funds, idempotency, currency |
| `legal_app/test/` | API client, auth lifecycle, session gate, search screen — all with fakes |

CI (`.github/workflows/ci.yml`) runs the backend suite, then `flutter analyze`
and `flutter test` for both Flutter apps. Analysis is a compile gate: errors
fail the job, pre-existing info/warning lints are printed but do not.

---

## 7. Security notes

**Identity.** `authenticate()` verifies the ID token with the Admin SDK and
takes `uid`/`email` from the *token*, not from the request. The profile document
is loaded for `role` and `name` only; fields of the document cannot override the
verified caller.

**Roles.** Server-assigned. `role` is stripped from provisioning and
self-service updates. `PATCH /users/:id/role` and `DELETE /users/:id` are
admin-only. The Flutter apps never infer admin rights from "signed in".

**Authorization.** Every collection route scopes reads and writes to
`req.user.uid` unless the caller is an admin; a record with no owner id counts
as *not owned*. Ownership cannot be transferred through an update.

**Firestore rules.** `firestore.rules` allows a signed-in account to read its
own `users/{uid}` document and denies everything else to the client SDK. That is
exactly the access the admin console needs; all other data is server-only. The
rules are **not deployed by this repository's CI** — see section 9.

**Secrets.**
- `backend/.env` and `backend/serviceAccount.json` are git-ignored.
- No private key or service account has ever been committed (verified across the
  full git history).
- The AI screens read `GEMINI_API_KEY` from `--dart-define`; a literal key used
  to be committed here and must be treated as compromised — see section 8.

**Android.** `INTERNET` is declared in both apps' main manifests. Cleartext
traffic is debug/profile only.

---

## 8. Known limitations

Honest list. Nothing below is a working feature.

- **Web and iOS Firebase options are placeholders.** `firebase_options.dart`
  has real values for Android only, so `Firebase.initializeApp` fails on web/iOS
  and the app reports "authentication is not configured for this build".
  Registration and sign-in are Android-only today.
- **No physical-device run.** All verification of the Flutter code in this
  repository is static analysis and unit/widget tests. Nobody has signed up,
  navigated and signed out on a real device as part of this work.
- **AI features need a key.** `GEMINI_API_KEY` must be supplied at build time
  (`--dart-define=GEMINI_API_KEY=...`); without it the three AI screens report
  that they are not configured. A key compiled into a client binary can always
  be extracted — for production, proxy these calls through the backend. A
  literal key was previously committed in
  `views/chatbot/chatbot.dart`, `views/aidocumentsreview/aireview.dart` and
  `views/aicasepredictiontool/aicaseprditionaitool.dart`; it has been removed
  from the code but remains in git history, so **it must be revoked** in the
  Google Cloud console.
- **Screens still showing sample data**: case detail
  (`views/cases/casedashboard.dart`), lawyer detail (`views/home/details.dart`),
  the cart/order-history screens (`views/cartscreen/`, `views/order/`,
  `views/profile/past_orders.dart`), the address book, wallet/top-up,
  subscriptions, reviews, chat and settings. The lists that read the API today
  are cases, favourites, popular lawyers, top lawyers, search and the profile.
  Bookings exist in the API and are created by the availability screen
  (`views/availablitycalendar/`); the history list (`views/order/`) still shows
  sample rows.
- **`LegalServicesAppDoc/`** is a duplicate export of an older copy of the app
  kept for documentation. It is not built and is not maintained.
- **Wallet top-ups are not real**: crediting requires an administrator, because
  there is no payment provider webhook to prove money arrived.
- **Firestore rules are written but not deployed** (section 9).
- **No composite indexes** are required: every query that would need one was
  written to filter on a single field and sort in memory (see the comments in
  `routes/chats.js` and `routes/wallet.js`). `firestore.indexes.json` is
  therefore empty on purpose.

---

## 9. Deployment

Backend (any Node 22 host):

```bash
cd backend
npm ci --omit=dev
NODE_ENV=production \
SERVICE_ACCOUNT_PATH=/etc/legal/serviceAccount.json \
CORS_ORIGINS=https://admin.example.com \
npm start
```

In production the API returns generic 5xx messages, requires the CORS allowlist
(explicitly configured origins only) and never logs token contents.

Firestore rules:

```bash
firebase deploy --only firestore:rules      # from the repository root
```

`firebase.json` at the repository root points at `firestore.rules` and
`firestore.indexes.json`. Deploying indexes *synchronises* them, which removes
indexes that are not listed; the file is empty because no composite index is
needed, so read it before running `--only firestore:indexes`.

Android release build:

```bash
cd legal_app
flutter build apk --release --dart-define=API_BASE_URL=https://api.example.com/api
```

The release manifest does not permit cleartext HTTP, so a `http://` URL will
fail at runtime by design.
