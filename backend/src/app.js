import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import rateLimit from 'express-rate-limit';

import { env, resolveCorsOrigins } from './config/env.js';
import apiRoutes from './routes/index.js';
import { errorHandler, notFoundHandler } from './middleware/errorHandler.js';

export const MAX_JSON_BODY_BYTES = 2 * 1024 * 1024; // 2 MiB

/**
 * Resolve a stable client IP address across Cloud Run / Cloud Functions Gen 2
 * (where `X-Forwarded-For` carries the client IP and the internal IPC socket may
 * leave `req.ip` undefined in local Functions Emulator runs) and standalone TCP.
 */
export function resolveClientIp(req) {
  const forwarded = req.headers['x-forwarded-for'];
  if (typeof forwarded === 'string' && forwarded.trim() !== '') {
    return forwarded.split(',')[0].trim();
  }
  return req.ip || req.socket?.remoteAddress || '127.0.0.1';
}

/**
 * Lightweight, unauthenticated readiness check that verifies the Express +
 * Cloud Functions HTTP layer is healthy without reading secrets or querying
 * Firestore.
 */
export function healthHandler(_req, res) {
  res.json({
    success: true,
    status: 'ok',
    timestamp: new Date().toISOString(),
  });
}

/**
 * Create the Express application shared between:
 *   - Firebase Cloud Functions Gen 2 (`backend/index.js` -> `export const api`)
 *   - Standalone local HTTP server (`backend/src/index.js`)
 */
export function createApp({ extraRoutes } = {}) {
  const app = express();

  // Trust the first upstream proxy hop (Firebase Hosting / Google Frontend on
  // Cloud Run) so `req.ip` and `express-rate-limit` resolve client IPs safely
  // when `X-Forwarded-For` is present.
  app.set('trust proxy', 1);

  // Security headers
  app.use(helmet());

  // CORS — allow native mobile apps (no Origin header), allowed web origins
  // (Firebase Hosting domains + explicit CORS_ORIGINS), and localhost origins
  // during non-production development.
  app.use(
    cors({
      origin: (origin, callback) => {
        if (!origin) return callback(null, true);
        const currentNodeEnv =
          process.env.NODE_ENV || (env.isCloudFunction ? 'production' : env.nodeEnv);
        const allowedOrigins = resolveCorsOrigins({
          ...process.env,
          NODE_ENV: currentNodeEnv,
        });
        if (
          allowedOrigins.includes(origin) ||
          (currentNodeEnv !== 'production' && origin.startsWith('http://localhost:'))
        ) {
          return callback(null, true);
        }
        callback(new Error(`Origin ${origin} not allowed by CORS`));
      },
      credentials: true,
    }),
  );

  // Rate limiting (100 requests per 15 min per client IP)
  app.use(
    rateLimit({
      windowMs: 15 * 60 * 1000,
      max: 100,
      standardHeaders: true,
      legacyHeaders: false,
      keyGenerator: resolveClientIp,
      validate: { ip: false },
      message: {
        success: false,
        error: 'Too many requests, please try again later.',
      },
    }),
  );

  // Cloud Functions (`functions-framework`) buffers the HTTP stream into
  // `req.rawBody` and populates `req.body` before handing the request to
  // Express, without marking body-parser's internal `req._body` flag. Handle
  // pre-buffered payloads cleanly while enforcing the same 2 MiB ceiling as
  // standalone `express.json({ limit: '2mb' })`.
  app.use((req, _res, next) => {
    if (Buffer.isBuffer(req.rawBody) && req.rawBody.length > MAX_JSON_BODY_BYTES) {
      const tooLarge = new Error('Request entity too large.');
      tooLarge.status = 413;
      return next(tooLarge);
    }
    if (req.body !== undefined) {
      req._body = true;
      return next();
    }
    if (Buffer.isBuffer(req.rawBody)) {
      const contentType = (req.headers['content-type'] || '').toLowerCase();
      if (contentType.includes('application/json')) {
        const rawText = req.rawBody.toString('utf8');
        req._body = true;
        if (!rawText.trim()) {
          req.body = {};
          return next();
        }
        try {
          req.body = JSON.parse(rawText);
          return next();
        } catch (_err) {
          const badJson = new SyntaxError('Malformed JSON payload.');
          badJson.status = 400;
          return next(badJson);
        }
      }
    }
    return next();
  });

  // Body parsing & request logging for standalone HTTP execution
  app.use(express.json({ limit: '2mb' }));
  app.use(express.urlencoded({ extended: true }));
  if (process.env.NODE_ENV !== 'test') {
    app.use(morgan('dev'));
  }

  // Lightweight health probe available both via Firebase Hosting (`/api/health`)
  // and direct Cloud Functions URL (`/health`), before any Firebase/DB calls.
  app.get(['/api/health', '/health'], healthHandler);

  // Reject accidentally doubled `/api/api/...` paths explicitly so client
  // base-URL misconfigurations fail fast with a clear 404 instead of matching
  // anything ambiguously.
  app.use('/api/api', notFoundHandler);

  // Mount API routes:
  //   - `/api` handles requests arriving through Firebase Hosting rewrites
  //     (`https://legal-102026.web.app/api/...`, where Hosting preserves the
  //     full `/api/...` path) as well as standalone local servers.
  //   - `/` handles direct invocations of the Cloud Function URL
  //     (`https://us-central1-legal-102026.cloudfunctions.net/api/...`, where
  //     Cloud Functions strips the function name prefix).
  app.use('/api', apiRoutes);
  app.use('/', apiRoutes);
  if (extraRoutes) {
    app.use(extraRoutes);
  }

  // 404 & central error handling
  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}

const app = createApp();

export default app;
