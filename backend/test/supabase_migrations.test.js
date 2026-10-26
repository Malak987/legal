import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { after, before, describe, it } from 'node:test';
import { PGlite } from '@electric-sql/pglite';

const testDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(testDir, '../..');
const migrationsDir = path.join(repoRoot, 'supabase', 'migrations');
const archivedCandidatesDir = path.join(repoRoot, 'supabase', 'archive', 'unapplied_candidates');
const categoryMigrationFile = '20261024102004_legal_categories_and_assignments.sql';
const archivedCandidateFiles = [
  '20261023100000_harden_rls_auth_and_storage.sql',
  '20261023101500_authenticated_transactional_rpcs.sql',
];
const ids = {
  client: '00000000-0000-4000-8000-000000000001',
  otherClient: '00000000-0000-4000-8000-000000000002',
  lawyer: '00000000-0000-4000-8000-000000000003',
  admin: '00000000-0000-4000-8000-000000000004',
  unconfirmed: '00000000-0000-4000-8000-000000000005',
  linkedLegacyAuth: '00000000-0000-4000-8000-000000000006',
  emailOnlyAuth: '00000000-0000-4000-8000-000000000007',
  otherLawyer: '00000000-0000-4000-8000-000000000008',
  noProfileAuth: '00000000-0000-4000-8000-000000000009',
  badMappingAuth: '00000000-0000-4000-8000-000000000010',
};

let db;
let caseId;
let unassignedCaseId;
let taskId;
let planId;
let notificationId;

const bootstrapSql = `
  CREATE ROLE anon;
  CREATE ROLE authenticated;
  CREATE ROLE service_role BYPASSRLS;

  CREATE SCHEMA auth;
  CREATE SCHEMA extensions;
  -- Test-only pgcrypto stand-in. It deliberately is not SHA-256; the migration
  -- test verifies byte canonicalization and use of the digest interface, while
  -- the exact algorithm is reserved for real PostgreSQL 17 staging checks.
  CREATE FUNCTION extensions.digest(p_value bytea, p_algorithm text)
  RETURNS bytea
  LANGUAGE sql IMMUTABLE
  AS $$
    SELECT decode(
      md5(encode(p_value, 'hex')) || md5(p_algorithm || encode(p_value, 'hex')),
      'hex'
    )
  $$;
  CREATE TABLE auth.users (
    id uuid PRIMARY KEY,
    email text,
    email_confirmed_at timestamptz,
    phone text,
    phone_confirmed_at timestamptz,
    raw_user_meta_data jsonb NOT NULL DEFAULT '{}'::jsonb,
    raw_app_meta_data jsonb NOT NULL DEFAULT '{}'::jsonb
  );
  CREATE FUNCTION auth.uid() RETURNS uuid
  LANGUAGE sql STABLE
  AS $$ SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  CREATE FUNCTION auth.role() RETURNS text
  LANGUAGE sql STABLE
  AS $$ SELECT nullif(current_setting('request.jwt.claim.role', true), '') $$;
  GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;
  GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated, service_role;
  GRANT EXECUTE ON FUNCTION auth.role() TO anon, authenticated, service_role;

  -- Minimal Supabase Storage catalog for exercising the shipped bucket
  -- policies. Production Storage owns these relations and the foldername helper.
  CREATE SCHEMA storage;
  CREATE TABLE storage.buckets (
    id text PRIMARY KEY,
    name text NOT NULL,
    public boolean NOT NULL DEFAULT false,
    file_size_limit bigint,
    allowed_mime_types text[]
  );
  CREATE TABLE storage.objects (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    bucket_id text NOT NULL,
    name text NOT NULL,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb
  );
  CREATE TABLE storage.buckets_analytics (id text PRIMARY KEY);
  ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
  CREATE FUNCTION storage.foldername(text) RETURNS text[]
  LANGUAGE sql IMMUTABLE
  AS $$
    SELECT CASE
      WHEN position('/' in $1) > 0
        THEN string_to_array(regexp_replace($1, '/[^/]*$', ''), '/')
      ELSE ARRAY[]::text[]
    END
  $$;
  GRANT USAGE ON SCHEMA storage TO anon, authenticated, service_role;
  GRANT SELECT, INSERT, UPDATE, DELETE ON storage.objects TO authenticated, service_role;
  GRANT SELECT ON storage.buckets TO anon, authenticated, service_role;
`;

async function migrationFiles() {
  return (await readdir(migrationsDir))
    .filter((file) => file.endsWith('.sql'))
    .sort();
}

async function applyMigrations(targetDb, files, directory = migrationsDir) {
  for (const file of files) {
    let sql = await readFile(path.join(directory, file), 'utf8');
    // PGlite does not bundle contrib/pgcrypto. gen_random_uuid is a core
    // PostgreSQL function in the project's PG17 target and remains available.
    sql = sql.replace(
      /CREATE EXTENSION IF NOT EXISTS pgcrypto\s*;/i,
      '-- skipped by PGlite: gen_random_uuid is built into PostgreSQL 13+',
    );
    await targetDb.exec(sql);
  }
}

async function simulateLegacyBroadGrantsForHardeningTest(targetDb) {
  // Deliberately over-grant this synthetic pre-hardening baseline so the
  // candidate migration proves it can remove dangerous privileges. This is a
  // worst-case test fixture, not a replica of the current live project's
  // grants (which were re-inspected separately on 2026-10-24).
  await targetDb.exec(
    'GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role',
  );
  await targetDb.exec(
    'GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA storage TO anon, authenticated, service_role',
  );
}

async function assertInitialMigrationSnapshot(targetDb) {
  const shape = await targetDb.query(`
    SELECT
      (SELECT count(*)::int FROM information_schema.tables
        WHERE table_schema = 'public' AND table_type = 'BASE TABLE') AS table_count,
      (SELECT count(*)::int FROM information_schema.columns
        WHERE table_schema = 'public') AS column_count,
      (SELECT count(*)::int FROM pg_constraint c
        JOIN pg_class r ON r.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = r.relnamespace
        WHERE n.nspname = 'public' AND c.contype = 'c') AS check_count,
      (SELECT count(*)::int FROM pg_constraint c
        JOIN pg_class r ON r.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = r.relnamespace
        WHERE n.nspname = 'public' AND c.contype = 'f') AS foreign_key_count,
      (SELECT count(*)::int FROM pg_constraint c
        JOIN pg_class r ON r.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = r.relnamespace
        WHERE n.nspname = 'public' AND c.contype = 'p') AS primary_key_count,
      (SELECT count(*)::int FROM pg_constraint c
        JOIN pg_class r ON r.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = r.relnamespace
        WHERE n.nspname = 'public' AND c.contype = 'u') AS unique_count,
      (SELECT count(*)::int FROM pg_trigger t
        JOIN pg_class r ON r.oid = t.tgrelid
        JOIN pg_namespace n ON n.oid = r.relnamespace
        WHERE n.nspname = 'public' AND NOT t.tgisinternal) AS public_trigger_count,
      (SELECT count(*)::int FROM pg_policies WHERE schemaname = 'public') AS policy_count,
      (SELECT count(*)::int FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.prokind = 'f') AS function_count,
      (SELECT count(*)::int FROM pg_indexes WHERE schemaname = 'public') AS index_count,
      (SELECT count(*)::int FROM pg_class r
        JOIN pg_namespace n ON n.oid = r.relnamespace
        WHERE n.nspname = 'public' AND r.relkind = 'r' AND r.relrowsecurity) AS rls_table_count,
      has_table_privilege('anon', 'public.users', 'TRUNCATE') AS anon_truncate,
      has_table_privilege('authenticated', 'public.users', 'TRUNCATE') AS authenticated_truncate,
      has_table_privilege('service_role', 'public.users', 'TRUNCATE') AS service_truncate,
      has_column_privilege('anon', 'public.bookings', 'status', 'UPDATE') AS anon_status_update,
      has_column_privilege('authenticated', 'public.bookings', 'status', 'UPDATE') AS authenticated_status_update,
      (SELECT count(*)::int FROM information_schema.columns
        WHERE table_schema='public' AND table_name='lawyers' AND column_name='experience') AS has_experience,
      (SELECT count(*)::int FROM information_schema.columns
        WHERE table_schema='public' AND table_name='bookings' AND column_name='idempotency_key') AS has_idempotency_key,
      (SELECT count(*)::int FROM information_schema.views
        WHERE table_schema='public' AND table_name='public_reviews') AS has_public_reviews_view
  `);
  assert.deepEqual(shape.rows[0], {
    table_count: 18,
    column_count: 153,
    check_count: 35,
    foreign_key_count: 23,
    primary_key_count: 18,
    unique_count: 7,
    public_trigger_count: 14,
    policy_count: 54,
    function_count: 9,
    index_count: 67,
    rls_table_count: 18,
    anon_truncate: true,
    authenticated_truncate: true,
    service_truncate: true,
    anon_status_update: true,
    authenticated_status_update: true,
    has_experience: 0,
    has_idempotency_key: 0,
    has_public_reviews_view: 0,
  });

  const broadGrants = await targetDb.query(`
    SELECT
      bool_and(has_table_privilege('anon', r.oid, 'DELETE')) AS anon_delete,
      bool_and(has_table_privilege('anon', r.oid, 'INSERT')) AS anon_insert,
      bool_and(has_table_privilege('anon', r.oid, 'REFERENCES')) AS anon_references,
      bool_and(has_table_privilege('anon', r.oid, 'SELECT')) AS anon_select,
      bool_and(has_table_privilege('anon', r.oid, 'TRIGGER')) AS anon_trigger,
      bool_and(has_table_privilege('anon', r.oid, 'TRUNCATE')) AS anon_truncate,
      bool_and(has_table_privilege('anon', r.oid, 'UPDATE')) AS anon_update,
      bool_and(has_table_privilege('authenticated', r.oid, 'DELETE')) AS authenticated_delete,
      bool_and(has_table_privilege('authenticated', r.oid, 'INSERT')) AS authenticated_insert,
      bool_and(has_table_privilege('authenticated', r.oid, 'REFERENCES')) AS authenticated_references,
      bool_and(has_table_privilege('authenticated', r.oid, 'SELECT')) AS authenticated_select,
      bool_and(has_table_privilege('authenticated', r.oid, 'TRIGGER')) AS authenticated_trigger,
      bool_and(has_table_privilege('authenticated', r.oid, 'TRUNCATE')) AS authenticated_truncate,
      bool_and(has_table_privilege('authenticated', r.oid, 'UPDATE')) AS authenticated_update,
      bool_and(has_table_privilege('service_role', r.oid, 'DELETE')) AS service_delete,
      bool_and(has_table_privilege('service_role', r.oid, 'INSERT')) AS service_insert,
      bool_and(has_table_privilege('service_role', r.oid, 'REFERENCES')) AS service_references,
      bool_and(has_table_privilege('service_role', r.oid, 'SELECT')) AS service_select,
      bool_and(has_table_privilege('service_role', r.oid, 'TRIGGER')) AS service_trigger,
      bool_and(has_table_privilege('service_role', r.oid, 'TRUNCATE')) AS service_truncate,
      bool_and(has_table_privilege('service_role', r.oid, 'UPDATE')) AS service_update
      FROM pg_class r
      JOIN pg_namespace n ON n.oid = r.relnamespace
     WHERE n.nspname = 'public' AND r.relkind = 'r'
  `);
  assert.deepEqual(broadGrants.rows[0], {
    anon_delete: true,
    anon_insert: true,
    anon_references: true,
    anon_select: true,
    anon_trigger: true,
    anon_truncate: true,
    anon_update: true,
    authenticated_delete: true,
    authenticated_insert: true,
    authenticated_references: true,
    authenticated_select: true,
    authenticated_trigger: true,
    authenticated_truncate: true,
    authenticated_update: true,
    service_delete: true,
    service_insert: true,
    service_references: true,
    service_select: true,
    service_trigger: true,
    service_truncate: true,
    service_update: true,
  });

  const columns = await targetDb.query(`
    SELECT table_name, array_agg(column_name ORDER BY ordinal_position) AS columns
      FROM information_schema.columns
     WHERE table_schema = 'public'
     GROUP BY table_name
     ORDER BY table_name
  `);
  assert.deepEqual(columns.rows, [
    { table_name: 'availability', columns: ['id', 'lawyer_id', 'lawyer_name', 'date', 'slots', 'created_at', 'updated_at'] },
    { table_name: 'booking_slots', columns: ['id', 'lawyer_id', 'date', 'slot', 'booking_id', 'user_id', 'created_at'] },
    { table_name: 'bookings', columns: ['id', 'user_id', 'lawyer_id', 'lawyer_name', 'date', 'time', 'hours', 'total_price', 'status', 'slot_keys', 'created_at', 'updated_at'] },
    { table_name: 'cases', columns: ['id', 'user_id', 'title', 'description', 'client_name', 'case_type', 'priority', 'status', 'due_date', 'created_at', 'updated_at'] },
    { table_name: 'chat_messages', columns: ['id', 'chat_id', 'sender_id', 'sender_name', 'text', 'created_at'] },
    { table_name: 'chats', columns: ['id', 'participants', 'participant_names', 'last_message', 'created_at', 'updated_at'] },
    { table_name: 'earnings', columns: ['id', 'user_id', 'balance', 'total_earnings', 'breakdown', 'created_at', 'updated_at'] },
    { table_name: 'favorites', columns: ['id', 'user_id', 'lawyer_id', 'created_at'] },
    { table_name: 'lawyers', columns: ['id', 'user_id', 'name', 'specialty', 'price', 'price_value', 'image', 'rating', 'location', 'bio', 'is_popular', 'is_top', 'created_at', 'updated_at'] },
    { table_name: 'notifications', columns: ['id', 'user_id', 'title', 'content', 'type', 'icon', 'read', 'created_at', 'updated_at'] },
    { table_name: 'plans', columns: ['id', 'title', 'price', 'price_value', 'color', 'features', 'is_popular', 'created_at', 'updated_at'] },
    { table_name: 'reviews', columns: ['id', 'user_id', 'user_name', 'lawyer_id', 'rating', 'comment', 'created_at', 'updated_at'] },
    { table_name: 'subscriptions', columns: ['id', 'user_id', 'plan_id', 'plan_title', 'status', 'start_date', 'end_date', 'created_at', 'updated_at'] },
    { table_name: 'tasks', columns: ['id', 'user_id', 'title', 'description', 'due_date', 'priority', 'status', 'created_at', 'updated_at'] },
    { table_name: 'users', columns: ['id', 'uid', 'auth_user_id', 'name', 'email', 'phone', 'role', 'avatar', 'address', 'created_at', 'updated_at'] },
    { table_name: 'wallet_idempotency', columns: ['id', 'user_id', 'type', 'amount', 'currency', 'balance', 'transaction', 'created_at'] },
    { table_name: 'wallet_transactions', columns: ['id', 'user_id', 'type', 'amount', 'description', 'balance', 'currency', 'idempotency_key_hash', 'created_at', 'updated_at'] },
    { table_name: 'wallets', columns: ['id', 'user_id', 'balance', 'currency', 'created_at', 'updated_at'] },
  ]);

  const foreignKeys = await targetDb.query(`
    SELECT r.relname AS table_name, c.conname AS constraint_name,
           pg_get_constraintdef(c.oid, true) AS definition
      FROM pg_constraint c
      JOIN pg_class r ON r.oid = c.conrelid
      JOIN pg_namespace n ON n.oid = r.relnamespace
     WHERE n.nspname = 'public' AND c.contype = 'f'
     ORDER BY r.relname, c.conname
  `);
  assert.deepEqual(foreignKeys.rows, [
    { table_name: 'availability', constraint_name: 'availability_lawyer_id_fkey', definition: 'FOREIGN KEY (lawyer_id) REFERENCES lawyers(id) ON DELETE CASCADE' },
    { table_name: 'booking_slots', constraint_name: 'booking_slots_booking_id_fkey', definition: 'FOREIGN KEY (booking_id) REFERENCES bookings(id) ON DELETE CASCADE' },
    { table_name: 'booking_slots', constraint_name: 'booking_slots_lawyer_id_fkey', definition: 'FOREIGN KEY (lawyer_id) REFERENCES lawyers(id) ON DELETE CASCADE' },
    { table_name: 'booking_slots', constraint_name: 'booking_slots_user_id_fkey', definition: 'FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE' },
    { table_name: 'bookings', constraint_name: 'bookings_lawyer_id_fkey', definition: 'FOREIGN KEY (lawyer_id) REFERENCES lawyers(id) ON DELETE RESTRICT' },
    { table_name: 'bookings', constraint_name: 'bookings_user_id_fkey', definition: 'FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE' },
    { table_name: 'cases', constraint_name: 'cases_user_id_fkey', definition: 'FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL' },
    { table_name: 'chat_messages', constraint_name: 'chat_messages_chat_id_fkey', definition: 'FOREIGN KEY (chat_id) REFERENCES chats(id) ON DELETE CASCADE' },
    { table_name: 'chat_messages', constraint_name: 'chat_messages_sender_id_fkey', definition: 'FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE' },
    { table_name: 'earnings', constraint_name: 'earnings_user_id_fkey', definition: 'FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE' },
    { table_name: 'favorites', constraint_name: 'favorites_lawyer_id_fkey', definition: 'FOREIGN KEY (lawyer_id) REFERENCES lawyers(id) ON DELETE CASCADE' },
    { table_name: 'favorites', constraint_name: 'favorites_user_id_fkey', definition: 'FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE' },
    { table_name: 'lawyers', constraint_name: 'lawyers_user_id_fkey', definition: 'FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL' },
    { table_name: 'notifications', constraint_name: 'notifications_user_id_fkey', definition: 'FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE' },
    { table_name: 'reviews', constraint_name: 'reviews_lawyer_id_fkey', definition: 'FOREIGN KEY (lawyer_id) REFERENCES lawyers(id) ON DELETE CASCADE' },
    { table_name: 'reviews', constraint_name: 'reviews_user_id_fkey', definition: 'FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE' },
    { table_name: 'subscriptions', constraint_name: 'subscriptions_plan_id_fkey', definition: 'FOREIGN KEY (plan_id) REFERENCES plans(id) ON DELETE RESTRICT' },
    { table_name: 'subscriptions', constraint_name: 'subscriptions_user_id_fkey', definition: 'FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE' },
    { table_name: 'tasks', constraint_name: 'tasks_user_id_fkey', definition: 'FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE' },
    { table_name: 'users', constraint_name: 'users_auth_user_id_fkey', definition: 'FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE SET NULL' },
    { table_name: 'wallet_idempotency', constraint_name: 'wallet_idempotency_user_id_fkey', definition: 'FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE' },
    { table_name: 'wallet_transactions', constraint_name: 'wallet_transactions_user_id_fkey', definition: 'FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE' },
    { table_name: 'wallets', constraint_name: 'wallets_user_id_fkey', definition: 'FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE' },
  ]);

  const functions = await targetDb.query(`
    SELECT p.oid::regprocedure::text AS signature,
           p.prosecdef AS security_definer,
           coalesce(array_to_string(p.proconfig, ','), '') AS config
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.prokind = 'f'
     ORDER BY p.oid::regprocedure::text
  `);
  assert.deepEqual(functions.rows.map((row) => row.signature), [
    'current_app_user_id()',
    'current_app_user_role()',
    'is_admin()',
    'is_lawyer_or_admin()',
    'link_migrated_auth_user()',
    'rpc_recalculate_lawyer_rating(text)',
    'rpc_reserve_booking_slots(text,text,text,text,text,text,integer,numeric,text,text[],integer[])',
    'rpc_wallet_mutate(text,text,numeric,text,text)',
    'set_updated_at()',
  ]);
  assert.ok(functions.rows.every((row) => row.security_definer === true));
  assert.ok(functions.rows.every((row) => row.config === 'search_path=public'));
  const functionGrants = await targetDb.query(`
    SELECT
      has_function_privilege('anon', 'public.current_app_user_id()', 'EXECUTE') AS anon_identity,
      has_function_privilege('authenticated', 'public.current_app_user_id()', 'EXECUTE') AS auth_identity,
      has_function_privilege('anon', 'public.is_admin()', 'EXECUTE') AS anon_admin_helper,
      has_function_privilege('authenticated', 'public.is_admin()', 'EXECUTE') AS auth_admin_helper,
      has_function_privilege('anon', 'public.link_migrated_auth_user()', 'EXECUTE') AS anon_trigger_helper,
      has_function_privilege('authenticated', 'public.set_updated_at()', 'EXECUTE') AS auth_timestamp_trigger,
      has_function_privilege('anon', 'public.rpc_recalculate_lawyer_rating(text)', 'EXECUTE') AS anon_rating_rpc,
      has_function_privilege('authenticated', 'public.rpc_reserve_booking_slots(text,text,text,text,text,text,integer,numeric,text,text[],integer[])', 'EXECUTE') AS auth_booking_rpc,
      has_function_privilege('service_role', 'public.rpc_reserve_booking_slots(text,text,text,text,text,text,integer,numeric,text,text[],integer[])', 'EXECUTE') AS service_booking_rpc,
      has_function_privilege('authenticated', 'public.rpc_wallet_mutate(text,text,numeric,text,text)', 'EXECUTE') AS auth_wallet_rpc,
      has_function_privilege('service_role', 'public.rpc_wallet_mutate(text,text,numeric,text,text)', 'EXECUTE') AS service_wallet_rpc
  `);
  assert.deepEqual(functionGrants.rows[0], {
    anon_identity: true,
    auth_identity: true,
    anon_admin_helper: true,
    auth_admin_helper: true,
    anon_trigger_helper: true,
    auth_timestamp_trigger: true,
    anon_rating_rpc: false,
    auth_booking_rpc: false,
    service_booking_rpc: true,
    auth_wallet_rpc: false,
    service_wallet_rpc: true,
  });

  const policyCounts = await targetDb.query(`
    SELECT tablename, count(*)::int AS policy_count
      FROM pg_policies
     WHERE schemaname = 'public'
     GROUP BY tablename
     ORDER BY tablename
  `);
  assert.deepEqual(policyCounts.rows, [
    { tablename: 'availability', policy_count: 2 },
    { tablename: 'booking_slots', policy_count: 2 },
    { tablename: 'bookings', policy_count: 2 },
    { tablename: 'cases', policy_count: 4 },
    { tablename: 'chat_messages', policy_count: 3 },
    { tablename: 'chats', policy_count: 4 },
    { tablename: 'earnings', policy_count: 2 },
    { tablename: 'favorites', policy_count: 3 },
    { tablename: 'lawyers', policy_count: 4 },
    { tablename: 'notifications', policy_count: 4 },
    { tablename: 'plans', policy_count: 2 },
    { tablename: 'reviews', policy_count: 4 },
    { tablename: 'subscriptions', policy_count: 4 },
    { tablename: 'tasks', policy_count: 4 },
    { tablename: 'users', policy_count: 4 },
    { tablename: 'wallet_idempotency', policy_count: 2 },
    { tablename: 'wallet_transactions', policy_count: 2 },
    { tablename: 'wallets', policy_count: 2 },
  ]);

  const triggers = await targetDb.query(`
    SELECT t.tgname AS trigger_name
      FROM pg_trigger t
      JOIN pg_class r ON r.oid = t.tgrelid
      JOIN pg_namespace n ON n.oid = r.relnamespace
     WHERE n.nspname = 'public' AND NOT t.tgisinternal
     ORDER BY t.tgname
  `);
  assert.deepEqual(triggers.rows.map((row) => row.trigger_name), [
    'trg_availability_updated_at',
    'trg_bookings_updated_at',
    'trg_cases_updated_at',
    'trg_chats_updated_at',
    'trg_earnings_updated_at',
    'trg_lawyers_updated_at',
    'trg_notifications_updated_at',
    'trg_plans_updated_at',
    'trg_reviews_updated_at',
    'trg_subscriptions_updated_at',
    'trg_tasks_updated_at',
    'trg_users_updated_at',
    'trg_wallet_transactions_updated_at',
    'trg_wallets_updated_at',
  ]);

  const statuses = await targetDb.query(`
    SELECT c.conname, pg_get_constraintdef(c.oid, true) AS definition
      FROM pg_constraint c
     WHERE c.conrelid IN ('public.bookings'::regclass, 'public.tasks'::regclass)
       AND c.conname IN ('bookings_status_check', 'tasks_status_check')
     ORDER BY c.conname
  `);
  assert.deepEqual(statuses.rows.map((row) => row.conname), [
    'bookings_status_check',
    'tasks_status_check',
  ]);
  assert.match(statuses.rows[0].definition, /'Confirmed'/);
  assert.doesNotMatch(statuses.rows[0].definition, /'Active'/);
  assert.match(statuses.rows[1].definition, /'Pending'/);
  assert.match(statuses.rows[1].definition, /'Completed'/);
  assert.doesNotMatch(statuses.rows[1].definition, /'Cancelled'/);

  const defaults = await targetDb.query(`
    SELECT table_name, column_default
      FROM information_schema.columns
     WHERE table_schema = 'public'
       AND ((table_name = 'bookings' AND column_name = 'status')
         OR (table_name = 'tasks' AND column_name = 'status'))
     ORDER BY table_name
  `);
  assert.deepEqual(defaults.rows, [
    { table_name: 'bookings', column_default: "'Confirmed'::text" },
    { table_name: 'tasks', column_default: "'Pending'::text" },
  ]);
}

async function seedPreHardeningStatuses(targetDb) {
  await targetDb.query(
    `INSERT INTO public.users (id, uid, name, email, role)
     VALUES ('status-owner', 'status-owner', 'Status Keeper', 'status@example.test', 'client')`,
  );
  await targetDb.query(
    `INSERT INTO public.lawyers (id, name, specialty, price, price_value)
     VALUES ('status-lawyer', 'Status Counsel', 'Civil', '$100/hour', 100)`,
  );
  await targetDb.query(
    `INSERT INTO public.bookings
       (id, user_id, lawyer_id, date, time, hours, total_price, status)
     VALUES ('legacy-confirmed-booking', 'status-owner', 'status-lawyer',
             '2026-10-28', '09:00', 1, 100, 'Confirmed')`,
  );
  await targetDb.query(
    `INSERT INTO public.tasks (id, user_id, title, status)
     VALUES ('legacy-task-pending', 'status-owner', 'Legacy pending task', 'Pending'),
            ('legacy-task-progress', 'status-owner', 'Legacy in-progress task', 'In Progress'),
            ('legacy-task-completed', 'status-owner', 'Legacy completed task', 'Completed')`,
  );
}

async function setSubject(subject, role = 'authenticated') {
  await db.query("SELECT set_config('request.jwt.claim.sub', $1, true)", [
    subject ?? '',
  ]);
  await db.query("SELECT set_config('request.jwt.claim.role', $1, true)", [
    role,
  ]);
}

async function asRole(role, subject, callback) {
  await db.exec('BEGIN');
  try {
    await db.exec(`SET LOCAL ROLE ${role}`);
    await setSubject(subject, role);
    return await callback();
  } finally {
    await db.exec('ROLLBACK');
  }
}

async function expectSqlError(statement, parameters, expectedCode = '42501') {
  await db.exec('SAVEPOINT expected_sql_error');
  let caught;
  try {
    await db.query(statement, parameters);
  } catch (error) {
    caught = error;
  }
  if (!caught) {
    await db.exec('ROLLBACK TO SAVEPOINT expected_sql_error');
    await db.exec('RELEASE SAVEPOINT expected_sql_error');
    assert.fail(`Expected SQLSTATE ${expectedCode}, but statement succeeded: ${statement}`);
  }
  await db.exec('ROLLBACK TO SAVEPOINT expected_sql_error');
  await db.exec('RELEASE SAVEPOINT expected_sql_error');
  assert.equal(caught.code, expectedCode, caught.message);
  return caught;
}

async function seedFixtures() {
  // Client-provided raw_user_meta_data.role is deliberately untrusted.
  await db.query(
    `INSERT INTO auth.users (id, email, email_confirmed_at, raw_user_meta_data)
     VALUES ($1, 'client@example.test', now(), '{"name":"Client One","role":"admin"}'::jsonb),
            ($2, 'other@example.test', now(), '{"name":"Client Two"}'::jsonb),
            ($3, 'lawyer@example.test', now(), '{"name":"Lawyer One"}'::jsonb),
            ($4, 'admin@example.test', now(), '{"name":"Admin One"}'::jsonb),
            ($5, 'pending@example.test', NULL, '{"name":"Pending User"}'::jsonb),
            ($6, 'other-lawyer@example.test', now(), '{"name":"Lawyer Two"}'::jsonb),
            ($7, 'no-profile@example.test', NULL, '{"name":"No Profile"}'::jsonb)`,
    [ids.client, ids.otherClient, ids.lawyer, ids.admin, ids.unconfirmed, ids.otherLawyer, ids.noProfileAuth],
  );

  // Legacy profiles must only link through the explicit admin-controlled Auth
  // app_metadata mapping, never by a matching email alone.
  await db.query(
    `INSERT INTO public.users (id, uid, name, email, role)
     VALUES ('legacy-uid-verified', 'legacy-uid-verified', 'Legacy Lawyer', 'legacy@example.test', 'lawyer'),
            ('legacy-uid-email-only', 'legacy-uid-email-only', 'Unlinked Legacy', 'email-only@example.test', 'client'),
            ('legacy-uid-mismatch', 'legacy-uid-mismatch', 'Protected Legacy', 'person@example.test', 'lawyer')`,
  );
  await db.query(
    `INSERT INTO auth.users (id, email, email_confirmed_at, raw_user_meta_data, raw_app_meta_data)
     VALUES ($1, 'legacy@example.test', now(), '{"name":"Impersonated Name","role":"admin"}'::jsonb,
             '{"legacy_uid":"legacy-uid-verified","legacy_migration_verified":"true"}'::jsonb),
            ($2, 'email-only@example.test', now(), '{"legacy_uid":"legacy-uid-email-only","legacy_migration_verified":"true","role":"admin"}'::jsonb,
             '{}'::jsonb),
            ($3, 'attacker@example.test', now(), '{"name":"Wrong Email"}'::jsonb,
             '{"legacy_uid":"legacy-uid-mismatch","legacy_migration_verified":"true"}'::jsonb)`,
    [ids.linkedLegacyAuth, ids.emailOnlyAuth, ids.badMappingAuth],
  );

  // Confirmation is a separate UPDATE in GoTrue. The trigger must provision
  // the ordinary client profile at confirmation time, not before it.
  assert.equal(
    (await db.query('SELECT count(*)::int AS n FROM public.users WHERE auth_user_id = $1', [
      ids.unconfirmed,
    ])).rows[0].n,
    0,
  );
  await db.query('UPDATE auth.users SET email_confirmed_at = now() WHERE id = $1', [
    ids.unconfirmed,
  ]);

  await db.query("UPDATE public.users SET role = 'lawyer' WHERE id IN ($1, $2)", [ids.lawyer, ids.otherLawyer]);
  await db.query("UPDATE public.users SET role = 'admin' WHERE id = $1", [ids.admin]);
  await db.query(
    `INSERT INTO public.lawyers (id, user_id, name, specialty, price, price_value, experience)
     VALUES ('lawyer-1', $1, 'Trusted Lawyer', 'Civil', '$100/hour', 100, '12 years'),
            ('lawyer-2', $2, 'Second Lawyer', 'Family', '$80/hour', 80, '8 years')`,
    [ids.lawyer, ids.otherLawyer],
  );
  await db.query(
    `INSERT INTO public.availability (lawyer_id, lawyer_name, date, slots)
     VALUES ('lawyer-1', 'Trusted Lawyer', '2026-10-24', '["09:00","10:00","11:00"]'::jsonb)`,
  );
  caseId = (await db.query(
    `INSERT INTO public.cases (user_id, title, status)
     VALUES ($1, 'Client A case', 'Open') RETURNING id`,
    [ids.client],
  )).rows[0].id;
  await db.query(
    `INSERT INTO public.cases (user_id, title, status)
     VALUES ($1, 'Client B case', 'Open')`,
    [ids.otherClient],
  );
  unassignedCaseId = (await db.query(
    `INSERT INTO public.cases (user_id, title, status)
     VALUES (NULL, 'Unassigned case', 'Open') RETURNING id`,
  )).rows[0].id;
  taskId = (await db.query(
    `INSERT INTO public.tasks (user_id, title, status)
     VALUES ($1, 'Prepare documents', 'Pending') RETURNING id`,
    [ids.client],
  )).rows[0].id;
  planId = (await db.query(
    `INSERT INTO public.plans (title, price, price_value)
     VALUES ('Standard', '$25', 25) RETURNING id`,
  )).rows[0].id;
  notificationId = (await db.query(
    `INSERT INTO public.notifications (user_id, title, content)
     VALUES ($1, 'Original notice', 'Initial content') RETURNING id`,
    [ids.client],
  )).rows[0].id;
  await db.query(
    `INSERT INTO public.wallets (id, user_id, balance, currency)
     VALUES ($1, $1, 500, 'USD')`,
    [ids.client],
  );
  await db.query(
    `INSERT INTO public.earnings (id, user_id, balance, total_earnings)
     VALUES ($1, $1, 125, 900), ($2, $2, 75, 400)`,
    [ids.client, ids.otherClient],
  );
}

describe('initial local migration snapshot (PGlite; not current-live parity)', () => {
  let baselineDb;

  before(async () => {
    baselineDb = new PGlite();
    await baselineDb.exec(bootstrapSql);
    const files = await migrationFiles();
    assert.deepEqual(files.slice(0, 2), [
      '20261022174110_initial_legal_schema_and_rls.sql',
      '20261022174313_transactional_rpc_functions.sql',
    ]);
    const initialSql = await readFile(path.join(migrationsDir, files[0]), 'utf8');
    assert.match(initialSql, /^-- Migration: 20261022174110_initial_legal_schema_and_rls\.sql/m);
    await applyMigrations(baselineDb, files.slice(0, 2));
    await simulateLegacyBroadGrantsForHardeningTest(baselineDb);
  });

  after(async () => {
    await baselineDb?.close();
  });

  it('reproduces the two local baseline migrations under a deliberately over-privileged test grant set', async () => {
    await assertInitialMigrationSnapshot(baselineDb);
  });
});

describe('archived unapplied migration candidates (PGlite PostgreSQL integration)', () => {
  before(async () => {
    db = new PGlite();
    await db.exec(bootstrapSql);
    const liveFiles = await migrationFiles();
    const baselineFiles = liveFiles.slice(0, 2);
    assert.deepEqual(archivedCandidateFiles, [
      '20261023100000_harden_rls_auth_and_storage.sql',
      '20261023101500_authenticated_transactional_rpcs.sql',
    ]);
    await applyMigrations(db, baselineFiles);
    await simulateLegacyBroadGrantsForHardeningTest(db);
    await seedPreHardeningStatuses(db);
    await applyMigrations(db, archivedCandidateFiles, archivedCandidatesDir);
    await seedFixtures();
  });

  after(async () => {
    await db?.close();
  });

  it('preserves existing statuses and allows legacy labels without a data rewrite', async () => {
    assert.equal(
      (await db.query(
        "SELECT status FROM public.bookings WHERE id = 'legacy-confirmed-booking'",
      )).rows[0].status,
      'Confirmed',
    );
    const tasks = await db.query(
      "SELECT id, status FROM public.tasks WHERE id LIKE 'legacy-task-%' ORDER BY id",
    );
    assert.deepEqual(tasks.rows, [
      { id: 'legacy-task-completed', status: 'Completed' },
      { id: 'legacy-task-pending', status: 'Pending' },
      { id: 'legacy-task-progress', status: 'In Progress' },
    ]);

    await asRole('service_role', null, async () => {
      const legacyToDo = await db.query(
        `INSERT INTO public.tasks (user_id, title, status)
         VALUES ('status-owner', 'Legacy To Do label', 'To Do') RETURNING status`,
      );
      const legacyDone = await db.query(
        `INSERT INTO public.tasks (user_id, title, status)
         VALUES ('status-owner', 'Legacy Done label', 'Done') RETURNING status`,
      );
      assert.equal(legacyToDo.rows[0].status, 'To Do');
      assert.equal(legacyDone.rows[0].status, 'Done');
    });
  });

  it('applies the archived RLS/RPC candidates and replaces broad test grants with their reviewed surface', async () => {
    const tables = await db.query(
      `SELECT count(*)::int AS n
         FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relrowsecurity`,
    );
    assert.equal(tables.rows[0].n, 18);

    const hardenedPolicyCounts = await db.query(`
      SELECT tablename, count(*)::int AS policy_count
        FROM pg_policies
       WHERE schemaname = 'public'
       GROUP BY tablename
       ORDER BY tablename
    `);
    assert.deepEqual(hardenedPolicyCounts.rows, [
      { tablename: 'availability', policy_count: 4 },
      { tablename: 'booking_slots', policy_count: 1 },
      { tablename: 'bookings', policy_count: 1 },
      { tablename: 'cases', policy_count: 4 },
      { tablename: 'chat_messages', policy_count: 1 },
      { tablename: 'chats', policy_count: 2 },
      { tablename: 'earnings', policy_count: 1 },
      { tablename: 'favorites', policy_count: 3 },
      { tablename: 'lawyers', policy_count: 4 },
      { tablename: 'notifications', policy_count: 4 },
      { tablename: 'plans', policy_count: 4 },
      { tablename: 'reviews', policy_count: 1 },
      { tablename: 'subscriptions', policy_count: 1 },
      { tablename: 'tasks', policy_count: 4 },
      { tablename: 'users', policy_count: 2 },
      { tablename: 'wallet_idempotency', policy_count: 1 },
      { tablename: 'wallet_transactions', policy_count: 1 },
      { tablename: 'wallets', policy_count: 1 },
    ]);
    assert.equal(hardenedPolicyCounts.rows.reduce((sum, row) => sum + row.policy_count, 0), 40);
    const hardenedPolicyNames = await db.query(`
      SELECT tablename, policyname, cmd
        FROM pg_policies
       WHERE schemaname = 'public'
       ORDER BY tablename, policyname
    `);
    assert.deepEqual(hardenedPolicyNames.rows, [
      { tablename: 'availability', policyname: 'availability_delete_owner_or_admin', cmd: 'DELETE' },
      { tablename: 'availability', policyname: 'availability_insert_owner_or_admin', cmd: 'INSERT' },
      { tablename: 'availability', policyname: 'availability_select_public', cmd: 'SELECT' },
      { tablename: 'availability', policyname: 'availability_update_owner_or_admin', cmd: 'UPDATE' },
      { tablename: 'booking_slots', policyname: 'booking_slots_select_owner_or_admin', cmd: 'SELECT' },
      { tablename: 'bookings', policyname: 'bookings_select_owner_or_admin', cmd: 'SELECT' },
      { tablename: 'cases', policyname: 'cases_delete_owner_or_admin', cmd: 'DELETE' },
      { tablename: 'cases', policyname: 'cases_insert_owner_or_admin', cmd: 'INSERT' },
      { tablename: 'cases', policyname: 'cases_select_owner_or_admin', cmd: 'SELECT' },
      { tablename: 'cases', policyname: 'cases_update_owner_or_admin', cmd: 'UPDATE' },
      { tablename: 'chat_messages', policyname: 'chat_messages_select_participant_or_admin', cmd: 'SELECT' },
      { tablename: 'chats', policyname: 'chats_delete_participant_or_admin', cmd: 'DELETE' },
      { tablename: 'chats', policyname: 'chats_select_participant_or_admin', cmd: 'SELECT' },
      { tablename: 'earnings', policyname: 'earnings_select_owner_or_admin', cmd: 'SELECT' },
      { tablename: 'favorites', policyname: 'favorites_delete_owner_or_admin', cmd: 'DELETE' },
      { tablename: 'favorites', policyname: 'favorites_insert_owner_or_admin', cmd: 'INSERT' },
      { tablename: 'favorites', policyname: 'favorites_select_owner_or_admin', cmd: 'SELECT' },
      { tablename: 'lawyers', policyname: 'lawyers_delete_admin_only', cmd: 'DELETE' },
      { tablename: 'lawyers', policyname: 'lawyers_insert_admin_only', cmd: 'INSERT' },
      { tablename: 'lawyers', policyname: 'lawyers_select_public', cmd: 'SELECT' },
      { tablename: 'lawyers', policyname: 'lawyers_update_admin_only', cmd: 'UPDATE' },
      { tablename: 'notifications', policyname: 'notifications_delete_owner_or_admin', cmd: 'DELETE' },
      { tablename: 'notifications', policyname: 'notifications_insert_admin_only', cmd: 'INSERT' },
      { tablename: 'notifications', policyname: 'notifications_select_owner_or_admin', cmd: 'SELECT' },
      { tablename: 'notifications', policyname: 'notifications_update_read_owner_or_admin', cmd: 'UPDATE' },
      { tablename: 'plans', policyname: 'plans_delete_admin_only', cmd: 'DELETE' },
      { tablename: 'plans', policyname: 'plans_insert_admin_only', cmd: 'INSERT' },
      { tablename: 'plans', policyname: 'plans_select_public', cmd: 'SELECT' },
      { tablename: 'plans', policyname: 'plans_update_admin_only', cmd: 'UPDATE' },
      { tablename: 'reviews', policyname: 'reviews_select_public', cmd: 'SELECT' },
      { tablename: 'subscriptions', policyname: 'subscriptions_select_owner_or_admin', cmd: 'SELECT' },
      { tablename: 'tasks', policyname: 'tasks_delete_owner_or_admin', cmd: 'DELETE' },
      { tablename: 'tasks', policyname: 'tasks_insert_owner_or_admin', cmd: 'INSERT' },
      { tablename: 'tasks', policyname: 'tasks_select_owner_or_admin', cmd: 'SELECT' },
      { tablename: 'tasks', policyname: 'tasks_update_owner_or_admin', cmd: 'UPDATE' },
      { tablename: 'users', policyname: 'users_select_self_or_admin', cmd: 'SELECT' },
      { tablename: 'users', policyname: 'users_update_self_or_admin', cmd: 'UPDATE' },
      { tablename: 'wallet_idempotency', policyname: 'wallet_idempotency_select_owner_or_admin', cmd: 'SELECT' },
      { tablename: 'wallet_transactions', policyname: 'wallet_tx_select_owner_or_admin', cmd: 'SELECT' },
      { tablename: 'wallets', policyname: 'wallets_select_owner_or_admin', cmd: 'SELECT' },
    ]);
    assert.deepEqual(
      (await db.query(`SELECT policyname, cmd FROM pg_policies WHERE schemaname = 'storage' ORDER BY policyname`))
        .rows,
      [
        { policyname: 'legal_documents_delete_owner_or_admin', cmd: 'DELETE' },
        { policyname: 'legal_documents_read_owner_or_admin', cmd: 'SELECT' },
      ],
    );

    const trustedDml = await db.query(`
      SELECT bool_and(has_table_privilege('service_role', c.oid, 'SELECT')) AS service_select,
             bool_and(has_table_privilege('service_role', c.oid, 'INSERT')) AS service_insert,
             bool_and(has_table_privilege('service_role', c.oid, 'UPDATE')) AS service_update,
             bool_and(has_table_privilege('service_role', c.oid, 'DELETE')) AS service_delete
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = 'public' AND c.relkind = 'r'
    `);
    assert.deepEqual(trustedDml.rows[0], {
      service_select: true,
      service_insert: true,
      service_update: true,
      service_delete: true,
    });

    const unsafePrivileges = await db.query(`
      SELECT r.relname AS table_name,
        has_table_privilege('anon', r.oid, 'TRUNCATE') AS anon_truncate,
        has_table_privilege('authenticated', r.oid, 'TRUNCATE') AS authenticated_truncate,
        has_table_privilege('service_role', r.oid, 'TRUNCATE') AS service_truncate,
        has_table_privilege('anon', r.oid, 'REFERENCES') AS anon_references,
        has_table_privilege('authenticated', r.oid, 'REFERENCES') AS authenticated_references,
        has_table_privilege('service_role', r.oid, 'REFERENCES') AS service_references,
        has_table_privilege('anon', r.oid, 'TRIGGER') AS anon_trigger,
        has_table_privilege('authenticated', r.oid, 'TRIGGER') AS authenticated_trigger,
        has_table_privilege('service_role', r.oid, 'TRIGGER') AS service_trigger,
        has_table_privilege('anon', r.oid, 'INSERT') AS anon_insert,
        has_table_privilege('anon', r.oid, 'UPDATE') AS anon_update,
        has_table_privilege('anon', r.oid, 'DELETE') AS anon_delete,
        c.relrowsecurity AS rls_enabled,
        c.relforcerowsecurity AS force_rls
      FROM pg_class r
      JOIN pg_namespace n ON n.oid = r.relnamespace
      JOIN pg_class c ON c.oid = r.oid
      WHERE n.nspname = 'public' AND r.relkind = 'r'
      ORDER BY r.relname
    `);
    assert.equal(unsafePrivileges.rows.length, 18);
    for (const row of unsafePrivileges.rows) {
      assert.equal(row.anon_truncate, false, `${row.table_name}: anon TRUNCATE`);
      assert.equal(row.authenticated_truncate, false, `${row.table_name}: authenticated TRUNCATE`);
      assert.equal(row.service_truncate, false, `${row.table_name}: service_role TRUNCATE`);
      assert.equal(row.anon_references, false, `${row.table_name}: anon REFERENCES`);
      assert.equal(row.authenticated_references, false, `${row.table_name}: authenticated REFERENCES`);
      assert.equal(row.service_references, false, `${row.table_name}: service_role REFERENCES`);
      assert.equal(row.anon_trigger, false, `${row.table_name}: anon TRIGGER`);
      assert.equal(row.authenticated_trigger, false, `${row.table_name}: authenticated TRIGGER`);
      assert.equal(row.service_trigger, false, `${row.table_name}: service_role TRIGGER`);
      assert.equal(row.anon_insert, false, `${row.table_name}: anon INSERT`);
      assert.equal(row.anon_update, false, `${row.table_name}: anon UPDATE`);
      assert.equal(row.anon_delete, false, `${row.table_name}: anon DELETE`);
      assert.equal(row.rls_enabled, true, `${row.table_name}: RLS enabled`);
      assert.equal(row.force_rls, false, `${row.table_name}: FORCE RLS not yet enabled`);
    }

    const grants = await db.query(`
      SELECT
        has_table_privilege('anon', 'public.users', 'SELECT') AS anon_users,
        has_table_privilege('anon', 'public.users', 'TRUNCATE') AS anon_truncate,
        has_table_privilege('authenticated', 'public.bookings', 'INSERT') AS client_booking_insert,
        has_table_privilege('authenticated', 'public.bookings', 'UPDATE') AS client_booking_update,
        has_table_privilege('authenticated', 'public.chats', 'UPDATE') AS client_chat_update,
        has_table_privilege('authenticated', 'public.chats', 'DELETE') AS client_chat_delete,
        has_table_privilege('anon', 'public.chats', 'DELETE') AS anon_chat_delete,
        has_table_privilege('service_role', 'public.bookings', 'TRUNCATE') AS service_truncate,
        has_column_privilege('authenticated', 'public.bookings', 'id', 'SELECT') AS client_booking_id_read,
        has_column_privilege('authenticated', 'public.bookings', 'idempotency_key_hash', 'SELECT') AS client_booking_hash_read,
        has_column_privilege('authenticated', 'public.users', 'role', 'UPDATE') AS role_update,
        has_column_privilege('authenticated', 'public.users', 'email', 'UPDATE') AS email_update,
        has_column_privilege('authenticated', 'public.users', 'uid', 'UPDATE') AS uid_update,
        has_column_privilege('authenticated', 'public.users', 'auth_user_id', 'UPDATE') AS auth_user_id_update,
        has_column_privilege('anon', 'public.lawyers', 'name', 'SELECT') AS anon_lawyer_name_read,
        has_column_privilege('anon', 'public.lawyers', 'user_id', 'SELECT') AS anon_lawyer_owner_read,
        has_column_privilege('authenticated', 'public.lawyers', 'user_id', 'SELECT') AS auth_lawyer_owner_read,
        has_column_privilege('anon', 'public.reviews', 'user_id', 'SELECT') AS anon_review_author_read,
        has_column_privilege('authenticated', 'public.reviews', 'user_id', 'SELECT') AS review_author_read,
        has_table_privilege('authenticated', 'public.public_reviews', 'SELECT') AS redacted_view_read
    `);
    assert.deepEqual(grants.rows[0], {
      anon_users: false,
      anon_truncate: false,
      client_booking_insert: false,
      client_booking_update: false,
      client_chat_update: false,
      client_chat_delete: true,
      anon_chat_delete: false,
      service_truncate: false,
      client_booking_id_read: true,
      client_booking_hash_read: false,
      role_update: false,
      email_update: false,
      uid_update: false,
      auth_user_id_update: false,
      anon_lawyer_name_read: true,
      anon_lawyer_owner_read: false,
      auth_lawyer_owner_read: false,
      anon_review_author_read: false,
      review_author_read: false,
      redacted_view_read: true,
    });
    await asRole('anon', null, async () => {
      await expectSqlError('TRUNCATE public.users', [], '42501');
    });
    await asRole('authenticated', ids.client, async () => {
      await expectSqlError('TRUNCATE public.users', [], '42501');
    });
    await asRole('authenticated', ids.admin, async () => {
      await expectSqlError('TRUNCATE public.users', [], '42501');
    });
    await asRole('service_role', null, async () => {
      await expectSqlError('TRUNCATE public.users', [], '42501');
    });

    const storageGrants = await db.query(`
      SELECT
        has_table_privilege('anon', 'storage.objects', 'SELECT') AS anon_select,
        has_table_privilege('anon', 'storage.objects', 'INSERT') AS anon_insert,
        has_table_privilege('authenticated', 'storage.objects', 'SELECT') AS auth_select,
        has_table_privilege('authenticated', 'storage.objects', 'INSERT') AS auth_insert,
        has_table_privilege('authenticated', 'storage.objects', 'UPDATE') AS auth_update,
        has_table_privilege('authenticated', 'storage.objects', 'DELETE') AS auth_delete,
        has_table_privilege('service_role', 'storage.objects', 'SELECT') AS service_select,
        has_table_privilege('service_role', 'storage.objects', 'INSERT') AS service_insert,
        has_table_privilege('service_role', 'storage.objects', 'UPDATE') AS service_update,
        has_table_privilege('service_role', 'storage.objects', 'DELETE') AS service_delete,
        has_table_privilege('service_role', 'storage.objects', 'TRUNCATE') AS service_truncate,
        has_schema_privilege('anon', 'storage', 'USAGE') AS anon_schema_usage,
        has_schema_privilege('authenticated', 'storage', 'USAGE') AS auth_schema_usage,
        has_schema_privilege('service_role', 'storage', 'USAGE') AS service_schema_usage,
        has_table_privilege('authenticated', 'storage.buckets', 'SELECT') AS auth_bucket_select,
        has_table_privilege('authenticated', 'storage.buckets', 'INSERT') AS auth_bucket_insert,
        has_table_privilege('service_role', 'storage.buckets', 'SELECT') AS service_bucket_select,
        has_table_privilege('service_role', 'storage.buckets', 'TRUNCATE') AS service_bucket_truncate,
        has_table_privilege('anon', 'storage.buckets_analytics', 'SELECT') AS anon_analytics_select,
        has_table_privilege('authenticated', 'storage.buckets_analytics', 'SELECT') AS auth_analytics_select,
        has_table_privilege('service_role', 'storage.buckets_analytics', 'SELECT') AS service_analytics_select
    `);
    assert.deepEqual(storageGrants.rows[0], {
      anon_select: false,
      anon_insert: false,
      auth_select: true,
      auth_insert: false,
      auth_update: false,
      auth_delete: true,
      service_select: true,
      service_insert: true,
      service_update: true,
      service_delete: true,
      service_truncate: false,
      anon_schema_usage: false,
      auth_schema_usage: true,
      service_schema_usage: true,
      auth_bucket_select: false,
      auth_bucket_insert: false,
      service_bucket_select: true,
      service_bucket_truncate: false,
      anon_analytics_select: false,
      auth_analytics_select: false,
      service_analytics_select: false,
    });

    const helperGrants = await db.query(`
      SELECT
        has_function_privilege('anon', 'public.current_app_user_id()', 'EXECUTE') AS anon_identity,
        has_function_privilege('authenticated', 'public.current_app_user_id()', 'EXECUTE') AS auth_identity,
        has_function_privilege('service_role', 'public.current_app_user_id()', 'EXECUTE') AS service_identity,
        has_function_privilege('anon', 'public.is_admin()', 'EXECUTE') AS anon_admin_helper,
        has_function_privilege('authenticated', 'public.is_admin()', 'EXECUTE') AS auth_admin_helper,
        has_function_privilege('anon', 'public.link_migrated_auth_user()', 'EXECUTE') AS anon_auth_trigger,
        has_function_privilege('authenticated', 'public.link_migrated_auth_user()', 'EXECUTE') AS auth_auth_trigger,
        has_function_privilege('service_role', 'public.link_migrated_auth_user()', 'EXECUTE') AS service_auth_trigger,
        has_function_privilege('anon', 'public.set_updated_at()', 'EXECUTE') AS anon_timestamp_trigger,
        has_function_privilege('authenticated', 'public.set_updated_at()', 'EXECUTE') AS auth_timestamp_trigger,
        has_function_privilege('service_role', 'public.set_updated_at()', 'EXECUTE') AS service_timestamp_trigger
    `);
    assert.deepEqual(helperGrants.rows[0], {
      anon_identity: false,
      auth_identity: true,
      service_identity: false,
      anon_admin_helper: false,
      auth_admin_helper: true,
      anon_auth_trigger: false,
      auth_auth_trigger: false,
      service_auth_trigger: false,
      anon_timestamp_trigger: false,
      auth_timestamp_trigger: false,
      service_timestamp_trigger: false,
    });

    const functionGrants = await db.query(`
      SELECT
        has_function_privilege('anon', 'public.rpc_create_booking(text,text,text,integer,text,text)', 'EXECUTE') AS anon_booking,
        has_function_privilege('authenticated', 'public.rpc_create_booking(text,text,text,integer,text,text)', 'EXECUTE') AS auth_booking,
        has_function_privilege('anon', 'public.rpc_delete_booking(text)', 'EXECUTE') AS anon_booking_delete,
        has_function_privilege('authenticated', 'public.rpc_delete_booking(text)', 'EXECUTE') AS auth_booking_delete,
        has_function_privilege('anon', 'public.rpc_notification_update(text,jsonb)', 'EXECUTE') AS anon_notification_update,
        has_function_privilege('authenticated', 'public.rpc_notification_update(text,jsonb)', 'EXECUTE') AS auth_notification_update,
        has_function_privilege('authenticated', 'public.rpc_wallet_mutate(text,text,numeric,text,text)', 'EXECUTE') AS auth_wallet,
        has_function_privilege('anon', 'public.rpc_wallet_mutate(text,text,numeric,text,text)', 'EXECUTE') AS anon_wallet,
        has_function_privilege('service_role', 'public.rpc_wallet_mutate(text,text,numeric,text,text)', 'EXECUTE') AS service_wallet,
        has_function_privilege('service_role', 'public.rpc_recalculate_lawyer_rating(text)', 'EXECUTE') AS legacy_rating_rpc,
        has_function_privilege('service_role', 'public.rpc_reserve_booking_slots(text,text,text,text,text,text,integer,numeric,text,text[],integer[])', 'EXECUTE') AS legacy_server_booking,
        to_regprocedure('public.rpc_admin_set_subscription_status(text,text,timestamptz,timestamptz)') IS NULL AS no_direct_subscription_activation
    `);
    assert.deepEqual(functionGrants.rows[0], {
      anon_booking: false,
      auth_booking: true,
      anon_booking_delete: false,
      auth_booking_delete: true,
      anon_notification_update: false,
      auth_notification_update: true,
      auth_wallet: true,
      anon_wallet: false,
      service_wallet: false,
      legacy_rating_rpc: true,
      legacy_server_booking: true,
      no_direct_subscription_activation: true,
    });

    const hardenedFunctions = await db.query(`
      SELECT p.oid::regprocedure::text AS signature,
             p.prosecdef AS security_definer,
             COALESCE(array_to_string(p.proconfig, ','), '') AS config
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.prokind = 'f'
       ORDER BY p.oid::regprocedure::text
    `);
    for (const fn of hardenedFunctions.rows.filter((row) => row.security_definer)) {
      assert.equal(fn.config, 'search_path=pg_catalog, public, pg_temp', `${fn.signature} path`);
      assert.equal(await db.query(
        `SELECT has_function_privilege('anon', $1::regprocedure, 'EXECUTE') AS allowed`,
        [fn.signature],
      ).then((result) => result.rows[0].allowed), false, `${fn.signature} anon execute`);
    }
    const timestampHelper = hardenedFunctions.rows.find((row) => row.signature === 'set_updated_at()');
    assert.equal(timestampHelper.security_definer, false);
    assert.equal(timestampHelper.config, 'search_path=pg_catalog');

    const viewOptions = await db.query(`
      SELECT reloptions FROM pg_class WHERE oid = 'public.public_reviews'::regclass
    `);
    assert.ok(viewOptions.rows[0].reloptions.includes('security_barrier=true'));
    assert.ok(viewOptions.rows[0].reloptions.includes('security_invoker=true'));

    const bucket = await db.query(
      "SELECT public, file_size_limit, allowed_mime_types FROM storage.buckets WHERE id = 'legal-documents'",
    );
    assert.deepEqual(bucket.rows[0], {
      public: false,
      file_size_limit: 10485760,
      allowed_mime_types: ['application/pdf'],
    });
  });

  it('provisions only confirmed Auth profiles and never links a legacy profile by email alone', async () => {
    const normal = await db.query(
      'SELECT id, role, name FROM public.users WHERE auth_user_id = $1',
      [ids.client],
    );
    assert.equal(normal.rows.length, 1);
    assert.equal(normal.rows[0].id, ids.client);
    assert.equal(normal.rows[0].role, 'client');
    assert.equal(normal.rows[0].name, 'Client One');

    const confirmedLater = await db.query(
      'SELECT id, role FROM public.users WHERE auth_user_id = $1',
      [ids.unconfirmed],
    );
    assert.equal(confirmedLater.rows.length, 1);
    assert.equal(confirmedLater.rows[0].role, 'client');

    const explicitLegacy = await db.query(
      "SELECT auth_user_id, role FROM public.users WHERE id = 'legacy-uid-verified'",
    );
    assert.equal(explicitLegacy.rows[0].auth_user_id, ids.linkedLegacyAuth);
    assert.equal(explicitLegacy.rows[0].role, 'lawyer');

    const emailOnly = await db.query(
      "SELECT auth_user_id FROM public.users WHERE id = 'legacy-uid-email-only'",
    );
    assert.equal(emailOnly.rows[0].auth_user_id, null);
    const separateClient = await db.query(
      'SELECT role FROM public.users WHERE auth_user_id = $1',
      [ids.emailOnlyAuth],
    );
    assert.equal(separateClient.rows[0].role, 'client');

    const wrongEmailMapping = await db.query(
      "SELECT auth_user_id FROM public.users WHERE id = 'legacy-uid-mismatch'",
    );
    assert.equal(wrongEmailMapping.rows[0].auth_user_id, null);
    assert.equal(
      (await db.query('SELECT count(*)::int AS n FROM public.users WHERE auth_user_id = $1', [ids.badMappingAuth]))
        .rows[0].n,
      0,
      'a verified legacy UID with a mismatched confirmed email fails closed without provisioning a second profile',
    );
    assert.equal(
      (await db.query('SELECT count(*)::int AS n FROM public.users WHERE auth_user_id = $1', [ids.noProfileAuth]))
        .rows[0].n,
      0,
      'an unconfirmed user has no application profile',
    );

    await asRole('authenticated', ids.noProfileAuth, async () => {
      const identity = (await db.query(
        'SELECT public.current_app_user_id() AS app_id, public.current_app_user_role() AS app_role',
      )).rows[0];
      assert.equal(identity.app_id, null, 'JWT subject alone is not an application identity');
      assert.equal(identity.app_role, null);
      await expectSqlError(
        "SELECT public.rpc_create_booking('lawyer-1', '2026-10-24', '09:00', 1, NULL)",
        [],
        '42501',
      );
    });
  });

  it('enforces client/lawyer/admin row boundaries, column grants, and private storage paths', async () => {
    await asRole('anon', null, async () => {
      const publicLawyers = await db.query('SELECT id, name FROM public.lawyers');
      assert.equal(publicLawyers.rows.length, 3);
      await expectSqlError('SELECT user_id FROM public.lawyers', [], '42501');
      await expectSqlError('SELECT user_id FROM public.reviews', [], '42501');
      assert.equal((await db.query('SELECT id FROM public.plans')).rows.length, 1);
      assert.equal((await db.query('SELECT id FROM public.public_reviews')).rows.length, 0);
      await expectSqlError('SELECT id FROM public.users', [], '42501');
      await expectSqlError('SELECT name FROM storage.objects', [], '42501');
      await expectSqlError('SELECT id FROM storage.buckets', [], '42501');
      await expectSqlError(
        'INSERT INTO storage.objects (bucket_id, name) VALUES ($1, $2)',
        ['legal-documents', 'anon/documents/file.pdf'],
        '42501',
      );
      await expectSqlError(
        "INSERT INTO public.lawyers (name, price) VALUES ('Anonymous record', '$1/hour')",
        [],
        '42501',
      );
    });

    await asRole('authenticated', ids.client, async () => {
      const visibleUsers = await db.query('SELECT id FROM public.users');
      assert.deepEqual(visibleUsers.rows.map((row) => row.id), [ids.client]);
      const updatedProfile = await db.query(
        "UPDATE public.users SET name = 'Client One Updated' WHERE id = $1 RETURNING name",
        [ids.client],
      );
      assert.equal(updatedProfile.rows[0].name, 'Client One Updated');
      assert.equal(
        (await db.query('SELECT public.is_eligible_case_owner($1) AS eligible', [ids.otherClient])).rows[0]
          .eligible,
        false,
      );
      const visibleCases = await db.query('SELECT id FROM public.cases');
      assert.deepEqual(visibleCases.rows.map((row) => row.id), [caseId]);
      assert.deepEqual(
        (await db.query('SELECT user_id FROM public.earnings ORDER BY user_id')).rows,
        [{ user_id: ids.client }],
        'earnings RLS exposes only the current owner row',
      );
      assert.deepEqual(
        (await db.query('SELECT user_id FROM public.wallets')).rows,
        [{ user_id: ids.client }],
        'wallet RLS exposes only the current owner row',
      );
      assert.equal(
        (await db.query("SELECT id FROM public.lawyers WHERE id = 'lawyer-1'")).rows.length,
        1,
        'authenticated users may read the public lawyer catalogue',
      );
      await expectSqlError(
        "INSERT INTO public.lawyers (name, price) VALUES ('Client forged', '$1/hour')",
        [],
        '42501',
      );
      assert.equal(
        (await db.query("UPDATE public.lawyers SET name = 'Client forged' WHERE id = 'lawyer-1' RETURNING id"))
          .rows.length,
        0,
        'RLS must hide admin-only lawyer updates from a regular client',
      );
      await expectSqlError(
        'INSERT INTO public.cases (user_id, title) VALUES ($1, $2)',
        [ids.otherClient, 'Forged owner'],
        '42501',
      );
      await expectSqlError(
        "UPDATE public.users SET role = 'admin' WHERE id = $1",
        [ids.client],
        '42501',
      );
      await expectSqlError(
        'UPDATE public.users SET auth_user_id = $1 WHERE id = $2',
        [ids.otherClient, ids.client],
        '42501',
      );
      await expectSqlError(
        'UPDATE public.users SET uid = $1 WHERE id = $2',
        [ids.otherClient, ids.client],
        '42501',
      );
      await expectSqlError(
        "UPDATE public.users SET email = 'forged@example.test' WHERE id = $1",
        [ids.client],
        '42501',
      );
      await expectSqlError('SELECT user_id FROM public.reviews', [], '42501');
      await expectSqlError('SELECT user_id FROM public.lawyers', [], '42501');
      await expectSqlError('UPDATE public.earnings SET balance = 0 WHERE user_id = $1', [ids.client], '42501');
      await expectSqlError('UPDATE public.wallets SET balance = 0 WHERE user_id = $1', [ids.client], '42501');
      const readFlag = await db.query(
        'UPDATE public.notifications SET read = true WHERE id = $1 RETURNING read',
        [notificationId],
      );
      assert.equal(readFlag.rows[0].read, true, 'an owner may mark only the read flag');
      await expectSqlError(
        "UPDATE public.notifications SET content = 'forged' WHERE id = $1",
        [notificationId],
        '42501',
      );
      assert.equal((await db.query('SELECT user_name FROM public.public_reviews')).rows.length, 0);
      await expectSqlError(
        'INSERT INTO storage.objects (bucket_id, name) VALUES ($1, $2)',
        ['legal-documents', `${ids.otherClient}/documents/other.pdf`],
        '42501',
      );
      await expectSqlError(
        'INSERT INTO storage.objects (bucket_id, name) VALUES ($1, $2)',
        ['legal-documents', `${ids.client}/private/other.pdf`],
        '42501',
      );
      await expectSqlError(
        'INSERT INTO storage.objects (bucket_id, name) VALUES ($1, $2)',
        ['legal-documents', `${ids.client}/documents/other.txt`],
        '42501',
      );
      await expectSqlError(
        'INSERT INTO storage.objects (bucket_id, name) VALUES ($1, $2)',
        ['legal-documents', `${ids.client}/documents/../other.pdf`],
        '42501',
      );
      await expectSqlError(
        'INSERT INTO storage.objects (bucket_id, name) VALUES ($1, $2)',
        ['legal-documents', `${ids.client}/documents/opaque_123.pdf`],
        '42501',
      );
      // The trusted Edge upload uses the server-only Storage role only after
      // it validates the bytes and derives the mapped owner path.
      await db.exec('RESET ROLE');
      await db.exec('SET LOCAL ROLE service_role');
      const uploaded = await db.query(
        'INSERT INTO storage.objects (bucket_id, name) VALUES ($1, $2) RETURNING name',
        ['legal-documents', `${ids.client}/documents/opaque_123.pdf`],
      );
      assert.equal(uploaded.rows[0].name, `${ids.client}/documents/opaque_123.pdf`);
      await db.exec('SET LOCAL ROLE authenticated');
      await setSubject(ids.otherClient);
      assert.equal(
        (await db.query('SELECT id FROM storage.objects WHERE name = $1', [uploaded.rows[0].name]))
          .rows.length,
        0,
        'a different owner cannot read the private object',
      );
      assert.deepEqual(
        (await db.query('DELETE FROM storage.objects WHERE name = $1 RETURNING name', [uploaded.rows[0].name]))
          .rows,
        [],
        'a different owner cannot delete the private object',
      );
      await setSubject(ids.client);
      await expectSqlError(
        'UPDATE storage.objects SET name = $1 WHERE name = $2',
        [`${ids.client}/documents/renamed.pdf`, uploaded.rows[0].name],
        '42501',
      );
      assert.deepEqual(
        (await db.query('DELETE FROM storage.objects WHERE name = $1 RETURNING name', [uploaded.rows[0].name]))
          .rows,
        [{ name: uploaded.rows[0].name }],
        'the owner can remove the temporary PDF',
      );
    });

    await asRole('authenticated', ids.lawyer, async () => {
      assert.equal((await db.query("SELECT public.is_lawyer_owner('lawyer-1') AS allowed")).rows[0].allowed, true);
      assert.equal((await db.query("SELECT public.is_lawyer_owner('lawyer-2') AS allowed")).rows[0].allowed, false);
      const ownAvailability = await db.query(
        `INSERT INTO public.availability (lawyer_id, lawyer_name, date, slots)
         VALUES ('lawyer-1', 'Lawyer One', '2026-10-25', '["09:00"]'::jsonb)
         RETURNING id`,
      );
      assert.ok(ownAvailability.rows[0].id);
      await expectSqlError(
        `INSERT INTO public.availability (lawyer_id, lawyer_name, date, slots)
         VALUES ('lawyer-2', 'Forged Lawyer', '2026-10-25', '["09:00"]'::jsonb)`,
        [],
        '42501',
      );
      await expectSqlError(
        `INSERT INTO public.availability (lawyer_id, lawyer_name, date, slots)
         VALUES ('not-owned-lawyer', 'Lawyer One', '2026-10-25', '["09:00"]'::jsonb)`,
        [],
        '42501',
      );
    });

    await asRole('authenticated', ids.otherLawyer, async () => {
      const ownAvailability = await db.query(
        `INSERT INTO public.availability (lawyer_id, lawyer_name, date, slots)
         VALUES ('lawyer-2', 'Second Lawyer', '2026-10-25', '["10:00"]'::jsonb)
         RETURNING id`,
      );
      assert.ok(ownAvailability.rows[0].id);
      await expectSqlError(
        `INSERT INTO public.availability (lawyer_id, lawyer_name, date, slots)
         VALUES ('lawyer-1', 'Forged Lawyer', '2026-10-25', '["11:00"]'::jsonb)`,
        [],
        '42501',
      );
    });

    await asRole('authenticated', ids.admin, async () => {
      const allUsers = await db.query('SELECT id FROM public.users');
      assert.ok(allUsers.rows.length >= 7);
      const stats = await db.query('SELECT public.rpc_dashboard_stats() AS result');
      assert.equal(stats.rows[0].result.lawyers, 3);

      const createdLawyer = await db.query(
        `INSERT INTO public.lawyers (name, price)
         VALUES ('Admin-managed counsel', '$250/hour') RETURNING id`,
      );
      const createdId = createdLawyer.rows[0].id;
      assert.ok(createdId);
      const updatedLawyer = await db.query(
        'UPDATE public.lawyers SET name = $1 WHERE id = $2 RETURNING name',
        ['Updated counsel', createdId],
      );
      assert.equal(updatedLawyer.rows[0].name, 'Updated counsel');
      const deletedLawyer = await db.query(
        'DELETE FROM public.lawyers WHERE id = $1 RETURNING id',
        [createdId],
      );
      assert.equal(deletedLawyer.rows[0].id, createdId);
    });
  });

  it('enforces favorites owner isolation for reads, inserts, RPCs, and deletes', async () => {
    let clientFavoriteId;
    let otherFavoriteId;

    // Keep both owners' actions in one transaction so each principal observes
    // the same rows while the test still rolls back its fixture mutations.
    await db.exec('BEGIN');
    try {
      await db.exec('SET LOCAL ROLE authenticated');
      await setSubject(ids.client);
      const favorite = (await db.query(
        "SELECT public.rpc_favorite_add('lawyer-1') AS result",
      )).rows[0].result;
      clientFavoriteId = favorite.id;
      assert.equal(favorite.user_id, ids.client);
      assert.equal(favorite.lawyer_id, 'lawyer-1');
      assert.deepEqual(
        (await db.query('SELECT id FROM public.favorites ORDER BY id')).rows.map((row) => row.id),
        [clientFavoriteId],
      );

      await expectSqlError(
        'INSERT INTO public.favorites (user_id, lawyer_id) VALUES ($1, $2)',
        [ids.otherClient, 'lawyer-1'],
        '42501',
      );
      await expectSqlError(
        'UPDATE public.favorites SET lawyer_id = $1 WHERE id = $2',
        ['lawyer-1', clientFavoriteId],
        '42501',
      );

      await setSubject(ids.otherClient);
      assert.deepEqual(
        (await db.query('SELECT id FROM public.favorites ORDER BY id')).rows,
        [],
        'RLS hides a different owner\'s saved lawyer',
      );
      assert.deepEqual(
        (await db.query('DELETE FROM public.favorites WHERE id = $1 RETURNING id', [clientFavoriteId]))
          .rows,
        [],
        'RLS makes cross-owner deletion a no-op',
      );

      const otherFavorite = (await db.query(
        "SELECT public.rpc_favorite_add('lawyer-1') AS result",
      )).rows[0].result;
      otherFavoriteId = otherFavorite.id;
      assert.notEqual(otherFavoriteId, clientFavoriteId);
      assert.equal(otherFavorite.user_id, ids.otherClient);
      assert.deepEqual(
        (await db.query('SELECT id FROM public.favorites ORDER BY id')).rows.map((row) => row.id),
        [otherFavoriteId],
      );

      await setSubject(ids.client);
      assert.deepEqual(
        (await db.query('SELECT id FROM public.favorites ORDER BY id')).rows.map((row) => row.id),
        [clientFavoriteId],
        'the original owner still sees only their own favorite',
      );
      assert.deepEqual(
        (await db.query('DELETE FROM public.favorites WHERE id = $1 RETURNING id', [clientFavoriteId]))
          .rows,
        [{ id: clientFavoriteId }],
        'the owner can remove their favorite',
      );

      await setSubject(ids.otherClient);
      assert.deepEqual(
        (await db.query('SELECT id FROM public.favorites ORDER BY id')).rows.map((row) => row.id),
        [otherFavoriteId],
        'the other owner\'s row remains untouched',
      );
    } finally {
      await db.exec('ROLLBACK');
    }

    await asRole('anon', null, async () => {
      await expectSqlError('SELECT id FROM public.favorites', [], '42501');
      await expectSqlError(
        "SELECT public.rpc_favorite_add('lawyer-1')",
        [],
        '42501',
      );
    });
  });

  it('reserves, replays, conflicts, reschedules, and cancels bookings atomically', async () => {
    await asRole('authenticated', ids.client, async () => {
      const first = (await db.query(
        "SELECT public.rpc_create_booking('lawyer-1', '2026-10-24', '9:00 am', 1, 'booking-key-1') AS result",
      )).rows[0].result;
      assert.equal(first.replayed, false);
      assert.equal(first.booking.user_id, ids.client);
      assert.equal(first.booking.status, 'Pending');
      assert.equal(Number(first.booking.total_price), 100);
      const firstId = first.booking.id;
      assert.equal(first.booking.slot_keys.length, 1);

      const replay = (await db.query(
        "SELECT public.rpc_create_booking('lawyer-1', '2026-10-24', '09:00', 1, 'booking-key-1') AS result",
      )).rows[0].result;
      assert.equal(replay.replayed, true);
      assert.equal(replay.booking.id, firstId);

      const mismatch = (await db.query(
        "SELECT public.rpc_create_booking('lawyer-1', '2026-10-24', '10:00', 1, 'booking-key-1') AS result",
      )).rows[0].result;
      assert.equal(mismatch.error, 'IDEMPOTENCY_KEY_MISMATCH');

      const second = (await db.query(
        "SELECT public.rpc_create_booking('lawyer-1', '2026-10-24', '10:00', 1, 'booking-key-2') AS result",
      )).rows[0].result;
      assert.equal(second.replayed, false);
      const conflicting = (await db.query(
        "SELECT public.rpc_create_booking('lawyer-1', '2026-10-24', '09:00', 1, 'booking-key-3') AS result",
      )).rows[0].result;
      assert.equal(conflicting.error, 'BOOKING_OVERLAP');

      await expectSqlError(
        'SELECT public.rpc_admin_set_booking_status($1, $2)',
        [firstId, 'Completed'],
        '42501',
      );
      await setSubject(ids.otherClient);
      await expectSqlError(
        'SELECT public.rpc_cancel_booking($1)',
        [second.booking.id],
        '42501',
      );
      await expectSqlError(
        'SELECT public.rpc_delete_booking($1)',
        [second.booking.id],
        '42501',
      );
      await setSubject(ids.client);

      const cancelled = (await db.query('SELECT public.rpc_cancel_booking($1) AS result', [
        firstId,
      ])).rows[0].result;
      assert.equal(cancelled.status, 'Cancelled');
      assert.deepEqual(cancelled.slot_keys, []);
      assert.equal(
        (await db.query('SELECT count(*)::int AS n FROM public.booking_slots WHERE booking_id = $1', [
          firstId,
        ])).rows[0].n,
        0,
      );
      await setSubject(ids.admin);
      await expectSqlError(
        'SELECT public.rpc_admin_set_booking_status($1, $2)',
        [firstId, 'Active'],
        '22023',
      );
      assert.equal(
        (await db.query('SELECT status FROM public.bookings WHERE id = $1', [firstId])).rows[0].status,
        'Cancelled',
      );
      await setSubject(ids.client);

      const third = (await db.query(
        "SELECT public.rpc_create_booking('lawyer-1', '2026-10-24', '09:00', 1, 'booking-key-4') AS result",
      )).rows[0].result;
      assert.equal(third.error, undefined);
      assert.equal(third.booking.status, 'Pending');

      // Move the administrator's JWT into the same transaction. A conflict
      // must keep the original lock and booking intact.
      await setSubject(ids.admin);
      const rescheduleConflict = (await db.query(
        'SELECT public.rpc_admin_reschedule_booking($1, $2, $3, $4, $5) AS result',
        [third.booking.id, 'lawyer-1', '2026-10-24', '10:00', 1],
      )).rows[0].result;
      assert.equal(rescheduleConflict.error, 'BOOKING_OVERLAP');
      const unchanged = await db.query('SELECT date, time FROM public.bookings WHERE id = $1', [
        third.booking.id,
      ]);
      assert.equal(unchanged.rows[0].time, '09:00');
      assert.equal(
        (await db.query('SELECT count(*)::int AS n FROM public.booking_slots WHERE booking_id = $1', [
          third.booking.id,
        ])).rows[0].n,
        1,
      );
      const deleted = (await db.query('SELECT public.rpc_delete_booking($1) AS result', [
        third.booking.id,
      ])).rows[0].result;
      assert.deepEqual(deleted, { id: third.booking.id });
      assert.equal(
        (await db.query('SELECT count(*)::int AS n FROM public.bookings WHERE id = $1', [
          third.booking.id,
        ])).rows[0].n,
        0,
      );
      assert.equal(
        (await db.query('SELECT count(*)::int AS n FROM public.booking_slots WHERE booking_id = $1', [
          third.booking.id,
        ])).rows[0].n,
        0,
      );
    });

    await asRole('authenticated', null, async () => {
      await expectSqlError(
        "SELECT public.rpc_create_booking('lawyer-1', '2026-10-24', '09:00', 1, NULL)",
        [],
        '42501',
      );
    });
  });

  it('keeps wallet balance, ledger, idempotency, and authorization in one transaction', async () => {
    await asRole('authenticated', ids.client, async () => {
      await expectSqlError(
        "SELECT public.rpc_wallet_mutate($1, 'credit', 500, 'unverified top-up', 'credit-key')",
        [ids.client],
        '42501',
      );
      const insufficient = (await db.query(
        "SELECT public.rpc_wallet_mutate($1, 'debit', 501, 'too much', 'debit-key') AS result",
        [ids.client],
      )).rows[0].result;
      assert.equal(insufficient.error, 'INSUFFICIENT_FUNDS');
      assert.equal(Number(insufficient.available), 500);

      await setSubject(ids.admin);
      await expectSqlError(
        'UPDATE public.wallets SET balance = 1000 WHERE user_id = $1',
        [ids.client],
        '42501',
      );

      await setSubject(ids.client);
      const debit = (await db.query(
        "SELECT public.rpc_wallet_mutate($1, 'debit', 100, 'client spend', 'debit-key') AS result",
        [ids.client],
      )).rows[0].result;
      assert.equal(Number(debit.balance), 400);
      assert.equal(Object.hasOwn(debit.transaction, 'idempotency_key_hash'), false);
      const replay = (await db.query(
        "SELECT public.rpc_wallet_mutate($1, 'debit', 100, 'client spend', '  debit-key  ') AS result",
        [ids.client],
      )).rows[0].result;
      assert.equal(replay.replayed, true);
      assert.equal(Number(replay.balance), 400);
      assert.equal(Object.hasOwn(replay.transaction, 'idempotency_key_hash'), false);
      const mismatch = (await db.query(
        "SELECT public.rpc_wallet_mutate($1, 'debit', 50, 'different operation', 'debit-key') AS result",
        [ids.client],
      )).rows[0].result;
      assert.equal(mismatch.error, 'IDEMPOTENCY_KEY_MISMATCH');
      const wallet = await db.query('SELECT balance FROM public.wallets WHERE user_id = $1', [
        ids.client,
      ]);
      assert.equal(Number(wallet.rows[0].balance), 400);
      const ledger = await db.query(
        'SELECT count(id)::int AS n FROM public.wallet_transactions WHERE user_id = $1',
        [ids.client],
      );
      assert.equal(ledger.rows[0].n, 1);

      // PGlite's test-only digest is intentionally not cryptographic, but the
      // exact UTF-8(owner) + NUL + trimmed-key bytes must match the Express
      // contract and the same digest must key both persisted records.
      const digestInputHex = Buffer.from(`${ids.client}\u0000debit-key`, 'utf8').toString('hex');
      const expectedTestDigest =
        createHash('md5').update(digestInputHex).digest('hex') +
        createHash('md5').update(`sha256${digestInputHex}`).digest('hex');
      await expectSqlError(
        'SELECT idempotency_key_hash FROM public.wallet_transactions WHERE user_id = $1',
        [ids.client],
        '42501',
      );
      const visibleTransactions = await db.query(
        'SELECT id,user_id,type,amount,description,balance,currency,created_at,updated_at FROM public.wallet_transactions WHERE user_id = $1',
        [ids.client],
      );
      assert.equal(Object.hasOwn(visibleTransactions.rows[0], 'idempotency_key_hash'), false);
      await expectSqlError('SELECT id FROM public.wallet_idempotency WHERE user_id = $1', [ids.client]);
      await db.exec('RESET ROLE');
      const persistedHash = (await db.query(
        'SELECT idempotency_key_hash FROM public.wallet_transactions WHERE user_id = $1',
        [ids.client],
      )).rows[0].idempotency_key_hash;
      assert.equal(persistedHash, expectedTestDigest);
      assert.equal(
        (await db.query('SELECT id FROM public.wallet_idempotency WHERE user_id = $1', [ids.client]))
          .rows[0].id,
        expectedTestDigest,
      );
      await db.exec('SET LOCAL ROLE authenticated');

      await setSubject(ids.otherClient);
      assert.deepEqual((await db.query('SELECT user_id FROM public.wallets')).rows, []);
      assert.deepEqual((await db.query('SELECT user_id FROM public.wallet_transactions')).rows, []);
      await expectSqlError(
        "SELECT public.rpc_wallet_mutate($1, 'debit', 1, 'cross-user', NULL)",
        [ids.client],
        '42501',
      );

      await setSubject(ids.admin);
      const adminCredit = (await db.query(
        "SELECT public.rpc_wallet_mutate($1, 'credit', 50, 'manual Admin adjustment', 'admin-credit-key') AS result",
        [ids.client],
      )).rows[0].result;
      assert.equal(Number(adminCredit.balance), 450);
      const adminCreditReplay = (await db.query(
        "SELECT public.rpc_wallet_mutate($1, 'credit', 50, 'manual Admin adjustment', ' admin-credit-key ') AS result",
        [ids.client],
      )).rows[0].result;
      assert.equal(adminCreditReplay.replayed, true);
      assert.equal(Number(adminCreditReplay.balance), 450);
    });

    await asRole('service_role', null, async () => {
      await expectSqlError(
        "SELECT public.rpc_wallet_mutate($1, 'credit', 1, 'service bypass', NULL)",
        [ids.client],
        '42501',
      );
    });
  });

  it('makes chat, review, task, case, subscription, and favorite workflows role-safe', async () => {
    await asRole('authenticated', ids.client, async () => {
      await expectSqlError(
        'SELECT public.rpc_notification_update($1, $2::jsonb)',
        [notificationId, JSON.stringify({ title: 'Owner content edit' })],
        '42501',
      );
      await expectSqlError(
        'SELECT public.rpc_notification_update($1, $2::jsonb)',
        [notificationId, JSON.stringify({ user_id: ids.otherClient })],
        '42501',
      );
      const ownNotification = (await db.query(
        'SELECT public.rpc_notification_update($1, $2::jsonb) AS result',
        [notificationId, JSON.stringify({ read: true })],
      )).rows[0].result;
      assert.equal(ownNotification.title, 'Original notice');
      assert.equal(ownNotification.content, 'Initial content');
      assert.equal(ownNotification.read, true);
      assert.equal(ownNotification.user_id, ids.client, 'a client cannot reassign its notice');

      const createdChat = (await db.query(
        'SELECT public.rpc_chat_create(ARRAY[$1, $2], $3) AS result',
        [ids.client, ids.lawyer, 'Initial message'],
      )).rows[0].result;
      const chatId = createdChat.chat.id;
      assert.equal(createdChat.chat.last_message, 'Initial message');
      assert.equal(createdChat.message.sender_id, ids.client);
      assert.equal(createdChat.message.sender_name, 'Client One');
      assert.equal(createdChat.chat.participant_names[ids.lawyer], 'Lawyer One');

      const sent = (await db.query(
        'SELECT public.rpc_chat_send_message($1, $2) AS result',
        [chatId, 'Follow-up'],
      )).rows[0].result;
      assert.equal(sent.sender_id, ids.client);
      assert.equal(
        (await db.query('SELECT last_message FROM public.chats WHERE id = $1', [chatId])).rows[0]
          .last_message,
        'Follow-up',
      );
      await expectSqlError('UPDATE public.chats SET participants = ARRAY[$1] WHERE id = $2', [
        ids.client,
        chatId,
      ]);
      await setSubject(ids.otherClient);
      assert.equal((await db.query('SELECT id FROM public.chats WHERE id = $1', [chatId])).rows.length, 0);
      await expectSqlError(
        'SELECT public.rpc_notification_update($1, $2::jsonb)',
        [notificationId, JSON.stringify({ title: 'Cross-user edit' })],
        '42501',
      );
      await expectSqlError(
        'SELECT public.rpc_task_update($1, $2::jsonb)',
        [taskId, JSON.stringify({ title: 'Cross-owner task edit' })],
        '42501',
      );
      await expectSqlError(
        'SELECT public.rpc_chat_send_message($1, $2)',
        [chatId, 'forged'],
        '42501',
      );

      await setSubject(ids.client);
      const review = (await db.query(
        "SELECT public.rpc_review_submit('lawyer-1', 4.5, 'Helpful counsel') AS result",
      )).rows[0].result;
      assert.equal(review.user_id, ids.client);
      assert.equal(review.user_name, 'Client One');
      assert.equal(
        (await db.query("SELECT rating FROM public.lawyers WHERE id = 'lawyer-1'")).rows[0].rating,
        '4.50',
      );
      const duplicateReview = (await db.query(
        "SELECT public.rpc_review_submit('lawyer-1', 5, 'duplicate') AS result",
      )).rows[0].result;
      assert.equal(duplicateReview.error, 'DUPLICATE_REVIEW');
      const publicReview = await db.query('SELECT * FROM public.public_reviews');
      assert.equal(publicReview.rows.length, 1);
      assert.equal(Object.hasOwn(publicReview.rows[0], 'user_id'), false);

      const task = (await db.query('SELECT public.rpc_task_set_status($1, $2) AS result', [
        taskId,
        'In Progress',
      ])).rows[0].result;
      assert.equal(task.status, 'In Progress');
      assert.equal(
        (await db.query('SELECT public.rpc_task_set_status($1, $2) AS result', [
          taskId,
          'Completed',
        ])).rows[0].result.status,
        'Completed',
      );
      await expectSqlError(
        'SELECT public.rpc_task_set_status($1, $2)',
        [taskId, 'Cancelled'],
      );
      const taskPatch = (await db.query(
        'SELECT public.rpc_task_update($1, $2::jsonb) AS result',
        [taskId, JSON.stringify({ title: 'Prepare exhibits', description: 'Collect signed copies' })],
      )).rows[0].result;
      assert.equal(taskPatch.title, 'Prepare exhibits');
      assert.equal(taskPatch.description, 'Collect signed copies');
      await expectSqlError(
        'SELECT public.rpc_task_update($1, $2::jsonb)',
        [taskId, JSON.stringify({ status: 'Cancelled' })],
        '42501',
      );
      const casePatch = (await db.query(
        'SELECT public.rpc_case_update($1, $2::jsonb) AS result',
        [caseId, JSON.stringify({ title: 'Updated client case', description: 'Reviewed by counsel', status: 'In Progress' })],
      )).rows[0].result;
      assert.equal(casePatch.title, 'Updated client case');
      assert.equal(casePatch.status, 'In Progress');
      await expectSqlError(
        'SELECT public.rpc_case_update($1, $2::jsonb)',
        [caseId, JSON.stringify({ user_id: ids.otherClient })],
        '42501',
      );
      await expectSqlError(
        'SELECT public.rpc_case_set_status($1, $2)',
        ['nonexistent-case', 'Closed'],
        'P0002',
      );
      const closed = (await db.query('SELECT public.rpc_case_set_status($1, $2) AS result', [
        caseId,
        'Closed',
      ])).rows[0].result;
      assert.equal(closed.status, 'Closed');
      await setSubject(ids.otherClient);
      await expectSqlError(
        'SELECT public.rpc_case_set_status($1, $2)',
        [unassignedCaseId, 'Closed'],
        '42501',
      );
      await setSubject(ids.admin);
      const adminClosedUnassigned = (await db.query(
        'SELECT public.rpc_case_set_status($1, $2) AS result',
        [unassignedCaseId, 'Closed'],
      )).rows[0].result;
      assert.equal(adminClosedUnassigned.status, 'Closed');
      await setSubject(ids.client);

      const favorite1 = (await db.query(
        "SELECT public.rpc_favorite_add('lawyer-1') AS result",
      )).rows[0].result;
      const favorite2 = (await db.query(
        "SELECT public.rpc_favorite_add('lawyer-1') AS result",
      )).rows[0].result;
      assert.equal(favorite2.id, favorite1.id);

      const subscription = (await db.query('SELECT public.rpc_subscription_create($1) AS result', [
        planId,
      ])).rows[0].result;
      assert.equal(subscription.status, 'Pending');
      assert.equal(subscription.plan_title, 'Standard');
      assert.equal(
        (await db.query("SELECT to_regprocedure('public.rpc_admin_set_subscription_status(text,text,timestamptz,timestamptz)') IS NULL AS missing"))
          .rows[0].missing,
        true,
        'paid subscription activation is not exposed as an authenticated RPC',
      );
      await expectSqlError(
        "UPDATE public.subscriptions SET status = 'Active' WHERE id = $1",
        [subscription.id],
        '42501',
      );
      await setSubject(ids.admin);
      await expectSqlError(
        "UPDATE public.subscriptions SET status = 'Active' WHERE id = $1",
        [subscription.id],
        '42501',
      );
      await setSubject(ids.client);
      const cancelled = (await db.query('SELECT public.rpc_subscription_cancel($1) AS result', [
        subscription.id,
      ])).rows[0].result;
      assert.equal(cancelled.status, 'Cancelled');
      assert.equal(
        (await db.query('SELECT public.rpc_subscription_delete($1) AS result', [subscription.id]))
          .rows[0].result.deleted,
        true,
      );

      await expectSqlError(
        'SELECT public.rpc_admin_set_user_role($1, $2)',
        [ids.otherClient, 'admin'],
        '42501',
      );
      await expectSqlError(
        'SELECT public.rpc_admin_review_moderate($1, $2, $3)',
        [review.id, 5, 'forged admin moderation'],
        '42501',
      );

      const activeSubscription = (await db.query(
        'SELECT public.rpc_subscription_create($1) AS result',
        [planId],
      )).rows[0].result;

      await setSubject(ids.admin);
      const reassignedNotification = (await db.query(
        'SELECT public.rpc_notification_update($1, $2::jsonb) AS result',
        [notificationId, JSON.stringify({ user_id: ids.otherClient, type: 'account' })],
      )).rows[0].result;
      assert.equal(reassignedNotification.user_id, ids.otherClient);
      assert.equal(reassignedNotification.type, 'account');
      const assigned = (await db.query(
        'SELECT public.rpc_admin_assign_case_owner($1, $2) AS result',
        [caseId, ids.lawyer],
      )).rows[0].result;
      assert.equal(assigned.user_id, ids.lawyer);
      const roleChanged = (await db.query(
        "SELECT public.rpc_admin_set_user_role($1, 'client') AS result",
        [ids.otherClient],
      )).rows[0].result;
      assert.equal(roleChanged.role, 'client');
      const secondAdmin = (await db.query(
        "SELECT public.rpc_admin_set_user_role($1, 'admin') AS result",
        [ids.otherClient],
      )).rows[0].result;
      assert.equal(secondAdmin.role, 'admin');
      const demotedAdmin = (await db.query(
        "SELECT public.rpc_admin_set_user_role($1, 'client') AS result",
        [ids.otherClient],
      )).rows[0].result;
      assert.equal(demotedAdmin.role, 'client');
      await expectSqlError(
        "SELECT public.rpc_admin_set_user_role($1, 'client')",
        [ids.admin],
        '42501',
      );
      assert.equal(
        (await db.query('SELECT role FROM public.users WHERE id = $1', [ids.admin])).rows[0].role,
        'admin',
        'the final administrator cannot demote themselves',
      );
      await db.query('SELECT public.rpc_admin_review_moderate($1, $2, $3)', [
        review.id,
        5,
        'Moderated review',
      ]);
      assert.equal(
        (await db.query("SELECT rating FROM public.lawyers WHERE id = 'lawyer-1'")).rows[0].rating,
        '5.00',
      );
      await db.query('SELECT public.rpc_admin_review_delete($1)', [review.id]);
      assert.equal(
        (await db.query("SELECT rating FROM public.lawyers WHERE id = 'lawyer-1'")).rows[0].rating,
        '0.00',
      );

      // Only the privileged test fixture marks this subscription active; no
      // authenticated PostgREST RPC/table grant can grant the entitlement.
      await db.exec('RESET ROLE');
      await db.query("UPDATE public.subscriptions SET status = 'Active' WHERE id = $1", [
        activeSubscription.id,
      ]);
      await db.exec('SET LOCAL ROLE authenticated');
      await setSubject(ids.admin);
      await expectSqlError(
        "UPDATE public.subscriptions SET status = 'Cancelled' WHERE id = $1",
        [activeSubscription.id],
        '42501',
      );
      await expectSqlError(
        'SELECT public.rpc_subscription_delete($1)',
        [activeSubscription.id],
        '42501',
      );
      await setSubject(ids.client);
      await expectSqlError(
        'SELECT public.rpc_subscription_delete($1)',
        [activeSubscription.id],
        '42501',
      );
      const activeCancelled = (await db.query(
        'SELECT public.rpc_subscription_cancel($1) AS result',
        [activeSubscription.id],
      )).rows[0].result;
      assert.equal(activeCancelled.status, 'Cancelled');
      assert.equal(
        (await db.query('SELECT public.rpc_subscription_delete($1) AS result', [activeSubscription.id]))
          .rows[0].result.deleted,
        true,
      );
    });
  });

  it('keeps public reviews visible through a security-invoker view without exposing reviewer IDs', async () => {
    await db.exec('BEGIN');
    try {
      await db.exec('SET LOCAL ROLE authenticated');
      await setSubject(ids.client);
      const submitted = (await db.query(
        "SELECT public.rpc_review_submit('lawyer-1', 4, 'Public-safe review') AS result",
      )).rows[0].result;
      assert.equal(submitted.user_id, ids.client);

      await db.exec('RESET ROLE');
      await db.exec('SET LOCAL ROLE anon');
      await setSubject(null, 'anon');
      const anonView = await db.query('SELECT * FROM public.public_reviews');
      assert.equal(anonView.rows.length, 1);
      assert.equal(anonView.rows[0].user_name, 'Client One');
      assert.equal(Object.hasOwn(anonView.rows[0], 'user_id'), false);
      assert.equal((await db.query('SELECT id, user_name FROM public.reviews')).rows.length, 1);
      await expectSqlError('SELECT user_id FROM public.reviews', [], '42501');

      await db.exec('RESET ROLE');
      await db.exec('SET LOCAL ROLE authenticated');
      await setSubject(ids.otherClient);
      const otherView = await db.query('SELECT id, user_name FROM public.public_reviews');
      assert.equal(otherView.rows.length, 1, 'review text remains public to authenticated users');
      await expectSqlError('SELECT user_id FROM public.reviews', [], '42501');
    } finally {
      await db.exec('ROLLBACK');
    }
  });
});

describe('legal categories and lawyer/case assignments (isolated PGlite migration test)', () => {
  let categoryDb;
  const categoryAdmin = '00000000-0000-4000-8000-000000000021';
  const categoryClient = '00000000-0000-4000-8000-000000000022';
  let corporateCategoryId;
  let familyCategoryId;

  async function setCategorySubject(subject, role = 'authenticated') {
    await categoryDb.query("SELECT set_config('request.jwt.claim.sub', $1, true)", [subject ?? '']);
    await categoryDb.query("SELECT set_config('request.jwt.claim.role', $1, true)", [role]);
  }

  async function withCategoryAdmin(callback) {
    await categoryDb.exec('BEGIN');
    try {
      await categoryDb.exec('SET LOCAL ROLE authenticated');
      await setCategorySubject(categoryAdmin);
      const result = await callback();
      await categoryDb.exec('COMMIT');
      return result;
    } catch (error) {
      await categoryDb.exec('ROLLBACK');
      throw error;
    }
  }

  async function expectCategorySqlError(
    statement,
    parameters,
    expectedCode,
    { withinTransaction = false } = {},
  ) {
    if (!withinTransaction) await categoryDb.exec('BEGIN');
    await categoryDb.exec('SAVEPOINT expected_category_sql_error');
    let caught;
    try {
      await categoryDb.query(statement, parameters);
    } catch (error) {
      caught = error;
    }
    await categoryDb.exec('ROLLBACK TO SAVEPOINT expected_category_sql_error');
    await categoryDb.exec('RELEASE SAVEPOINT expected_category_sql_error');
    if (!withinTransaction) await categoryDb.exec('ROLLBACK');
    if (!caught) {
      assert.fail(`Expected SQLSTATE ${expectedCode}, but statement succeeded: ${statement}`);
    }
    if (Array.isArray(expectedCode)) {
      assert.ok(expectedCode.includes(caught.code), `${caught.message} (SQLSTATE ${caught.code})`);
    } else {
      assert.equal(caught.code, expectedCode, caught.message);
    }
  }

  before(async () => {
    categoryDb = new PGlite();
    await categoryDb.exec(bootstrapSql);
    const files = await migrationFiles();
    assert.deepEqual(files, [
      '20261022174110_initial_legal_schema_and_rls.sql',
      '20261022174313_transactional_rpc_functions.sql',
      '20261024020757_conservative_live_security_hardening.sql',
      '20261024021003_close_anon_internal_function_access.sql',
      '20261024021013_restrict_rls_helper_function_execution.sql',
      '20261024021402_add_missing_foreign_key_indexes.sql',
      '20261024021409_tighten_availability_and_user_identity.sql',
      '20261024021423_restrict_subscription_owner_updates.sql',
      categoryMigrationFile,
      '20261024123238_secure_rls_helper_functions_private_schema.sql',
      '20261025140000_supabase_security_storage.sql',
      '20261025141000_identity_owner_lawyer_access.sql',
      '20261025142000_authenticated_transactional_rpcs.sql',
      '20261025143000_supabase_native_workflows.sql',
      '20261025144000_admin_native_workflows.sql',
    ]);
    await applyMigrations(categoryDb, files.slice(0, 2));

    // Existing free-text lawyers/cases survive the additive relation migration
    // unchanged; their new foreign-key columns remain NULL until explicitly
    // assigned by an administrator.
    await categoryDb.query(
      `INSERT INTO public.lawyers (id, name, specialty, price, price_value)
       VALUES ('legacy-category-lawyer', 'Legacy Counsel', 'General Practice', '$100/hour', 100)`,
    );
    await categoryDb.query(
      `INSERT INTO public.cases (id, title, case_type)
       VALUES ('legacy-category-case', 'Legacy case', 'Unmapped legacy type')`,
    );
    await applyMigrations(categoryDb, files.slice(2));

    // Reproduce the already-present live composite index. The similarly shaped
    // local candidate uses a different name and would create a duplicate, so it
    // must stay archived and out of active migration discovery.
    await categoryDb.exec(
      'CREATE INDEX cases_lawyer_category_idx ON public.cases USING btree (lawyer_id, category_id)',
    );

    // A profile id equal to auth.uid() is sufficient for is_admin() in the
    // isolated RLS test; no Firebase/production identities or data are used.
    await categoryDb.query(
      `INSERT INTO public.users (id, uid, name, email, role)
       VALUES ($1, $1, 'Category Admin', 'category-admin@example.test', 'admin')`,
      [categoryAdmin],
    );
  });

  after(async () => {
    await categoryDb?.close();
  });

  it('adds a public read-only category catalogue, admin-only writes and safe case/lawyer relationships', async () => {
    const existing = await categoryDb.query(`
      SELECT l.category_id AS lawyer_category, l.experience,
             c.lawyer_id AS case_lawyer, c.category_id AS case_category,
             c.case_type
        FROM public.lawyers l CROSS JOIN public.cases c
       WHERE l.id = 'legacy-category-lawyer' AND c.id = 'legacy-category-case'
    `);
    assert.deepEqual(existing.rows[0], {
      lawyer_category: null,
      experience: '',
      case_lawyer: null,
      case_category: null,
      case_type: 'Unmapped legacy type',
    });
    const assignmentIndex = await categoryDb.query(
      "SELECT indexname, indexdef FROM pg_indexes WHERE schemaname='public' AND tablename='cases' AND indexname='cases_lawyer_category_idx'",
    );
    assert.equal(assignmentIndex.rows.length, 1);
    assert.match(assignmentIndex.rows[0].indexdef, /\(lawyer_id, category_id\)/);
    const duplicateCandidateIndex = await categoryDb.query(
      "SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='cases' AND indexname='idx_cases_lawyer_category'",
    );
    assert.equal(duplicateCandidateIndex.rows.length, 0);

    await categoryDb.exec('BEGIN');
    try {
      await categoryDb.exec('SET LOCAL ROLE anon');
      await setCategorySubject(null, 'anon');
      assert.deepEqual(
        (await categoryDb.query('SELECT id, name, slug FROM public.legal_categories')).rows,
        [],
      );
      await expectCategorySqlError(
        `INSERT INTO public.legal_categories (id, name, slug)
         VALUES ('anon-category', 'Anonymous Category', 'anonymous-category')`,
        [],
        '42501',
        { withinTransaction: true },
      );
    } finally {
      await categoryDb.exec('ROLLBACK');
    }

    await categoryDb.exec('BEGIN');
    try {
      await categoryDb.exec('SET LOCAL ROLE authenticated');
      await setCategorySubject(categoryClient);
      await expectCategorySqlError(
        `INSERT INTO public.legal_categories (id, name, slug)
         VALUES ('client-category', 'Client Category', 'client-category')`,
        [],
        '42501',
        { withinTransaction: true },
      );
    } finally {
      await categoryDb.exec('ROLLBACK');
    }

    await withCategoryAdmin(async () => {
      corporateCategoryId = (await categoryDb.query(
        `INSERT INTO public.legal_categories (name, slug)
         VALUES ('Corporate Law', 'corporate-law') RETURNING id`,
      )).rows[0].id;
      familyCategoryId = (await categoryDb.query(
        `INSERT INTO public.legal_categories (name, slug)
         VALUES ('Family Law', 'family-law') RETURNING id`,
      )).rows[0].id;
    });

    await categoryDb.query(
      `INSERT INTO public.lawyers
         (id, name, specialty, price, price_value, category_id)
       VALUES ('categorized-lawyer', 'Category Counsel', 'Corporate Law', '$150/hour', 150, $1)`,
      [corporateCategoryId],
    );
    await categoryDb.query(
      `INSERT INTO public.cases (id, title, lawyer_id, category_id, case_type)
       VALUES ('categorized-case', 'Assigned case', 'categorized-lawyer', $1, 'Corporate Law')`,
      [corporateCategoryId],
    );

    await expectCategorySqlError(
      `INSERT INTO public.cases (id, title, lawyer_id)
       VALUES ('lawyer-only-case', 'Incomplete assignment', 'categorized-lawyer')`,
      [],
      '23514',
    );
    await expectCategorySqlError(
      `INSERT INTO public.cases (id, title, category_id)
       VALUES ('category-only-case', 'Incomplete assignment', $1)`,
      [corporateCategoryId],
      '23514',
    );
    await expectCategorySqlError(
      `INSERT INTO public.cases (id, title, lawyer_id, category_id)
       VALUES ('mismatched-case', 'Mismatched assignment', 'categorized-lawyer', $1)`,
      [familyCategoryId],
      '23503',
    );
    await expectCategorySqlError(
      'DELETE FROM public.legal_categories WHERE id = $1',
      [corporateCategoryId],
      ['23503', '23001'],
    );

    await withCategoryAdmin(async () => {
      await categoryDb.query(
        `UPDATE public.legal_categories
            SET name = 'Commercial Law', slug = 'commercial-law'
          WHERE id = $1`,
        [corporateCategoryId],
      );
      await categoryDb.query(
        'DELETE FROM public.legal_categories WHERE id = $1',
        [familyCategoryId],
      );
    });

    assert.deepEqual(
      (await categoryDb.query(`
        SELECT l.specialty, c.case_type
          FROM public.lawyers l CROSS JOIN public.cases c
         WHERE l.id = 'categorized-lawyer' AND c.id = 'categorized-case'
      `)).rows[0],
      { specialty: 'Commercial Law', case_type: 'Commercial Law' },
    );
    assert.equal(
      (await categoryDb.query('SELECT count(*)::int AS n FROM public.legal_categories')).rows[0].n,
      1,
    );

    await assert.rejects(
      () => categoryDb.query(
        `INSERT INTO public.legal_categories (id, name, slug)
         VALUES ('duplicate-name', 'commercial law', 'commercial-law-2')`,
      ),
      (error) => error.code === '23505',
    );
  });

  it('exposes private lawyer links only through the administrator-checked RPC', async () => {
    const lawyerUserId = 'category-lawyer-profile';
    const categoryName = (await categoryDb.query(
      'SELECT name FROM public.legal_categories WHERE id = $1',
      [corporateCategoryId],
    )).rows[0].name;
    await categoryDb.query(
      `INSERT INTO public.users (id, uid, name, email, role)
       VALUES ($1, $1, 'Provisioned Lawyer', 'provisioned-lawyer@example.test', 'lawyer')`,
      [lawyerUserId],
    );

    await withCategoryAdmin(async () => {
      const saved = (await categoryDb.query(
        `SELECT public.rpc_admin_lawyer_save(
           NULL, $1, $2, $3, '10 years', '$100/hour', 100,
           'images/lawyer2.png', 0, 'Cairo', 'Synthetic test profile', false, false
         ) AS result`,
        ['Provisioned Counsel', lawyerUserId, corporateCategoryId],
      )).rows[0].result;
      assert.equal(saved.user_id, lawyerUserId);
      assert.equal(saved.category_id, corporateCategoryId);
      assert.equal(saved.specialty, categoryName);

      const page = (await categoryDb.query(
        `SELECT public.rpc_admin_lawyers_page(1, 10, 'Provisioned', NULL, NULL, NULL) AS result`,
      )).rows[0].result;
      assert.equal(page.total, 1);
      assert.equal(page.items[0].user_id, lawyerUserId);

      await expectCategorySqlError(
        `INSERT INTO public.lawyers (user_id, name, specialty, price, price_value, category_id)
         VALUES ($1, 'Bypass Attempt', 'Commercial Law', '$100/hour', 100, $2)`,
        [lawyerUserId, corporateCategoryId],
        '42501',
        { withinTransaction: true },
      );
      await expectCategorySqlError(
        `SELECT public.rpc_admin_lawyer_save(
           NULL, 'Second Profile', $1, $2, '', '$100/hour', 100,
           'images/lawyer2.png', 0, '', '', false, false
         )`,
        [lawyerUserId, corporateCategoryId],
        '23505',
        { withinTransaction: true },
      );
    });

    await categoryDb.exec('BEGIN');
    try {
      await categoryDb.exec('SET LOCAL ROLE authenticated');
      await setCategorySubject(categoryClient);
      await expectCategorySqlError(
        `SELECT public.rpc_admin_lawyers_page(1, 10, NULL, NULL, NULL, NULL)`,
        [],
        '42501',
        { withinTransaction: true },
      );
    } finally {
      await categoryDb.exec('ROLLBACK');
    }
  });
});

describe('identity, owner, lawyer and phone-auth proposal (isolated PGlite only)', () => {
  let identityDb;
  let baselineCaseBookingPolicies;
  const identityIds = {
    clientAuth: '00000000-0000-4000-8000-000000000031',
    otherClientAuth: '00000000-0000-4000-8000-000000000032',
    lawyerAuth: '00000000-0000-4000-8000-000000000033',
    otherLawyerAuth: '00000000-0000-4000-8000-000000000034',
    adminAuth: '00000000-0000-4000-8000-000000000035',
    noProfileAuth: '00000000-0000-4000-8000-000000000036',
    unconfirmedEmailAuth: '00000000-0000-4000-8000-000000000037',
    trustedLawyerAuth: '00000000-0000-4000-8000-000000000038',
    phoneClientAuth: '00000000-0000-4000-8000-000000000039',
    emailOnlyAuth: '00000000-0000-4000-8000-000000000040',
    verifiedLegacyAuth: '00000000-0000-4000-8000-000000000041',
    ownerAuth: '00000000-0000-4000-8000-000000000042',
  };

  async function setIdentityClaims(subject, role = 'authenticated') {
    await identityDb.query("SELECT set_config('request.jwt.claim.sub', $1, true)", [subject ?? '']);
    await identityDb.query("SELECT set_config('request.jwt.claim.role', $1, true)", [role]);
  }

  async function withIdentityPrincipal(subject, callback, role = 'authenticated') {
    await identityDb.exec('BEGIN');
    try {
      await identityDb.exec(`SET LOCAL ROLE ${role}`);
      await setIdentityClaims(subject, role);
      const result = await callback();
      await identityDb.exec('COMMIT');
      return result;
    } catch (error) {
      await identityDb.exec('ROLLBACK');
      throw error;
    }
  }

  async function expectIdentitySqlError(subject, statement, parameters = [], expectedCode = '42501') {
    await identityDb.exec('BEGIN');
    await identityDb.exec('SET LOCAL ROLE authenticated');
    await setIdentityClaims(subject, 'authenticated');
    await identityDb.exec('SAVEPOINT expected_identity_error');
    let caught;
    try {
      await identityDb.query(statement, parameters);
    } catch (error) {
      caught = error;
    }
    await identityDb.exec('ROLLBACK TO SAVEPOINT expected_identity_error');
    await identityDb.exec('RELEASE SAVEPOINT expected_identity_error');
    await identityDb.exec('ROLLBACK');
    if (!caught) assert.fail(`Expected SQLSTATE ${expectedCode}: ${statement}`);
    assert.equal(caught.code, expectedCode, caught.message);
  }

  before(async () => {
    identityDb = new PGlite();
    await identityDb.exec(bootstrapSql);
    const files = await migrationFiles();
    const preProposalFiles = files.filter(
      (file) => file < '20261025140000_supabase_security_storage.sql',
    );
    await applyMigrations(identityDb, preProposalFiles);
    baselineCaseBookingPolicies = (await identityDb.query(
      `SELECT tablename, policyname, permissive, roles, cmd, qual, with_check
         FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename IN ('cases', 'bookings', 'booking_slots')
        ORDER BY tablename, policyname`,
    )).rows;
    const proposalSql = await readFile(
      path.join(repoRoot, 'supabase', 'proposals', '20261024_identity_owner_lawyer_access.sql'),
      'utf8',
    );
    await identityDb.exec(proposalSql);
    // Mirror the limited authenticated table grants inspected in Supabase;
    // RLS remains enabled and is the subject of these tests.
    await identityDb.exec(`
      GRANT USAGE ON SCHEMA public TO authenticated, service_role;
      GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
        public.users, public.cases, public.bookings, public.booking_slots
        TO authenticated, service_role;
      GRANT SELECT ON TABLE public.lawyers, public.legal_categories TO authenticated, service_role;
    `);

    // Synthetic identities deliberately use different Auth UUIDs and legacy
    // application IDs; they are not copied from any project or person.
    const authUsers = [
      [identityIds.clientAuth, 'client@example.test'],
      [identityIds.otherClientAuth, 'other-client@example.test'],
      [identityIds.lawyerAuth, 'lawyer@example.test'],
      [identityIds.otherLawyerAuth, 'other-lawyer@example.test'],
      [identityIds.adminAuth, 'admin@example.test'],
      [identityIds.ownerAuth, 'owner@example.test'],
    ];
    for (const [id, email] of authUsers) {
      await identityDb.query('INSERT INTO auth.users (id, email) VALUES ($1, $2)', [id, email]);
    }

    const profiles = [
      ['client-legacy', identityIds.clientAuth, 'Client One', 'client@example.test', 'client'],
      ['other-client-legacy', identityIds.otherClientAuth, 'Client Two', 'other-client@example.test', 'client'],
      ['lawyer-legacy', identityIds.lawyerAuth, 'Lawyer One', 'lawyer@example.test', 'lawyer'],
      ['other-lawyer-legacy', identityIds.otherLawyerAuth, 'Lawyer Two', 'other-lawyer@example.test', 'lawyer'],
      ['admin-profile', identityIds.adminAuth, 'Admin One', 'admin@example.test', 'admin'],
    ];
    for (const [id, authId, name, email, role] of profiles) {
      await identityDb.query(
        `INSERT INTO public.users (id, uid, auth_user_id, name, email, role)
         VALUES ($1, $1, $2, $3, $4, $5)`,
        [id, authId, name, email, role],
      );
    }
    // A conflicting native-UUID-shaped profile proves explicit auth_user_id
    // mapping takes precedence over id equality.
    await identityDb.query(
      `INSERT INTO public.users (id, uid, name, email, role)
       VALUES ($1, $1, 'Decoy Client', 'decoy@example.test', 'client')`,
      [identityIds.lawyerAuth],
    );

    await identityDb.query(
      `INSERT INTO public.users (id, uid, name, email, role)
       VALUES ('legacy-unlinked', 'legacy-unlinked', 'Legacy Unlinked', 'same@example.test', 'client'),
              ('legacy-verified', 'legacy-verified', 'Legacy Verified', 'verified@example.test', 'client')`,
    );

    await identityDb.query(
      `INSERT INTO public.legal_categories (id, name, slug)
       VALUES ('identity-category', 'Identity Test', 'identity-test')`,
    );
    await identityDb.query(
      `INSERT INTO public.lawyers (id, user_id, name, specialty, price, price_value, category_id)
       VALUES ('lawyer-record-one', 'lawyer-legacy', 'Lawyer One', 'Identity Test', '$100/hour', 100, 'identity-category'),
              ('lawyer-record-two', 'other-lawyer-legacy', 'Lawyer Two', 'Identity Test', '$120/hour', 120, 'identity-category')`,
    );
    await identityDb.query(
      `INSERT INTO public.cases (id, user_id, title, case_type, lawyer_id, category_id)
       VALUES ('identity-case-one', 'client-legacy', 'Assigned to lawyer one', 'Identity Test', 'lawyer-record-one', 'identity-category'),
              ('identity-case-two', 'other-client-legacy', 'Assigned to lawyer two', 'Identity Test', 'lawyer-record-two', 'identity-category'),
              ('identity-case-unassigned', 'client-legacy', 'Unassigned', 'Identity Test', NULL, NULL)`,
    );
    await identityDb.query(
      `INSERT INTO public.bookings
         (id, user_id, lawyer_id, lawyer_name, date, time, hours, total_price, status)
       VALUES ('identity-booking-one', 'client-legacy', 'lawyer-record-one', 'Lawyer One', '2026-12-01', '09:00', 1, 100, 'Pending'),
              ('identity-booking-two', 'other-client-legacy', 'lawyer-record-two', 'Lawyer Two', '2026-12-02', '10:00', 1, 120, 'Pending')`,
    );
    await identityDb.query(
      `INSERT INTO public.booking_slots (id, lawyer_id, date, slot, booking_id, user_id)
       VALUES ('identity-slot-one', 'lawyer-record-one', '2026-12-01', 540, 'identity-booking-one', 'client-legacy')`,
    );
  });

  after(async () => {
    await identityDb?.close();
  });

  it('fails closed on missing identities and prefers explicit Auth UUID mappings', async () => {
    await withIdentityPrincipal(identityIds.lawyerAuth, async () => {
      const mapped = await identityDb.query(
        'SELECT private.current_app_user_id() AS app_id, private.current_app_user_role() AS app_role',
      );
      assert.deepEqual(mapped.rows[0], { app_id: 'lawyer-legacy', app_role: 'lawyer' });
    });

    await withIdentityPrincipal(identityIds.noProfileAuth, async () => {
      const missing = await identityDb.query(
        'SELECT private.current_app_user_id() AS app_id, private.current_app_user_role() AS app_role',
      );
      assert.deepEqual(missing.rows[0], { app_id: null, app_role: null });
    });
  });

  it('provisions only confirmed contacts, fixes public signup roles, and requires exact legacy mapping', async () => {
    await identityDb.query(
      `INSERT INTO auth.users (id, email, raw_user_meta_data)
       VALUES ($1, 'new-client@example.test', '{"name":"New Client","role":"owner"}'::jsonb)`,
      [identityIds.unconfirmedEmailAuth],
    );
    assert.equal(
      (await identityDb.query('SELECT count(*)::int AS n FROM public.users WHERE auth_user_id = $1', [identityIds.unconfirmedEmailAuth])).rows[0].n,
      0,
    );
    await identityDb.query('UPDATE auth.users SET email_confirmed_at = now() WHERE id = $1', [identityIds.unconfirmedEmailAuth]);
    assert.equal(
      (await identityDb.query('SELECT role FROM public.users WHERE auth_user_id = $1', [identityIds.unconfirmedEmailAuth])).rows[0].role,
      'client',
      'user-editable role metadata never grants owner',
    );

    await identityDb.query(
      `INSERT INTO auth.users (id, email, raw_user_meta_data, raw_app_meta_data)
       VALUES ($1, 'new-lawyer@example.test', '{"role":"admin"}'::jsonb, '{"signup_role":"lawyer"}'::jsonb)`,
      [identityIds.trustedLawyerAuth],
    );
    assert.equal(
      (await identityDb.query('SELECT count(*)::int AS n FROM public.users WHERE auth_user_id = $1', [identityIds.trustedLawyerAuth])).rows[0].n,
      0,
    );
    await identityDb.query('UPDATE auth.users SET email_confirmed_at = now() WHERE id = $1', [identityIds.trustedLawyerAuth]);
    assert.equal(
      (await identityDb.query('SELECT role FROM public.users WHERE auth_user_id = $1', [identityIds.trustedLawyerAuth])).rows[0].role,
      'lawyer',
      'only trusted raw_app_meta_data can mark a confirmed email signup as lawyer',
    );

    await identityDb.query(
      `INSERT INTO auth.users (id, phone, raw_user_meta_data, raw_app_meta_data)
       VALUES ($1, '+201000000042', '{"name":"Phone Client","role":"owner"}'::jsonb, '{"signup_role":"lawyer"}'::jsonb)`,
      [identityIds.phoneClientAuth],
    );
    assert.equal(
      (await identityDb.query('SELECT count(*)::int AS n FROM public.users WHERE auth_user_id = $1', [identityIds.phoneClientAuth])).rows[0].n,
      0,
    );
    await identityDb.query('UPDATE auth.users SET phone_confirmed_at = now() WHERE id = $1', [identityIds.phoneClientAuth]);
    const phoneProfile = (await identityDb.query(
      'SELECT name, email, phone, role FROM public.users WHERE auth_user_id = $1',
      [identityIds.phoneClientAuth],
    )).rows[0];
    assert.deepEqual(phoneProfile, {
      name: 'Phone Client',
      email: '',
      phone: '+201000000042',
      role: 'client',
    });

    await identityDb.query(
      `INSERT INTO auth.users (id, email, email_confirmed_at, raw_user_meta_data)
       VALUES ($1, 'same@example.test', now(), '{"name":"Different Auth Account"}'::jsonb)`,
      [identityIds.emailOnlyAuth],
    );
    assert.equal(
      (await identityDb.query("SELECT auth_user_id FROM public.users WHERE id = 'legacy-unlinked'")).rows[0].auth_user_id,
      null,
      'email equality alone does not claim a legacy row',
    );
    assert.equal(
      (await identityDb.query('SELECT role FROM public.users WHERE auth_user_id = $1', [identityIds.emailOnlyAuth])).rows[0].role,
      'client',
    );

    await identityDb.query(
      `INSERT INTO auth.users (id, email, email_confirmed_at, raw_app_meta_data)
       VALUES ($1, 'verified@example.test', now(),
               '{"legacy_uid":"legacy-verified","legacy_migration_verified":"true"}'::jsonb)`,
      [identityIds.verifiedLegacyAuth],
    );
    assert.deepEqual(
      (await identityDb.query("SELECT id, auth_user_id FROM public.users WHERE id = 'legacy-verified'")).rows[0],
      { id: 'legacy-verified', auth_user_id: identityIds.verifiedLegacyAuth },
    );
  });

  it('scopes client writes and assigned-lawyer reads without granting lawyers writes', async () => {
    await withIdentityPrincipal(identityIds.clientAuth, async () => {
      const rows = await identityDb.query('SELECT id FROM public.cases ORDER BY id');
      assert.deepEqual(rows.rows.map((row) => row.id), [
        'identity-case-one',
        'identity-case-unassigned',
      ]);
      await identityDb.query(
        `INSERT INTO public.cases (id, user_id, title)
         VALUES ('client-owned-case', 'client-legacy', 'Client owned')`,
      );
    });

    await expectIdentitySqlError(
      identityIds.clientAuth,
      `INSERT INTO public.cases (id, user_id, title)
       VALUES ('cross-owner-case', 'other-client-legacy', 'Cross owner')`,
      [],
      '42501',
    );

    await withIdentityPrincipal(identityIds.lawyerAuth, async () => {
      const cases = await identityDb.query('SELECT id FROM public.cases ORDER BY id');
      assert.deepEqual(cases.rows.map((row) => row.id), ['identity-case-one']);
      const bookings = await identityDb.query('SELECT id FROM public.bookings ORDER BY id');
      assert.deepEqual(bookings.rows.map((row) => row.id), ['identity-booking-one']);
      assert.equal(
        (await identityDb.query('SELECT count(*)::int AS n FROM public.booking_slots')).rows[0].n,
        0,
        'slot rows remain hidden from lawyers',
      );
    });

    await expectIdentitySqlError(
      identityIds.lawyerAuth,
      `INSERT INTO public.cases (id, user_id, title, lawyer_id, category_id)
       VALUES ('lawyer-write-case', 'client-legacy', 'No lawyer writes', 'lawyer-record-one', 'identity-category')`,
      [],
      '42501',
    );
    await withIdentityPrincipal(identityIds.lawyerAuth, async () => {
      const caseUpdate = await identityDb.query(
        "UPDATE public.cases SET status = 'Closed' WHERE id = 'identity-case-one'",
      );
      const caseDelete = await identityDb.query(
        "DELETE FROM public.cases WHERE id = 'identity-case-one'",
      );
      assert.equal(caseUpdate.rowCount, 0, 'RLS must hide assigned cases from lawyer UPDATE');
      assert.equal(caseDelete.rowCount, 0, 'RLS must hide assigned cases from lawyer DELETE');

      const bookingUpdate = await identityDb.query(
        "UPDATE public.bookings SET status = 'Completed' WHERE id = 'identity-booking-one'",
      );
      const bookingDelete = await identityDb.query(
        "DELETE FROM public.bookings WHERE id = 'identity-booking-one'",
      );
      assert.equal(bookingUpdate.rowCount, 0, 'RLS must hide assigned bookings from lawyer UPDATE');
      assert.equal(bookingDelete.rowCount, 0, 'RLS must hide assigned bookings from lawyer DELETE');
    });

    await expectIdentitySqlError(
      identityIds.lawyerAuth,
      `INSERT INTO public.bookings
         (id, user_id, lawyer_id, lawyer_name, date, time, hours, total_price)
       VALUES ('lawyer-write-booking', 'client-legacy', 'lawyer-record-one', 'Lawyer One', '2026-12-03', '11:00', 1, 100)`,
      [],
      '42501',
    );

    const unchanged = await identityDb.query(
      "SELECT status FROM public.cases WHERE id = 'identity-case-one'",
    );
    assert.equal(unchanged.rows[0].status, 'Open');
  });

  it('reserves owner lifecycle changes for a real service-role JWT or direct SQL operator', async () => {
    await withIdentityPrincipal(identityIds.ownerAuth, async () => {
      await identityDb.query(
        `INSERT INTO public.users (id, uid, auth_user_id, name, email, role)
         VALUES ('owner-profile', 'owner-profile', $1, 'Trusted Owner', 'owner@example.test', 'owner')`,
        [identityIds.ownerAuth],
      );
    }, 'service_role');

    await assert.rejects(
      () => withIdentityPrincipal(identityIds.ownerAuth, () => identityDb.query(
        `INSERT INTO public.users (id, uid, auth_user_id, name, email, role)
         VALUES ('second-owner', 'second-owner', $1, 'Second Owner', 'second@example.test', 'owner')`,
        ['00000000-0000-4000-8000-000000000043'],
      ), 'service_role'),
      (error) => error.code === '23505',
    );

    await expectIdentitySqlError(
      identityIds.adminAuth,
      `INSERT INTO public.users (id, uid, name, email, role)
       VALUES ('self-appointed-owner', 'self-appointed-owner', 'Self Owner', 'self@example.test', 'owner')`,
      [],
      '42501',
    );
    await expectIdentitySqlError(
      identityIds.adminAuth,
      "UPDATE public.users SET role = 'client' WHERE id = 'owner-profile'",
      [],
      '42501',
    );

    await identityDb.exec(`
      CREATE FUNCTION public.test_security_definer_owner_change()
      RETURNS void
      LANGUAGE plpgsql
      SECURITY DEFINER
      SET search_path = pg_catalog, public
      AS $test$
      BEGIN
        UPDATE public.users SET role = 'client' WHERE id = 'owner-profile';
      END;
      $test$;
    `);
    await expectIdentitySqlError(
      identityIds.adminAuth,
      'SELECT public.test_security_definer_owner_change()',
      [],
      '42501',
    );

    await withIdentityPrincipal(identityIds.ownerAuth, async () => {
      const role = await identityDb.query(
        'SELECT private.current_app_user_role() AS role, private.is_admin() AS privileged',
      );
      assert.deepEqual(role.rows[0], { role: 'owner', privileged: true });
      assert.equal(
        (await identityDb.query('SELECT count(*)::int AS n FROM public.cases')).rows[0].n,
        4,
        'owner sees all rows created so far',
      );
      await identityDb.query(
        `INSERT INTO public.cases (id, user_id, title)
         VALUES ('owner-created-case', 'client-legacy', 'Owner operation')`,
      );
    });

    await withIdentityPrincipal(identityIds.ownerAuth, async () => {
      await identityDb.query("UPDATE public.users SET role = 'admin' WHERE id = 'owner-profile'");
      await identityDb.query("UPDATE public.users SET role = 'owner' WHERE id = 'owner-profile'");
    }, 'service_role');

    // SQL Editor/operator path: session_user remains postgres and there is no
    // PostgREST JWT role. Keep the test changes transactional and roll them back.
    await identityDb.exec('BEGIN');
    const directDemotion = await identityDb.query(
      "UPDATE public.users SET role = 'admin' WHERE id = 'owner-profile'",
    );
    assert.equal(directDemotion.rowCount, 1);
    const directRestoration = await identityDb.query(
      "UPDATE public.users SET role = 'owner' WHERE id = 'owner-profile'",
    );
    assert.equal(directRestoration.rowCount, 1);
    await identityDb.exec('ROLLBACK');
  });

  it('the companion rollback restores the original policy set and role check', async () => {
    await withIdentityPrincipal(identityIds.ownerAuth, async () => {
      await identityDb.query("DELETE FROM public.users WHERE id = 'owner-profile'");
    }, 'service_role');

    const rollbackSql = await readFile(
      path.join(repoRoot, 'supabase', 'proposals', '20261024_identity_owner_lawyer_access_rollback.sql'),
      'utf8',
    );
    await identityDb.exec(rollbackSql);

    const proposalPolicies = await identityDb.query(
      `SELECT count(*)::int AS n FROM pg_policies
        WHERE schemaname = 'public'
          AND policyname IN ('cases_select_assigned_lawyer', 'bookings_select_assigned_lawyer')`,
    );
    assert.equal(proposalPolicies.rows[0].n, 0);
    const restoredPolicies = await identityDb.query(
      `SELECT tablename, policyname, permissive, roles, cmd, qual, with_check
         FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename IN ('cases', 'bookings', 'booking_slots')
        ORDER BY tablename, policyname`,
    );
    assert.deepEqual(restoredPolicies.rows, baselineCaseBookingPolicies);
    const ownerIndex = await identityDb.query(
      "SELECT count(*)::int AS n FROM pg_indexes WHERE schemaname='public' AND indexname='users_single_owner_key'",
    );
    assert.equal(ownerIndex.rows[0].n, 0);
    await assert.rejects(
      () => identityDb.query(
        `INSERT INTO public.users (id, uid, name, email, role)
         VALUES ('rollback-owner', 'rollback-owner', 'Rollback Owner', 'rollback@example.test', 'owner')`,
      ),
      (error) => error.code === '23514',
    );
    const trigger = await identityDb.query(
      `SELECT pg_get_triggerdef(t.oid) AS definition
         FROM pg_trigger t
         JOIN pg_class r ON r.oid = t.tgrelid
         JOIN pg_namespace n ON n.oid = r.relnamespace
        WHERE n.nspname = 'auth' AND r.relname = 'users' AND t.tgname = 'trg_auth_users_link_migrated'`,
    );
    assert.match(trigger.rows[0].definition, /AFTER INSERT ON auth\.users/);
    const helper = await identityDb.query(
      "SELECT private.current_app_user_id() AS id",
      [],
    );
    assert.equal(helper.rows[0].id, null);
  });
});
