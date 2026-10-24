import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import rateLimit from 'express-rate-limit';

import { env, resolveCorsOrigins } from './config/env.js';
import apiRoutes from './routes/index.js';
import { errorHandler, notFoundHandler } from './middleware/errorHandler.js';

export const MAX_JSON_BODY_BYTES = 2 * 1024 * 1024;

export function resolveClientIp(req) {
  const forwarded = req.headers['x-forwarded-for'];
  if (typeof forwarded === 'string' && forwarded.trim() !== '') {
    return forwarded.split(',')[0].trim();
  }
  return req.ip || req.socket?.remoteAddress || '127.0.0.1';
}

export function healthHandler(_req, res) {
  res.json({ success: true, status: 'ok', timestamp: new Date().toISOString() });
}

export function createApp({ extraRoutes } = {}) {
  const app = express();
  app.set('trust proxy', 1);
  app.use(helmet());
  app.use(cors({
    origin: (origin, callback) => {
      if (!origin) return callback(null, true);
      const currentNodeEnv = process.env.NODE_ENV || env.nodeEnv;
      const allowedOrigins = resolveCorsOrigins({ ...process.env, NODE_ENV: currentNodeEnv });
      if (
        allowedOrigins.includes(origin) ||
        (currentNodeEnv !== 'production' && origin.startsWith('http://localhost:'))
      ) {
        return callback(null, true);
      }
      return callback(new Error('Origin is not allowed by CORS.'));
    },
    credentials: true,
  }));
  app.use(rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 100,
    standardHeaders: true,
    legacyHeaders: false,
    keyGenerator: resolveClientIp,
    validate: { ip: false },
    message: { success: false, error: 'Too many requests, please try again later.' },
  }));
  // Cloud Functions may pass an already-parsed body and an ended request stream,
  // so express.json() cannot enforce its size limit against the raw bytes there.
  app.use((req, _res, next) => {
    const rawBody = req.rawBody;
    const rawBytes = Buffer.isBuffer(rawBody)
      ? rawBody.length
      : ArrayBuffer.isView(rawBody)
        ? rawBody.byteLength
        : typeof rawBody === 'string'
          ? Buffer.byteLength(rawBody)
          : 0;
    if (rawBytes > MAX_JSON_BODY_BYTES) {
      const error = new Error('Request body too large.');
      error.status = 413;
      error.type = 'entity.too.large';
      return next(error);
    }
    return next();
  });
  app.use(express.json({ limit: MAX_JSON_BODY_BYTES }));
  app.use(express.urlencoded({ extended: true }));
  if (process.env.NODE_ENV !== 'test') app.use(morgan('dev'));

  app.get(['/api/health', '/health'], healthHandler);
  app.use('/api', apiRoutes);
  if (extraRoutes) app.use(extraRoutes);
  app.use(notFoundHandler);
  app.use(errorHandler);
  return app;
}

const app = createApp();
export default app;
