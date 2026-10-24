import { spawnSync } from 'node:child_process';

// The anon/publishable key is intentionally supplied from the build environment:
// it is public client configuration, not a service-role credential.
const supabaseUrl = (process.env.SUPABASE_URL || 'https://qqfzbecwhewswkyxgebu.supabase.co').trim();
const supabaseAnonKey = (process.env.SUPABASE_ANON_KEY || '').trim();
const apiBaseUrl = (process.env.API_BASE_URL || '/api').trim().replace(/\/+$/, '') || '/api';
const authRedirectUrl = (process.env.SUPABASE_AUTH_REDIRECT_URL || '').trim();

function isServiceRoleKey(value) {
  if (value.startsWith('sb_secret_')) return true;
  const payload = value.split('.')[1];
  if (!payload) return false;
  try {
    return JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')).role === 'service_role';
  } catch {
    return false;
  }
}

if (!supabaseAnonKey) {
  console.error(
    'Missing SUPABASE_ANON_KEY. Provide the public anon/publishable key through the build environment; never use a service-role key.',
  );
  process.exit(1);
}
if (isServiceRoleKey(supabaseAnonKey)) {
  console.error(
    'Refusing to embed a Supabase service-role/secret key. Supply a public anon/publishable key as SUPABASE_ANON_KEY.',
  );
  process.exit(1);
}

const dartDefines = {
  SUPABASE_URL: supabaseUrl,
  SUPABASE_ANON_KEY: supabaseAnonKey,
  API_BASE_URL: apiBaseUrl,
  SUPABASE_AUTH_REDIRECT_URL: authRedirectUrl,
};
const args = [
  'build',
  'web',
  ...Object.entries(dartDefines).map(([name, value]) => `--dart-define=${name}=${value}`),
];
// Do not let a server-only credential reach the Flutter process, even through
// inherited environment variables. Only the public values above become Dart defines.
const flutterEnv = { ...process.env };
delete flutterEnv.SUPABASE_SERVICE_ROLE_KEY;
const result = spawnSync('flutter', args, { stdio: 'inherit', env: flutterEnv });

if (result.error) {
  console.error(`Could not start Flutter web build: ${result.error.message}`);
  process.exit(1);
}
process.exitCode = result.status ?? 1;
