/**
 * Emulator integration tests for the Supabase-first API boundary:
 *   - Firebase Hosting Emulator (`127.0.0.1:5000`) -> `/api{,/**}` rewrite
 *   - Firebase Cloud Functions Gen 2 Emulator (`127.0.0.1:5001`) -> `us-central1-api`
 *   - Firebase Auth Emulator (`127.0.0.1:9099`) -> real Firebase ID tokens, which
 *     must not authenticate against Supabase-only profile routes
 *   - Cloud Firestore Emulator (`127.0.0.1:8080`) -> confirms rejected Firebase
 *     requests do not create legacy `users/{uid}` profiles when available
 *
 * Run locally without Java:
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 firebase emulators:exec --project legal-102026 --only auth,functions,hosting "npm --prefix backend run test:emulator"
 * Run with Firestore Emulator (local with Java or CI):
 *   firebase emulators:exec --project legal-102026 --only auth,firestore,functions,hosting "RUN_FIRESTORE_E2E=1 npm --prefix backend run test:emulator"
 */

import assert from 'node:assert/strict';
import admin from 'firebase-admin';
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
  'Firebase Hosting + Cloud Functions Gen 2 + Auth/Firestore Emulator Suite (Supabase migration guard)',
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

    it('rejects Firebase Auth tokens on Supabase-only profile routes before payload handling', async () => {
      // Authentication is required before request-body validation.
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

      // A valid Firebase Auth Emulator ID token is not a Supabase access token.
      // The migrated API must reject it even when the JSON body is malformed.
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
      assert.equal(invalidPayloadRes.status, 401);
      const invalidBody = await invalidPayloadRes.json();
      assert.equal(invalidBody.success, false);
    });

    it('does not provision or expose a legacy Firestore profile from a Firebase Auth token', async (t) => {
      const firestoreHost =
        process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
      const firestoreOpen = await isTcpPortOpen(firestoreHost);
      if (process.env.RUN_FIRESTORE_E2E === '1') {
        assert.equal(firestoreOpen, true, 'Firestore emulator must be listening');
      }

      const email = `client-${Date.now()}@legal-test.local`;
      const authUser = await signUpAuthEmulatorUser(email);
      const headers = {
        Authorization: `Bearer ${authUser.idToken}`,
        'Content-Type': 'application/json',
        Origin: 'https://legal-102026.web.app',
      };

      const createUserRes = await fetch(`${HOSTING_BASE}/api/users/me`, {
        method: 'POST',
        headers,
        body: JSON.stringify({ name: 'Amira Hassan', phone: '+201001234567' }),
      });
      assert.equal(createUserRes.status, 401);
      const createUserBody = await createUserRes.json();
      assert.equal(createUserBody.success, false);

      const meRes = await fetch(
        `${HOSTING_BASE}/api/users/${authUser.localId}`,
        { headers },
      );
      assert.equal(meRes.status, 401);

      if (!firestoreOpen) {
        t.diagnostic(
          'Firestore emulator is unavailable; the Supabase-only API rejection was still verified.',
        );
        return;
      }

      // Firestore rules intentionally deny client REST reads. Inspect only an
      // explicitly configured local emulator with Firebase Admin; this check
      // cannot touch a production project or credential.
      assert.ok(
        process.env.FIRESTORE_EMULATOR_HOST,
        'FIRESTORE_EMULATOR_HOST must explicitly identify the local emulator',
      );
      const firestoreHostname = firestoreHost.startsWith('[')
        ? firestoreHost.slice(1, firestoreHost.indexOf(']'))
        : firestoreHost.slice(0, firestoreHost.lastIndexOf(':'));
      assert.ok(
        ['127.0.0.1', 'localhost', '::1'].includes(firestoreHostname),
        `Refusing non-local Firestore host: ${firestoreHostname}`,
      );

      const firestoreApp = admin.initializeApp(
        { projectId: PROJECT_ID },
        `supabase-migration-check-${Date.now()}`,
      );
      try {
        const profile = await admin
          .firestore(firestoreApp)
          .collection('users')
          .doc(authUser.localId)
          .get();
        assert.equal(profile.exists, false, 'no legacy Firestore profile is created');
      } finally {
        await firestoreApp.delete();
      }
    });
  },
);
