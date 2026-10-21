/**
 * Regression tests for `GET /api/chats`.
 *
 * They cover the two failures that made the admin panel's Chats screen break:
 *
 *  1. `where('participants','array-contains',x).orderBy('updatedAt','desc')`
 *     needs a Firestore COMPOSITE index. It is not deployed, so Firestore
 *     answered `9 FAILED_PRECONDITION` and the panel rendered a 500.
 *  2. The list was filtered by the caller's own uid, and an administrator is a
 *     participant in nobody's conversation, so the screen was always empty.
 *
 * No Firebase project, credentials or network access are required: the tests
 * copy `src/` into a temporary directory and replace `config/firebase.js` with
 * a test double, then mount the REAL routes and the REAL auth/error middleware.
 *
 * Run with:  node --test test/
 */

import assert from 'node:assert/strict';
import { once } from 'node:events';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { after, before, describe, it } from 'node:test';

import express from 'express';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const BACKEND_ROOT = path.resolve(HERE, '..');
const SRC_DIR = path.join(BACKEND_ROOT, 'src');

/**
 * Test double for `src/config/firebase.js`.
 *
 * It is written into the temporary copy of `src/`, so every module under test
 * (`routes/chats.js`, `middleware/auth.js`, …) picks it up through the normal
 * ESM resolution walk-up to `<tmp>/node_modules`.
 */
const FIREBASE_STUB = `
const fx = () => (globalThis.__chatsFixture ??= {
  mode: 'ok', chats: [], calls: [], user: null, error: null,
});

function snap(docs) {
  return Promise.resolve({ empty: docs.length === 0, docs });
}

const db = {
  collection(name) {
    const entry = { collection: name, where: [], orderBy: [], limit: null };
    fx().calls.push(entry);

    const chain = {
      where(field, op, value) { entry.where.push({ field, op, value }); return chain; },
      orderBy(field, dir) { entry.orderBy.push({ field, dir }); return chain; },
      limit(n) { entry.limit = n; return chain; },
      get() {
        if (fx().mode === 'fail') return Promise.reject(fx().error);
        let docs = fx().chats.map((c) => ({ ...c }));
        for (const w of entry.where) {
          if (w.op === 'array-contains') {
            docs = docs.filter(
              (d) => Array.isArray(d[w.field]) && d[w.field].includes(w.value),
            );
          }
        }
        return snap(docs.map((d) => ({ id: d.id, data: () => d })));
      },
      doc(id) {
        return {
          get: () => snap([]),
          collection: (sub) => db.collection(name + '/' + id + '/' + sub),
          update: () => Promise.resolve(),
          delete: () => Promise.resolve(),
        };
      },
      add: () => Promise.resolve({ get: () => snap([]) }),
    };
    return chain;
  },
  batch() {
    return { set() {}, delete() {}, commit: () => Promise.resolve() };
  },
};

export function initializeFirebase() { return { app: {}, firestore: db, auth: {} }; }
export function getDb() { return db; }
export function getAuth() {
  return {
    verifyIdToken: async (token) => {
      const user = fx().user;
      if (!user || token !== user.token) {
        throw new Error('Decoding Firebase ID token failed.');
      }
      return { uid: user.uid, email: user.email, role: user.role };
    },
  };
}
export const admin = {
  firestore: { FieldValue: { serverTimestamp: () => 'SERVER_TS' } },
};
`;

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/** Stand-in for a Firestore `Timestamp`. */
const ts = (millis) => ({ toMillis: () => millis });

const ADMIN = {
  uid: 'admin-uid',
  email: 'admin@legalapp.com',
  role: 'admin',
  token: 'ADMIN_TOKEN',
};

const CLIENT_001 = {
  uid: 'client-001',
  email: 'client001@example.com',
  role: 'client',
  token: 'CLIENT_001_TOKEN',
};

const CHATS = [
  {
    id: 'chat-1',
    participants: ['client-001', 'lawyer-001'],
    participantNames: { 'client-001': 'James Powell', 'lawyer-001': 'Maddy Lin' },
    lastMessage: 'oldest',
    updatedAt: ts(1000),
  },
  {
    id: 'chat-2',
    participants: ['client-002', 'lawyer-002'],
    participantNames: { 'client-002': 'Sara Ali', 'lawyer-002': 'Omar Adel' },
    lastMessage: 'newest',
    updatedAt: ts(3000),
  },
  {
    id: 'chat-3',
    participants: ['client-003', 'lawyer-001'],
    participantNames: { 'client-003': 'Nour Hassan', 'lawyer-001': 'Maddy Lin' },
    lastMessage: 'middle',
    updatedAt: ts(2000),
  },
  {
    // No `updatedAt`: must survive the in-memory sort instead of being dropped.
    id: 'chat-4',
    participants: ['client-004', 'lawyer-003'],
    participantNames: { 'client-004': 'Kareem Fouad', 'lawyer-003': 'Lina Samir' },
    lastMessage: 'no timestamp',
  },
];

const FAILED_PRECONDITION = Object.assign(
  new Error(
    '9 FAILED_PRECONDITION: The query requires an index. You can create it here: ' +
      'https://console.firebase.google.com/v1/r/project/legal-102026/firestore/indexes',
  ),
  { code: 9 },
);

let tmpDir;
let server;
let baseUrl;

before(async () => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'legal-chats-test-'));
  fs.cpSync(SRC_DIR, path.join(tmpDir, 'src'), { recursive: true });
  fs.symlinkSync(
    path.join(BACKEND_ROOT, 'node_modules'),
    path.join(tmpDir, 'node_modules'),
    'dir',
  );
  fs.writeFileSync(
    path.join(tmpDir, 'src', 'config', 'firebase.js'),
    FIREBASE_STUB,
  );

  const apiRoutes = (
    await import(pathToFileURL(path.join(tmpDir, 'src', 'routes', 'index.js')).href)
  ).default;
  const { notFoundHandler, errorHandler } = await import(
    pathToFileURL(path.join(tmpDir, 'src', 'middleware', 'errorHandler.js')).href
  );

  const app = express();
  app.use(express.json());
  app.use('/api', apiRoutes);
  app.use(notFoundHandler);
  app.use(errorHandler);

  server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(() => {
  server?.close();
  if (tmpDir) fs.rmSync(tmpDir, { recursive: true, force: true });
});

function setFixture(overrides = {}) {
  globalThis.__chatsFixture = {
    mode: 'ok',
    chats: CHATS.map((c) => ({ ...c })),
    calls: [],
    user: null,
    error: null,
    ...overrides,
  };
}

/** Every query the route issued against the `chats` collection. */
function chatQueries() {
  return (globalThis.__chatsFixture?.calls ?? []).filter(
    (c) => c.collection === 'chats',
  );
}

async function getChats({ token, query = '' } = {}) {
  const headers = token ? { Authorization: `Bearer ${token}` } : {};
  const res = await fetch(`${baseUrl}/api/chats${query}`, { headers });
  return { status: res.status, body: await res.json() };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('GET /api/chats — authorization is preserved', () => {
  it('rejects a request without an Authorization header with 401', async () => {
    setFixture();
    const { status, body } = await getChats();

    assert.equal(status, 401);
    assert.equal(body.success, false);
    assert.match(body.message, /Missing Authorization header/);
    assert.equal(chatQueries().length, 0, 'must not touch Firestore');
  });

  it('rejects an invalid/expired token with 401', async () => {
    setFixture({ user: CLIENT_001 });
    const { status, body } = await getChats({ token: 'NOT_A_VALID_TOKEN' });

    assert.equal(status, 401);
    assert.equal(body.success, false);
    assert.equal(chatQueries().length, 0, 'must not touch Firestore');
  });
});

describe('GET /api/chats — administrator', () => {
  it('lists every conversation, newest first, including ones with no timestamp', async () => {
    setFixture({ user: ADMIN });
    const { status, body } = await getChats({ token: ADMIN.token });

    assert.equal(status, 200);
    assert.equal(body.success, true, 'envelope { success, message, data }');
    assert.ok(Array.isArray(body.data), 'data must be a bare list for listDataOf()');

    // chat-2 (3000) > chat-3 (2000) > chat-1 (1000) > chat-4 (no timestamp)
    assert.deepEqual(
      body.data.map((c) => c.id),
      ['chat-2', 'chat-3', 'chat-1', 'chat-4'],
    );
    assert.equal(body.data.length, 4, 'no conversation may be dropped');
  });

  it('does NOT filter by the admin uid (regression: admin saw an empty list)', async () => {
    setFixture({ user: ADMIN });
    await getChats({ token: ADMIN.token });

    const queries = chatQueries();
    assert.equal(queries.length, 1, 'exactly one chats query');
    assert.deepEqual(
      queries[0].where,
      [],
      'an admin is a participant in no conversation, so the list must not be ' +
        'filtered by their uid',
    );
  });

  it('can still narrow the list with ?userId=', async () => {
    setFixture({ user: ADMIN });
    const { status, body } = await getChats({
      token: ADMIN.token,
      query: '?userId=client-001',
    });

    assert.equal(status, 200);
    assert.deepEqual(body.data.map((c) => c.id), ['chat-1']);

    const queries = chatQueries();
    assert.deepEqual(queries[0].where, [
      { field: 'participants', op: 'array-contains', value: 'client-001' },
    ]);
  });
});

describe('GET /api/chats — non-administrator', () => {
  it('lists only the conversations the caller participates in', async () => {
    setFixture({ user: CLIENT_001 });
    const { status, body } = await getChats({ token: CLIENT_001.token });

    assert.equal(status, 200);
    assert.deepEqual(body.data.map((c) => c.id), ['chat-1']);

    const queries = chatQueries();
    assert.deepEqual(queries[0].where, [
      { field: 'participants', op: 'array-contains', value: 'client-001' },
    ]);
  });

  it('ignores ?userId= from a non-admin (cannot read other users chats)', async () => {
    setFixture({ user: CLIENT_001 });
    const { status, body } = await getChats({
      token: CLIENT_001.token,
      query: '?userId=client-002',
    });

    assert.equal(status, 200);
    assert.deepEqual(
      body.data.map((c) => c.id),
      ['chat-1'],
      'the caller must still only see their own conversations',
    );
    assert.deepEqual(chatQueries()[0].where, [
      { field: 'participants', op: 'array-contains', value: 'client-001' },
    ]);
  });
});

describe('GET /api/chats — Firestore index strategy', () => {
  it('never combines array-contains with orderBy (no composite index needed)', async () => {
    for (const user of [ADMIN, CLIENT_001]) {
      setFixture({ user });
      await getChats({ token: user.token });
      await getChats({ token: user.token, query: '?userId=client-002' });

      for (const q of chatQueries()) {
        const hasArrayContains = q.where.some((w) => w.op === 'array-contains');
        assert.ok(
          !(hasArrayContains && q.orderBy.length > 0),
          'array-contains + orderBy requires a composite index that is not deployed',
        );
        assert.equal(
          q.orderBy.length,
          0,
          'ordering is applied in memory (see utils/firestore.js)',
        );
      }
    }
  });

  it('surfaces a Firestore failure as 500 instead of masking it', async () => {
    setFixture({ user: ADMIN, mode: 'fail', error: FAILED_PRECONDITION });
    const { status, body } = await getChats({ token: ADMIN.token });

    assert.equal(status, 500, 'database errors must not be swallowed');
    assert.equal(body.success, false);
    assert.match(body.message, /FAILED_PRECONDITION/);
  });
});
