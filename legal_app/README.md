# Legal Services — Mobile App (`legal_app`)

Flutter mobile client for clients and lawyers, backed by Firebase Authentication and the deployed Cloud Functions Gen 2 API (`https://legal-102026.web.app/api`).

## API Configuration

`lib/services/api_client.dart` resolves the API base URL automatically:

1. Explicit override: `--dart-define=API_BASE_URL=...`
2. Opt-in local Firebase Emulator mode: `--dart-define=USE_LOCAL_EMULATOR=true` (`http://10.0.2.2:5000/api` on Android emulator, `http://localhost:5000/api` on iOS simulator / desktop)
3. **Default for all debug, profile, and release builds:** `https://legal-102026.web.app/api` (no laptop server required)

## Commands

```bash
cd legal_app
flutter pub get

# Static analysis & widget/unit tests
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test

# Run against deployed Firebase API (default)
flutter run

# Run against local Firebase Emulator Suite
flutter run --dart-define=USE_LOCAL_EMULATOR=true

# Build release Android APK
flutter build apk --release
```
