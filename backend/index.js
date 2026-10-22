import { onRequest } from 'firebase-functions/v2/https';
import app from './src/app.js';

/**
 * Primary HTTPS API entry point for Firebase Cloud Functions (2nd gen).
 *
 * Deployed region: `us-central1`
 * Firebase Hosting rewrite: `/api{,/**}` -> `api` (`us-central1`)
 *
 * Note: `cors` is set to `false` at the Functions wrapper layer because
 * `src/app.js` enforces dynamic origin allowlisting directly inside Express.
 */
export const api = onRequest(
  {
    region: 'us-central1',
    cors: false,
    invoker: 'public',
    timeoutSeconds: 60,
    memory: '256MiB',
    maxInstances: 20,
  },
  app,
);

export { app };
