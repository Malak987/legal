import { onRequest } from 'firebase-functions/v2/https';
import app from './src/app.js';

/**
 * Primary HTTPS API entry point for Firebase Cloud Functions Gen 2.
 *
 * Firebase Hosting rewrites `/api{,/**}` to this function in `us-central1`.
 * Express retains its own CORS allowlist so runtime origin configuration stays
 * in one place rather than being duplicated in the Functions wrapper.
 */
export const api = onRequest(
  {
    region: 'us-central1',
    cors: false,
    invoker: 'public',
    // Bind the server-only credential from Firebase Secret Manager at runtime.
    // Never add its value to source, Flutter defines, or browser configuration.
    secrets: ['SUPABASE_SERVICE_ROLE_KEY'],
    timeoutSeconds: 60,
    memory: '256MiB',
    maxInstances: 20,
  },
  app,
);

export { app };
