/**
 * Shared test harness for the backend authorization tests.
 *
 * It copies `src/` into a temporary directory, installs in-memory test
 * boundaries for the legacy Firebase fixture store and the Supabase Auth,
 * public-read, and RPC edges, then mounts the REAL routes, the REAL auth
 * middleware and the REAL error handler. A route receives a marked
 * caller-scoped test database only after the fixture verifier accepts the
 * bearer token; role, ownership and input checks remain in the real route code.
 *
 * Nothing touches a live Firebase or Supabase project, no credentials are
 * needed, and no network access is required. Every query the routes issue is
 * recorded so the tests can assert their query shapes.
 *
 * Used by: users.test.js, wallet.test.js, notifications.test.js,
 * favorites.test.js, chats_authorization.test.js, availability.test.js,
 * ownership.test.js
 */

import { once } from 'node:events';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import express from 'express';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const BACKEND_ROOT = path.resolve(HERE, '..', '..');
const SRC_DIR = path.join(BACKEND_ROOT, 'src');

/**
 * Source of the `config/firebase.js` test double written into the temp copy.
 *
 * Control object: `globalThis.__fx = { collections, user, error, calls }`.
 * Tests mutate it between requests.
 */
const FIREBASE_STUB = `
const fx = () => (globalThis.__fx ??= {
  collections: {},   // name -> [{ id, ...data }]
  user: null,        // { uid, role, token } — the authenticated caller
  error: null,       // when set, every read rejects with it
  calls: [],         // every query issued, for composite-index assertions
  failWritesTo: null, // collection name whose writes throw (failure injection)
  versions: {},      // "collection/id" -> monotonic write counter (MVCC)
  txAttempts: 0,     // transactions attempted, including retries
  authUpdates: [],   // calls to auth.updateUser (email synchronisation)
  failAuthUpdates: null, // message thrown by auth.updateUser, when set
  rpcCalls: [],      // caller-scoped RPCs requested by the Supabase test seam
  rpcHandlers: {},   // per-test RPC handlers (never backed by a live client)
});

let sequence = 0;
const nextId = () => 'gen-' + (++sequence);

function snapshot(docs) {
  return {
    empty: docs.length === 0,
    docs: docs.map((d) => ({ id: d.id, data: () => ({ ...d }) })),
  };
}

function one(doc) {
  return doc
    ? { exists: true, id: doc.id, data: () => ({ ...doc }) }
    : { exists: false, id: null, data: () => undefined };
}

function clone(list) {
  return (list ?? []).map((d) => ({ ...d }));
}

function store(name) {
  const f = fx();
  if (!f.collections[name]) f.collections[name] = [];
  return f.collections[name];
}

/// Throws when the test injected a write failure for this collection.
function guardWrite(name) {
  const f = fx();
  if (f.failWritesTo === name) {
    throw new Error('simulated write failure: ' + name);
  }
}

/// Logical version of a document, used for optimistic conflict detection.
/// Bumped on every write so an in-flight transaction can tell that a document
/// it read has changed underneath it.
function versionOf(key) {
  const f = fx();
  if (!f.versions) f.versions = {};
  return f.versions[key] ?? 0;
}

function bumpVersion(key) {
  const f = fx();
  if (!f.versions) f.versions = {};
  f.versions[key] = versionOf(key) + 1;
}

/// Shallow snapshot deep enough to restore the in-memory store after a
/// failed transaction: documents are flat and writes mutate them in place.
function snapshotCollections() {
  const out = {};
  for (const [name, list] of Object.entries(fx().collections)) {
    out[name] = list.map((d) => ({ ...d }));
  }
  return out;
}

function matches(doc, constraints) {
  return constraints.every((c) => {
    if (c.op === '==') return doc[c.field] === c.value;
    if (c.op === 'in') return Array.isArray(c.value) && c.value.includes(doc[c.field]);
    if (c.op === 'array-contains') {
      return Array.isArray(doc[c.field]) && doc[c.field].includes(c.value);
    }
    return true;
  });
}

const db = {
  collection(name) {
    const entry = { collection: name, where: [], orderBy: [], limit: null, op: 'get' };
    fx().calls.push(entry);

    const chain = {
      where(field, op, value) { entry.where.push({ field, op, value }); return chain; },
      orderBy(field, dir) { entry.orderBy.push({ field, dir }); return chain; },
      limit(n) { entry.limit = n; return chain; },
      startAfter() { return chain; },
      async get() {
        if (fx().error) throw fx().error;
        let docs = clone(store(name)).filter((d) => matches(d, entry.where));
        const comparable = (value) => {
          if (value && typeof value.toMillis === 'function') return value.toMillis();
          if (value instanceof Date) return value.getTime();
          return value;
        };
        for (const order of [...entry.orderBy].reverse()) {
          docs.sort((left, right) => {
            const a = comparable(left[order.field]);
            const b = comparable(right[order.field]);
            if (a === b) return 0;
            if (a === undefined || a === null) return 1;
            if (b === undefined || b === null) return -1;
            const result = a < b ? -1 : 1;
            return order.dir === 'desc' ? -result : result;
          });
        }
        if (entry.limit !== null) docs = docs.slice(0, entry.limit);
        entry.op = 'get';
        return snapshot(docs);
      },
      async add(data) {
        guardWrite(name);
        const id = nextId();
        const doc = { id, ...data };
        store(name).push(doc);
        entry.op = 'add';
        return { id, get: async () => one(store(name).find((d) => d.id === id)) };
      },
      doc(id) { return docRef(name, id ?? nextId()); },
      batch() {
        const ops = [];
        return {
          set(ref, data) { ops.push(() => ref._set(data)); },
          delete(ref) { ops.push(() => ref._delete()); },
          async commit() { for (const op of ops) await op(); },
        };
      },
    };
    return chain;
  },
};

/// Optimistic-concurrency emulation of \`db.runTransaction\`.
///
/// WHAT THIS MODELS (documented Firestore behaviour):
///   * every document read through \`tx.get(docRef)\` is version-tracked, and
///     the commit is rejected if any of those versions moved — Firestore's
///     "read version / conflict" contract;
///   * a rejected transaction is re-run from the start, like the SDK retry;
///   * writes are applied as one unit, so a failure part-way leaves the store
///     exactly as it was (all-or-nothing);
///   * creating a document that another transaction created concurrently is a
///     conflict, not a silent overwrite;
///   * every transactional read yields to the event loop first, so requests
///     genuinely overlap — without that yield the whole transaction runs in one
///     microtask chain and "concurrent" tests would execute serially and prove
///     nothing.
///
/// WHAT THIS DOES NOT MODEL (and must never be claimed as verified):
///   * QUERY reads inside a transaction are NOT version-tracked. Firestore
///     documents that transactions do not get phantom protection for queries
///     either — a \`where(...)\` check inside a transaction therefore cannot be
///     used as a uniqueness guarantee. This is deliberate: it keeps the local
///     harness from handing the route a promise production does not make.
///     The wallet route therefore guards uniqueness with a DETERMINISTIC
///     document id (see src/routes/wallet.js), never with a query.
///   * latency, partial network failures, multi-region behaviour, and the
///     server-side read set for queries are not simulated.
// The real SDK keeps retrying until the transaction deadline (about a minute),
// not a fixed handful of attempts. A low cap here would turn healthy
// contention into a bogus ABORTED failure, so keep it comfortably above the
// widest race any test drives.
const MAX_TRANSACTION_ATTEMPTS = 10;

db.runTransaction = async function runTransaction(fn) {
  for (let attempt = 1; attempt <= MAX_TRANSACTION_ATTEMPTS; attempt += 1) {
    fx().txAttempts += 1;

    const ops = [];
    const reads = new Map(); // doc key -> version observed at read time
    const tx = {
      get: async (target) => {
        // Yield to the event loop before answering. A real Firestore read is a
        // network round-trip, which is what lets two requests overlap at all;
        // without this the whole transaction runs inside one microtask chain
        // and concurrent requests silently execute one after another, so the
        // conflict detector would never be tested.
        await new Promise((resolve) => setImmediate(resolve));
        const result = await target.get();
        // Only document reads participate in conflict detection.
        if (target && target.__kind === 'doc') {
          reads.set(target.__key, versionOf(target.__key));
        }
        return result;
      },
      set: (ref, data, options) => { ops.push(() => ref.set(data, options)); return tx; },
      update: (ref, data) => { ops.push(() => ref.update(data)); return tx; },
      delete: (ref) => { ops.push(() => ref.delete()); return tx; },
    };

    const result = await fn(tx);

    // A document this transaction read changed before it could commit.
    let conflicted = false;
    for (const [key, seen] of reads) {
      if (versionOf(key) !== seen) { conflicted = true; break; }
    }
    if (conflicted) continue;

    const backup = snapshotCollections();
    try {
      for (const op of ops) await op();
    } catch (error) {
      fx().collections = backup;
      throw error;
    }
    return result;
  }

  const error = new Error('ABORTED: transaction contention, too many retries');
  error.code = 'aborted';
  throw error;
};

function docRef(collectionName, id) {
  const find = () => store(collectionName).find((d) => d.id === id);
  const key = collectionName + '/' + id;
  const ref = {
    // Marked so \`runTransaction\` can record which documents were read.
    __kind: 'doc',
    __key: key,
    // Firestore's DocumentReference exposes the id, and routes rely on it.
    id,
    get: async () => one(find()),
    async update(patch) {
      guardWrite(collectionName);
      bumpVersion(key);
      const doc = find();
      if (doc) Object.assign(doc, patch);
    },
    async set(data, options) {
      guardWrite(collectionName);
      bumpVersion(key);
      const doc = find();
      if (!doc) store(collectionName).push({ id, ...data });
      else if (options && options.merge) Object.assign(doc, data);
      else Object.assign(doc, { id }, data);
    },
    // Mirrors DocumentReference.create(): atomic, and it rejects instead of
    // overwriting. Profile provisioning relies on this to answer 409 rather
    // than replacing an existing document. (This block is inside the
    // FIREBASE_STUB template literal, so no backticks or dollar-braces.)
    async create(data) {
      guardWrite(collectionName);
      if (find()) {
        const error = new Error(
          '6 ALREADY_EXISTS: Document already exists: ' + key,
        );
        error.code = 'already-exists';
        throw error;
      }
      bumpVersion(key);
      store(collectionName).push({ id, ...data });
      return { id };
    },
    async delete() {
      guardWrite(collectionName);
      bumpVersion(key);
      const list = store(collectionName);
      const i = list.findIndex((d) => d.id === id);
      if (i !== -1) list.splice(i, 1);
    },
    collection(sub) { return db.collection(collectionName + '/' + id + '/' + sub); },
  };
  return ref;
}

export function initializeFirebase() {
  return { app: {}, firestore: db, auth: {} };
}
export function getDb() { return db; }
export function getAuth() {
  return {
    verifyIdToken: async (token) => {
      const user = fx().user;
      if (!user || token !== user.token) {
        throw new Error('Decoding Firebase ID token failed.');
      }
      return {
        uid: user.uid,
        email: user.email ?? (user.uid + '@example.com'),
        // A freshly created email/password account has not clicked a
        // verification link yet. Defaults to verified so existing fixtures
        // keep working; a test can set email_verified: false explicitly.
        email_verified: user.email_verified ?? true,
        role: user.role,
        name: user.name ?? 'Test User',
      };
    },
    deleteUser: async () => {},
    // Mirrors admin.auth().updateUser(uid, properties); the route uses it to
    // keep the Firebase sign-in email in step with the profile document.
    updateUser: async (uid, properties = {}) => {
      if (fx().failAuthUpdates) throw new Error(fx().failAuthUpdates);
      fx().authUpdates.push({ uid, ...properties });
      return { uid, ...properties };
    },
  };
}
export const admin = {
  firestore: { FieldValue: { serverTimestamp: () => 'SERVER_TS' } },
};
`;

let tmpDir = null;
let server = null;
let bootPromise = null;

/** Boots (once) an Express app backed by the stubbed Firestore. */
export async function startApp() {
  if (bootPromise) return bootPromise;

  bootPromise = (async () => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'legal-authz-test-'));
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
    fs.copyFileSync(
      path.join(HERE, 'supabase_test_adapter.js'),
      path.join(tmpDir, 'src', 'config', 'supabase_test_adapter.js'),
    );

    // Routes and middleware keep importing the same API surface, but the
    // temporary copy routes those imports through the test-only boundary. The
    // real supabase.js module remains underneath so its serializers, mapping
    // tables and document API are still exercised; only its Auth/public/RPC
    // external I/O is substituted.
    const rewriteAdapterImports = (directory) => {
      for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
        const entryPath = path.join(directory, entry.name);
        if (entry.isDirectory()) {
          rewriteAdapterImports(entryPath);
        } else if (entry.isFile() && entry.name.endsWith('.js')) {
          const source = fs.readFileSync(entryPath, 'utf8');
          const rewritten = source.replace(
            /(['"])\.\.\/config\/supabase\.js\1/g,
            '$1../config/supabase_test_adapter.js$1',
          );
          if (rewritten !== source) fs.writeFileSync(entryPath, rewritten);
        }
      }
    };
    rewriteAdapterImports(path.join(tmpDir, 'src'));

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
    return `http://127.0.0.1:${server.address().port}`;
  })();

  return bootPromise;
}

/**
 * Imports a module from the temporary copy of `src/` that the routes run from.
 *
 * Those modules are wired to the in-memory Firestore double, so a test can
 * drive them directly. Needed for properties that cannot be observed through
 * HTTP: two booking requests for one slot almost never overlap on the wire, so
 * the atomicity of the reservation has to be exercised by starting two
 * transactions in the same tick.
 *
 * @param {string} relativePath  path inside `src/`, e.g. `utils/bookingReservation.js`
 */
export async function stubModule(relativePath) {
  await startApp();
  return import(
    pathToFileURL(path.join(tmpDir, 'src', relativePath)).href
  );
}

/** Tears the temporary server down. */
export function stopApp() {
  server?.close();
  server = null;
  bootPromise = null;
  if (tmpDir) fs.rmSync(tmpDir, { recursive: true, force: true });
  tmpDir = null;
}

/**
 * Resets the in-memory database and the authenticated caller.
 *
 * @param {object} options
 * @param {Record<string, Array<object>>} [options.collections] seed documents
 * @param {{uid: string, role: string, token: string}} [options.user] caller
 */
export function reset({ collections = {}, user = null } = {}) {
  globalThis.__fx = {
    collections: Object.fromEntries(
      Object.entries(collections).map(([name, docs]) => [name, docs.map((d) => ({ ...d }))]),
    ),
    user,
    error: null,
    calls: [],
    failWritesTo: null,
    versions: {},
    txAttempts: 0,
    authUpdates: [],
    failAuthUpdates: null,
    rpcCalls: [],
    rpcHandlers: {},
    lawyerSignupCalls: [],
    lawyerSignupHandler: null,
  };
}

/** Makes writes to one collection throw, to prove transactional rollback. */
export function failWritesTo(collectionName) {
  globalThis.__fx.failWritesTo = collectionName;
}

/**
 * Fixture accounts.
 *
 * `authenticate` resolves the caller's role from the `users` profile document,
 * so a test that wants an admin must ALSO seed the profile (see `users()`).
 */
export const PEOPLE = {
  client1: { uid: 'client-1', name: 'Client One', role: 'client' },
  client2: { uid: 'client-2', name: 'Client Two', role: 'client' },
  lawyer1: { uid: 'lawyer-1', name: 'Lawyer One', role: 'lawyer' },
  lawyer2: { uid: 'lawyer-2', name: 'Lawyer Two', role: 'lawyer' },
  admin1: { uid: 'admin-1', name: 'Admin One', role: 'admin' },
  owner1: { uid: 'owner-1', name: 'Owner One', role: 'owner' },
};

/** Profile documents for the `users` collection, in the shape routes read. */
export function users(...keys) {
  return keys.map((key) => ({
    id: PEOPLE[key].uid,
    uid: PEOPLE[key].uid,
    name: PEOPLE[key].name,
    // Matches the addresses the fixtures send to `PUT /users/:id`, so a
    // profile update that keeps the same email is a genuine no-op.
    email: `${key}@example.com`,
    role: PEOPLE[key].role,
  }));
}

export const tokenFor = (key) => `token-${PEOPLE[key].uid}`;

/** The authenticated caller for subsequent requests (`null` = anonymous). */
export function setUser(user) {
  globalThis.__fx.user = user;
}

/** Authenticates subsequent requests as one of `PEOPLE`. */
export function signIn(key) {
  const person = PEOPLE[key];
  setUser({ uid: person.uid, role: person.role, name: person.name, token: tokenFor(key) });
}

/** Makes every Firestore read reject — used to prove errors are not masked. */
export function setFailure(error) {
  globalThis.__fx.error = error;
}

/** Reads the live in-memory collection (to assert nothing was written). */
export function docs(collectionName) {
  return (globalThis.__fx.collections[collectionName] ?? []).map((d) => ({ ...d }));
}

/** Makes `auth.updateUser` throw, to prove the profile is not written. */
export function failAuthUpdates(message = 'auth update failed') {
  globalThis.__fx.failAuthUpdates = message;
}

/** Firebase Auth mutations requested since the last reset (email sync). */
export function authUpdates() {
  return globalThis.__fx.authUpdates.map((u) => ({ ...u }));
}

/** Registers an isolated handler for one request-scoped RPC in a route test. */
export function setRpcHandler(functionName, handler) {
  if (typeof handler !== 'function') {
    throw new TypeError('An RPC test handler must be a function.');
  }
  globalThis.__fx.rpcHandlers[functionName] = handler;
}

/** Caller-scoped RPC invocations made since the last reset. */
export function rpcCalls() {
  return globalThis.__fx.rpcCalls.map((call) => structuredClone(call));
}

/** Registers an isolated trusted lawyer-signup boundary for route tests. */
export function setLawyerSignupHandler(handler) {
  if (typeof handler !== 'function') {
    throw new TypeError('A lawyer signup test handler must be a function.');
  }
  globalThis.__fx.lawyerSignupHandler = handler;
}

/** Public lawyer-signup payloads observed by the isolated Auth fixture. */
export function lawyerSignupCalls() {
  return (globalThis.__fx.lawyerSignupCalls ?? []).map((call) => structuredClone(call));
}

/** Every query the routes issued since the last reset. */
export function queries() {
  return globalThis.__fx.calls.map((c) => ({ ...c }));
}

/** Performs a request against the test app. */
export async function request(method, urlPath, { token, body, headers: extra } = {}) {
  const base = await startApp();
  const headers = { ...(extra || {}) };
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';

  const res = await fetch(`${base}${urlPath}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });

  const text = await res.text();
  let parsed = null;
  try {
    parsed = text ? JSON.parse(text) : null;
  } catch (_err) {
    parsed = { raw: text };
  }
  return { status: res.status, body: parsed };
}

export const get = (p, o) => request('GET', p, o);
export const post = (p, o) => request('POST', p, o);
export const put = (p, o) => request('PUT', p, o);
export const patch = (p, o) => request('PATCH', p, o);
export const del = (p, o) => request('DELETE', p, o);
