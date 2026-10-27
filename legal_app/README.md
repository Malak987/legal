# Legal Services — Mobile App (`legal_app`)

Flutter client for the Legal Services platform. It uses **Supabase** directly: Supabase Auth (password sign-in, refresh-token sessions, password recovery), PostgREST/RPC under RLS, and private Storage. AI/document-upload Edge Function source exists, but no Edge Functions are deployed to the connected project yet; those screens are not live. The client does not call the Express/Cloud Functions API and has no Firebase client SDK/configuration dependency.

## Supabase configuration (required)

The app needs two **public** values, compiled in as Dart defines:

| Define | Value |
|--------|-------|
| `SUPABASE_URL` | `https://qqfzbecwhewswkyxgebu.supabase.co` (default if omitted) |
| `SUPABASE_ANON_KEY` | The project's public **publishable** key (`sb_publishable_…`) or legacy **anon** key. No default. |
| `SUPABASE_AUTH_REDIRECT_URL` | Optional. Needed for password-recovery links; must be in the Supabase Auth redirect allow-list. |

`lib/config/supabase_client_config.dart` validates these values **once at startup**: presence, URL format (`https`; `http` only for localhost/`10.0.2.2`), public-key format, wrong-project legacy keys, and secret/service-role keys. The one validated config is shared by sign-in, session restoration and every data request. If it is invalid, the app shows a configuration screen that names the missing define and makes no network request.

**Never** use a `service_role` or `sb_secret_…` key in this app. The app and the helper both refuse it.

### Local config and normal development workflow

Use the ignored `legal_app/supabase.local.json`. Create it only when it is absent, so an existing local configuration is never overwritten:

```bash
cd legal_app
[ -e supabase.local.json ] || cp supabase.local.example.json supabase.local.json
```

Replace the example placeholder with the project's public anon/publishable key. The configured URL may use this project's documented default. Set `SUPABASE_AUTH_REDIRECT_URL` only when the mobile callback for this platform has been approved and allow-listed; do not copy the Admin callback blindly. Never put a service-role/secret key in this file; the helper rejects those field names without reading or printing their values because Flutter's `--dart-define-from-file` passes every field to the app.

The app's normal startup validates the compiled defines before creating Supabase clients. The validating helper additionally checks the local file before invoking Flutter, prints only a redacted key description, and removes `SUPABASE_SERVICE_ROLE_KEY` / `SUPABASE_SECRET_KEY` from Flutter's process environment.

**VS Code:** open the repository root, choose an Android device in the device selector, and press Run on **Legal App Android (local Supabase)**. The checked-in launch configuration passes `--dart-define-from-file=supabase.local.json`; its pre-launch task validates that exact file first. A second iOS profile is available on macOS/Xcode hosts.

**Android Studio/IntelliJ:** set the Flutter run configuration's working directory to `legal_app`, entry point to `lib/main.dart`, and Additional run args to `--dart-define-from-file=supabase.local.json`. Add a Before Launch External Tool running `dart run tool/supabase_flutter.dart validate --file-only` with working directory `legal_app`. Set `SUPABASE_SERVICE_ROLE_KEY` and `SUPABASE_SECRET_KEY` to empty values in the Flutter Run configuration's environment so parent-process secrets cannot be inherited. The preflight must complete before Flutter Run starts.

For terminal development, use the validated wrapper (replace the device ID with one shown by `flutter devices`):

```bash
cd legal_app
dart run tool/supabase_flutter.dart run -d <android-device-id>
```

A bare `flutter run` does **not** read `supabase.local.json`. Use the validated wrapper or preflighted IDE profiles rather than bypassing validation with raw Flutter commands. Defines are fixed at compile time; stop and relaunch after changing them because hot restart does not update them.

### Release builds

Run the same validating wrapper from `legal_app`:

```bash
# Android release APK
dart run tool/supabase_flutter.dart build apk --release

# Android Play Store bundle
dart run tool/supabase_flutter.dart build appbundle --release

# iOS IPA (macOS + Xcode only)
dart run tool/supabase_flutter.dart build ipa --release
```

The wrapper validates URL/key and project mismatch where detectable, injects the resolved values into that exact build, and fails before Flutter if the public key is missing, a placeholder, malformed, or secret/service-role. For an Xcode archive, first run `dart run tool/supabase_flutter.dart build ios --release --config-only`, then archive using the generated Flutter configuration. Never build release artifacts by invoking Gradle/Xcode directly without passing the validated Flutter defines.

The same local file may be used by Android and iOS for `SUPABASE_URL` and `SUPABASE_ANON_KEY`; platform-specific redirect URLs remain separate operator-approved values. The project URL and public key are compile-time client configuration, not secrets.

## Deliberately unavailable legacy screens

The active booking-history route is backed by the signed-in user's Supabase bookings. The separate `HistoryScreen` still contains unrelated sample places/caregivers and is not routed from active navigation. The old retail cart/checkout files are likewise disconnected from the app's primary routes. Both duplicate payment-screen implementations now show an explicit unavailable message, collect no card details, and cannot navigate to an order-success screen. No payment-provider/webhook reconciliation or paid booking creation is deployed; do not enable checkout until that server-verified flow exists.

## Checks

```bash
cd legal_app
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test            # no key needed; configuration tests use fake values
```

## CI

The `legal-app` CI job only analyzes and tests, so it needs no key and builds no artifact. Nothing can ship from it with a fabricated key. A future mobile build job must run `dart run tool/supabase_flutter.dart build …` with `SUPABASE_ANON_KEY` supplied from a repository variable. The helper fails on a missing, placeholder or secret key instead of building.
