/**
 * End-to-end integration tests against real Firebase Emulator Suite processes:
 *   - Firebase Hosting Emulator (`127.0.0.1:5000`) -> `/api{,/**}` rewrite
 *   - Firebase Cloud Functions Gen 2 Emulator (`127.0.0.1:5001`) -> `us-central1-api`
 *   - Firebase Auth Emulator (`127.0.0.1:9099`) -> real JWT ID tokens
 *   - Cloud Firestore Emulator (`127.0.0.1:8080`, automatically tested when active)
 *
 * Run locally without Java:
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 firebase emulators:exec --project legal-102026 --only auth,functions,hosting "npm --prefix backend run test:emulator"
 * Run full stack with Firestore Emulator (local with Java or CI):
 *   firebase emulators:exec --project legal-102026 --only auth,firestore,functions,hosting "RUN_FIRESTORE_E2E=1 npm --prefix backend run test:emulator"
 */

import assert from 'node:assert/strict';
import net from 'node:net';
import { describe, it } from 'node:test';

const ENABLED = process.env.RUN_FIREBASE_EMULATOR_TESTS === '1';
const PROJECT_ID = process.env.GCLOUD_PROJECT || 'legal-102026';
const HOSTING_BASE = `http://${process.env.FIREBASE_HOSTING_EMULATOR_HOST || '127.0.0.1:5000'}`;
const FUNCTIONS_BASE = `http://127.0.0.1:5001/${PROJECT_ID}/us-central1/api`;
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';

async function isTcpPortOpen(hostPort) {
  const [host, rawPort] = hostPort.split(':');
  const port = Number(rawPort);
  if (!host || !port) return false;
  return new Promise((resolve) => {
    const sock = net.createConnection({ host, port });
    sock.setTimeout(500);
    sock.once('connect', () => {
      sock.destroy();
      resolve(true);
    });
    sock.once('error', () => resolve(false));
    sock.once('timeout', () => {
      sock.destroy();
      resolve(false);
    });
  });
}

async function signUpAuthEmulatorUser(email, password = 'Password123!') {
  const res = await fetch(
    `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-emulator-api-key`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    },
  );
  assert.equal(res.status, 200, 'Auth emulator signUp should succeed');
  return res.json();
}

describe(
  'Firebase Hosting + Cloud Functions Gen 2 + Auth (+ Firestore) Emulator Suite',
  { skip: !ENABLED && 'Set RUN_FIREBASE_EMULATOR_TESTS=1 via firebase emulators:exec' },
  () => {
    it('rewrites GET /api/health on Firebase Hosting to the Gen 2 `api` function cleanly', async () => {
      const res = await fetch(`${HOSTING_BASE}/api/health`, {
        headers: { Origin: 'https://legal-102026.web.app' },
      });
      assert.equal(res.status, 200);
      assert.equal(
        res.headers.get('access-control-allow-origin'),
        'https://legal-102026.web.app',
      );
      const body = await res.json();
      assert.equal(body.success, true);
      assert.equal(body.status, 'ok');
      assert.equal(typeof body.timestamp, 'string');
    });

    it('also serves GET /health directly on the Cloud Functions Gen 2 endpoint', async () => {
      const res = await fetch(`${FUNCTIONS_BASE}/health`);
      assert.equal(res.status, 200);
      const body = await res.json();
      assert.equal(body.success, true);
      assert.equal(body.status, 'ok');
    });

    it('returns 404 on accidental double /api/api/... paths through Firebase Hosting', async () => {
      const res = await fetch(`${HOSTING_BASE}/api/api/health`);
      assert.equal(res.status, 404);
      const body = await res.json();
      assert.equal(body.success, false);
    });

    it('parses JSON POST bodies through Hosting + Functions without stream hang and verifies real Firebase Auth JWTs', async () => {
      // 1. Unauthenticated POST /api/users/me -> 401
      const unauthRes = await fetch(`${HOSTING_BASE}/api/users/me`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Origin: 'https://legal-102026.web.app',
        },
        body: JSON.stringify({ name: 'Test User' }),
      });
      assert.equal(unauthRes.status, 401);
      const unauthBody = await unauthRes.json();
      assert.equal(unauthBody.success, false);

      // 2. Real Firebase Auth Emulator JWT + invalid payload (`name` missing) -> 400
      const authUser = await signUpAuthEmulatorUser(
        `probe-${Date.now()}@legal-test.local`,
      );
      const invalidPayloadRes = await fetch(`${HOSTING_BASE}/api/users/me`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${authUser.idToken}`,
          'Content-Type': 'application/json',
          Origin: 'https://legal-102026.web.app',
        },
        body: JSON.stringify({ name: '' }),
      });
      assert.equal(invalidPayloadRes.status, 400);
      const invalidBody = await invalidPayloadRes.json();
      assert.equal(invalidBody.success, false);
    });

    it('executes full authenticated Firestore CRUD through Hosting -> Gen 2 Function -> Firestore', async (t) => {
      const firestoreOpen = await isTcpPortOpen(
        process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080',
      );
      if (!firestoreOpen && process.env.RUN_FIRESTORE_E2E !== '1') {
        t.skip('Firestore emulator port 8080 not listening in Java-less sandbox');
        return;
      }

      const email = `client-${Date.now()}@legal-test.local`;
      const authUser = await signUpAuthEmulatorUser(email);
      const headers = {
        Authorization: `Bearer ${authUser.idToken}`,
        'Content-Type': 'application/json',
        Origin: 'https://legal-102026.web.app',
      };

      // 1. Provision user profile via POST /api/users/me through Hosting rewrite
      const createUserRes = await fetch(`${HOSTING_BASE}/api/users/me`, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          name: 'Amira Hassan',
          phone: '+201001234567',
        }),
      });
      assert.equal(createUserRes.status, 201);
      const createdUser = await createUserRes.json();
      assert.equal(createdUser.success, true);
      assert.equal(createdUser.data.uid, authUser.localId);
      assert.equal(createdUser.data.role, 'client');

      // 2. Read own profile via GET /api/users/:uid through Hosting rewrite
      const meRes = await fetch(
        `${HOSTING_BASE}/api/users/${authUser.localId}`,
        { headers },
      );
      assert.equal(meRes.status, 200);
      const meBody = await meRes.json();
      assert.equal(meBody.data.email, email);

      // 3. Public GET /api/lawyers through Hosting rewrite
      const lawyersRes = await fetch(`${HOSTING_BASE}/api/lawyers`);
      assert.equal(lawyersRes.status, 200);
      const lawyersBody = await lawyersRes.json();
      assert.equal(lawyersBody.success, true);
      assert.equal(Array.isArray(lawyersBody.data.items), true);
    });
  },
);
