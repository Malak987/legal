import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import rateLimit from 'express-rate-limit';

import env from './config/env.js';
import { initializeFirebase } from './config/firebase.js';
import apiRoutes from './routes/index.js';
import { notFoundHandler, errorHandler } from './middleware/errorHandler.js';
import { runSeed } from './seed.js';

const app = express();

// ---------- Security & middleware ----------
app.use(helmet());
app.use(
  cors({
    origin: (origin, callback) => {
      // Allow requests with no origin (mobile apps, curl, server-to-server)
      if (!origin || env.corsOrigins.includes(origin)) return callback(null, true);
      return callback(new Error(`Origin "${origin}" not allowed by CORS`));
    },
    credentials: true,
  }),
);
app.use(express.json({ limit: '2mb' }));
app.use(express.urlencoded({ extended: true }));
app.use(morgan(env.nodeEnv === 'production' ? 'combined' : 'dev'));

// Basic rate limiting to protect the API
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 1000,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, message: 'Too many requests, please try again later.' },
});
app.use('/api', limiter);

// ---------- Routes ----------
app.get('/', (_req, res) => {
  res.json({
    success: true,
    message: 'Legal Services API is running 🚀',
    docs: '/api/health',
  });
});

app.get('/api/health', (_req, res) => {
  res.json({
    success: true,
    status: 'ok',
    timestamp: new Date().toISOString(),
    environment: env.nodeEnv,
  });
});

app.use('/api', apiRoutes);

// ---------- 404 & errors ----------
app.use(notFoundHandler);
app.use(errorHandler);

// ---------- Start ----------
const server = app.listen(env.port, async () => {
  console.log(`\n⚖️  Legal Services API`);
  console.log(`   Environment : ${env.nodeEnv}`);
  console.log(`   URL         : http://localhost:${env.port}`);
  console.log(`   Health      : http://localhost:${env.port}/api/health\n`);

  try {
    initializeFirebase();
    if (env.seedOnStart) {
      console.log('[Server] SEED_ON_START=true — running seed...\n');
      await runSeed();
    }
  } catch (err) {
    console.error('[Server] Firebase/seed error:', err.message);
    console.error('   Continuing without Firebase. Fix the config and restart.\n');
  }
});

// Graceful shutdown
const shutdown = () => {
  console.log('\n[Server] Shutting down...');
  server.close(() => process.exit(0));
};
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

export default app;
