# 🏛️ Legal Services App — Backend, Database & Admin Panel

This folder contains everything needed to run the Legal Services application with a
real database and an admin dashboard.

```
تطبيق/
├── LegalServicesApp-code/     → The Flutter mobile app (connected to the API)
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
| `LegalServicesApp-code/lib/config/firebase_options.dart` | mobile app    |

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
cd LegalServicesApp-code
flutter pub get
flutter run
```

The app defaults to `http://10.0.2.2:5000/api` (Android emulator). For a physical device
or another platform pass your computer's LAN IP:

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:5000/api
```

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

## 5. Security notes

- Passwords are handled by Firebase Authentication (never stored in Firestore).
- The API verifies the ID token on every protected request and checks the user's role.
- Firestore should stay in **production mode** (rules locked down) since all access goes
  through the backend / authenticated clients.
- Change `ADMIN_JWT_SECRET`, and never deploy with a seed password you have used anywhere else.

---

## 6. Deploying

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