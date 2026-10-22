# Supabase PostgreSQL & Auth Migration Guide

## 1. Connected Supabase Project

- **Project Name:** `legal`
- **Project Ref:** `qqfzbecwhewswkyxgebu`
- **Project URL:** `https://qqfzbecwhewswkyxgebu.supabase.co`
- **Database Host:** `db.qqfzbecwhewswkyxgebu.supabase.co` (PostgreSQL 17)
- **Region:** `eu-west-1`

## 2. Version-Controlled Migrations

All schema definitions, constraints, indexes, triggers, Row Level Security (RLS) policies, and transactional RPC functions live in `supabase/migrations/`:

1. `20261022174110_initial_legal_schema_and_rls.sql`
   - Normalized PostgreSQL tables (`users`, `lawyers`, `cases`, `bookings`, `booking_slots`, `tasks`, `chats`, `chat_messages`, `reviews`, `favorites`, `wallets`, `wallet_transactions`, `wallet_idempotency`, `plans`, `subscriptions`, `notifications`, `earnings`, `availability`).
   - Primary keys, foreign keys, `CHECK` constraints, `UNIQUE` constraints (`(lawyer_id, date, slot)` on `booking_slots`, `(user_id, lawyer_id)` on `reviews` and `favorites`), and B-Tree/GIN indexes.
   - Automatic `updated_at` trigger (`public.set_updated_at()`) and Firebase-to-Supabase user identity linking trigger (`public.link_migrated_auth_user()`).
   - Server-side authorization helpers (`public.current_app_user_id()`, `public.current_app_user_role()`, `public.is_admin()`, `public.is_lawyer_or_admin()`) and explicit Row Level Security (RLS) policies on all 18 tables.
2. `20261022174313_transactional_rpc_functions.sql`
   - Server-only (`service_role`) ACID transactional functions:
     - `public.rpc_reserve_booking_slots`
     - `public.rpc_wallet_mutate`
     - `public.rpc_recalculate_lawyer_rating`

## 3. Firebase Auth User Migration & Password Reset Strategy

Firebase Authentication uses custom modified scrypt password hashes with project-specific signer keys and salt separators that **cannot** be assumed to import directly into Supabase Auth (`bcrypt`/`argon2`).

To preserve every user's identity (`uid`), foreign key ownership (`user_id`), and role (`client` | `lawyer` | `admin`) without data loss:

1. **Preserve `public.users.id` (`uid`) and `role`:**
   - Existing `users/{uid}` documents from Firestore are imported into `public.users` keeping their original `id` and `uid` (for example `client-001`, `lawyer-001`, or 28-character Firebase UIDs) and their server-side `role` (`client`, `lawyer`, `admin`).
   - All child tables (`cases`, `bookings`, `tasks`, `wallets`, `reviews`, `favorites`, `subscriptions`, `notifications`, `earnings`) reference `public.users(id)` and remain intact.
2. **Provision Supabase Auth Accounts & Link `auth_user_id`:**
   - Provision each migrated user in Supabase Auth (`auth.users`) by email via `supabase.auth.admin.createUser({ email, email_confirm: true, user_metadata: { name, legacy_uid: uid } })`.
   - The `AFTER INSERT ON auth.users` database trigger (`public.link_migrated_auth_user()`) and the backend's `verifyIdToken()` automatically link `public.users.auth_user_id = auth.users.id` where the confirmed email matches.
   - Both PostgreSQL RLS (`public.current_app_user_id()`) and the Express `authenticate` middleware resolve `auth.uid()` to `public.users.id`, so migrated users seamlessly access their historical cases, bookings, chats, and wallets.
3. **Password Reset Flow for Migrated Users:**
   - Trigger a password recovery email via Supabase Auth (`supabase.auth.resetPasswordForEmail(email)`) or distribute a one-time recovery link via `supabase.auth.admin.generateLink({ type: 'recovery', email })` so migrated users set a new password before their first Supabase sign-in.

## 4. Backup, Data Migration, Validation, and Rollback Procedure

### Step 1: Pre-Migration Backup (Required Before Migrating Real User Data)
```bash
# 1. Export Firestore collections to a timestamped GCS bucket
gcloud firestore export gs://<firebase-project>-backups/pre-supabase-$(date +%Y%m%d-%H%M%S)

# 2. Export Firebase Auth user metadata (UIDs, emails, display names)
npx firebase-tools auth:export backups/firebase-users-$(date +%Y%m%d).json --format=json

# 3. Dump current Supabase PostgreSQL schema & data before import
pg_dump --clean --if-exists --quote-all-identifiers \
  "postgresql://postgres:<password>@db.qqfzbecwhewswkyxgebu.supabase.co:5432/postgres" \
  > backups/supabase-pre-import-$(date +%Y%m%d).sql
```

### Step 2: Validation & Dry-Run Check
1. Verify record counts per collection (`users`, `lawyers`, `cases`, `bookings`, `booking_slots`, `tasks`, `chats`, `chat_messages`, `reviews`, `favorites`, `wallets`, `wallet_transactions`, `plans`, `subscriptions`, `notifications`, `earnings`, `availability`).
2. Verify sum of `wallets.balance` and `bookings.total_price` matches between the Firestore export and PostgreSQL tables.
3. Verify RLS policies (`relrowsecurity = true` on all 18 `public` tables).

### Step 3: Rollback Procedure
If any validation check fails during cutover:
1. Revert the backend runtime environment (`unset SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY`) and client `--dart-define=SUPABASE_ANON_KEY` flags so traffic immediately falls back to the untouched Firebase/Firestore configuration.
2. Restore the PostgreSQL snapshot if needed:
   ```bash
   psql "postgresql://postgres:<password>@db.qqfzbecwhewswkyxgebu.supabase.co:5432/postgres" \
     -f backups/supabase-pre-import-<timestamp>.sql
   ```
