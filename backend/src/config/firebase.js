import admin from 'firebase-admin';
import fs from 'node:fs';
import env, { resolveFirebaseProjectId } from './env.js';
import { isSupabaseConfigured, initializeSupabase } from './supabase.js';

let app = null;
let firestore = null;
let auth = null;

/**
 * Returns true when Firebase Admin can authenticate without a local
 * `serviceAccount.json` file:
 *   - Firebase Cloud Functions Gen 2 / Cloud Run (`K_SERVICE`, `FUNCTION_TARGET`, `FIREBASE_CONFIG`)
 *   - Explicit Google Cloud Application Default Credentials (`GOOGLE_APPLICATION_CREDENTIALS`)
 *   - Firebase Emulator Suite (`FUNCTIONS_EMULATOR`, `FIRESTORE_EMULATOR_HOST`, `FIREBASE_AUTH_EMULATOR_HOST`)
 */
export function canUseManagedCredentials(envVars = process.env) {
  return Boolean(
    envVars.K_SERVICE ||
      envVars.FUNCTION_TARGET ||
      envVars.FIREBASE_CONFIG ||
      envVars.GOOGLE_APPLICATION_CREDENTIALS ||
      envVars.FUNCTIONS_EMULATOR === 'true' ||
      envVars.FIRESTORE_EMULATOR_HOST ||
      envVars.FIREBASE_AUTH_EMULATOR_HOST,
  );
}

/**
 * Initialize Firebase Admin SDK safely across Cloud Functions Gen 2,
 * Firebase Emulator Suite, and local standalone development:
 *   1. Reuse existing initialized app instance if already initialized.
 *   2. In Cloud Functions / Cloud Run / Emulators / ADC environments, call
 *      `admin.initializeApp()` so Google Cloud managed runtime credentials are
 *      used automatically without requiring any private-key JSON file.
 *   3. In standalone local development outside Cloud Functions, fall back to
 *      an untracked local `serviceAccount.json` if present.
 */
export function initializeFirebase() {
  if (app && firestore && auth) return { app, firestore, auth };

  if (isSupabaseConfigured()) {
    const supa = initializeSupabase();
    app = supa.client;
    firestore = supa.db;
    auth = supa.auth;
    console.log(
      `[Supabase] Initialized PostgreSQL + Auth backend (${process.env.SUPABASE_URL || env.supabaseUrl})`,
    );
    return { app, firestore, auth };
  }

  if (admin.apps.length > 0) {
    app = admin.app();
    firestore = admin.firestore();
    auth = admin.auth();
    return { app, firestore, auth };
  }

  const projectId =
    resolveFirebaseProjectId() || env.firebaseProjectId || undefined;

  if (canUseManagedCredentials()) {
    app = projectId ? admin.initializeApp({ projectId }) : admin.initializeApp();
    firestore = admin.firestore();
    auth = admin.auth();
    console.log(
      `[Firebase] Initialized with managed runtime credentials (project: ${projectId || 'default'})`,
    );
    return { app, firestore, auth };
  }

  if (!fs.existsSync(env.serviceAccountPath)) {
    throw new Error(
      `\n[Backend] Database/Auth credentials not configured and local key not found at:\n  ${env.serviceAccountPath}\n\n` +
        'Options:\n' +
        '  0. Supabase PostgreSQL + Auth (primary): set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in backend/.env.\n' +
        '  1. Production / Cloud Functions Gen 2 uses managed Application Default Credentials (K_SERVICE) automatically.\n' +
        '  2. Local Emulators: run `npm run emulator` (no service account file needed).\n' +
        '  3. Standalone local against live Firebase: place an untracked JSON key at `backend/serviceAccount.json`.\n',
    );
  }

  const serviceAccount = JSON.parse(
    fs.readFileSync(env.serviceAccountPath, 'utf8'),
  );

  const resolvedProjectId = projectId || serviceAccount.project_id || undefined;

  app = admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: resolvedProjectId,
  });

  firestore = admin.firestore();
  auth = admin.auth();

  console.log(`[Firebase] Initialized (project: ${resolvedProjectId})`);
  return { app, firestore, auth };
}

export function useSupabaseClient(customClient) {
  const supa = initializeSupabase(customClient);
  app = supa.client;
  firestore = supa.db;
  auth = supa.auth;
  return { app, firestore, auth };
}

export function getDb() {
  if (!firestore) initializeFirebase();
  return firestore;
}

export function getAuth() {
  if (!auth) initializeFirebase();
  return auth;
}

export { admin };
export default admin;
