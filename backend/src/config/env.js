import dotenv from 'dotenv';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Load environment variables from the project root (.env)
dotenv.config({ path: path.resolve(__dirname, '../../.env') });

const env = {
  port: parseInt(process.env.PORT || '5000', 10),
  nodeEnv: process.env.NODE_ENV || 'development',
  corsOrigins: (process.env.CORS_ORIGINS || 'http://localhost:5173')
    .split(',')
    .map((o) => o.trim())
    .filter(Boolean),
  serviceAccountPath: path.resolve(
    path.dirname(__dirname),
    process.env.SERVICE_ACCOUNT_PATH || './serviceAccount.json',
  ),
  firebaseProjectId: process.env.FIREBASE_PROJECT_ID || '',
  adminJwtSecret: process.env.ADMIN_JWT_SECRET || 'dev-secret',
  seedOnStart: process.env.SEED_ON_START === 'true',
};

export default env;
