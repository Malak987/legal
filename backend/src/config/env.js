import fs from 'node:fs';
import dotenv from 'dotenv';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Load environment variables from the project root (.env)
dotenv.config({ path: path.resolve(__dirname, '../../.env') });

/// Backend root directory (<backend>/), matching the `.env` lookup above.
const backendRoot = path.resolve(__dirname, '../../');

/// `<backend>/src/` — the directory older versions of this file resolved the
/// service account from (`path.dirname(__dirname)`), where existing working
/// installations may still keep the file.
const srcRoot = path.dirname(__dirname);

/// Resolves the Firebase Admin service-account JSON.
///
/// The documented location is `<backend>/serviceAccount.json`. Older code
/// resolved the path from `<backend>/src/` instead, so working installations
/// exist with the file in *either* directory. Both are accepted (documented
/// location first) so an upgrade can never break a running backend.
///
/// Only the resolved PATH is exposed here: the file's contents (private key)
/// are never read, logged or exported by this module.
function resolveServiceAccountPath() {
  const configured = process.env.SERVICE_ACCOUNT_PATH || './serviceAccount.json';

  const candidates = path.isAbsolute(configured)
    ? [configured]
    : [
        path.resolve(backendRoot, configured), // documented: <backend>/
        path.resolve(srcRoot, configured), // legacy:    <backend>/src/
      ];

  return candidates.find((candidate) => fs.existsSync(candidate)) ?? candidates[0];
}

const env = {
  port: parseInt(process.env.PORT || '5000', 10),
  nodeEnv: process.env.NODE_ENV || 'development',
  corsOrigins: (process.env.CORS_ORIGINS || 'http://localhost:5173')
    .split(',')
    .map((o) => o.trim())
    .filter(Boolean),
  serviceAccountPath: resolveServiceAccountPath(),
  firebaseProjectId: process.env.FIREBASE_PROJECT_ID || '',
  seedOnStart: process.env.SEED_ON_START === 'true',
};

// NOTE: there is deliberately no signing secret here. Authorization is decided
// entirely from the verified Firebase ID token plus the `role` on the caller's
// profile document (see middleware/auth.js). A previous `ADMIN_JWT_SECRET`
// entry was never read by any code path and defaulted to a literal string,
// which is exactly the kind of setting that later gets mistaken for a real
// control, so it was removed instead of being given a value.


export default env;
