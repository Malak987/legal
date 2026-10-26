# Legal Services — Admin Web Panel

Flutter Web administrative console for the Legal Services platform. The panel uses Supabase Auth and caller-JWT PostgREST/RPC operations; it has no dependency on the legacy Express API. Firebase Hosting is retained only as the static web host.

## Runtime architecture

- **Hosted UI:** Firebase Hosting (`admin_panel/build/web`). Its `/api` rewrite has been removed; the panel makes browser requests directly to the configured Supabase project.
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

Flutter web cannot read shell or hosting environment variables at runtime. The URL and **public** anon/publishable key must be passed as `--dart-define` values when the app is compiled. Pick one of the following:

```bash
cd admin_panel
flutter pub get

# A) Helper scripts (recommended): read SUPABASE_ANON_KEY from the shell or
#    from the git-ignored admin_panel/supabase.local.json.
cp supabase.local.example.json supabase.local.json   # then paste the public key
node scripts/run_web.mjs                              # flutter run -d chrome + defines
node scripts/build_web.mjs                            # release build -> build/web

# B) Plain Flutter commands
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://qqfzbecwhewswkyxgebu.supabase.co \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
flutter build web --release \
  --dart-define=SUPABASE_URL=https://qqfzbecwhewswkyxgebu.supabase.co \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"

# C) Flutter's own file option (also works from IDE launch configurations)
flutter run -d chrome --dart-define-from-file=supabase.local.json
```

Notes:

- `export SUPABASE_ANON_KEY=...` on its own does **nothing** for `flutter run`/`flutter build`. It only works through the scripts above or when you pass it as `--dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"`.
- Defines are compiled into the app. After you change one, quit `flutter run` and start it again. Hot restart does not apply new defines.
- IDE runs need the same defines. In VS Code, add `"toolArgs": ["--dart-define-from-file=supabase.local.json"]` to the launch configuration. In Android Studio, put the same flag under *Additional run args*.
- The key is printed only in redacted form (`sb_publishable_… (N chars)`). `build_web.mjs` confirms the compiled `main.dart.js` contains the configured values without printing them.
- Only the public anon/publishable key is allowed. Secret (`sb_secret_…`) and service-role keys are refused by both the scripts and the app.

### Checks and deployment

```bash
cd admin_panel
flutter analyze
flutter test
node --test scripts/*.test.mjs

# Deploy from the repository root. Firebase's predeploy hook runs
# scripts/build_web.mjs, which fails unless a valid public key is configured.
# Configure the Auth redirect allow-list and verify applied SQL migrations first.
cd ..
SUPABASE_ANON_KEY='<public anon/publishable key>' firebase deploy --only hosting --project legal-102026
```

### CI

Set the GitHub repository variable **`SUPABASE_ANON_KEY`** (Settings → Secrets and variables → Actions → Variables) to the project's public anon/publishable key. `SUPABASE_URL` and `SUPABASE_AUTH_REDIRECT_URL` are optional variables. If `SUPABASE_ANON_KEY` is missing, CI no longer substitutes a fake key. It compiles a key-less, non-deployable check into `build/web-compile-check` and adds a warning annotation. Invalid values (malformed URL, placeholder, secret key) fail the job. Flutter's browser bundle is public by design, so never place secrets in this variable.
