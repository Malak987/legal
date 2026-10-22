import dotenv from 'dotenv';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const backendRoot = path.resolve(__dirname, '../..');

export const DEFAULT_FIREBASE_PROJECT_ID = 'legal-102026';

/**
 * Returns true when running inside Cloud Functions / Cloud Run or the
 * Firebase Functions Emulator, where runtime configuration comes from the
 * platform rather than a developer's local `backend/.env` file.
 */
export function isCloudFunctionsRuntime(envVars = process.env) {
  return Boolean(
    envVars.K_SERVICE ||
      envVars.FUNCTION_TARGET ||
      envVars.FUNCTIONS_EMULATOR === 'true',
  );
}

// Load `backend/.env` only during local standalone execution so leftover local
// settings (`NODE_ENV=development`, `SEED_ON_START`, etc.) can never leak into
// Cloud Functions or the Firebase Functions Emulator.
if (!isCloudFunctionsRuntime()) {
  dotenv.config({ path: path.join(backendRoot, '.env') });
}

/**
 * Extract `projectId` from the JSON string Google Cloud injects in
 * `FIREBASE_CONFIG` when explicit project env vars are omitted.
 */
export function parseFirebaseConfigProjectId(rawFirebaseConfig) {
  if (!rawFirebaseConfig || typeof rawFirebaseConfig !== 'string') {
    return '';
  }
  if (!rawFirebaseConfig.trim().startsWith('{')) {
    return '';
  }
  try {
    const parsed = JSON.parse(rawFirebaseConfig);
    return typeof parsed?.projectId === 'string' ? parsed.projectId.trim() : '';
  } catch (_err) {
    return '';
  }
}

export function resolveFirebaseProjectId(envVars = process.env) {
  return (
    envVars.FIREBASE_PROJECT_ID ||
    envVars.GCLOUD_PROJECT ||
    envVars.GOOGLE_CLOUD_PROJECT ||
    parseFirebaseConfigProjectId(envVars.FIREBASE_CONFIG) ||
    ''
  ).trim();
}

/**
 * Compute default Firebase Hosting origins for `<projectId>` and resolve any
 * comma-separated `CORS_ORIGINS` override.
 */
export function resolveCorsOrigins(envVars = process.env) {
  const explicit = (envVars.CORS_ORIGINS || '').trim();
  if (explicit) {
    return explicit
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean);
  }
  const projectId =
    resolveFirebaseProjectId(envVars) || DEFAULT_FIREBASE_PROJECT_ID;
  const origins = [
    `https://${projectId}.web.app`,
    `https://${projectId}.firebaseapp.com`,
  ];
  const nodeEnv = (envVars.NODE_ENV || 'development').trim();
  if (nodeEnv !== 'production') {
    origins.push('http://localhost:5173');
  }
  return origins;
}

/**
 * Resolve the path to the optional local Firebase service account JSON file.
 *
 * Cloud Functions uses Google Cloud Application Default Credentials directly
 * (`admin.initializeApp()`) and never requires a JSON key file. For legacy
 * local standalone execution, we resolve in order:
 *   1. `SERVICE_ACCOUNT_PATH` (explicit path, relative to `backend/` if not absolute)
 *   2. `<backend>/serviceAccount.json` (canonical default)
 *   3. `<backend>/src/serviceAccount.json` (legacy fallback if present and (2) is not)
 */
export function resolveServiceAccountPath({
  serviceAccountEnv = process.env.SERVICE_ACCOUNT_PATH,
  rootDir = backendRoot,
  existsSync = fs.existsSync,
} = {}) {
  if (serviceAccountEnv && serviceAccountEnv.trim() !== '') {
    return path.resolve(rootDir, serviceAccountEnv.trim());
  }
  const preferred = path.resolve(rootDir, './serviceAccount.json');
  if (existsSync(preferred)) {
    return preferred;
  }
  const legacy = path.resolve(rootDir, './src/serviceAccount.json');
  if (existsSync(legacy)) {
    return legacy;
  }
  return preferred;
}

const isCloudFunction = isCloudFunctionsRuntime();
const nodeEnv = process.env.NODE_ENV || (isCloudFunction ? 'production' : 'development');

export const env = {
  port: parseInt(process.env.PORT || '5000', 10),
  nodeEnv,
  isCloudFunction,
  corsOrigins: resolveCorsOrigins({ ...process.env, NODE_ENV: nodeEnv }),
  serviceAccountPath: resolveServiceAccountPath(),
  firebaseProjectId: resolveFirebaseProjectId(),
  // Automatic startup seeding is strictly forbidden in Cloud Functions and in
  // production environments.
  seedOnStart:
    !isCloudFunction &&
    nodeEnv !== 'production' &&
    process.env.SEED_ON_START === 'true',
};

export default env;
