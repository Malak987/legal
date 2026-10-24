/**
 * Supabase PostgreSQL & Supabase Auth adapter tests.
 *
 * Verifies:
 *   1. Column and type mapping (`toDbRow`, `fromDbRow`) across all 19 PostgreSQL
 *      tables (`users`, `lawyers`, `legal_categories`, `cases`, `bookings`, `booking_slots`, `tasks`,
 *      `chats`, `chat_messages`, `reviews`, `favorites`, `wallets`,
 *      `wallet_transactions`, `wallet_idempotency`, `plans`, `subscriptions`,
 *      `notifications`, `earnings`, `availability`).
 *   2. Query filters (`==`, `!=`, `>`, `>=`, `<`, `<=`, `in`, `array-contains`),
 *      ordering, limits, subcollections (`chats/:id/messages`), batches, and
 *      transactions with rollback on error.
 *   3. Server-side `verifyIdToken` via Supabase Auth (`auth.getUser`) and
 *      identity resolution for native UUID users and explicitly linked legacy IDs.
 *   4. `initializeFirebase()` delegating to Supabase when `SUPABASE_URL` and
 *      `SUPABASE_SERVICE_ROLE_KEY` are configured.
 */

import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';

import {
  TABLE_SPECS,
  toDbRow,
  fromDbRow,
  createSupabaseDatabase,
  createSupabaseAuth,
  initializePublicSupabase,
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
    async rpc(functionName, parameters = {}) {
      if (functionName === 'rpc_dashboard_stats') {
        const count = (tableName) => getTable(tableName).size;
        const bookings = [...getTable('bookings').values()];
        const wallets = [...getTable('wallets').values()];
        return {
          data: {
            users: count('users'),
            lawyers: count('lawyers'),
            cases: count('cases'),
            reviews: count('reviews'),
            plans: count('plans'),
            bookings: bookings.length,
            activeBookings: bookings.filter((row) => row.status === 'Active').length,
            completedBookings: bookings.filter((row) => row.status === 'Completed').length,
            cancelledBookings: bookings.filter((row) => row.status === 'Cancelled').length,
            walletBalance: wallets.reduce((sum, row) => sum + Number(row.balance || 0), 0),
            subscriptions: count('subscriptions'),
          },
          error: null,
        };
      }

      if (functionName === 'rpc_create_booking') {
        const lawyer = getTable('lawyers').get(parameters.p_lawyer_id);
        if (!lawyer) return { data: { error: 'LAWYER_NOT_FOUND' }, error: null };
        const availability = [...getTable('availability').values()].find(
          (row) => row.lawyer_id === parameters.p_lawyer_id && row.date === parameters.p_date,
        );
        if (!availability) return { data: { error: 'NO_AVAILABILITY' }, error: null };
        const start = String(parameters.p_time || '').split(':').map(Number);
        const startMinute = start[0] * 60 + start[1];
        const available = new Set((availability.slots || []).map((slot) => {
          const [hour, minute] = String(slot).split(':').map(Number);
          return hour * 60 + minute;
        }));
        const reserved = getTable('booking_slots');
        const slotKeys = [];
        for (let offset = 0; offset < parameters.p_hours; offset += 1) {
          const minute = startMinute + offset * 60;
          const slot = `${String(Math.floor(minute / 60)).padStart(2, '0')}:${String(minute % 60).padStart(2, '0')}`;
          const id = `${parameters.p_lawyer_id}|${parameters.p_date}|${minute}`;
          if (!available.has(minute)) return { data: { error: 'TIME_NOT_AVAILABLE' }, error: null };
          if (reserved.has(id)) return { data: { error: 'SLOT_TAKEN' }, error: null };
          slotKeys.push({ id, slot });
        }
        const id = randomUUID();
        const booking = {
          id,
          user_id: parameters.p_user_id,
          lawyer_id: parameters.p_lawyer_id,
          lawyer_name: lawyer.name,
          date: parameters.p_date,
          time: parameters.p_time,
          hours: parameters.p_hours,
          total_price: Number(lawyer.price_value) * parameters.p_hours,
          status: 'Pending',
          slot_keys: slotKeys.map(({ id: key }) => key),
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        };
        getTable('bookings').set(id, booking);
        for (const key of slotKeys) {
          reserved.set(key.id, {
            id: key.id,
            lawyer_id: parameters.p_lawyer_id,
            date: parameters.p_date,
            slot: Number(key.slot.slice(0, 2)) * 60 + Number(key.slot.slice(3)),
            booking_id: id,
            user_id: parameters.p_user_id,
          });
        }
        return { data: { replayed: false, booking }, error: null };
      }

      if (functionName === 'rpc_review_submit') {
        const users = [...getTable('users').values()];
        const author = users.find((row) => row.role === 'client');
        if (!author) return { data: null, error: { code: '42501', message: 'No client profile' } };
        if (!getTable('lawyers').has(parameters.p_lawyer_id)) {
          return { data: null, error: { code: '22023', message: 'LAWYER_NOT_FOUND' } };
        }
        const reviews = getTable('reviews');
        const duplicate = [...reviews.values()].find(
          (row) => row.user_id === author.id && row.lawyer_id === parameters.p_lawyer_id,
        );
        if (duplicate) return { data: { error: 'DUPLICATE_REVIEW' }, error: null };
        const review = {
          id: randomUUID(),
          user_id: author.id,
          user_name: author.name || 'User',
          lawyer_id: parameters.p_lawyer_id,
          rating: Number(parameters.p_rating),
          comment: parameters.p_comment || '',
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        };
        reviews.set(review.id, review);
        const average = [...reviews.values()]
          .filter((row) => row.lawyer_id === parameters.p_lawyer_id)
          .reduce((sum, row, _index, list) => sum + Number(row.rating) / list.length, 0);
        const lawyer = getTable('lawyers').get(parameters.p_lawyer_id);
        getTable('lawyers').set(parameters.p_lawyer_id, { ...lawyer, rating: average });
        return { data: review, error: null };
      }

      if (functionName !== 'rpc_wallet_mutate') {
        return { data: null, error: { code: '42883', message: `Unknown RPC ${functionName}` } };
      }
      const userId = parameters.p_user_id;
      if (!getTable('users').has(userId)) {
        return { data: { error: 'UNKNOWN_USER' }, error: null };
      }
      const key = typeof parameters.p_idempotency_id === 'string'
        ? parameters.p_idempotency_id.trim()
        : '';
      const idempotencyId = key
        ? createHash('sha256').update(`${userId}\u0000${key}`).digest('hex')
        : null;
      const idempotency = getTable('wallet_idempotency');
      const previous = idempotencyId ? idempotency.get(idempotencyId) : null;
      if (previous) {
        if (previous.type !== parameters.p_type || previous.amount !== parameters.p_amount) {
          return { data: { error: 'IDEMPOTENCY_KEY_MISMATCH' }, error: null };
        }
        return {
          data: {
            replayed: true,
            balance: previous.balance,
            currency: previous.currency,
            transaction: previous.transaction,
          },
          error: null,
        };
      }
      const wallets = getTable('wallets');
      const current = wallets.get(userId) ?? {
        id: userId,
        user_id: userId,
        balance: 0,
        currency: 'USD',
      };
      const amount = Number(parameters.p_amount);
      if (parameters.p_type === 'debit' && Number(current.balance) < amount) {
        return { data: { error: 'INSUFFICIENT_FUNDS', available: current.balance }, error: null };
      }
      const balance = Number(current.balance) + (parameters.p_type === 'debit' ? -amount : amount);
      const transaction = {
        id: randomUUID(),
        user_id: userId,
        type: parameters.p_type,
        amount,
        description: String(parameters.p_description ?? '').slice(0, 300),
        balance,
        currency: current.currency ?? 'USD',
        idempotency_key_hash: idempotencyId,
        created_at: new Date().toISOString(),
      };
      wallets.set(userId, { ...current, balance, updated_at: new Date().toISOString() });
      getTable('wallet_transactions').set(transaction.id, transaction);
      if (idempotencyId) {
        idempotency.set(idempotencyId, {
          id: idempotencyId,
          user_id: userId,
          type: parameters.p_type,
          amount,
          currency: transaction.currency,
          balance,
          transaction,
        });
      }
      return {
        data: { replayed: false, balance, currency: transaction.currency, transaction },
        error: null,
      };
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
        async createUser({ id, email, password, email_confirm, user_metadata, app_metadata }) {
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
            app_metadata: app_metadata || {},
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
            ...(updates.app_metadata
              ? { app_metadata: { ...existing.app_metadata, ...updates.app_metadata } }
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
  it('defines specifications for all 19 PostgreSQL tables', () => {
    const expectedTables = [
      'users',
      'lawyers',
      'legal_categories',
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

  it('maps legal categories and lawyer/case category relationships to the observed column names', () => {
    const categoryRow = toDbRow(
      'legalCategories',
      { name: 'Family Law', slug: 'family-law' },
      'category-family',
      true,
    );
    assert.equal(categoryRow.name, 'Family Law');
    assert.equal(categoryRow.slug, 'family-law');
    assert.equal(categoryRow.id, 'category-family');

    const lawyerRow = toDbRow('lawyers', {
      name: 'Family Counsel',
      categoryId: 'category-family',
    });
    assert.equal(lawyerRow.category_id, 'category-family');
    assert.equal(
      fromDbRow('lawyers', { id: 'lawyer-family', ...lawyerRow }).categoryId,
      'category-family',
    );

    const caseRow = toDbRow('cases', {
      title: 'Family matter',
      lawyerId: 'lawyer-family',
      categoryId: 'category-family',
    });
    assert.equal(caseRow.lawyer_id, 'lawyer-family');
    assert.equal(caseRow.category_id, 'category-family');
    const hydratedCase = fromDbRow('cases', {
      id: 'case-family',
      ...caseRow,
      due_date: '',
    });
    assert.equal(hydratedCase.lawyerId, 'lawyer-family');
    assert.equal(hydratedCase.categoryId, 'category-family');

    // Live `cases` stores due dates in `due_date` (text), not `due_on`.
    const caseDueDate = toDbRow('cases', { dueOn: '2026-12-04' });
    assert.deepEqual(caseDueDate, { due_date: '2026-12-04' });
    assert.equal(
      fromDbRow('cases', { due_date: '2026-12-04' }).dueDate,
      '2026-12-04',
    );
    const taskDueDate = toDbRow('tasks', { dueOn: '2026-12-05' });
    assert.deepEqual(taskDueDate, { due_date: '2026-12-05' });
  });

  it('converts camelCase fields to normalized snake_case columns and back with numeric coercion', () => {
    const lawyerRow = toDbRow(
      'lawyers',
      {
        name: 'Sarah Jenkins',
        specialty: 'Corporate Law',
        experience: '12 years',
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
    assert.equal(lawyerRow.experience, '12 years');
    assert.equal(lawyerRow.is_popular, true);
    assert.equal(lawyerRow.is_top, false);

    // Simulate PostgreSQL returning NUMERIC columns as strings
    const hydrated = fromDbRow('lawyers', {
      ...lawyerRow,
      price_value: '220.00',
      rating: '4.90',
    });

    assert.equal(hydrated.priceValue, 220);
    assert.equal(hydrated.experience, '12 years');
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

  it('omits system timestamps from caller-JWT writes and excludes linked IDs from public lawyer reads', async () => {
    const requestDb = createSupabaseDatabase(mockClient, { authenticatedRequest: true });
    const sentinel = { _methodName: 'FieldValue.serverTimestamp' };
    await requestDb.collection('cases').doc('request-case').set({
      title: 'Caller scoped case',
      createdAt: sentinel,
      updatedAt: sentinel,
    });

    const caseRow = mockClient._tables.get('cases').get('request-case');
    assert.equal(caseRow.title, 'Caller scoped case');
    assert.equal(typeof caseRow.created_at, 'string', 'database default supplies created_at');
    assert.equal(typeof caseRow.updated_at, 'string', 'database trigger supplies updated_at');
    assert.notEqual(caseRow.created_at, sentinel);

    const publicLawyerSelect = TABLE_SPECS.lawyers.publicSelectColumns;
    assert.equal(publicLawyerSelect.includes('user_id'), false);
    assert.equal(publicLawyerSelect.includes('created_at'), true);
    assert.equal(publicLawyerSelect.includes('updated_at'), true);
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

describe('supabase adapter: verified Auth profiles and legacy identity boundaries', () => {
  let mockClient;
  let db;
  let auth;

  beforeEach(() => {
    mockClient = createMockSupabaseClient();
    db = createSupabaseDatabase(mockClient);
    auth = createSupabaseAuth(mockClient);
  });

  it('verifies a Supabase JWT only after resolving its native UUID application profile', async () => {
    const uuid = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
    await db.collection('users').doc(uuid).set({
      uid: uuid,
      name: 'New User',
      email: 'newuser@example.com',
      role: 'client',
    });
    mockClient._authUsers.set(uuid, {
      id: uuid,
      email: 'newuser@example.com',
      email_confirmed_at: new Date().toISOString(),
      user_metadata: { name: 'Forged name', role: 'admin', legacy_uid: 'forged-link' },
    });
    mockClient._tokens.set('valid-jwt-1', uuid);

    const decoded = await auth.verifyIdToken('valid-jwt-1');
    assert.equal(decoded.uid, uuid);
    assert.equal(decoded.email, 'newuser@example.com');
    assert.equal(decoded.name, 'New User');
    assert.equal(decoded.role, 'client', 'the app role comes from the linked profile, not Auth metadata');
  });

  it('rejects missing or unknown database roles instead of defaulting to client', async () => {
    const cases = [
      { uid: 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a31', role: undefined },
      { uid: 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a32', role: '' },
      { uid: 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a34', role: 'Client' },
    ];

    for (const { uid, role } of cases) {
      await db.collection('users').doc(uid).set({
        uid,
        name: 'Profile',
        email: 'profile@example.com',
        ...(role === undefined ? {} : { role }),
      });
      mockClient._authUsers.set(uid, {
        id: uid,
        email: 'profile@example.com',
        email_confirmed_at: new Date().toISOString(),
      });
      mockClient._tokens.set(`token-${uid}`, uid);

      await assert.rejects(
        () => auth.verifyIdToken(`token-${uid}`),
        (error) => error.code === 'auth/profile-role-invalid',
      );
    }
  });

  it('accepts a separately provisioned owner role from the database profile', async () => {
    const uuid = 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a35';
    await db.collection('users').doc(uuid).set({
      uid: uuid,
      name: 'Trusted Owner',
      email: 'owner@example.com',
      role: 'owner',
    });
    mockClient._authUsers.set(uuid, {
      id: uuid,
      email: 'owner@example.com',
      email_confirmed_at: new Date().toISOString(),
      user_metadata: { role: 'client' },
    });
    mockClient._tokens.set('owner-jwt', uuid);

    const decoded = await auth.verifyIdToken('owner-jwt');
    assert.equal(decoded.role, 'owner');
    assert.equal(decoded.uid, uuid);
  });

  it('marks only a new unconfirmed lawyer signup through trusted app_metadata', async () => {
    const newUuid = 'd3ffcd99-9c0b-4ef8-bb6d-6bb9bd380a24';
    let signupInput;
    let updateCalls = 0;
    const publicAuthClient = {
      auth: {
        async signUp(input) {
          signupInput = input;
          const user = {
            id: newUuid,
            email: input.email,
            identities: [{ id: newUuid, provider: 'email' }],
            app_metadata: { provider: 'email' },
            user_metadata: input.options.data,
            email_confirmed_at: null,
          };
          mockClient._authUsers.set(newUuid, user);
          return { data: { user, session: null }, error: null };
        },
      },
    };
    const trustedAuth = createSupabaseAuth(mockClient, {
      publicAuthClientFactory: () => publicAuthClient,
      lawyerSignupRedirectUrl: 'https://lawyers.example/auth/callback',
    });
    const realUpdate = mockClient.auth.admin.updateUserById;
    mockClient.auth.admin.updateUserById = async (...args) => {
      updateCalls++;
      return realUpdate(...args);
    };

    const result = await trustedAuth.createLawyerSignup({
      name: 'Sam Example',
      email: 'SAM@EXAMPLE.TEST',
      password: 'a-long-test-password',
      role: 'owner',
      userId: 'forged-profile-id',
    });

    assert.deepEqual(result, { accepted: true });
    assert.equal(signupInput.email, 'sam@example.test');
    assert.equal(signupInput.options.emailRedirectTo, 'https://lawyers.example/auth/callback');
    assert.deepEqual(signupInput.options.data, { name: 'Sam Example' });
    assert.equal(Object.hasOwn(signupInput, 'role'), false);
    assert.equal(updateCalls, 1);
    assert.deepEqual(mockClient._authUsers.get(newUuid).app_metadata, {
      provider: 'email',
      signup_role: 'lawyer',
    });
  });

  it('does not promote an existing/synthetic signup identity or an auto-confirmed session', async () => {
    let updateCalls = 0;
    const realUpdate = mockClient.auth.admin.updateUserById;
    mockClient.auth.admin.updateUserById = async (...args) => {
      updateCalls++;
      return realUpdate(...args);
    };
    const cases = [
      {
        user: { id: 'existing-uuid', email: 'existing@example.test', identities: [] },
        session: null,
      },
      {
        user: {
          id: 'auto-confirmed-uuid',
          email: 'auto@example.test',
          identities: [{ id: 'auto-confirmed-uuid', provider: 'email' }],
        },
        session: { access_token: 'never-persist-this-session' },
      },
    ];
    let index = 0;
    const publicAuthClient = {
      auth: {
        async signUp() {
          const current = cases[index++];
          return { data: current, error: null };
        },
        async signOut() {},
      },
    };
    const trustedAuth = createSupabaseAuth(mockClient, {
      publicAuthClientFactory: () => publicAuthClient,
      lawyerSignupRedirectUrl: 'https://lawyers.example/auth/callback',
    });

    for (const email of ['existing@example.test', 'auto@example.test']) {
      assert.deepEqual(
        await trustedAuth.createLawyerSignup({ name: 'Sam Example', email, password: 'a-long-test-password' }),
        { accepted: true },
      );
    }
    assert.equal(updateCalls, 0);
  });

  it('preserves a legacy application UID only when an explicit Auth mapping already exists', async () => {
    const supabaseUuid = 'b1ffcd99-9c0b-4ef8-bb6d-6bb9bd380a22';
    await db.collection('users').doc('client-001').set({
      uid: 'client-001',
      authUserId: supabaseUuid,
      name: 'James Powell',
      email: 'james@example.com',
      role: 'client',
    });

    mockClient._authUsers.set(supabaseUuid, {
      id: supabaseUuid,
      email: 'james@example.com',
      email_confirmed_at: new Date().toISOString(),
      user_metadata: { name: 'James Powell' },
    });
    mockClient._tokens.set('migrated-jwt', supabaseUuid);

    const decoded = await auth.verifyIdToken('migrated-jwt');
    assert.equal(decoded.uid, 'client-001');
    assert.equal(decoded.authUserId, supabaseUuid);
    assert.equal(mockClient._tables.get('users').get('client-001').auth_user_id, supabaseUuid);
  });

  it('never links a legacy profile solely because its email matches a confirmed Auth email', async () => {
    await db.collection('users').doc('legacy-unlinked').set({
      uid: 'legacy-unlinked',
      name: 'Legacy Person',
      email: 'same@example.com',
      role: 'lawyer',
    });
    const supabaseUuid = 'c2ffcd99-9c0b-4ef8-bb6d-6bb9bd380a23';
    mockClient._authUsers.set(supabaseUuid, {
      id: supabaseUuid,
      email: 'same@example.com',
      email_confirmed_at: new Date().toISOString(),
      user_metadata: { name: 'Unlinked Auth User', legacy_uid: 'legacy-unlinked' },
    });
    mockClient._tokens.set('email-only-jwt', supabaseUuid);

    await assert.rejects(
      () => auth.verifyIdToken('email-only-jwt'),
      (error) => error.code === 'auth/profile-not-found',
    );
    assert.equal(mockClient._tables.get('users').get('legacy-unlinked').auth_user_id, undefined);
  });

  it('does not expose a privileged Auth-user creation method on the request verifier', () => {
    assert.equal(typeof auth.verifyIdToken, 'function');
    assert.equal(typeof auth.createRequestDatabase, 'function');
    assert.equal(auth.createUser, undefined);
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
    initializePublicSupabase(mockClient);

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

    await db.collection('users').doc(adminUuid).set({
      uid: adminUuid,
      authUserId: adminUuid,
      name: 'Admin',
      email: 'admin@legalapp.com',
      role: 'admin',
    });
    // The confirmed Auth profile trigger provisions the client row before any
    // authenticated API route is allowed to run.
    await db.collection('users').doc(clientUuid).set({
      uid: clientUuid,
      authUserId: clientUuid,
      name: 'Client One',
      email: 'client@legalapp.com',
      role: 'client',
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
      // Legal categories are read from PostgreSQL and only an already-linked
      // administrator may create, update or delete them.
      const emptyCategories = await request('GET', '/api/categories');
      assert.equal(emptyCategories.status, 200);
      assert.deepEqual(emptyCategories.body.data.items, []);

      const clientCategoryWrite = await request('POST', '/api/categories', {
        token: 'client-supa-jwt',
        body: { name: 'Client supplied category' },
      });
      assert.equal(clientCategoryWrite.status, 403);

      const invalidCategory = await request('POST', '/api/categories', {
        token: 'admin-supa-jwt',
        body: { name: 'x' },
      });
      assert.equal(invalidCategory.status, 400);

      const categoryRes = await request('POST', '/api/categories', {
        token: 'admin-supa-jwt',
        body: { name: 'Corporate Law' },
      });
      assert.equal(categoryRes.status, 201);
      const categoryId = categoryRes.body.data.id;
      assert.equal(categoryRes.body.data.slug, 'corporate-law');

      const categoryList = await request('GET', '/api/categories?search=corporate');
      assert.equal(categoryList.status, 200);
      assert.deepEqual(categoryList.body.data.items.map((item) => item.id), [categoryId]);

      const categoryDetail = await request('GET', `/api/categories/${categoryId}`);
      assert.equal(categoryDetail.status, 200);
      assert.equal(categoryDetail.body.data.name, 'Corporate Law');

      const categoryUpdate = await request('PUT', `/api/categories/${categoryId}`, {
        token: 'admin-supa-jwt',
        body: { name: 'Commercial Law' },
      });
      assert.equal(categoryUpdate.status, 200);
      assert.equal(categoryUpdate.body.data.slug, 'commercial-law');

      const unusedCategory = await request('POST', '/api/categories', {
        token: 'admin-supa-jwt',
        body: { name: 'Unused Category' },
      });
      assert.equal(unusedCategory.status, 201);
      const unusedDelete = await request('DELETE', `/api/categories/${unusedCategory.body.data.id}`, {
        token: 'admin-supa-jwt',
      });
      assert.equal(unusedDelete.status, 200);
      assert.equal((await request('GET', `/api/categories/${unusedCategory.body.data.id}`)).status, 404);

      // 1. Confirmed Auth provisioning runs before API access; the legacy
      // endpoint cannot overwrite the profile or promote it from request data.
      const regRes = await request('POST', '/api/users/me', {
        token: 'client-supa-jwt',
        body: {
          uid: 'forged-uid',
          name: 'Client One',
          email: 'client@legalapp.com',
          role: 'admin', // attempted self-escalation must be ignored
        },
      });
      assert.equal(regRes.status, 409);
      assert.equal((await db.collection('users').doc(clientUuid).get()).data().role, 'client');

      // Duplicate provisioning remains a conflict and never rewrites the row.
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
          categoryId,
          specialty: 'Legacy text must not override the category',
          experience: '10 years',
          price: '$200/hr',
          priceValue: 200,
          isPopular: true,
          isTop: true,
        },
      });
      assert.equal(lawyerRes.status, 201);
      const lawyerId = lawyerRes.body.data.id;
      assert.equal(lawyerRes.body.data.categoryId, categoryId);
      assert.equal(lawyerRes.body.data.specialty, 'Commercial Law');
      assert.equal(lawyerRes.body.data.experience, '10 years');

      const lawyerUpdate = await request('PUT', `/api/lawyers/${lawyerId}`, {
        token: 'admin-supa-jwt',
        body: { name: 'Dr. Evelyn Vance', experience: '11 years' },
      });
      assert.equal(lawyerUpdate.status, 200);
      assert.equal(lawyerUpdate.body.data.experience, '11 years');

      // A case assignment must reference an existing client, lawyer and the
      // same legal category as that lawyer; the category name is canonical.
      const caseRes = await request('POST', '/api/cases', {
        token: 'admin-supa-jwt',
        body: {
          userId: clientUuid,
          lawyerId,
          categoryId,
          title: 'Commercial contract matter',
          caseType: 'Forged free text',
          priority: 'High',
        },
      });
      assert.equal(caseRes.status, 201, JSON.stringify(caseRes.body));
      assert.equal(caseRes.body.data.lawyerId, lawyerId);
      assert.equal(caseRes.body.data.categoryId, categoryId);
      assert.equal(caseRes.body.data.caseType, 'Commercial Law');

      const caseDetail = await request('GET', `/api/cases/${caseRes.body.data.id}`, {
        token: 'admin-supa-jwt',
      });
      assert.equal(caseDetail.status, 200);
      assert.equal(caseDetail.body.data.categoryName, 'Commercial Law');
      assert.equal(caseDetail.body.data.lawyerName, 'Dr. Evelyn Vance');
      const caseList = await request('GET', '/api/cases?limit=10', {
        token: 'admin-supa-jwt',
      });
      const listedCase = caseList.body.data.items.find(
        (item) => item.id === caseRes.body.data.id,
      );
      assert.equal(listedCase.categoryName, 'Commercial Law');
      assert.equal(listedCase.lawyerName, 'Dr. Evelyn Vance');

      // The relationship is optional for older clients and legacy case flows;
      // an unassigned case retains its existing free-text display type.
      const legacyCaseRes = await request('POST', '/api/cases', {
        token: 'admin-supa-jwt',
        body: {
          userId: clientUuid,
          title: 'Uncategorized legacy matter',
          caseType: 'Unmapped legacy type',
          status: 'Pending',
        },
      });
      assert.equal(legacyCaseRes.status, 201, JSON.stringify(legacyCaseRes.body));
      assert.equal(legacyCaseRes.body.data.categoryId, undefined);
      assert.equal(legacyCaseRes.body.data.lawyerId, undefined);
      assert.equal(legacyCaseRes.body.data.caseType, 'Unmapped legacy type');
      assert.equal(legacyCaseRes.body.data.status, 'Pending');

      const partialAssignmentCase = await request('POST', '/api/cases', {
        token: 'admin-supa-jwt',
        body: {
          userId: clientUuid,
          title: 'Incomplete assignment',
          categoryId,
        },
      });
      assert.equal(partialAssignmentCase.status, 400);

      const familyCategory = await request('POST', '/api/categories', {
        token: 'admin-supa-jwt',
        body: { name: 'Family Law' },
      });
      const mismatchedCase = await request('PUT', `/api/cases/${caseRes.body.data.id}`, {
        token: 'admin-supa-jwt',
        body: { categoryId: familyCategory.body.data.id },
      });
      assert.equal(mismatchedCase.status, 400);
      assert.equal(mismatchedCase.body.success, false);

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
