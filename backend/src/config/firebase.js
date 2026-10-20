import admin from 'firebase-admin';
import fs from 'node:fs';
import env from './env.js';

let app = null;
let firestore = null;
let auth = null;

/**
 * Initialize Firebase Admin SDK using the service account JSON file.
 * If the file is missing we throw a helpful error with setup instructions.
 */
export function initializeFirebase() {
  if (app) return { app, firestore, auth };

  if (!fs.existsSync(env.serviceAccountPath)) {
    throw new Error(
      `\n[Firebase] Service account not found at:\n  ${env.serviceAccountPath}\n\n` +
        'To fix this:\n' +
        '  1. Go to Firebase Console > Project Settings > Service accounts\n' +
        '  2. Click "Generate new private key"\n' +
        '  3. Save the downloaded JSON as "serviceAccount.json" inside the backend folder\n',
    );
  }

  const serviceAccount = JSON.parse(
    fs.readFileSync(env.serviceAccountPath, 'utf8'),
  );

  const projectId =
    env.firebaseProjectId || serviceAccount.project_id || undefined;

  app = admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId,
  });

  firestore = admin.firestore();
  auth = admin.auth();

  console.log(`[Firebase] Initialized (project: ${projectId})`);
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
