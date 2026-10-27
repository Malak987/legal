# Legal Services — Admin Web Panel

Flutter Web administrative console for the Legal Services platform. The panel uses Supabase Auth and caller-JWT PostgREST/RPC operations; its UI calls Supabase directly rather than the legacy Express API. Firebase Hosting serves the static web app. The root VS Code launch profile prevalidates the ignored local Supabase file and passes it to Flutter; ordinary `flutter run` does not load that file automatically.

## Runtime architecture

- **Hosted UI:** Firebase Hosting serves the static bundle from `admin_panel/build/web`. The Admin UI's Auth and data requests go directly to the configured Supabase project.
- **Authentication:** Supabase Auth password sign-in, with the application role read from the trusted `public.users` mapping under RLS. Registration is not exposed. Accounts must be provisioned and assigned a role by a trusted operator.
- **Data access:** PostgREST queries use the caller's access token and database RLS. Operations that touch private lawyer-account links, administrative summaries, case assignments, booking states, and other privileged fields use narrow RPCs that verify the caller's stored role.
- **Client credentials:** The web bundle contains only the Supabase project URL and public anon/publishable key. Never provide a service-role/secret key to Flutter, browser code, or build variables.
- **Configuration:** Supabase settings are compile-time Dart defines only — `SUPABASE_URL`, `SUPABASE_ANON_KEY` (public anon/publishable key), and optional `SUPABASE_AUTH_REDIRECT_URL`. `lib/config/supabase_config.dart` validates them once at startup (presence, URL format, public-key format, secret-key rejection) and the single validated config is shared by sign-in, session restore and all data requests. An invalid build shows a configuration screen instead of the login form. The key is never committed. Auth redirect URLs must be added to Supabase Auth's allow-list.

## Current workflow boundaries

- Admin users, lawyers, categories, plans, cases, bookings, subscriptions, notifications, reviews, chats, and dashboard data are read from Supabase with server-side filtering/pagination where supported and RLS enforcement.
- Lawyer link management, case assignment/status, booking state/rescheduling, review moderation, subscription cancellation, dashboard aggregation, and availability reads use authorized SQL RPCs.
- User email is managed by Supabase Auth; the panel does not directly edit it. Account deletion is disabled until a reviewed retention/deletion workflow exists.
- Paid subscription activation/expiry is not exposed as a manual admin action; it needs a verified payment-provider reconciliation flow.
- This repository currently has no deployed Edge Functions. No AI, payment, SMTP delivery, or private Storage workflow is claimed as deployed by this panel.

## Development and deployment

### Supabase configuration (required)

The Flutter app sees only compile-time Dart defines. It does **not** read the shell or Hosting environment at runtime, and plain `flutter run` does not load a JSON file unless that file is explicitly passed to Flutter.

Keep local values in the ignored `admin_panel/supabase.local.json`. If it does not exist, copy the example without overwriting an existing file:

```bash
cd admin_panel
[ -e supabase.local.json ] || cp supabase.local.example.json supabase.local.json
```

Edit that local file with `SUPABASE_URL` and the real public `SUPABASE_ANON_KEY`. The example key is a placeholder and must be replaced. Add `SUPABASE_AUTH_REDIRECT_URL` only after its exact callback URL is approved and allow-listed in Supabase Auth. Never put a service-role/secret key in the file. The preflight also rejects server-only Supabase field names, without reading or printing their values, because IDE `--dart-define-from-file` passes every field to Flutter.

### Normal Run / Debug

Open the repository root in VS Code and select **Admin Web (local Supabase)** in Run and Debug. Its pre-launch task validates `admin_panel/supabase.local.json` without printing the key, then Flutter Web receives the same file through `--dart-define-from-file`.

From a terminal, the equivalent validated run command is:

```bash
cd admin_panel
node scripts/run_web.mjs
```

In Android Studio/IntelliJ, set the Flutter run configuration's working directory to `admin_panel`, entry point to `lib/main.dart`, and **Additional run args** to `--dart-define-from-file=supabase.local.json`. Add a Before Launch external tool that runs `node scripts/validate_supabase_config.mjs --file-only` with working directory `admin_panel`. Set `SUPABASE_SERVICE_ROLE_KEY` and `SUPABASE_SECRET_KEY` to empty values in the Flutter Run configuration's environment so parent-process secrets cannot be inherited.

Use the configured IDE profiles or validated wrapper as the supported entry points; do not bypass their preflight with a raw `flutter run`. A bare `flutter run -d chrome` cannot see `supabase.local.json`. Fully stop and relaunch after changing defines; hot restart does not rebuild them.

### Release build

```bash
cd admin_panel
node scripts/build_web.mjs --no-wasm-dry-run
```

The script resolves environment values first and then the ignored local file, validates the URL/public key before invoking Flutter, filters server-only environment variables, and verifies the output bundle without printing the key. It writes the normal release output to `build/web`. Never use `--allow-unconfigured-compile-check` for a release; the keyless compile-check output is not deployable.

### Checks and Hosting deployment

```bash
cd admin_panel
flutter analyze
flutter test
node --test scripts/*.test.mjs
```

After a separately approved Hosting deployment and after the Firebase configuration is aligned to the confirmed project/site, the explicit project command is `firebase deploy --only hosting --project legal-dashboard-1`. Do not rely on the current default alias until it is corrected; no deployment is implied by this documentation.

### CI

Set the GitHub repository variable **`SUPABASE_ANON_KEY`** (Settings → Secrets and variables → Actions → Variables) to the project's public anon/publishable key. `SUPABASE_URL` and `SUPABASE_AUTH_REDIRECT_URL` are optional variables. If `SUPABASE_ANON_KEY` is missing, CI no longer substitutes a fake key. It compiles a key-less, non-deployable check into `build/web-compile-check` and adds a warning annotation. Invalid values (malformed URL, placeholder, secret key) fail the job. Flutter's browser bundle is public by design, so never place secrets in this variable.
