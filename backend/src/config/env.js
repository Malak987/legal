import dotenv from 'dotenv';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const backendRoot = path.resolve(__dirname, '../..');

export const DEFAULT_FIREBASE_PROJECT_ID = 'legal-102026';
export const DEFAULT_SUPABASE_PROJECT_REF = 'qqfzbecwhewswkyxgebu';
export const DEFAULT_SUPABASE_URL = `https://${DEFAULT_SUPABASE_PROJECT_REF}.supabase.co`;

/**
 * Cloud Functions / Cloud Run and the Firebase Functions emulator receive
 * configuration from their runtime. Do not load a developer's local `.env`
 * there: local NODE_ENV, seed flags, or credentials must not leak into runtime.
 */
export function isCloudFunctionsRuntime(envVars = process.env) {
  return Boolean(
    envVars.K_SERVICE ||
      envVars.FUNCTION_TARGET ||
      envVars.FUNCTIONS_EMULATOR === 'true',
  );
}

const isCloudFunction = isCloudFunctionsRuntime();
if (!isCloudFunction) {
  dotenv.config({ path: path.join(backendRoot, '.env') });
}

/** Extract Firebase's projectId from the managed runtime FIREBASE_CONFIG JSON. */
export function parseFirebaseConfigProjectId(rawFirebaseConfig) {
  if (typeof rawFirebaseConfig !== 'string' || !rawFirebaseConfig.trim().startsWith('{')) {
    return '';
  }
  try {
    const parsed = JSON.parse(rawFirebaseConfig);
    return typeof parsed?.projectId === 'string' ? parsed.projectId.trim() : '';
  } catch {
    return '';
  }
}

/** Resolve Firebase's project ID without depending on a local key file. */
export function resolveFirebaseProjectId(envVars = process.env) {
  return (
    envVars.FIREBASE_PROJECT_ID ||
    envVars.GCLOUD_PROJECT ||
    envVars.GOOGLE_CLOUD_PROJECT ||
    parseFirebaseConfigProjectId(envVars.FIREBASE_CONFIG) ||
    ''
  ).trim();
}

/** Resolve a comma-separated CORS override or environment-appropriate defaults. */
export function resolveCorsOrigins(envVars = process.env) {
  const explicit = (envVars.CORS_ORIGINS || '').trim();
  if (explicit) {
    return explicit.split(',').map((value) => value.trim()).filter(Boolean);
  }

  const nodeEnv = (envVars.NODE_ENV || 'development').trim();
  if (nodeEnv !== 'production') {
    return ['http://localhost:3000', 'http://localhost:5173'];
  }

  const projectId = resolveFirebaseProjectId(envVars) || DEFAULT_FIREBASE_PROJECT_ID;
  return [
    `https://${projectId}.web.app`,
    `https://${projectId}.firebaseapp.com`,
  ];
}

/**
 * Resolve the optional local Firebase Admin key path without reading it.
 * Explicit relative paths are resolved from `backend/`; an existing legacy
 * `src/serviceAccount.json` is accepted, but never copied into configuration.
 */
export function resolveServiceAccountPath({
  serviceAccountEnv = process.env.SERVICE_ACCOUNT_PATH,
  rootDir = backendRoot,
  existsSync = fs.existsSync,
} = {}) {
  if (serviceAccountEnv && serviceAccountEnv.trim()) {
    return path.resolve(rootDir, serviceAccountEnv.trim());
  }
  const preferred = path.resolve(rootDir, './serviceAccount.json');
  if (existsSync(preferred)) return preferred;
  const legacy = path.resolve(rootDir, './src/serviceAccount.json');
  return existsSync(legacy) ? legacy : preferred;
}

const nodeEnv = (
  process.env.NODE_ENV || (isCloudFunction ? 'production' : 'development')
).trim();

export const env = {
  port: Number.parseInt(process.env.PORT || '5000', 10),
  nodeEnv,
  isCloudFunction,
  corsOrigins: resolveCorsOrigins({ ...process.env, NODE_ENV: nodeEnv }),
  firebaseProjectId: resolveFirebaseProjectId(),
  serviceAccountPath: resolveServiceAccountPath(),
  supabaseProjectRef: (
    process.env.SUPABASE_PROJECT_REF || DEFAULT_SUPABASE_PROJECT_REF
  ).trim(),
  supabaseUrl: (process.env.SUPABASE_URL || '').trim(),
  supabaseAnonKey: (process.env.SUPABASE_ANON_KEY || '').trim(),
  supabaseServiceRoleKey: (
    process.env.SUPABASE_SERVICE_ROLE_KEY ||
    process.env.SUPABASE_SECRET_KEY ||
    ''
  ).trim(),
  supabaseAuthRedirectUrl: (process.env.SUPABASE_AUTH_REDIRECT_URL || '').trim(),
  lawyerSignupRedirectUrl: (process.env.LAWYER_SIGNUP_REDIRECT_URL || '').trim(),
  // Startup seeding is never enabled in Cloud Functions or production.
  seedOnStart:
    !isCloudFunction &&
    nodeEnv !== 'production' &&
    process.env.SEED_ON_START === 'true',
};

/**
 * Lawyer registration remains closed unless an operator explicitly enables it
 * and supplies a redirect URI that is allow-listed in Supabase Auth.
 */
export function isLawyerSignupEnabled(envVars = process.env) {
  const enabled = String(envVars.ENABLE_LAWYER_SIGNUP || '').trim().toLowerCase() === 'true';
  const redirect = String(
    envVars.LAWYER_SIGNUP_REDIRECT_URL || envVars.SUPABASE_AUTH_REDIRECT_URL || '',
  ).trim();
  return enabled && redirect.length > 0;
}

export default env;
