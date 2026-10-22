# legal_app — mobile client

Flutter client for clients and lawyers. See the repository
[README](../README.md) for architecture, the API, and the data model.

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000/api   # Android emulator
flutter analyze
flutter test
```

- `API_BASE_URL` overrides the default backend address; a physical device needs
  your LAN IP, and release builds need an **https** URL (cleartext HTTP is
  allowed in debug/profile manifests only).
- The AI screens require `--dart-define=GEMINI_API_KEY=...`; without it they
  report that the feature is not configured. No key is stored in this repository.
- Firebase is configured for Android only — the web and iOS entries in
  `lib/config/firebase_options.dart` are still placeholders.

Screens that still render sample data, and the rest of the current limitations,
are listed in the root README (§8).
