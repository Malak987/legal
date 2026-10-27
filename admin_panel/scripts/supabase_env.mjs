// Shared Supabase configuration for the admin panel's run/build scripts.
//
// Flutter web reads Supabase settings ONLY from compile-time Dart defines
// (lib/config/app_config.dart). Shell and hosting environment variables are not
// visible to the compiled app, so these scripts translate them into
// --dart-define flags. Validation mirrors lib/config/supabase_config.dart.
//
// Never print the key value: use redactKey() in every message.
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const ADMIN_PANEL_DIR = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export const LOCAL_CONFIG_FILE = 'supabase.local.json';
export const DEFAULT_SUPABASE_URL = 'https://qqfzbecwhewswkyxgebu.supabase.co';
export const DEFINE_NAMES = ['SUPABASE_URL', 'SUPABASE_ANON_KEY', 'SUPABASE_AUTH_REDIRECT_URL'];
export const LEGACY_CI_PLACEHOLDER_KEY = 'ci-public-anon-key-for-build-only';
const SERVER_ONLY_ENV = ['SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_SECRET_KEY'];
const LOOPBACK_HOSTS = new Set(['localhost', '127.0.0.1', '[::1]']);

function jwtClaims(value) {
  const parts = value.split('.');
  if (parts.length !== 3 || parts.some((part) => !part)) return null;
  try {
    const claims = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
    return claims && typeof claims === 'object' ? claims : null;
  } catch {
    return null;
  }
}

export function isServiceRoleKey(value) {
  return value.startsWith('sb_secret_') || jwtClaims(value)?.role === 'service_role';
}

/** Non-secret description such as `sb_publishable_… (46 chars)`. */
export function redactKey(value) {
  if (!value) return '(missing)';
  for (const prefix of ['sb_publishable_', 'sb_secret_']) {
    if (value.startsWith(prefix)) return `${prefix}… (${value.length} chars)`;
  }
  if (jwtClaims(value)) return `JWT … (${value.length} chars)`;
  return `… (${value.length} chars)`;
}

function readLocalFile(adminDir) {
  const file = join(adminDir, LOCAL_CONFIG_FILE);
  if (!existsSync(file)) return { values: {}, file: null };
  let parsed;
  try {
    parsed = JSON.parse(readFileSync(file, 'utf8'));
  } catch (error) {
    throw new Error(`${LOCAL_CONFIG_FILE} is not valid JSON (${error.message}).`);
  }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new Error(`${LOCAL_CONFIG_FILE} must contain a JSON object of Dart defines.`);
  }
  const serverOnlyFields = SERVER_ONLY_ENV.filter((name) => Object.hasOwn(parsed, name));
  if (serverOnlyFields.length) {
    throw new Error(
      `${LOCAL_CONFIG_FILE} contains server-only Supabase field names (${serverOnlyFields.join(', ')}). Remove those fields; values are never read or printed.`,
    );
  }
  return { values: parsed, file };
}

/**
 * Resolves the public Dart defines. Precedence per value: process environment,
 * then the git-ignored admin_panel/supabase.local.json, then (URL only) the
 * connected project's URL.
 */
export function loadSupabaseDefines({ env = process.env, adminDir = ADMIN_PANEL_DIR } = {}) {
  const local = readLocalFile(adminDir);
  const sources = {};
  const defines = {};
  for (const name of DEFINE_NAMES) {
    const fromEnv = typeof env[name] === 'string' ? env[name].trim() : '';
    const fromFile = typeof local.values[name] === 'string' ? local.values[name].trim() : '';
    if (fromEnv) {
      defines[name] = fromEnv;
      sources[name] = 'environment';
    } else if (fromFile) {
      defines[name] = fromFile;
      sources[name] = LOCAL_CONFIG_FILE;
    } else if (name === 'SUPABASE_URL') {
      defines[name] = DEFAULT_SUPABASE_URL;
      sources[name] = 'default';
    } else {
      defines[name] = '';
      sources[name] = 'unset';
    }
  }
  defines.SUPABASE_URL = defines.SUPABASE_URL.replace(/\/+$/, '');
  return { defines, sources, localFile: local.file };
}

/** Returns `{ code, message }` issues; an empty array means valid. */
export function validateSupabaseDefines(defines) {
  const issues = [];
  const url = (defines.SUPABASE_URL || '').trim();
  const key = (defines.SUPABASE_ANON_KEY || '').trim();

  let parsed = null;
  if (!url) {
    issues.push({ code: 'missingUrl', message: 'SUPABASE_URL is empty.' });
  } else {
    try {
      parsed = new URL(url);
    } catch {
      parsed = null;
    }
    const hasPath = parsed && parsed.pathname !== '/' && parsed.pathname !== '';
    if (
      !parsed ||
      !['https:', 'http:'].includes(parsed.protocol) ||
      !parsed.hostname ||
      parsed.username ||
      parsed.password ||
      parsed.search ||
      parsed.hash ||
      hasPath ||
      /\s/.test(url) ||
      !/^https?:\/\/[^/]/.test(url)
    ) {
      issues.push({
        code: 'malformedUrl',
        message:
          'SUPABASE_URL must be the project base URL (https://<project-ref>.supabase.co) with no path such as /rest/v1, query string or credentials.',
      });
      parsed = null;
    } else if (parsed.protocol === 'http:' && !LOOPBACK_HOSTS.has(parsed.hostname)) {
      issues.push({ code: 'insecureUrl', message: 'SUPABASE_URL must use https (http only for localhost).' });
    }
  }

  const claims = jwtClaims(key);
  if (!key) {
    issues.push({
      code: 'missingKey',
      message: `SUPABASE_ANON_KEY is empty. Export it or put it in admin_panel/${LOCAL_CONFIG_FILE}.`,
    });
  } else if (isServiceRoleKey(key)) {
    issues.push({
      code: 'secretKey',
      message: 'SUPABASE_ANON_KEY contains a secret/service-role key. Only the public anon/publishable key is allowed.',
    });
  } else if (
    key === LEGACY_CI_PLACEHOLDER_KEY ||
    !(/^sb_publishable_[A-Za-z0-9_-]{10,}$/.test(key) || claims?.role === 'anon')
  ) {
    issues.push({
      code: 'malformedKey',
      message: 'SUPABASE_ANON_KEY is not a Supabase public key (sb_publishable_… or legacy anon JWT); is it a placeholder?',
    });
  }

  if (claims?.ref && parsed?.hostname.endsWith('.supabase.co') && parsed.hostname.split('.')[0] !== claims.ref) {
    issues.push({
      code: 'projectMismatch',
      message: 'SUPABASE_ANON_KEY belongs to a different Supabase project than SUPABASE_URL.',
    });
  }
  return issues;
}

export function dartDefineArgs(defines) {
  return DEFINE_NAMES.filter((name) => defines[name] !== undefined).map(
    (name) => `--dart-define=${name}=${defines[name]}`,
  );
}

/** Prevent optional CLI args from bypassing the validated public config. */
export function rejectUnsafeFlutterConfigArgs(args) {
  const protectedNames = new Set([...DEFINE_NAMES, ...SERVER_ONLY_ENV]);
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === '--dart-define-from-file' || arg.startsWith('--dart-define-from-file=')) {
      throw new Error('Do not pass --dart-define-from-file in extra Flutter arguments; use the validated local config.');
    }
    let define = '';
    if (arg === '--dart-define') define = args[index + 1] || '';
    else if (arg.startsWith('--dart-define=')) define = arg.slice('--dart-define='.length);
    if (protectedNames.has(define.split('=', 1)[0])) {
      throw new Error('Do not override Supabase defines in extra Flutter arguments; use the validated local config.');
    }
  }
}

/** Copy of the environment without server-only credentials. */
export function flutterEnv(env = process.env) {
  const copy = { ...env };
  for (const name of SERVER_ONLY_ENV) delete copy[name];
  return copy;
}

export function describeConfig({ defines, sources }) {
  return [
    `  SUPABASE_URL      ${defines.SUPABASE_URL || '(missing)'} [${sources.SUPABASE_URL}]`,
    `  SUPABASE_ANON_KEY ${redactKey(defines.SUPABASE_ANON_KEY)} [${sources.SUPABASE_ANON_KEY}]`,
    `  SUPABASE_AUTH_REDIRECT_URL ${defines.SUPABASE_AUTH_REDIRECT_URL || '(not set)'} [${sources.SUPABASE_AUTH_REDIRECT_URL}]`,
  ].join('\n');
}

/** Command line for logs with the key redacted. */
export function printableCommand(args, defines) {
  const key = defines.SUPABASE_ANON_KEY;
  return ['flutter', ...args]
    .map((arg) => (key && arg.includes(key) ? arg.replace(key, redactKey(key)) : arg))
    .join(' ');
}

export function reportIssues(issues, log = console.error) {
  log('Supabase configuration is invalid:');
  for (const issue of issues) log(`  - ${issue.message}`);
  log(
    `Provide the PUBLIC values via the environment (export SUPABASE_ANON_KEY=...) or a git-ignored\n` +
      `admin_panel/${LOCAL_CONFIG_FILE} (see ${LOCAL_CONFIG_FILE.replace('.json', '.example.json')}). Never use a service-role/secret key.`,
  );
}
