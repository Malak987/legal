# Legal Services Platform

**Current baseline:** `main` at `42e431ab60ab8846f4feeefeb11b684b5a5d45ef` (audited 2026-10-26). The fresh source/database comparison is in [`CURRENT_STATE_AUDIT_2026-10-26.md`](CURRENT_STATE_AUDIT_2026-10-26.md).

## Architecture

Supabase is the single source of truth for application identity and data: Supabase Auth, PostgreSQL/PostgREST, security-definer RPCs, RLS, and private Storage. The Flutter mobile app and Flutter Web admin panel use the same project, IDs, relationships, and authorization model. Neither client uses Firebase Auth or Firestore for application data, and neither contains a service-role credential.

| Component | Role | Data path |
|---|---|---|
| `legal_app/` | Flutter mobile client | Supabase Auth + caller-JWT PostgREST/RPC + private Storage; business operations in `lib/services/app_repository.dart` |
| `admin_panel/` | Flutter Web administration | Supabase Auth + caller-JWT table queries and admin-checked RPCs; screens use `lib/services/api_service.dart` |
| `supabase/migrations/` | Canonical schema history | Versioned SQL for tables, constraints, triggers, grants, RLS, Storage, and workflows |
| `supabase/functions/` | Edge Function source | AI and document-upload implementations; **none are currently deployed to the connected Supabase project** |
| `backend/` | Optional server/API compatibility layer | Express routes deployed through Firebase Cloud Functions Gen 2; verifies Supabase sessions and uses caller-scoped PostgREST where supported. Server-only credentials stay in the function runtime. Current Flutter clients do not call this API. |
| Root `firebase.json` / `.firebaserc` | Existing hosting/runtime configuration | Hosts the admin web bundle and describes the Cloud Functions deployment. Firebase client SDK/config is not needed by the Flutter apps. |

Firebase remains a hosting/runtime dependency for the optional Express API and admin web delivery; it is **not** a second data source. The old Firestore rules and emulator tests are legacy backend artifacts, not the access-control layer for the current apps. Never use a Firebase identity token in place of a Supabase access token.

### Authorization model

- Public catalogue reads are limited to explicitly granted lawyer/category/plan/review projections and published availability.
- Private records are protected by forced RLS and caller-JWT RPCs. Case ownership, lawyer assignments, appointments, conversations, notifications, wallet, and subscriptions are checked against the linked application profile.
- Administrator RPCs check the stored role in the database; client-supplied role claims are not authoritative.
- Payment activation is intentionally unavailable pending a verified provider webhook. A client cannot credit their own wallet. The legacy retail checkout screens are disconnected, and both payment-screen implementations explicitly disable card entry and success navigation.
- The private `legal-documents` bucket accepts PDFs up to 10 MiB. Upload/AI Edge Function source exists locally, but the functions are not deployed; do not treat document-AI workflows as live.

## Supabase setup

The connected project URL is `https://qqfzbecwhewswkyxgebu.supabase.co` (project ref `qqfzbecwhewswkyxgebu`, region `eu-west-1`). Use only its **public anon/publishable** key in Flutter. Never put a service-role/secret key in Dart defines, the web build, or source control.

Keep each app's public Supabase configuration in its own ignored `supabase.local.json` (`admin_panel/` and `legal_app/`). If a file is absent, create it without overwriting an existing local file: `[ -e supabase.local.json ] || cp supabase.local.example.json supabase.local.json`, then replace the example placeholder locally with the public anon/publishable key. Never use a service-role/secret key in Flutter.

The root VS Code Run profiles preflight the app-specific file and pass it via `--dart-define-from-file`. For terminal runs, use the validated app wrappers:

```bash
(cd admin_panel && node scripts/run_web.mjs)
(cd legal_app && dart run tool/supabase_flutter.dart run -d <android-device-id>)
```

Release builds must also use the validated wrappers:

```bash
(cd admin_panel && node scripts/build_web.mjs --no-wasm-dry-run)
(cd legal_app && dart run tool/supabase_flutter.dart build appbundle --release)
```

Plain `flutter run`/`flutter build` do not automatically read local JSON. Use the preflighted IDE profiles or validated wrappers; do not bypass them with raw Flutter commands, which can skip validation and inherit shell environment. Keep Admin and mobile local configs and callbacks separate—never copy an Admin redirect into mobile. Add `SUPABASE_AUTH_REDIRECT_URL` only after the exact platform callback is approved and allow-listed.

The public key is compiled into a Flutter Web bundle by design; it must be protected by database grants and RLS, not treated as a secret. `.env`/local defines are not production configuration. Keep server-only credentials in the trusted server/Edge Function secret store.

### Synthetic local test seed only

`backend/src/seed.js` is for an isolated local Supabase stack only. It refuses production, requires `LEGAL_ALLOW_TEST_SEED=true`, a loopback `SUPABASE_TEST_URL`, and `SUPABASE_TEST_SERVICE_ROLE_KEY`. It creates synthetic `.invalid` records and no Auth users/passwords. Never point it at this connected project or any hosted database.

### Authentication configuration requiring an operator decision

At the audit snapshot, email signup is enabled and requires confirmation, but Supabase Auth has a `localhost` site URL and an empty redirect allow-list. A production web URL and mobile deep-link scheme must be chosen and explicitly allow-listed before registration confirmation/password recovery can be verified. Do not add a broad wildcard or guess a mobile URI.

## Schema and migrations

`supabase/migrations/` is the only migration discovery path. The connected database records all 16 migrations through `20261025144000_admin_native_workflows`; the current repository versions match that ledger. No schema migration was needed for this audit, and no production migration or data mutation was performed. New changes must be additive, reviewed, and tested in an isolated database before deployment. Do not replay recorded migrations, seed the connected project, or drop/replace production data.

The bucket `legal-documents` is private. Do not weaken bucket policies or make legal files public to work around missing function deployment.

## Backend and deployment

The Express API is retained as a separate, optional server-side/compatibility layer. Firebase Hosting forwards `/api` and `/api/**` to the `api` Cloud Function before the SPA fallback; the current Flutter clients still call Supabase directly. The API verifies Supabase sessions and uses caller-scoped access where supported. Firebase Functions use Node 22; server-only Supabase credentials belong in Firebase Secret Manager/runtime configuration.

The `backend/` source and deployment files are not proof that the API is deployed. Deploy only through the reviewed Firebase project workflow after confirming runtime secrets and access. Admin Hosting builds require valid public Supabase compile-time configuration. No Firebase or Supabase deployment was performed by this audit.

## Tests

From the repository root:

```bash
(cd backend && npm ci && npm test && npm audit)
(cd admin_panel && flutter pub get && flutter analyze && flutter test && node --test scripts/*.test.mjs)
(cd legal_app && flutter pub get && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test)
```

The backend package targets Node 22. Flutter commands require the Flutter SDK. Current verified test results and environment limitations are recorded in the audit snapshot. Do not claim a production end-to-end workflow passed without testing it with authorized safe accounts.

## Known live limitations

- Supabase Auth redirects are not configured for production (see above).
- The connected database currently has no legal-category rows and no cases/bookings/availability records; no synthetic production seed was added.
- Supabase Edge Function list and custom secret list were empty at the snapshot. AI/document-upload screens therefore have source code but no deployed function endpoint. AI also needs an operator-provided `GEMINI_API_KEY`.
- No payment gateway/webhook is configured; paid subscription activation must remain disabled/pending. Legacy payment screens display an unavailable notice and do not collect card data or create a fake success state.
- `LegalServicesAppDoc/` is a historical duplicate app snapshot; it is not a build target and is excluded from root Dart analysis.
