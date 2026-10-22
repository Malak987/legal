# Legal Services — Admin Web Panel

Flutter Web administrative console for managing users, lawyers, cases, bookings, tasks, wallets, chats, reviews, subscriptions, notifications, availability, and earnings on Firebase project `legal-102026`.

## Production Architecture

- **Hosted UI:** `https://legal-102026.web.app` (Firebase Hosting, built from `admin_panel/build/web`)
- **Backend API:** `https://legal-102026.web.app/api` (rewritten by Firebase Hosting `/api{,/**}` to the 2nd-generation Cloud Function `api` in `us-central1`)
- **Default API config:** `lib/config/app_config.dart` (`AppConfig.apiBaseUrl` defaults to `https://legal-102026.web.app/api`)

## Development & Deployment Commands

```bash
# Install dependencies & run checks
cd admin_panel
flutter pub get
flutter analyze
flutter test

# Run locally against the deployed Firebase API (default — no local backend server required)
flutter run -d chrome

# Run locally against Firebase Emulator Suite (`firebase emulators:start` on port 5000)
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:5000/api

# Deploy Admin Web Panel + `/api/**` Hosting rewrites from repository root
cd ..
firebase deploy --only hosting --project legal-102026
```
