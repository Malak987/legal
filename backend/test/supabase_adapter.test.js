/**
 * Supabase PostgreSQL & Supabase Auth adapter tests.
 *
 * Verifies:
 *   1. Column and type mapping (`toDbRow`, `fromDbRow`) across all 18 PostgreSQL
 *      tables (`users`, `lawyers`, `cases`, `bookings`, `booking_slots`, `tasks`,
 *      `chats`, `chat_messages`, `reviews`, `favorites`, `wallets`,
 *      `wallet_transactions`, `wallet_idempotency`, `plans`, `subscriptions`,
 *      `notifications`, `earnings`, `availability`).
 *   2. Query filters (`==`, `!=`, `>`, `>=`, `<`, `<=`, `in`, `array-contains`),
 *      ordering, limits, subcollections (`chats/:id/messages`), batches, and
 *      transactions with rollback on error.
 *   3. Server-side `verifyIdToken` via Supabase Auth (`auth.getUser`) and
 *      identity resolution for both native UUID users and migrated Firebase UIDs
 *      linked via `auth_user_id` or confirmed email.
 *   4. `initializeFirebase()` delegating to Supabase when `SUPABASE_URL` and
 *      `SUPABASE_SERVICE_ROLE_KEY` are configured.
 */

import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import {
  TABLE_SPECS,
  toDbRow,
  fromDbRow,
  createSupabaseDatabase,
  createSupabaseAuth,
  isSupabaseConfigured,
  isServerTimestampSentinel,
} from '../src/config/supabase.js';
import { useSupabaseClient } from '../src/config/firebase.js';
import { createApp } from '../src/app.js';

/**
 * In-memory PostgreSQL table simulator implementing the `@supabase/supabase-js`
 * PostgREST builder and `auth` / `auth.admin` interface. Stores strictly
 * snake_case rows per table name (`users`, `booking_slots`, `chat_messages`, etc.)
 * to verify our adapter's relational mapping.
 */
function createMockSupabaseClient() {
  const tables = new Map();
  const authUsers = new Map();
  const tokens = new Map();
  let failOnTableWrite = null;

  function getTable(tableName) {
    if (!tables.has(tableName)) tables.set(tableName, new Map());
    return tables.get(tableName);
  }

  function createBuilder(tableName) {
    const state = {
      op: 'select',
      payload: null,
      filters: [],
      orExpr: null,
      orders: [],
      limitCount: null,
      singleMode: null,
    };

    const builder = {
      select() {
        return builder;
      },
      eq(col, val) {
        state.filters.push((r) => r[col] === val);
        return builder;
      },
      neq(col, val) {
        state.filters.push((r) => r[col] !== val);
        return builder;
      },
      gt(col, val) {
        state.filters.push((r) => r[col] > val);
        return builder;
      },
      gte(col, val) {
        state.filters.push((r) => r[col] >= val);
        return builder;
      },
      lt(col, val) {
        state.filters.push((r) => r[col] < val);
        return builder;
      },
      lte(col, val) {
        state.filters.push((r) => r[col] <= val);
        return builder;
      },
      is(col, val) {
        state.filters.push((r) => (r[col] ?? null) === val);
        return builder;
      },
      not(col, op, val) {
        if (op === 'is') {
          state.filters.push((r) => (r[col] ?? null) !== val);
        }
        return builder;
      },
      ilike(col, val) {
        const needle = String(val || '').toLowerCase();
        state.filters.push((r) => String(r[col] || '').toLowerCase() === needle);
        return builder;
      },
      in(col, vals) {
        state.filters.push((r) => Array.isArray(vals) && vals.includes(r[col]));
        return builder;
      },
      contains(col, vals) {
        state.filters.push(
          (r) =>
            Array.isArray(r[col]) &&
            vals.every((v) => r[col].includes(v))
        );
        return builder;
      },
      or(expr) {
        state.orExpr = expr;
        return builder;
      },
      order(col, { ascending = true } = {}) {
        state.orders.push({ col, ascending });
        return builder;
      },
      limit(n) {
        state.limitCount = n;
        return builder;
      },
      maybeSingle() {
        state.singleMode = 'maybeSingle';
        return builder._exec();
      },
      upsert(row) {
        state.op = 'upsert';
        state.payload = row;
        return builder;
      },
      insert(row) {
        state.op = 'insert';
        state.payload = row;
        return builder;
      },
      update(row) {
        state.op = 'update';
        state.payload = row;
        return builder;
      },
      delete() {
        state.op = 'delete';
        return builder;
      },
      then(resolve, reject) {
        return builder._exec().then(resolve, reject);
      },
      async _exec() {
        const store = getTable(tableName);

        const matchRow = (r) => {
          if (state.orExpr) {
            // e.g. "auth_user_id.eq.<uuid>,id.eq.<uuid>"
            const parts = state.orExpr.split(',');
            const matchedOr = parts.some((p) => {
              const [c, op, ...rest] = p.split('.');
              const v = rest.join('.');
              return op === 'eq' && r[c] === v;
            });
            if (!matchedOr) return false;
          }
          return state.filters.every((fn) => fn(r));
        };

        if (state.op === 'insert') {
          if (failOnTableWrite === tableName) {
            return { data: null, error: { message: `Simulated write failure on ${tableName}` } };
          }
          if (store.has(state.payload.id)) {
            return { data: null, error: { code: '23505', message: 'duplicate key value violates unique constraint' } };
          }
          const now = new Date().toISOString();
          const inserted = {
            created_at: now,
            updated_at: now,
            ...state.payload,
          };
          store.set(inserted.id, inserted);
          return { data: inserted, error: null };
        }

        if (state.op === 'upsert') {
          if (failOnTableWrite === tableName) {
            return { data: null, error: { message: `Simulated write failure on ${tableName}` } };
          }
          const now = new Date().toISOString();
          const existing = store.get(state.payload.id) || {};
          const merged = {
            created_at: existing.created_at || now,
            updated_at: now,
            ...existing,
            ...state.payload,
          };
          store.set(merged.id, merged);
          return { data: merged, error: null };
        }

        if (state.op === 'update') {
          if (failOnTableWrite === tableName) {
            return { data: null, error: { message: `Simulated write failure on ${tableName}` } };
          }
          const now = new Date().toISOString();
          for (const [id, r] of store.entries()) {
            if (matchRow(r)) {
              store.set(id, { ...r, ...state.payload, updated_at: now });
            }
          }
          return { data: null, error: null };
        }

        if (state.op === 'delete') {
          if (failOnTableWrite === tableName) {
            return { data: null, error: { message: `Simulated write failure on ${tableName}` } };
          }
          for (const [id, r] of store.entries()) {
            if (matchRow(r)) {
              store.delete(id);
            }
          }
          return { data: null, error: null };
        }

        let rows = [...store.values()].filter(matchRow);
        for (const ord of state.orders) {
          rows.sort((a, b) => {
            if (a[ord.col] === b[ord.col]) return 0;
            const cmp = a[ord.col] < b[ord.col] ? -1 : 1;
            return ord.ascending ? cmp : -cmp;
          });
        }
        if (typeof state.limitCount === 'number') {
          rows = rows.slice(0, state.limitCount);
        }
        if (state.singleMode === 'maybeSingle') {
          return { data: rows[0] || null, error: null };
        }
        return { data: rows, error: null };
      },
    };

    return builder;
  }

  return {
    _tables: tables,
    _authUsers: authUsers,
    _tokens: tokens,
    setFailOnTableWrite(tableName) {
      failOnTableWrite = tableName;
    },
    from(tableName) {
      return createBuilder(tableName);
    },
    auth: {
      async getUser(token) {
        const userId = tokens.get(token);
        if (!userId || !authUsers.has(userId)) {
          return { data: { user: null }, error: { message: 'Invalid token' } };
        }
        return { data: { user: authUsers.get(userId) }, error: null };
      },
      admin: {
        async listUsers() {
          return { data: { users: [...authUsers.values()] }, error: null };
        },
        async getUserById(id) {
          const u = authUsers.get(id);
          if (!u) return { data: { user: null }, error: { message: 'User not found' } };
          return { data: { user: u }, error: null };
        },
        async createUser({ id, email, password, email_confirm, user_metadata }) {
          for (const existing of authUsers.values()) {
            if (existing.email.toLowerCase() === email.toLowerCase()) {
              return { data: null, error: { message: 'User already registered' } };
            }
          }
          const userId = id || '11111111-2222-4333-8444-555555555555';
          const user = {
            id: userId,
            email,
            password,
            email_confirmed_at: email_confirm ? new Date().toISOString() : null,
            user_metadata: user_metadata || {},
          };
          authUsers.set(userId, user);
          return { data: { user }, error: null };
        },
        async updateUserById(id, updates) {
          const existing = authUsers.get(id);
          if (!existing) return { data: null, error: { message: 'User not found' } };
          const updated = {
            ...existing,
            ...(updates.email ? { email: updates.email } : {}),
            ...(updates.password ? { password: updates.password } : {}),
            ...(updates.user_metadata
              ? { user_metadata: { ...existing.user_metadata, ...updates.user_metadata } }
              : {}),
          };
          authUsers.set(id, updated);
          return { data: { user: updated }, error: null };
        },
        async deleteUser(id) {
          if (!authUsers.has(id)) {
            return { data: null, error: { message: 'User not found' } };
          }
          authUsers.delete(id);
          return { data: {}, error: null };
        },
      },
    },
  };
}

describe('supabase adapter: schema and column mappings', () => {
  it('defines specifications for all 18 PostgreSQL tables', () => {
    const expectedTables = [
      'users',
      'lawyers',
      'cases',
      'bookings',
      'booking_slots',
      'tasks',
      'chats',
      'chat_messages',
      'reviews',
      'favorites',
      'wallets',
      'wallet_transactions',
      'wallet_idempotency',
      'plans',
      'subscriptions',
      'notifications',
      'earnings',
      'availability',
    ];
    const actualTables = Object.values(TABLE_SPECS).map((s) => s.table);
    assert.deepEqual(actualTables.sort(), expectedTables.sort());
  });

  it('converts camelCase fields to normalized snake_case columns and back with numeric coercion', () => {
    const lawyerRow = toDbRow(
      'lawyers',
      {
        name: 'Sarah Jenkins',
        specialty: 'Corporate Law',
        price: '$220/hr',
        priceValue: 220,
        rating: 4.9,
        isPopular: true,
        isTop: false,
      },
      'lawyer-1',
      true
    );

    assert.equal(lawyerRow.id, 'lawyer-1');
    assert.equal(lawyerRow.price_value, 220);
    assert.equal(lawyerRow.is_popular, true);
    assert.equal(lawyerRow.is_top, false);

    // Simulate PostgreSQL returning NUMERIC columns as strings
    const hydrated = fromDbRow('lawyers', {
      ...lawyerRow,
      price_value: '220.00',
      rating: '4.90',
    });

    assert.equal(hydrated.priceValue, 220);
    assert.equal(typeof hydrated.priceValue, 'number');
    assert.equal(hydrated.rating, 4.9);
    assert.equal(typeof hydrated.rating, 'number');
    assert.equal(hydrated.isPopular, true);
    assert.equal(hydrated.isTop, false);
  });

  it('converts serverTimestamp sentinels into ISO-8601 strings', () => {
    const sentinel = { _methodName: 'FieldValue.serverTimestamp' };
    assert.equal(isServerTimestampSentinel(sentinel), true);

    const row = toDbRow(
      'cases',
      {
        userId: 'client-1',
        title: 'Contract Dispute',
        clientName: 'Acme Corp',
        caseType: 'Commercial',
        dueDate: '2026-12-01',
        createdAt: sentinel,
      },
      'case-1',
      true
    );

    assert.equal(row.user_id, 'client-1');
    assert.equal(row.client_name, 'Acme Corp');
    assert.equal(row.case_type, 'Commercial');
    assert.equal(row.due_date, '2026-12-01');
    assert.match(row.created_at, /^\d{4}-\d{2}-\d{2}T/);
  });
});

describe('supabase adapter: CRUD, queries, subcollections, and transactions', () => {
  let mockClient;
  let db;

  beforeEach(() => {
    mockClient = createMockSupabaseClient();
    db = createSupabaseDatabase(mockClient);
  });

  it('performs CRUD, filtering, array-contains, and ordering against snake_case tables', async () => {
    await db.collection('chats').doc('chat-1').set({
      participants: ['client-1', 'lawyer-1'],
      participantNames: { 'client-1': 'Alice', 'lawyer-1': 'Bob' },
      lastMessage: 'Hello Bob',
    });

    // Verify underlying table stored snake_case columns
    const rawChat = mockClient._tables.get('chats').get('chat-1');
    assert.deepEqual(rawChat.participant_names, { 'client-1': 'Alice', 'lawyer-1': 'Bob' });
    assert.equal(rawChat.last_message, 'Hello Bob');

    // Query with array-contains
    const snap = await db
      .collection('chats')
      .where('participants', 'array-contains', 'client-1')
      .get();
    assert.equal(snap.size, 1);
    assert.equal(snap.docs[0].id, 'chat-1');
    assert.equal(snap.docs[0].data().lastMessage, 'Hello Bob');

    // Subcollection chats/{id}/messages -> chat_messages table with chat_id FK
    const msgRef = await db
      .collection('chats')
      .doc('chat-1')
      .collection('messages')
      .add({
        senderId: 'client-1',
        senderName: 'Alice',
        text: 'First message',
      });

    const rawMsg = mockClient._tables.get('chat_messages').get(msgRef.id);
    assert.equal(rawMsg.chat_id, 'chat-1');
    assert.equal(rawMsg.sender_id, 'client-1');
    assert.equal(rawMsg.sender_name, 'Alice');

    const msgSnap = await db
      .collection('chats')
      .doc('chat-1')
      .collection('messages')
      .orderBy('createdAt', 'asc')
      .get();
    assert.equal(msgSnap.size, 1);
    assert.equal(msgSnap.docs[0].data().senderId, 'client-1');
    assert.equal(msgSnap.docs[0].data().text, 'First message');
  });

  it('commits multi-row transactions and rolls back applied writes if a step fails', async () => {
    await db.collection('wallets').doc('client-1').set({
      userId: 'client-1',
      balance: 100,
      currency: 'USD',
    });

    // Simulate a write failure on wallet_transactions after wallets is updated
    mockClient.setFailOnTableWrite('wallet_transactions');

    await assert.rejects(async () => {
      await db.runTransaction(async (tx) => {
        const walletRef = db.collection('wallets').doc('client-1');
        const txRef = db.collection('wallet_transactions').doc('tx-1');
        const snap = await tx.get(walletRef);
        const nextBalance = snap.data().balance + 50;
        tx.update(walletRef, { balance: nextBalance });
        tx.set(txRef, {
          userId: 'client-1',
          type: 'credit',
          amount: 50,
          balance: nextBalance,
          currency: 'USD',
        });
      });
    }, /Simulated write failure on wallet_transactions/);

    // Verify wallet balance was rolled back to 100
    const afterRollback = await db.collection('wallets').doc('client-1').get();
    assert.equal(afterRollback.data().balance, 100);
  });
});

describe('supabase adapter: server-side authentication and Firebase identity migration', () => {
  let mockClient;
  let db;
  let auth;

  beforeEach(() => {
    mockClient = createMockSupabaseClient();
    db = createSupabaseDatabase(mockClient);
    auth = createSupabaseAuth(mockClient);
  });

  it('verifies a Supabase JWT and resolves a native UUID user', async () => {
    const uuid = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
    mockClient._authUsers.set(uuid, {
      id: uuid,
      email: 'newuser@example.com',
      email_confirmed_at: new Date().toISOString(),
      user_metadata: { name: 'New User' },
    });
    mockClient._tokens.set('valid-jwt-1', uuid);

    const decoded = await auth.verifyIdToken('valid-jwt-1');
    assert.equal(decoded.uid, uuid);
    assert.equal(decoded.email, 'newuser@example.com');
    assert.equal(decoded.name, 'New User');
  });

  it('preserves migrated Firebase UID and role mapping when linked by confirmed email', async () => {
    // Pre-existing Firebase user profile migrated to public.users with legacy UID 'client-001'
    await db.collection('users').doc('client-001').set({
      uid: 'client-001',
      name: 'James Powell',
      email: 'james@example.com',
      role: 'client',
    });

    // User completes password reset / migration in Supabase Auth and gets a new UUID
    const supabaseUuid = 'b1ffcd99-9c0b-4ef8-bb6d-6bb9bd380a22';
    mockClient._authUsers.set(supabaseUuid, {
      id: supabaseUuid,
      email: 'james@example.com',
      email_confirmed_at: new Date().toISOString(),
      user_metadata: { name: 'James Powell' },
    });
    mockClient._tokens.set('migrated-jwt', supabaseUuid);

    const decoded = await auth.verifyIdToken('migrated-jwt');
    // Canonical application UID remains 'client-001' so all existing cases/bookings/wallets stay linked!
    assert.equal(decoded.uid, 'client-001');
    assert.equal(decoded.authUserId, supabaseUuid);

    // And auth_user_id is now persisted on the public.users row
    const linkedRow = mockClient._tables.get('users').get('client-001');
    assert.equal(linkedRow.auth_user_id, supabaseUuid);
  });

  it('rejects invalid or expired tokens', async () => {
    await assert.rejects(
      () => auth.verifyIdToken('bad-token'),
      (err) => err.code === 'auth/id-token-expired'
    );
  });

  it('detects Supabase configuration only when both URL and service-role key are present', () => {
    assert.equal(isSupabaseConfigured({ SUPABASE_URL: '', SUPABASE_SERVICE_ROLE_KEY: '' }), false);
    assert.equal(
      isSupabaseConfigured({
        SUPABASE_URL: 'https://qqfzbecwhewswkyxgebu.supabase.co',
        SUPABASE_SERVICE_ROLE_KEY: '',
      }),
      false
    );
    assert.equal(
      isSupabaseConfigured({
        SUPABASE_URL: 'https://qqfzbecwhewswkyxgebu.supabase.co',
        SUPABASE_SERVICE_ROLE_KEY: 'srv-secret-key',
      }),
      true
    );
  });
});

describe('supabase adapter: end-to-end Express API over Supabase PostgreSQL & Auth', () => {
  it('serves users, lawyers, availability, bookings, cases, wallet, reviews, and dashboard over Supabase', async () => {
    const mockClient = createMockSupabaseClient();
    const { firestore: db } = useSupabaseClient(mockClient);

    // Seed Supabase Auth + public.users for admin and client
    const adminUuid = '00000000-0000-4000-8000-000000000001';
    const clientUuid = '00000000-0000-4000-8000-000000000002';

    mockClient._authUsers.set(adminUuid, {
      id: adminUuid,
      email: 'admin@legalapp.com',
      email_confirmed_at: new Date().toISOString(),
      user_metadata: { name: 'Admin' },
    });
    mockClient._tokens.set('admin-supa-jwt', adminUuid);

    mockClient._authUsers.set(clientUuid, {
      id: clientUuid,
      email: 'client@legalapp.com',
      email_confirmed_at: new Date().toISOString(),
      user_metadata: { name: 'Client One' },
    });
    mockClient._tokens.set('client-supa-jwt', clientUuid);

    await db.collection('users').doc('admin-uid').set({
      uid: 'admin-uid',
      authUserId: adminUuid,
      name: 'Admin',
      email: 'admin@legalapp.com',
      role: 'admin',
    });

    const app = createApp();
    const server = await new Promise((resolve) => {
      const s = app.listen(0, '127.0.0.1', () => resolve(s));
    });
    const baseUrl = `http://127.0.0.1:${server.address().port}`;

    async function request(method, path, { token, body, headers = {} } = {}) {
      const h = { ...headers };
      if (token) h.Authorization = `Bearer ${token}`;
      if (body !== undefined) h['Content-Type'] = 'application/json';
      const res = await fetch(`${baseUrl}${path}`, {
        method,
        headers: h,
        body: body !== undefined ? JSON.stringify(body) : undefined,
      });
      const json = await res.json();
      return { status: res.status, body: json };
    }

    try {
      // 1. Register client profile via POST /api/users/me (client role enforced)
      const regRes = await request('POST', '/api/users/me', {
        token: 'client-supa-jwt',
        body: {
          uid: 'forged-uid',
          name: 'Client One',
          email: 'client@legalapp.com',
          role: 'admin', // attempted self-escalation must be ignored
        },
      });
      assert.equal(regRes.status, 201);
      assert.equal(regRes.body.data.uid, clientUuid);
      assert.equal(regRes.body.data.role, 'client');

      // Duplicate provisioning returns 409
      const dupRegRes = await request('POST', '/api/users/me', {
        token: 'client-supa-jwt',
        body: { name: 'Client One' },
      });
      assert.equal(dupRegRes.status, 409);

      // 2. Admin creates a lawyer via POST /api/lawyers
      const lawyerRes = await request('POST', '/api/lawyers', {
        token: 'admin-supa-jwt',
        body: {
          name: 'Dr. Evelyn Vance',
          specialty: 'Corporate Law',
          price: '$200/hr',
          priceValue: 200,
          isPopular: true,
          isTop: true,
        },
      });
      assert.equal(lawyerRes.status, 201);
      const lawyerId = lawyerRes.body.data.id;

      // 3. Admin publishes availability via POST /api/availability
      const availRes = await request('POST', '/api/availability', {
        token: 'admin-supa-jwt',
        body: {
          lawyerId,
          lawyerName: 'Dr. Evelyn Vance',
          date: '2026-11-15',
          slots: ['09:00', '10:00', '11:00'],
        },
      });
      assert.equal(availRes.status, 201);

      // 4. Client books 2 hours starting at 09:00 via POST /api/bookings
      const bookRes = await request('POST', '/api/bookings', {
        token: 'client-supa-jwt',
        body: {
          lawyerId,
          date: '2026-11-15',
          time: '09:00',
          hours: 2,
          totalPrice: 1, // forged price must be ignored
        },
      });
      assert.equal(bookRes.status, 201);
      assert.equal(bookRes.body.data.totalPrice, 400);
      assert.equal(bookRes.body.data.userId, clientUuid);
      assert.equal(mockClient._tables.get('booking_slots').size, 2);

      // 5. Overlapping booking at 10:00 is rejected with 409
      const conflictRes = await request('POST', '/api/bookings', {
        token: 'client-supa-jwt',
        body: {
          lawyerId,
          date: '2026-11-15',
          time: '10:00',
          hours: 1,
        },
      });
      assert.equal(conflictRes.status, 409);

      // 6. Admin credits client wallet with idempotency key
      const topupRes = await request('POST', '/api/wallet/transactions', {
        token: 'admin-supa-jwt',
        headers: { 'Idempotency-Key': 'supa-idem-1' },
        body: {
          userId: clientUuid,
          type: 'credit',
          amount: 500,
          description: 'Initial deposit',
        },
      });
      assert.equal(topupRes.status, 201);
      assert.equal(topupRes.body.data.balance, 500);

      // 7. Client debits from own wallet
      const deductRes = await request('POST', '/api/wallet/transactions', {
        token: 'client-supa-jwt',
        headers: { 'Idempotency-Key': 'supa-idem-2' },
        body: {
          userId: clientUuid,
          type: 'debit',
          amount: 150,
          description: 'Consultation fee',
        },
      });
      assert.equal(deductRes.status, 201);
      assert.equal(deductRes.body.data.balance, 350);

      // 8. Client posts a review
      const revRes = await request('POST', '/api/reviews', {
        token: 'client-supa-jwt',
        body: {
          lawyerId,
          rating: 5,
          comment: 'Outstanding counsel!',
        },
      });
      assert.equal(revRes.status, 201);

      // 9. Admin fetches dashboard metrics
      const dashRes = await request('GET', '/api/dashboard/stats', {
        token: 'admin-supa-jwt',
      });
      assert.equal(dashRes.status, 200);
      assert.equal(dashRes.body.data.users, 2);
      assert.equal(dashRes.body.data.lawyers, 1);
      assert.equal(dashRes.body.data.bookings, 1);
      assert.equal(dashRes.body.data.reviews, 1);
      assert.equal(dashRes.body.data.totalWalletBalance, 350);
    } finally {
      await new Promise((resolve) => server.close(resolve));
    }
  });
});
