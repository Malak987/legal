/**
 * Cloud Functions Gen 2, Firebase Hosting rewrite, managed credentials, and
 * security contract tests.
 */

import assert from 'node:assert/strict';
import http from 'node:http';
import { after, before, describe, it } from 'node:test';

import { api } from '../index.js';
import app, { MAX_JSON_BODY_BYTES, createApp } from '../src/app.js';
import {
  DEFAULT_FIREBASE_PROJECT_ID,
  isCloudFunctionsRuntime,
  parseFirebaseConfigProjectId,
  resolveCorsOrigins,
  resolveFirebaseProjectId,
} from '../src/config/env.js';
import { canUseManagedCredentials } from '../src/config/firebase.js';

let server;
let baseUrl;

before(async () => {
  server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();
  baseUrl = `http://127.0.0.1:${port}`;
});

after(async () => {
  if (server) {
    await new Promise((resolve) => server.close(resolve));
  }
});

describe('Cloud Functions Gen 2 export contract (`backend/index.js`)', () => {
  it('exports a 2nd-gen HTTPS `api` function in us-central1 with Express CORS control', () => {
    assert.equal(typeof api, 'function');
    assert.equal(api.__endpoint?.platform, 'gcfv2');
    assert.deepEqual(api.__endpoint?.region, ['us-central1']);
    assert.equal(api.__endpoint?.httpsTrigger?.invoker?.[0], 'public');
    assert.equal(api.__endpoint?.timeoutSeconds, 60);
    assert.equal(api.__endpoint?.availableMemoryMb, 256);
    assert.equal(api.__endpoint?.maxInstances, 20);
  });
});

describe('Managed runtime credentials & seed safety (`env.js` + `firebase.js`)', () => {
  it('detects Cloud Run, Cloud Functions, and Emulator runtimes', () => {
    assert.equal(isCloudFunctionsRuntime({}), false);
    assert.equal(isCloudFunctionsRuntime({ K_SERVICE: 'api' }), true);
    assert.equal(isCloudFunctionsRuntime({ FUNCTION_TARGET: 'api' }), true);
    assert.equal(isCloudFunctionsRuntime({ FUNCTIONS_EMULATOR: 'true' }), true);
  });

  it('uses managed credentials without serviceAccount.json in Cloud Functions & Emulators', () => {
    assert.equal(canUseManagedCredentials({}), false);
    assert.equal(canUseManagedCredentials({ K_SERVICE: 'api' }), true);
    assert.equal(
      canUseManagedCredentials({
        FIREBASE_CONFIG: JSON.stringify({ projectId: 'legal-102026' }),
      }),
      true,
    );
    assert.equal(
      canUseManagedCredentials({ FIRESTORE_EMULATOR_HOST: '127.0.0.1:8080' }),
      true,
    );
    assert.equal(
      canUseManagedCredentials({ FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9099' }),
      true,
    );
  });

  it('resolves projectId from explicit env vars or injected FIREBASE_CONFIG JSON', () => {
    assert.equal(
      parseFirebaseConfigProjectId('{"projectId":"legal-102026","storageBucket":"x"}'),
      'legal-102026',
    );
    assert.equal(parseFirebaseConfigProjectId('storage.googleapis.com'), '');
    assert.equal(
      resolveFirebaseProjectId({
        FIREBASE_CONFIG: '{"projectId":"legal-102026"}',
      }),
      'legal-102026',
    );
  });

  it('allows Firebase Hosting domains by default in production and strips localhost', () => {
    const prodOrigins = resolveCorsOrigins({ NODE_ENV: 'production' });
    assert.deepEqual(prodOrigins, [
      `https://${DEFAULT_FIREBASE_PROJECT_ID}.web.app`,
      `https://${DEFAULT_FIREBASE_PROJECT_ID}.firebaseapp.com`,
    ]);

    const devOrigins = resolveCorsOrigins({ NODE_ENV: 'development' });
    assert.equal(devOrigins.includes('http://localhost:5173'), true);
  });
});

describe('Health endpoint, Hosting path preservation, and CORS headers', () => {
  it('serves lightweight GET /api/health without exposing secrets or database internals', async () => {
    const res = await fetch(`${baseUrl}/api/health`, {
      headers: { 'X-Forwarded-For': '203.0.113.10, 34.117.59.81' },
    });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.success, true);
    assert.equal(body.status, 'ok');
    assert.equal(typeof body.timestamp, 'string');
    assert.deepEqual(Object.keys(body).sort(), ['status', 'success', 'timestamp']);
  });

  it('serves GET /health for direct cloudfunctions.net invocations', async () => {
    const res = await fetch(`${baseUrl}/health`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.success, true);
    assert.equal(body.status, 'ok');
  });

  it('returns 404 on accidental double /api/api/... paths', async () => {
    const res = await fetch(`${baseUrl}/api/api/health`);
    assert.equal(res.status, 404);
    const body = await res.json();
    assert.equal(body.success, false);
  });

  it('allows Firebase Hosting Origin headers in production mode and rejects unknown origins', async () => {
    const prevNodeEnv = process.env.NODE_ENV;
    process.env.NODE_ENV = 'production';
    try {
      const okRes = await fetch(`${baseUrl}/api/health`, {
        headers: { Origin: 'https://legal-102026.web.app' },
      });
      assert.equal(okRes.status, 200);
      assert.equal(
        okRes.headers.get('access-control-allow-origin'),
        'https://legal-102026.web.app',
      );

      const blockedRes = await fetch(`${baseUrl}/api/health`, {
        headers: { Origin: 'https://malicious.example.com' },
      });
      assert.equal(blockedRes.status, 500);
      assert.equal(blockedRes.headers.get('access-control-allow-origin'), null);
    } finally {
      if (prevNodeEnv === undefined) delete process.env.NODE_ENV;
      else process.env.NODE_ENV = prevNodeEnv;
    }
  });

  it('handles pre-parsed `req.body` + `req.rawBody` from Cloud Functions without hanging and enforces 2 MiB ceiling', async () => {
    let capturedBody;
    const cfApp = createApp({
      extraRoutes: (req, res, next) => {
        if (req.method === 'POST' && req.path === '/__cf_probe') {
          capturedBody = req.body;
          return res.json({ ok: true, body: req.body });
        }
        return next();
      },
    });

    // Simulate functions-framework passing an already-ended stream with `req.body` + `req.rawBody`.
    const runSyntheticRequest = (rawBuffer, parsedBody) =>
      new Promise((resolve) => {
        const req = Object.assign(new http.IncomingMessage(null), {
          method: 'POST',
          url: '/__cf_probe',
          headers: {
            'content-type': 'application/json',
            host: 'legal-102026.web.app',
          },
          connection: { remoteAddress: '127.0.0.1' },
          socket: { remoteAddress: '127.0.0.1' },
          rawBody: rawBuffer,
          body: parsedBody,
        });
        req.push(null);

        const res = new http.ServerResponse(req);
        const chunks = [];
        const origWrite = res.write.bind(res);
        const origEnd = res.end.bind(res);
        res.write = (chunk, ...rest) => {
          if (chunk) chunks.push(Buffer.from(chunk));
          return origWrite(chunk, ...rest);
        };
        res.end = (chunk, ...rest) => {
          if (chunk) chunks.push(Buffer.from(chunk));
          origEnd(chunk, ...rest);
          resolve({ statusCode: res.statusCode, raw: Buffer.concat(chunks).toString('utf8') });
        };
        cfApp.handle(req, res);
      });

    const payload = { hello: 'functions-gen2' };
    const small = await runSyntheticRequest(
      Buffer.from(JSON.stringify(payload)),
      payload,
    );
    assert.equal(small.statusCode, 200);
    assert.deepEqual(capturedBody, payload);

    const oversized = await runSyntheticRequest(
      Buffer.alloc(MAX_JSON_BODY_BYTES + 128, 'a'),
      undefined,
    );
    assert.equal(oversized.statusCode, 413);
  });
});
