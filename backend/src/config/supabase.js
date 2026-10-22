import crypto from 'crypto';
import { createClient } from '@supabase/supabase-js';
import env from './env.js';

/**
 * Collection-to-PostgreSQL table specification.
 *
 * Maps the application's camelCase document properties to the normalized
 * PostgreSQL snake_case columns defined in `supabase/migrations/`.
 */
export const TABLE_SPECS = {
  users: {
    table: 'users',
    toColumn: {
      id: 'id',
      uid: 'uid',
      authUserId: 'auth_user_id',
      name: 'name',
      email: 'email',
      phone: 'phone',
      role: 'role',
      avatar: 'avatar',
      address: 'address',
      createdAt: 'created_at',
      updatedAt: 'updated_at',
    },
    numericFields: [],
    booleanFields: [],
    BeforeInsert(row, docId) {
      const id = docId || row.id || row.uid || crypto.randomUUID();
      row.id = id;
      row.uid = row.uid || id;
      if ( isUuid(id) && row.auth_user_id === undefined) {
        row.auth_user_id = null;
      }
      return row;
    },
  },
  lawyers: {
    table: 'lawyers',
    toColumn: {
      id: 'id',
      userId: 'user_id',
      name: 'name',
      specialty: 'specialty',
      price: 'price',
      priceValue: 'price_value',
      image: 'image',
      rating: 'rating',
      location: 'location',
      bio: 'bio',
      isPopular: 'is_popular',
      isTop: 'is_top',
      createdAt: 'created_at',
      updatedAt: 'updated_at',
    },
    numericFields: ['priceValue', 'rating'],
    booleanFields: ['isPopular', 'isTop'],
  },
  cases: {
    table: 'cases',
    toColumn: {
      id: 'id',
      userId: 'user_id',
      title: 'title',
      description: 'description',
      clientName: 'client_name',
      caseType: 'case_type',
      priority: 'priority',
      status: 'status',
      dueDate: 'due_date',
      createdAt: 'created_at',
      updatedAt: 'updated_at',
    },
    numericFields: [],
    booleanFields: [],
  },
  bookings: {
    table: 'bookings',
    toColumn: {
      id: 'id',
      userId: 'user_id',
      lawyerId: 'lawyer_id',
      lawyerName: 'lawyer_name',
      date: 'date',
      time: 'time',
      hours: 'hours',
      totalPrice: 'total_price',
      status: 'status',
      slotKeys: 'slot_keys',
      createdAt: 'created_at',
      updatedAt: 'updated_at',
    },
    numericFields: ['hours', 'totalPrice'],
    booleanFields: [],
  },
  bookingSlots: {
    table: 'booking_slots',
    toColumn: {
      id: 'id',
      lawyerId: 'lawyer_id',
      date: 'date',
      slot: 'slot',
      bookingId: 'booking_id',
      userId: 'user_id',
      createdAt: 'created_at',
    },
    numericFields: ['slot'],
    booleanFields: [],
  },
  tasks: {
    table: 'tasks',
    toColumn: {
      id: 'id',
      userId: 'user_id',
      title: 'title',
      description: 'description',
      dueDate: 'due_date',
      priority: 'priority',
      status: 'status',
      createdAt: 'created_at',
      updatedAt: 'updated_at',
    },
    numericFields: [],
    booleanFields: [],
  },
  chats: {
    table: 'chats',
    toColumn: {
      id: 'id',
      participants: 'participants',
      participantNames: 'participant_names',
      lastMessage: 'last_message',
      createdAt: 'created_at',
      updatedAt: 'updated_at',
    },
    numericFields: [],
    booleanFields: [],
  },
  messages: {
    table: 'chat_messages',
    toColumn: {
      id: 'id',
      chatId: 'chat_id',
      senderId: 'sender_id',
      senderName: 'sender_name',
      text: 'text',
      createdAt: 'created_at',
    },
    numericFields: [],
    booleanFields: [],
  },
  reviews: {
    table: 'reviews',
    toColumn: {
      id: 'id',
      userId: 'user_id',
      userName: 'user_name',
      lawyerId: 'lawyer_id',
      rating: 'rating',
      comment: 'comment',
      createdAt: 'created_at',
      updatedAt: 'updated_at',
    },
    numericFields: ['rating'],
    booleanFields: [],
  },
  favorites: {
    table: 'favorites',
    toColumn: {
      id: 'id',
      userId: 'user_id',
      lawyerId: 'lawyer_id',
      createdAt: 'created_at',
    },
    numericFields: [],
    booleanFields: [],
  },
  wallets: {
    table: 'wallets',
    toColumn: {
      id: 'id',
      userId: 'user_id',
      balance: 'balance',
      currency: 'currency',
      createdAt: 'created_at',
      updatedAt: 'updated_at',
    },
    numericFields: ['balance'],
    booleanFields: [],
    BeforeInsert(row, docId) {
      const id = docId || row.id || row.user_id;
      row.id = id;
      row.user_id = row.user_id || id;
      return row;
    },
  },
  wallet_transactions: {
    table: 'wallet_transactions',
    toColumn: {
      id: 'id',
      userId: 'user_id',
      type: 'type',
      amount: 'amount',
      description: 'description',
      balance: 'balance',
      currency: 'currency',
      idempotencyKeyHash: 'idempotency_key_hash',
      createdAt: 'created_at',
      updatedAt: 'updated_at',
    },
    numericFields: ['amount', 'balance'],
    booleanFields: [],
  },
  wallet_idempotency: {
    table: 'wallet_idempotency',
    toColumn: {
      id: 'id',
      userId: 'user_id',
      type: 'type',
      amount: 'amount',
      currency: 'currency',
      balance: 'balance',
      transaction: 'transaction',
      createdAt: 'created_at',
    },
    numericFields: ['amount', 'balance'],
    booleanFields: [],
  },
  plans: {
    table: 'plans',
    toColumn: {
      id: 'id',
      title: 'title',
      price: 'price',
      priceValue: 'price_value',
      color: 'color',
      features: 'features',
      isPopular: 'is_popular',
      createdAt: 'created_at',
      updatedAt: 'updated_at',
    },
    numericFields: ['priceValue'],
    booleanFields: ['isPopular'],
  },
  subscriptions: {
    table: 'subscriptions',
    toColumn: {
      id: 'id',
      userId: 'user_id',
      planId: 'plan_id',
      planTitle: 'plan_title',
      status: 'status',
      startDate: 'start_date',
      endDate: 'end_date',
      createdAt: 'created_at',
      updatedAt: 'updated_at',
    },
    numericFields: [],
    booleanFields: [],
  },
  notifications: {
    table: 'notifications',
    toColumn: {
      id: 'id',
      userId: 'user_id',
      title: 'title',
      content: 'content',
      type: 'type',
      icon: 'icon',
      read: 'read',
      createdAt: 'created_at',
      updatedAt: 'updated_at',
    },
    numericFields: [],
    booleanFields: ['read'],
  },
  earnings: {
    table: 'earnings',
    toColumn: {
      id: 'id',
      userId: 'user_id',
      balance: 'balance',
      totalEarnings: 'total_earnings',
      breakdown: 'breakdown',
      createdAt: 'created_at',
      updatedAt: 'updated_at',
    },
    numericFields: ['balance', 'totalEarnings'],
    booleanFields: [],
    BeforeInsert(row, docId) {
      const id = docId || row.id || row.user_id;
      row.id = id;
      row.user_id = row.user_id || id;
      return row;
    },
  },
  availability: {
    table: 'availability',
    toColumn: {
      id: 'id',
      lawyerId: 'lawyer_id',
      lawyerName: 'lawyer_name',
      date: 'date',
      slots: 'slots',
      createdAt: 'created_at',
      updatedAt: 'updated_at',
    },
    numericFields: [],
    booleanFields: [],
  },
};

for (const spec of Object.values(TABLE_SPECS)) {
  spec.toField = {};
  for (const [field, col] of Object.entries(spec.toColumn)) {
    spec.toField[col] = field;
  }
}

function isUuid(value) {
  return (
    typeof value === 'string' &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      value
    )
  );
}

/**
 * Detects Firestore's `FieldValue.serverTimestamp()` sentinel or our own
 * timestamp sentinel and converts it into an ISO-8601 UTC string.
 */
export function isServerTimestampSentinel(val) {
  if (!val || typeof val !== 'object') return false;
  if (val.__serverTimestamp === true) return true;
  if (val._methodName === 'FieldValue.serverTimestamp') return true;
  const ctorName = val.constructor?.name || '';
  if (ctorName.includes('ServerTimestampTransform') || ctorName.includes('FieldValue')) {
    return true;
  }
  return false;
}

export function normalizeValueForDb(val) {
  if (isServerTimestampSentinel(val)) {
    return new Date().toISOString();
  }
  if (val instanceof Date) {
    return val.toISOString();
  }
  if (Array.isArray(val)) {
    return val.map(normalizeValueForDb);
  }
  if (val && typeof val === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(val)) {
      if (v !== undefined) {
        out[k] = normalizeValueForDb(v);
      }
    }
    return out;
  }
  return val;
}

/**
 * Converts an application document object (camelCase) into a PostgreSQL row
 * object (snake_case) for the given collection specification.
 */
export function toDbRow(collectionName, data, docId = null, isInsert = false) {
  const spec = TABLE_SPECS[collectionName];
  if (!spec) {
    throw new Error(`Unsupported collection "${collectionName}"`);
  }
  const row = {};
  for (const [key, rawVal] of Object.entries(data || {})) {
    if (rawVal === undefined) continue;
    const col = spec.toColumn[key] || key;
    let val = normalizeValueForDb(rawVal);
    if (col === 'end_date' && val === '') {
      val = null;
    }
    if (col === 'user_id' && collectionName === 'cases' && val === '') {
      val = null;
    }
    row[col] = val;
  }
  if (docId) {
    row.id = docId;
  }
  if (isInsert && typeof spec.BeforeInsert === 'function') {
    spec.BeforeInsert(row, docId);
  }
  return row;
}

/**
 * Converts a PostgreSQL row (snake_case) back into the application's camelCase
 * document shape (excluding `id`, which is carried on `doc.id` and merged by
 * `docToObj`).
 */
export function fromDbRow(collectionName, row) {
  if (!row || typeof row !== 'object') return null;
  const spec = TABLE_SPECS[collectionName];
  if (!spec) return { ...row };

  const doc = {};
  for (const [col, val] of Object.entries(row)) {
    if (col === 'id') continue;
    if (col === 'auth_user_id' && val === null) continue;
    const field = spec.toField[col] || col;
    if (val !== null && val !== undefined && spec.numericFields.includes(field)) {
      const n = Number(val);
      doc[field] = Number.isNaN(n) ? val : n;
    } else if (val !== null && val !== undefined && spec.booleanFields.includes(field)) {
      doc[field] = Boolean(val);
    } else if (col === 'end_date' && val === null) {
      doc[field] = null;
    } else if (col === 'user_id' && collectionName === 'cases' && val === null) {
      doc[field] = null;
    } else {
      doc[field] = val;
    }
  }
  return doc;
}

class SupabaseDocSnapshot {
  constructor(id, data, ref) {
    this.id = id;
    this._data = data;
    this.exists = data !== null && data !== undefined;
    this.ref = ref;
  }

  data() {
    return this.exists ? { ...this._data } : undefined;
  }
}

class SupabaseQuerySnapshot {
  constructor(docs) {
    this.docs = docs;
    this.size = docs.length;
    this.empty = docs.length === 0;
  }
}

class SupabaseDocRef {
  constructor(client, collectionName, id, parentContext = {}) {
    this._client = client;
    this._collectionName = collectionName;
    this._spec = TABLE_SPECS[collectionName];
    if (!this._spec) {
      throw new Error(`Unknown collection: ${collectionName}`);
    }
    this.id = id || crypto.randomUUID();
    this._parentContext = parentContext;
  }

  collection(subCollectionName) {
    if (this._collectionName === 'chats' && subCollectionName === 'messages') {
      return new SupabaseCollectionRef(this._client, 'messages', {
        chatId: this.id,
      });
    }
    return new SupabaseCollectionRef(this._client, subCollectionName, {
      parentId: this.id,
    });
  }

  async get() {
    let query = this._client
      .from(this._spec.table)
      .select('*')
      .eq('id', this.id);

    if (this._parentContext.chatId) {
      query = query.eq('chat_id', this._parentContext.chatId);
    }

    let { data, error } = await query.maybeSingle();
    if (error) {
      throw new Error(
        `Supabase SELECT error on ${this._spec.table}/${this.id}: ${error.message}`
      );
    }
    if (!data && this._collectionName === 'users' && isUuid(this.id)) {
      const byAuth = await this._client
          .from('users')
          .select('*')
          .eq('auth_user_id', this.id)
          .maybeSingle();
      if (!byAuth.error && byAuth.data) {
        data = byAuth.data;
      }
    }
    if (!data) {
      return new SupabaseDocSnapshot(this.id, null, this);
    }
    return new SupabaseDocSnapshot(
      String(data.id),
      fromDbRow(this._collectionName, data),
      this
    );
  }

  async set(data, options = {}) {
    const payload = { ...data };
    if (this._parentContext.chatId && !payload.chatId) {
      payload.chatId = this._parentContext.chatId;
    }

    if (options && options.merge) {
      const existing = await this.get();
      if (existing.exists) {
        return this.update(payload);
      }
    }

    const row = toDbRow(this._collectionName, payload, this.id, true);
    const { error } = await this._client
      .from(this._spec.table)
      .upsert(row, { onConflict: 'id' });

    if (error) {
      throw new Error(
        `Supabase UPSERT error on ${this._spec.table}/${this.id}: ${error.message}`
      );
    }
    return this;
  }

  async create(data) {
    const existing = await this.get();
    if (existing.exists) {
      const err = new Error(
        `Document already exists: ${this._spec.table}/${this.id}`
      );
      err.code = 'already-exists';
      throw err;
    }

    const payload = { ...data };
    if (this._parentContext.chatId && !payload.chatId) {
      payload.chatId = this._parentContext.chatId;
    }

    const row = toDbRow(this._collectionName, payload, this.id, true);
    const { error } = await this._client.from(this._spec.table).insert(row);
    if (error) {
      if (
        error.code === '23505' ||
        /duplicate key|already exists/i.test(error.message || '')
      ) {
        const dupErr = new Error(
          `Document already exists: ${this._spec.table}/${this.id}`
        );
        dupErr.code = 'already-exists';
        throw dupErr;
      }
      throw new Error(
        `Supabase INSERT error on ${this._spec.table}/${this.id}: ${error.message}`
      );
    }
    return this;
  }

  async update(data) {
    const row = toDbRow(this._collectionName, data, null, false);
    delete row.id;

    let query = this._client
      .from(this._spec.table)
      .update(row)
      .eq('id', this.id);

    if (this._parentContext.chatId) {
      query = query.eq('chat_id', this._parentContext.chatId);
    }

    const { error } = await query;
    if (error) {
      throw new Error(
        `Supabase UPDATE error on ${this._spec.table}/${this.id}: ${error.message}`
      );
    }
    return this;
  }

  async delete() {
    let query = this._client
      .from(this._spec.table)
      .delete()
      .eq('id', this.id);

    if (this._parentContext.chatId) {
      query = query.eq('chat_id', this._parentContext.chatId);
    }

    const { error } = await query;
    if (error) {
      throw new Error(
        `Supabase DELETE error on ${this._spec.table}/${this.id}: ${error.message}`
      );
    }
    return this;
  }
}

class SupabaseQuery {
  constructor(
    client,
    collectionName,
    parentContext = {},
    filters = [],
    orders = [],
    limitCount = null
  ) {
    this._client = client;
    this._collectionName = collectionName;
    this._spec = TABLE_SPECS[collectionName];
    if (!this._spec) {
      throw new Error(`Unknown collection: ${collectionName}`);
    }
    this._parentContext = parentContext;
    this._filters = filters;
    this._orders = orders;
    this._limitCount = limitCount;
  }

  where(field, op, value) {
    return new SupabaseQuery(
      this._client,
      this._collectionName,
      this._parentContext,
      [...this._filters, { field, op, value }],
      this._orders,
      this._limitCount
    );
  }

  orderBy(field, direction = 'asc') {
    return new SupabaseQuery(
      this._client,
      this._collectionName,
      this._parentContext,
      this._filters,
      [...this._orders, { field, direction: direction.toLowerCase() === 'desc' ? 'desc' : 'asc' }],
      this._limitCount
    );
  }

  limit(n) {
    return new SupabaseQuery(
      this._client,
      this._collectionName,
      this._parentContext,
      this._filters,
      this._orders,
      n
    );
  }

  _mapColumn(field) {
    return this._spec.toColumn[field] || field;
  }

  async get() {
    let query = this._client.from(this._spec.table).select('*');

    if (this._parentContext.chatId) {
      query = query.eq('chat_id', this._parentContext.chatId);
    }

    for (const f of this._filters) {
      const col = this._mapColumn(f.field);
      switch (f.op) {
        case '==':
          if (f.value === null) {
            query = query.is(col, null);
          } else {
            query = query.eq(col, f.value);
          }
          break;
        case '!=':
          if (f.value === null) {
            query = query.not(col, 'is', null);
          } else {
            query = query.neq(col, f.value);
          }
          break;
        case '>':
          query = query.gt(col, f.value);
          break;
        case '>=':
          query = query.gte(col, f.value);
          break;
        case '<':
          query = query.lt(col, f.value);
          break;
        case '<=':
          query = query.lte(col, f.value);
          break;
        case 'in':
          query = query.in(col, Array.isArray(f.value) ? f.value : [f.value]);
          break;
        case 'array-contains':
          query = query.contains(col, [f.value]);
          break;
        default:
          throw new Error(`Unsupported query operator: ${f.op}`);
      }
    }

    for (const ord of this._orders) {
      const col = this._mapColumn(ord.field);
      query = query.order(col, { ascending: ord.direction !== 'desc' });
    }

    if (typeof this._limitCount === 'number' && this._limitCount > 0) {
      query = query.limit(this._limitCount);
    }

    const { data, error } = await query;
    if (error) {
      throw new Error(
        `Supabase QUERY error on ${this._spec.table}: ${error.message}`
      );
    }

    const docs = (data || []).map((row) => {
      const id = String(row.id);
      const ref = new SupabaseDocRef(
        this._client,
        this._collectionName,
        id,
        this._parentContext
      );
      return new SupabaseDocSnapshot(
        id,
        fromDbRow(this._collectionName, row),
        ref
      );
    });

    return new SupabaseQuerySnapshot(docs);
  }
}

class SupabaseCollectionRef extends SupabaseQuery {
  constructor(client, collectionName, parentContext = {}) {
    super(client, collectionName, parentContext);
  }

  doc(id) {
    return new SupabaseDocRef(
      this._client,
      this._collectionName,
      id || crypto.randomUUID(),
      this._parentContext
    );
  }

  async add(data) {
    const id = crypto.randomUUID();
    const ref = this.doc(id);
    await ref.set(data);
    return ref;
  }
}

class SupabaseWriteBatch {
  constructor() {
    this._ops = [];
  }

  set(ref, data, options) {
    this._ops.push(() => ref.set(data, options));
    return this;
  }

  update(ref, data) {
    this._ops.push(() => ref.update(data));
    return this;
  }

  delete(ref) {
    this._ops.push(() => ref.delete());
    return this;
  }

  async commit() {
    for (const op of this._ops) {
      await op();
    }
  }
}

/**
 * Creates a Firestore-compatible database adapter backed by Supabase PostgreSQL.
 *
 * All reads, writes, batches, and transactions operate against the normalized
 * PostgreSQL tables in `public` while preserving the Express routes' exact
 * camelCase data contracts.
 */
export function createSupabaseDatabase(supabaseClient) {
  return {
    _isSupabase: true,
    _client: supabaseClient,

    collection(name) {
      return new SupabaseCollectionRef(supabaseClient, name);
    },

    batch() {
      return new SupabaseWriteBatch();
    },

    /**
     * Executes a transactional callback with staged writes and rollback on
     * conflict or failure.
     */
    async runTransaction(updateFunction) {
      const stagedOps = [];
      const readSnapshots = new Map();

      const tx = {
        async get(target) {
          const snap = await target.get();
          if (target instanceof SupabaseDocRef) {
            readSnapshots.set(`${target._collectionName}:${target.id}`, {
              ref: target,
              existed: snap.exists,
              previousData: snap.exists ? snap.data() : null,
            });
          }
          return snap;
        },
        set(ref, data, options) {
          stagedOps.push({ type: 'set', ref, data, options });
          return tx;
        },
        create(ref, data) {
          stagedOps.push({ type: 'create', ref, data });
          return tx;
        },
        update(ref, data) {
          stagedOps.push({ type: 'update', ref, data });
          return tx;
        },
        delete(ref) {
          stagedOps.push({ type: 'delete', ref });
          return tx;
        },
      };

      const result = await updateFunction(tx);
      const appliedOps = [];

      try {
        for (const op of stagedOps) {
          const key = `${op.ref._collectionName}:${op.ref.id}`;
          let prior = readSnapshots.get(key);
          if (!prior) {
            const snap = await op.ref.get();
            prior = {
              ref: op.ref,
              existed: snap.exists,
              previousData: snap.exists ? snap.data() : null,
            };
          }

          if (op.type === 'set') {
            await op.ref.set(op.data, op.options);
          } else if (op.type === 'create') {
            await op.ref.create(op.data);
          } else if (op.type === 'update') {
            await op.ref.update(op.data);
          } else if (op.type === 'delete') {
            await op.ref.delete();
          }
          appliedOps.push(prior);
        }
      } catch (err) {
        // Compensating rollback in reverse order if a multi-row write fails
        for (let i = appliedOps.length - 1; i >= 0; i--) {
          const prior = appliedOps[i];
          try {
            if (prior.existed && prior.previousData) {
              await prior.ref.set(prior.previousData);
            } else if (!prior.existed) {
              await prior.ref.delete();
            }
          } catch {
            // Best-effort rollback
          }
        }
        throw err;
      }

      return result;
    },
  };
}

/**
 * Creates a server-side Auth adapter backed by Supabase Auth (`auth.users`)
 * and `public.users` identity mapping.
 *
 * Never trusts client-supplied roles: `verifyIdToken` validates the JWT with
 * Supabase Auth and resolves the canonical `uid` from `public.users` (supporting
 * both native Supabase UUIDs and migrated Firebase UIDs).
 */
export function createSupabaseAuth(supabaseClient) {
  async function resolveAuthUserId(uid) {
    if (isUuid(uid)) return uid;
    const { data } = await supabaseClient
      .from('users')
      .select('auth_user_id, email')
      .eq('id', uid)
      .maybeSingle();
    if (data?.auth_user_id) return data.auth_user_id;
    if (data?.email) {
      const { data: listData } = await supabaseClient.auth.admin.listUsers();
      const found = listData?.users?.find(
        (u) => (u.email || '').toLowerCase() === data.email.toLowerCase()
      );
      if (found) return found.id;
    }
    return null;
  }

  return {
    _isSupabase: true,
    _client: supabaseClient,

    async verifyIdToken(token) {
      if (!token || typeof token !== 'string') {
        const err = new Error('Invalid or expired token');
        err.code = 'auth/invalid-id-token';
        throw err;
      }

      const { data, error } = await supabaseClient.auth.getUser(token);
      if (error || !data?.user) {
        const err = new Error(error?.message || 'Invalid or expired token');
        err.code = 'auth/id-token-expired';
        throw err;
      }

      const authUser = data.user;
      const meta = authUser.user_metadata || {};
      let resolvedUid = authUser.id;
      let resolvedName = meta.name || meta.full_name || meta.display_name || '';

      // 1. Check if a public.users profile is linked via auth_user_id or id
      const { data: profileById } = await supabaseClient
        .from('users')
        .select('id, uid, name, email, auth_user_id')
        .or(`auth_user_id.eq.${authUser.id},id.eq.${authUser.id}`)
        .limit(1)
        .maybeSingle();

      if (profileById) {
        resolvedUid = profileById.id;
        resolvedName = resolvedName || profileById.name || '';
        if (!profileById.auth_user_id && isUuid(authUser.id)) {
          await supabaseClient
            .from('users')
            .update({ auth_user_id: authUser.id })
            .eq('id', profileById.id);
        }
      } else if (authUser.email && authUser.email_confirmed_at) {
        // 2. Link pre-migrated Firebase user profile by confirmed email if unlinked
        const { data: migratedProfile } = await supabaseClient
          .from('users')
          .select('id, uid, name, email, auth_user_id')
          .ilike('email', authUser.email)
          .is('auth_user_id', null)
          .limit(1)
          .maybeSingle();

        if (migratedProfile) {
          resolvedUid = migratedProfile.id;
          resolvedName = resolvedName || migratedProfile.name || '';
          await supabaseClient
            .from('users')
            .update({ auth_user_id: authUser.id })
            .eq('id', migratedProfile.id);
        }
      }

      return {
        uid: resolvedUid,
        authUserId: authUser.id,
        email: authUser.email || '',
        name: resolvedName,
        email_verified: Boolean(authUser.email_confirmed_at),
      };
    },

    async getUser(uid) {
      const authId = await resolveAuthUserId(uid);
      if (!authId) {
        const err = new Error(`No auth user found for uid: ${uid}`);
        err.code = 'auth/user-not-found';
        throw err;
      }
      const { data, error } = await supabaseClient.auth.admin.getUserById(authId);
      if (error || !data?.user) {
        const err = new Error(error?.message || 'User not found');
        err.code = 'auth/user-not-found';
        throw err;
      }
      return {
        uid,
        authUserId: data.user.id,
        email: data.user.email,
        displayName:
          data.user.user_metadata?.name ||
          data.user.user_metadata?.full_name ||
          '',
      };
    },

    async createUser({ uid, email, password, displayName, emailVerified = true }) {
      const payload = {
        email,
        password,
        email_confirm: Boolean(emailVerified),
        user_metadata: {
          name: displayName || '',
          full_name: displayName || '',
          legacy_uid: uid || undefined,
        },
      };
      if (isUuid(uid)) {
        payload.id = uid;
      }

      const { data, error } = await supabaseClient.auth.admin.createUser(payload);
      if (error) {
        // If user with this email already exists in Supabase Auth, update instead
        if (/already|exists|registered/i.test(error.message)) {
          const { data: listData } = await supabaseClient.auth.admin.listUsers();
          const existing = listData?.users?.find(
            (u) => (u.email || '').toLowerCase() === (email || '').toLowerCase()
          );
          if (existing) {
            await supabaseClient.auth.admin.updateUserById(existing.id, {
              password,
              email_confirm: Boolean(emailVerified),
              user_metadata: {
                name: displayName || '',
                full_name: displayName || '',
                legacy_uid: uid || undefined,
              },
            });
            return {
              uid: uid || existing.id,
              authUserId: existing.id,
              email: existing.email,
              displayName: displayName || '',
            };
          }
        }
        throw new Error(`Supabase createUser error: ${error.message}`);
      }

      return {
        uid: uid || data.user.id,
        authUserId: data.user.id,
        email: data.user.email,
        displayName: displayName || '',
      };
    },

    async updateUser(uid, { email, password, displayName, emailVerified }) {
      let authId = await resolveAuthUserId(uid);
      if (!authId && email) {
        const { data: listData } = await supabaseClient.auth.admin.listUsers();
        const found = listData?.users?.find(
          (u) => (u.email || '').toLowerCase() === email.toLowerCase()
        );
        if (found) authId = found.id;
      }
      if (!authId) {
        const err = new Error(`No auth user found for uid: ${uid}`);
        err.code = 'auth/user-not-found';
        throw err;
      }

      const updates = {};
      if (email !== undefined) updates.email = email;
      if (password !== undefined) updates.password = password;
      if (emailVerified !== undefined) updates.email_confirm = Boolean(emailVerified);
      if (displayName !== undefined) {
        updates.user_metadata = {
          name: displayName,
          full_name: displayName,
          legacy_uid: uid,
        };
      }

      const { data, error } = await supabaseClient.auth.admin.updateUserById(
        authId,
        updates
      );
      if (error) {
        throw new Error(`Supabase updateUser error: ${error.message}`);
      }
      return {
        uid,
        authUserId: data.user.id,
        email: data.user.email,
        displayName: displayName || '',
      };
    },

    async deleteUser(uid) {
      const authId = await resolveAuthUserId(uid);
      if (!authId) {
        const err = new Error(`User not found: ${uid}`);
        err.code = 'auth/user-not-found';
        throw err;
      }
      const { error } = await supabaseClient.auth.admin.deleteUser(authId);
      if (error) {
        if (/not found/i.test(error.message)) {
          const err = new Error(error.message);
          err.code = 'auth/user-not-found';
          throw err;
        }
        throw new Error(`Supabase deleteUser error: ${error.message}`);
      }
    },
  };
}

let cachedSupabaseClient = null;
let cachedDb = null;
let cachedAuth = null;

export function isSupabaseConfigured(envVars = process.env) {
  const url = (envVars.SUPABASE_URL || env.supabaseUrl || '').trim();
  const key = (
    envVars.SUPABASE_SERVICE_ROLE_KEY ||
    envVars.SUPABASE_SECRET_KEY ||
    env.supabaseServiceRoleKey ||
    ''
  ).trim();
  return Boolean(url && key);
}

export function initializeSupabase(customClient = null) {
  if (customClient) {
    cachedSupabaseClient = customClient;
    cachedDb = createSupabaseDatabase(customClient);
    cachedAuth = createSupabaseAuth(customClient);
    return { client: cachedSupabaseClient, db: cachedDb, auth: cachedAuth };
  }

  if (cachedSupabaseClient && cachedDb && cachedAuth) {
    return { client: cachedSupabaseClient, db: cachedDb, auth: cachedAuth };
  }

  const url = (process.env.SUPABASE_URL || env.supabaseUrl || '').trim();
  const serviceRoleKey = (
    process.env.SUPABASE_SERVICE_ROLE_KEY ||
    process.env.SUPABASE_SECRET_KEY ||
    env.supabaseServiceRoleKey ||
    ''
  ).trim();

  if (!url || !serviceRoleKey) {
    throw new Error(
      '[backend] Supabase credentials missing: set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY on the server.'
    );
  }

  cachedSupabaseClient = createClient(url, serviceRoleKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });
  cachedDb = createSupabaseDatabase(cachedSupabaseClient);
  cachedAuth = createSupabaseAuth(cachedSupabaseClient);
  return { client: cachedSupabaseClient, db: cachedDb, auth: cachedAuth };
}
