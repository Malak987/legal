import { createClient } from '@supabase/supabase-js';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const LOCAL_HOSTS = new Set(['localhost', '127.0.0.1', '::1']);
const CLIENT_ID = '11111111-1111-4111-8111-111111111111';
const LAWYER_USER_ID = '22222222-2222-4222-8222-222222222222';
const LAWYER_ID = 'test-lawyer-001';
const PLAN_ID = 'test-plan-001';
const CASE_ID = 'test-case-001';

export function resolveTestSeedConfig(env = process.env) {
  if (env.NODE_ENV === 'production') {
    throw new Error('The synthetic seed is disabled in production.');
  }
  if (env.LEGAL_ALLOW_TEST_SEED !== 'true') {
    throw new Error('Set LEGAL_ALLOW_TEST_SEED=true to explicitly allow the local synthetic seed.');
  }

  const rawUrl = env.SUPABASE_TEST_URL?.trim();
  const serviceRoleKey = env.SUPABASE_TEST_SERVICE_ROLE_KEY?.trim();
  if (!rawUrl || !serviceRoleKey) {
    throw new Error('SUPABASE_TEST_URL and SUPABASE_TEST_SERVICE_ROLE_KEY are required.');
  }

  let url;
  try {
    url = new URL(rawUrl);
  } catch {
    throw new Error('SUPABASE_TEST_URL must be a valid local Supabase URL.');
  }
  const hostname = url.hostname.replace(/^\[|\]$/g, '').toLowerCase();
  if (!['http:', 'https:'].includes(url.protocol) || !LOCAL_HOSTS.has(hostname)) {
    throw new Error('The synthetic seed only accepts a loopback Supabase URL.');
  }
  if (url.username || url.password || url.search || url.hash) {
    throw new Error('SUPABASE_TEST_URL must not contain credentials or URL parameters.');
  }

  return { url: url.toString().replace(/\/$/, ''), serviceRoleKey };
}

const syntheticRows = {
  users: [
    {
      id: CLIENT_ID,
      uid: CLIENT_ID,
      name: 'Synthetic Test Client',
      email: 'client.seed@example.invalid',
      phone: '',
      role: 'client',
      avatar: '',
      address: '',
    },
    {
      id: LAWYER_USER_ID,
      uid: LAWYER_USER_ID,
      name: 'Synthetic Test Lawyer',
      email: 'lawyer.seed@example.invalid',
      phone: '',
      role: 'lawyer',
      avatar: '',
      address: '',
    },
  ],
  lawyers: [
    {
      id: LAWYER_ID,
      user_id: LAWYER_USER_ID,
      name: 'Synthetic Test Lawyer',
      specialty: 'Family Law',
      price: 'USD 100 per hour',
      price_value: 100,
      image: '',
      rating: 0,
      location: 'Test-only location',
      bio: 'Synthetic record for local integration tests.',
      is_popular: false,
      is_top: false,
    },
  ],
  plans: [
    {
      id: PLAN_ID,
      title: 'Synthetic Test Plan',
      price: 'USD 0',
      price_value: 0,
      color: '#64748B',
      features: ['Local integration tests only'],
      is_popular: false,
    },
  ],
  cases: [
    {
      id: CASE_ID,
      user_id: CLIENT_ID,
      title: 'Synthetic Test Case',
      description: 'Local-only integration fixture.',
      client_name: 'Synthetic Test Client',
      case_type: 'Family Law',
      priority: 'Low',
      status: 'Open',
      due_date: '2030-01-01',
    },
  ],
};

export async function runSeed(env = process.env) {
  const { url, serviceRoleKey } = resolveTestSeedConfig(env);
  const client = createClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  try {
    // `ignoreDuplicates` is deliberate: profile identity/role fields are
    // guarded and a repeat seed must never rewrite them.
    const { error: userError } = await client
      .from('users')
      .upsert(syntheticRows.users, { onConflict: 'id', ignoreDuplicates: true });
    if (userError) throw userError;

    for (const table of ['lawyers', 'plans', 'cases']) {
      const { error } = await client
        .from(table)
        .upsert(syntheticRows[table], { onConflict: 'id' });
      if (error) throw error;
    }
    return { users: syntheticRows.users.length, lawyers: 1, plans: 1, cases: 1 };
  } finally {
    client.auth.stopAutoRefresh?.();
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  runSeed()
    .then((summary) => console.log('[Seed] Local synthetic rows are ready:', summary))
    .catch((error) => {
      console.error('[Seed] Refused or failed; no credentials were printed.');
      console.error(error instanceof Error ? error.message : 'Unknown seed error.');
      process.exitCode = 1;
    });
}
