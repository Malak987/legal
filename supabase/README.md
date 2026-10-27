# Supabase — current project and migration guidance

This directory is the canonical Supabase CLI project. The live project was re-audited on 2026-10-26; see [`../CURRENT_STATE_AUDIT_2026-10-26.md`](../CURRENT_STATE_AUDIT_2026-10-26.md) for the evidence-backed app/workflow matrix and test limitations.

## Connected project snapshot

- Project `legal`, ref `qqfzbecwhewswkyxgebu`, region `eu-west-1`, PostgreSQL 17.11.
- Supabase DB/Auth/REST/Storage were reported healthy.
- Live migration history contains all 16 versions found under `supabase/migrations/`, through `20261025144000_admin_native_workflows`. The deployed `public_reviews` view and current admin RPCs are present. Older reports claiming versions 12–16 were pending are superseded.
- RLS is enabled and forced on all 19 public base tables inspected. Admin RPCs check roles in PostgreSQL; anonymous execution was not granted to the audited admin RPCs. The `legal-documents` bucket is private, PDF-only, and capped at 10 MiB.
- No production migrations, data changes, Auth configuration changes, or Storage changes were made during the fresh audit.

## Migration rules

- `supabase/migrations/` is the one migration discovery path. Do not create a second root `migrations/` directory.
- The 16 recorded migrations are already applied; do not edit/replay them to repair behavior. Add a new, forward-only migration for future schema changes.
- Never seed, reset, truncate, drop, or replace live data. Test additive SQL against an isolated local database/branch first, then take/verify a recoverable backup and follow the project change process.
- Archived SQL under `archive/` and proposed SQL under `proposals/` is not active migration input. Do not copy it into migrations without an explicit review.

Typical local commands (require Supabase CLI and Docker):

```bash
supabase start
supabase db reset          # local development stack only; never against production
supabase test db
```

Before a production deployment, compare the local migration list with the live ledger and inspect a dry-run diff. A local unit test is not proof of live authorization; test with separately provisioned, non-production users for client, lawyer, and administrator roles.

## Client keys and secrets

The Flutter apps use the public anon/publishable key with authenticated Supabase access tokens. A service-role/secret key must never be bundled into Flutter or a browser build. Server-only keys belong in the trusted backend/Edge Function secret store. No custom Supabase secrets or Edge Functions were listed during this audit. The source files under `supabase/functions/` are not deployed just because they are in Git.

## Current workflow boundaries

- Auth/profile: Supabase Auth identity maps to a database `users` profile; stored role and RLS are authoritative.
- Cases, bookings/availability, tasks, chat, reviews, notifications, subscriptions, and wallet use RLS and narrowly-scoped RPCs as documented in the migrations.
- Subscription creation is pending-only until a payment provider webhook can securely activate entitlements. The wallet RPC does not allow a user to credit their own balance.
- Legal-document Storage is private. AI and document-upload functions are not live until source is deployed and required provider/server configuration is supplied.
- Auth email confirmation is enabled, but the live Auth site URL is localhost and the redirect allow-list is empty. An operator must provide approved web and mobile return URLs before production registration and recovery can be verified. Do not use broad redirect wildcards.

## Local verification

The repository's backend tests apply/inspect migrations in an isolated test database where configured. Flutter tests exercise client contracts but use fake HTTP/Auth fixtures; they do not prove production access. Record the exact test and environment results rather than presenting source presence as deployment or integration evidence.
