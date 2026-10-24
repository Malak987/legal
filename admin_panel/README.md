# Legal Services — Admin Web Panel

Flutter Web administrative console for the Legal Services platform. Firebase Hosting and the Firebase Functions deployment path remain in place; the panel uses Supabase Auth and the Express API for its current data flows.

## Production Architecture

- **Hosted UI:** `https://legal-102026.web.app` (Firebase Hosting, built from `admin_panel/build/web`)
- **Backend API:** same-origin `/api` (Firebase Hosting rewrites `/api{,/**}` to the 2nd-generation Cloud Function `api` in `us-central1`)
- **Supabase Auth:** `SUPABASE_URL` plus the public `SUPABASE_ANON_KEY`; the service-role key must never be passed to Flutter or browser code.
- **Web build:** `scripts/build_web.mjs` passes `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `API_BASE_URL` (defaults to `/api`), and optional `SUPABASE_AUTH_REDIRECT_URL` as Dart defines. Firebase Hosting predeploy and CI use this script. The anon key must be supplied through the build environment; it is not committed.
- For GitHub Actions, configure repository variable `SUPABASE_ANON_KEY` with the public anon/publishable key. `SUPABASE_URL`, `API_BASE_URL`, and `SUPABASE_AUTH_REDIRECT_URL` may also be supplied as variables. The build defaults the URL to the configured project and API path to `/api`. No service-role key is read or forwarded.

## Development & Deployment Commands

```bash
# Install dependencies & run checks
cd admin_panel
flutter pub get
flutter analyze
flutter test

# Run locally against Firebase Hosting + Functions emulators (Hosting on port 5000).
# Replace the placeholder with the public anon/publishable key for an isolated test project.
export SUPABASE_ANON_KEY='<public anon/publishable key>'
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://qqfzbecwhewswkyxgebu.supabase.co \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=API_BASE_URL=http://127.0.0.1:5000/api

# Build/deploy from repository root; Firebase predeploy invokes the configured build script.
# Supply SUPABASE_ANON_KEY in the environment; do not use a service-role key.
cd ..
firebase deploy --only hosting --project legal-102026
```
