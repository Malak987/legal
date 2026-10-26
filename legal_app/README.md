# Legal Services — Mobile App (`legal_app`)

Flutter client for the Legal Services platform. It uses **Supabase** directly: Supabase Auth (password sign-in, refresh-token sessions, password recovery), PostgREST/RPC under RLS, Storage, and the authenticated `ai-assistant` Edge Function. It does not call the legacy Express/Cloud Functions API. Firebase packages stay registered for plugin compatibility only and are not initialized.

## Supabase configuration (required)

The app needs two **public** values, compiled in as Dart defines:

| Define | Value |
|--------|-------|
| `SUPABASE_URL` | `https://qqfzbecwhewswkyxgebu.supabase.co` (default if omitted) |
| `SUPABASE_ANON_KEY` | The project's public **publishable** key (`sb_publishable_…`) or legacy **anon** key. No default. |
| `SUPABASE_AUTH_REDIRECT_URL` | Optional. Needed for password-recovery links; must be in the Supabase Auth redirect allow-list. |

`lib/config/supabase_client_config.dart` validates these values **once at startup**: presence, URL format (`https`; `http` only for localhost/`10.0.2.2`), public-key format, wrong-project legacy keys, and secret/service-role keys. The one validated config is shared by sign-in, session restoration and every data request. If it is invalid, the app shows a configuration screen that names the missing define and makes no network request.

**Never** use a `service_role` or `sb_secret_…` key in this app. The app and the helper both refuse it.

### Local defines file (recommended)

```bash
cd legal_app
cp supabase.local.example.json supabase.local.json   # git-ignored
# edit supabase.local.json and paste the PUBLIC key
```

Flutter reads this file natively with `--dart-define-from-file=supabase.local.json`. The helper `tool/supabase_flutter.dart` reads the same file, or the `SUPABASE_*` environment variables, validates the values with the app's own rules, then runs the exact `flutter` command with the defines. It prints the key only in redacted form.

### Why "configured" values can still be missing

- `String.fromEnvironment` sees **only** Dart defines given to the exact `flutter run`/`flutter build` command. Running `export SUPABASE_ANON_KEY=…` alone has no effect, unless you use the helper or pass `--dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"`.
- Defines are compiled in. After you change them, stop the app and run it again. Hot reload and hot restart do not apply them.
- IDE runs need the flag too. In VS Code, add `"toolArgs": ["--dart-define-from-file=supabase.local.json"]` to the launch configuration (`.vscode/` is git-ignored). In Android Studio, add it under *Run configuration → Additional run args*.
- Native builds started outside `flutter` do not receive new defines. `./gradlew assemble…` and archiving in Xcode reuse whatever the last `flutter` command wrote, so always build through `flutter build …` (see below).

## Run and build, per platform

| Target | Run (debug) | Release build |
|--------|-------------|---------------|
| Android (device/emulator) | `flutter run -d <device> --dart-define-from-file=supabase.local.json` | `flutter build apk --release --dart-define-from-file=supabase.local.json` or `flutter build appbundle --release --dart-define-from-file=supabase.local.json` |
| iOS (device/simulator, macOS host) | `flutter run -d <device> --dart-define-from-file=supabase.local.json` | `flutter build ipa --release --dart-define-from-file=supabase.local.json`. To archive in Xcode, first run `flutter build ios --release --config-only --dart-define-from-file=supabase.local.json` so `ios/Flutter/Generated.xcconfig` carries the defines. |
| Web | `flutter run -d chrome --dart-define-from-file=supabase.local.json` | `flutter build web --release --dart-define-from-file=supabase.local.json`. Hosting environment variables are not read; the values must be in the build. |

The same commands through the validating helper:

```bash
dart run tool/supabase_flutter.dart run -d <device>
dart run tool/supabase_flutter.dart build apk --release
dart run tool/supabase_flutter.dart build appbundle --release
dart run tool/supabase_flutter.dart build ipa --release
dart run tool/supabase_flutter.dart build web --release
```

Or pass the values explicitly:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://qqfzbecwhewswkyxgebu.supabase.co \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
```

Notes:

- **Local Supabase stack (debug only):** use `http://10.0.2.2:54321` from the Android emulator, or `http://127.0.0.1:54321` on the iOS simulator/web, with the local stack's anon key. Release Android builds block cleartext HTTP.
- **Desktop folders** (`linux/`, `macos/`, `windows/`) are Flutter template scaffolding and not supported targets. For example, the macOS sandbox entitlements do not grant outgoing network access.

## Checks

```bash
cd legal_app
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test            # no key needed; configuration tests use fake values
```

## CI

The `legal-app` CI job only analyzes and tests, so it needs no key and builds no artifact. Nothing can ship from it with a fabricated key. A future mobile build job must run `dart run tool/supabase_flutter.dart build …` with `SUPABASE_ANON_KEY` supplied from a repository variable. The helper fails on a missing, placeholder or secret key instead of building.
