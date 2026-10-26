# Legal Services — Admin Web Panel

Flutter Web administrative console for the Legal Services platform. The panel uses Supabase Auth and caller-JWT PostgREST/RPC operations; it has no dependency on the legacy Express API. Firebase Hosting is retained only as the static web host.

## Runtime architecture

- **Hosted UI:** Firebase Hosting (`admin_panel/build/web`). Its `/api` rewrite has been removed; the panel makes browser requests directly to the configured Supabase project.
- **Authentication:** Supabase Auth password sign-in, with the application role read from the trusted `public.users` mapping under RLS. Registration is not exposed. Accounts must be provisioned and assigned a role by a trusted operator.
- **Data access:** PostgREST queries use the caller's access token and database RLS. Operations that touch private lawyer-account links, administrative summaries, case assignments, booking states, and other privileged fields use narrow RPCs that verify the caller's stored role.
- **Client credentials:** The web bundle contains only the Supabase project URL and public anon/publishable key. Never provide a service-role/secret key to Flutter, browser code, or build variables.
- **Configuration:** `scripts/build_web.mjs` passes `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and optional `SUPABASE_AUTH_REDIRECT_URL` as Dart defines. The public anon/publishable key must be supplied by the build environment; it is not committed. Auth redirect URLs must be added to Supabase Auth's allow-list.

## Current workflow boundaries

- Admin users, lawyers, categories, plans, cases, bookings, subscriptions, notifications, reviews, chats, and dashboard data are read from Supabase with server-side filtering/pagination where supported and RLS enforcement.
- Lawyer link management, case assignment/status, booking state/rescheduling, review moderation, subscription cancellation, dashboard aggregation, and availability reads use authorized SQL RPCs.
- User email is managed by Supabase Auth; the panel does not directly edit it. Account deletion is disabled until a reviewed retention/deletion workflow exists.
- Paid subscription activation/expiry is not exposed as a manual admin action; it needs a verified payment-provider reconciliation flow.
- This repository currently has no deployed Edge Functions. No AI, payment, SMTP delivery, or private Storage workflow is claimed as deployed by this panel.

## Development and deployment

```bash
cd admin_panel
flutter pub get
flutter analyze
flutter test

# Local web run (replace the placeholder with the public anon/publishable key).
export SUPABASE_ANON_KEY='<public anon/publishable key>'
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://qqfzbecwhewswkyxgebu.supabase.co \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=SUPABASE_AUTH_REDIRECT_URL=https://your-host.example/auth/callback

# Build/deploy the static panel from repository root. Configure Auth redirect
# allow-list entries and verify applied SQL migrations before deployment.
cd ..
SUPABASE_ANON_KEY='<public anon/publishable key>' firebase deploy --only hosting --project legal-102026
```

CI builds with a non-production public placeholder when the repository variable is absent; configure `SUPABASE_ANON_KEY` to use a deployable web artifact. Flutter's browser bundle is public by design, so never place secrets in the public key variable.
