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
    selectColumns: 'id,uid,name,email,phone,role,avatar,address,created_at,updated_at',
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
    // `user_id` is selected only on authenticated server requests. Public
    // lawyer responses never expose the linked account identifier.
    selectColumns: 'id,user_id,category_id,name,specialty,experience,price,price_value,image,rating,location,bio,is_popular,is_top,created_at,updated_at',
    publicSelectColumns: 'id,category_id,name,specialty,experience,price,price_value,image,rating,location,bio,is_popular,is_top,created_at,updated_at',
    toColumn: {
      id: 'id',
      userId: 'user_id',
      categoryId: 'category_id',
      name: 'name',
      specialty: 'specialty',
      experience: 'experience',
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
  legalCategories: {
    table: 'legal_categories',
    selectColumns: 'id,name,slug,created_at,updated_at',
    toColumn: {
      id: 'id',
      name: 'name',
      slug: 'slug',
      createdAt: 'created_at',
      updatedAt: 'updated_at',
    },
    numericFields: [],
    booleanFields: [],
  },
  cases: {
    table: 'cases',
    toColumn: {
      id: 'id',
      userId: 'user_id',
      lawyerId: 'lawyer_id',
      categoryId: 'category_id',
      title: 'title',
      description: 'description',
      clientName: 'client_name',
      caseType: 'case_type',
      priority: 'priority',
      status: 'status',
      dueDate: 'due_date',
      // Legacy callers may still use the Firestore-era `dueOn` property.
      // PostgreSQL stores both API spellings in the observed `due_date` column.
      dueOn: 'due_date',
      createdAt: 'created_at',
      updatedAt: 'updated_at',
    },
    numericFields: [],
    booleanFields: [],
  },
  bookings: {
    table: 'bookings',
    selectColumns: 'id,user_id,lawyer_id,lawyer_name,date,time,hours,total_price,status,slot_keys,created_at,updated_at',
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
      // Keep the legacy document property, but target the live text column.
      dueOn: 'due_date',
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
    selectColumns: 'id,user_name,lawyer_id,rating,comment,created_at,updated_at',
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
    selectColumns: 'id,user_id,type,amount,description,balance,currency,created_at,updated_at',
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
 * Converts a server-side timestamp sentinel into an ISO-8601 UTC string.
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
    if (col === 'user_id' && ['cases', 'lawyers'].includes(collectionName) && val === '') {
      val = null;
    }
    if (col === 'category_id' && ['cases', 'lawyers'].includes(collectionName) && val === '') {
      val = null;
    }
    if (col === 'lawyer_id' && collectionName === 'cases' && val === '') {
      val = null;
    }
    if (['cases', 'tasks'].includes(collectionName) && col === 'due_date' && (val === null || val === '')) {
      val = '';
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
    // Idempotency digests are internal retry metadata, not part of either API
    // response contract. Keep them hidden even when a service-role query reads
    // the full physical row.
    if (
      col === 'idempotency_key_hash' &&
      ['bookings', 'wallet_transactions'].includes(collectionName)
    ) continue;
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
  if (['cases', 'tasks'].includes(collectionName)) {
    const storedDate = row.due_date;
    doc.dueDate = storedDate === null || storedDate === undefined
        ? ''
        : String(storedDate);
    delete doc.dueOn;
  }
  return doc;
}

function selectColumnsFor(spec, requestScoped) {
  return requestScoped
    ? (spec.selectColumns || '*')
    : (spec.publicSelectColumns || spec.selectColumns || '*');
}

function requestWritePayload(row, requestScoped) {
  if (!requestScoped || !row || typeof row !== 'object') return row;
  const { created_at: _createdAt, updated_at: _updatedAt, ...writable } = row;
  return writable;
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
  constructor(client, collectionName, id, parentContext = {}, requestScoped = false) {
    this._client = client;
    this._requestScoped = requestScoped;
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
      }, this._requestScoped);
    }
    return new SupabaseCollectionRef(this._client, subCollectionName, {
      parentId: this.id,
    }, this._requestScoped);
  }

  async get() {
    let query = this._client
      .from(this._spec.table)
      .select(selectColumnsFor(this._spec, this._requestScoped))
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
          .select(selectColumnsFor(this._spec, this._requestScoped))
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

    const row = requestWritePayload(
      toDbRow(this._collectionName, payload, this.id, true),
      this._requestScoped,
    );
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

    const row = requestWritePayload(
      toDbRow(this._collectionName, payload, this.id, true),
      this._requestScoped,
    );
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
    const row = requestWritePayload(
      toDbRow(this._collectionName, data, null, false),
      this._requestScoped,
    );
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
    limitCount = null,
    requestScoped = false
  ) {
    this._client = client;
    this._requestScoped = requestScoped;
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
      this._limitCount,
      this._requestScoped
    );
  }

  orderBy(field, direction = 'asc') {
    return new SupabaseQuery(
      this._client,
      this._collectionName,
      this._parentContext,
      this._filters,
      [...this._orders, { field, direction: direction.toLowerCase() === 'desc' ? 'desc' : 'asc' }],
      this._limitCount,
      this._requestScoped
    );
  }

  limit(n) {
    return new SupabaseQuery(
      this._client,
      this._collectionName,
      this._parentContext,
      this._filters,
      this._orders,
      n,
      this._requestScoped
    );
  }

  _mapColumn(field) {
    return this._spec.toColumn[field] || field;
  }

  async get() {
    let query = this._client
      .from(this._spec.table)
      .select(selectColumnsFor(this._spec, this._requestScoped));

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
        this._parentContext,
        this._requestScoped
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
  constructor(client, collectionName, parentContext = {}, requestScoped = false) {
    super(client, collectionName, parentContext, [], [], null, requestScoped);
  }

  doc(id) {
    return new SupabaseDocRef(
      this._client,
      this._collectionName,
      id || crypto.randomUUID(),
      this._parentContext,
      this._requestScoped
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
 * Creates the legacy-shaped route database adapter backed by Supabase PostgreSQL.
 *
 * All reads, writes, batches, and transactions operate against the normalized
 * PostgreSQL tables in `public` while preserving the Express routes' exact
 * camelCase data contracts.
 */
export function createSupabaseDatabase(supabaseClient, { authenticatedRequest = false } = {}) {
  return {
    _isSupabase: true,
    _isAuthenticatedRequest: authenticatedRequest,
    _client: supabaseClient,

    async rpcAsUser(functionName, parameters = {}) {
      if (!authenticatedRequest) {
        throw new Error('An authenticated Supabase request client is required for this RPC.');
      }
      if (!/^[a-z0-9_]+$/.test(functionName)) {
        throw new Error('Invalid Supabase RPC name.');
      }
      if (!supabaseClient || typeof supabaseClient.rpc !== 'function') {
        throw new Error('Supabase RPC support is not configured.');
      }
      const { data, error } = await supabaseClient.rpc(functionName, parameters);
      if (error) {
        const rpcError = new Error(`Supabase RPC error on ${functionName}: ${error.message}`);
        rpcError.code = error.code;
        rpcError.details = error.details;
        rpcError.hint = error.hint;
        throw rpcError;
      }
      return data;
    },


    collection(name) {
      return new SupabaseCollectionRef(supabaseClient, name, {}, authenticatedRequest);
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
 * Server-side Supabase Auth adapter. It verifies the bearer token with Auth,
 * resolves the linked application profile through `auth_user_id` (falling back
 * to the native-UUID profile ID), and never trusts role/name claims supplied
 * by the client.
 */
export function createSupabaseAuth(supabaseClient, {
  requestDatabaseFactory = null,
  publicAuthClientFactory = null,
  lawyerSignupRedirectUrl = null,
} = {}) {
  const createPublicAuthClient = () => {
    if (typeof publicAuthClientFactory === 'function') {
      return publicAuthClientFactory();
    }
    const url = (process.env.SUPABASE_URL || env.supabaseUrl || '').trim();
    const anonKey = (process.env.SUPABASE_ANON_KEY || env.supabaseAnonKey || '').trim();
    if (!url || !anonKey) {
      const error = new Error('Public Supabase Auth is not configured.');
      error.code = 'auth/lawyer-signup-unavailable';
      throw error;
    }
    return createClient(url, anonKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });
  };

  const getLawyerSignupRedirect = () => {
    const configured = typeof lawyerSignupRedirectUrl === 'function'
      ? lawyerSignupRedirectUrl()
      : lawyerSignupRedirectUrl;
    return (
      configured ||
      process.env.LAWYER_SIGNUP_REDIRECT_URL ||
      process.env.SUPABASE_AUTH_REDIRECT_URL ||
      env.lawyerSignupRedirectUrl ||
      env.supabaseAuthRedirectUrl ||
      ''
    ).trim();
  };

  const boundaryError = (code, message) => {
    const error = new Error(message);
    error.code = code;
    return error;
  };

  return {
    _isSupabase: true,
    _client: supabaseClient,

    createRequestDatabase(accessToken) {
      if (typeof requestDatabaseFactory === 'function') {
        return requestDatabaseFactory(accessToken);
      }
      return createSupabaseRequestDatabase(accessToken);
    },

    /**
     * Begins public lawyer onboarding through the anon-key Auth client, then
     * marks only a newly created, still-unconfirmed Auth identity with
     * server-owned app_metadata. The Auth trigger provisions the lawyer profile
     * only after email confirmation. No role, user ID, or service key comes
     * from the HTTP caller.
     */
    async createLawyerSignup({ name, email, password }) {
      const normalizedEmail = String(email || '').trim().toLowerCase();
      const displayName = String(name || '').trim();
      const redirectTo = getLawyerSignupRedirect();
      if (!redirectTo) {
        throw boundaryError(
          'auth/lawyer-signup-unavailable',
          'Lawyer signup redirect is not configured.',
        );
      }
      if (!normalizedEmail || !displayName || typeof password !== 'string' || !password) {
        throw boundaryError('auth/lawyer-signup-invalid', 'Invalid lawyer signup payload.');
      }
      if (!supabaseClient?.auth?.admin?.getUserById ||
          !supabaseClient?.auth?.admin?.updateUserById) {
        throw boundaryError(
          'auth/lawyer-signup-unavailable',
          'Trusted Supabase Auth Admin is not configured.',
        );
      }

      const publicAuth = createPublicAuthClient();
      if (typeof publicAuth?.auth?.signUp !== 'function') {
        throw boundaryError(
          'auth/lawyer-signup-unavailable',
          'Public Supabase Auth signup is not configured.',
        );
      }

      const { data, error } = await publicAuth.auth.signUp({
        email: normalizedEmail,
        password,
        options: {
          emailRedirectTo: redirectTo,
          data: { name: displayName },
        },
      });
      if (error) {
        const code = String(error.code || error.status || '').toLowerCase();
        const message = String(error.message || '').toLowerCase();
        if (
          code.includes('already') ||
          code.includes('exists') ||
          code.includes('registered') ||
          message.includes('already registered') ||
          message.includes('already exists')
        ) {
          // Keep account existence indistinguishable to the public caller.
          return { accepted: true };
        }
        throw boundaryError('auth/lawyer-signup-failed', 'Supabase Auth signup failed.');
      }

      const createdUser = data?.user;
      const identities = createdUser?.identities;
      if (
        !createdUser?.id ||
        String(createdUser.email || '').trim().toLowerCase() !== normalizedEmail ||
        !Array.isArray(identities) ||
        identities.length === 0
      ) {
        // Supabase may return a synthetic user without identities for an
        // existing address. Do not promote or disclose that account.
        return { accepted: true };
      }

      if (data?.session) {
        // Auto-confirmed signup is not this flow: the trigger may already have
        // made a client profile, and this endpoint must never upgrade it.
        if (typeof publicAuth.auth.signOut === 'function') {
          try { await publicAuth.auth.signOut({ scope: 'local' }); } catch {}
        }
        return { accepted: true };
      }

      const { data: lookup, error: lookupError } =
        await supabaseClient.auth.admin.getUserById(createdUser.id);
      if (lookupError) {
        throw boundaryError('auth/lawyer-signup-failed', 'Could not verify the new Auth identity.');
      }
      const authUser = lookup?.user;
      if (
        !authUser ||
        authUser.id !== createdUser.id ||
        String(authUser.email || '').trim().toLowerCase() !== normalizedEmail ||
        authUser.email_confirmed_at
      ) {
        // A missing, mismatched, or already-confirmed identity is never
        // rewritten. Existing accounts are handled through support instead.
        return { accepted: true };
      }

      const appMetadata = authUser.app_metadata && typeof authUser.app_metadata === 'object'
        ? authUser.app_metadata
        : {};
      const { data: update, error: updateError } =
        await supabaseClient.auth.admin.updateUserById(createdUser.id, {
          app_metadata: { ...appMetadata, signup_role: 'lawyer' },
        });
      const updatedUser = update?.user;
      if (
        updateError ||
        !updatedUser ||
        updatedUser.id !== createdUser.id ||
        updatedUser.app_metadata?.signup_role !== 'lawyer' ||
        updatedUser.email_confirmed_at
      ) {
        throw boundaryError('auth/lawyer-signup-failed', 'Could not safely mark the new Auth identity.');
      }
      return { accepted: true };
    },

    async verifyIdToken(token) {
      if (typeof token !== 'string' || token.trim() === '') {
        const error = new Error('Invalid or expired Supabase access token.');
        error.code = 'auth/invalid-id-token';
        throw error;
      }
      const { data, error } = await supabaseClient.auth.getUser(token.trim());
      if (error || !data?.user) {
        const authError = new Error('Invalid or expired Supabase access token.');
        authError.code = 'auth/id-token-expired';
        throw authError;
      }

      const authUser = data.user;
      let { data: profile, error: profileError } = await supabaseClient
        .from('users')
        .select('id,uid,auth_user_id,name,email,role')
        .eq('auth_user_id', authUser.id)
        .maybeSingle();
      if (profileError) throw profileError;

      // Native profiles use their Auth UUID as `id`; migrated profiles retain
      // their existing application ID and point `auth_user_id` at the UUID.
      // Do not infer or create that link from an email match here.
      if (!profile) {
        const nativeProfile = await supabaseClient
          .from('users')
          .select('id,uid,auth_user_id,name,email,role')
          .eq('id', authUser.id)
          .maybeSingle();
        if (nativeProfile.error) throw nativeProfile.error;
        profile = nativeProfile.data;
      }

      if (
        !profile ||
        profile.uid !== profile.id ||
        (profile.auth_user_id != null && profile.auth_user_id !== authUser.id)
      ) {
        const authError = new Error('No application profile is linked to this Supabase Auth UUID.');
        authError.code = 'auth/profile-not-found';
        throw authError;
      }

      // Role is database-authoritative. Never turn a missing or unknown role
      // into `client`; unknown schema roles fail closed until explicitly added.
      const validRoles = new Set(['client', 'lawyer', 'admin', 'owner']);
      if (!validRoles.has(profile.role)) {
        const authError = new Error('The linked application profile has no valid role.');
        authError.code = 'auth/profile-role-invalid';
        throw authError;
      }

      return {
        uid: profile.id,
        authUserId: authUser.id,
        email: authUser.email || profile.email || '',
        name: profile.name || '',
        role: profile.role,
        email_verified: Boolean(authUser.email_confirmed_at),
      };
    },
  };
}

let cachedSupabaseClient = null;
let cachedDb = null;
let cachedAuth = null;
let cachedPublicSupabaseClient = null;
let cachedPublicDb = null;

export function isSupabaseConfigured(envVars = process.env) {
  const url = (envVars.SUPABASE_URL || env.supabaseUrl || '').trim();
  const key = (
    envVars.SUPABASE_SERVICE_ROLE_KEY ||
    env.supabaseServiceRoleKey ||
    ''
  ).trim();
  return Boolean(url && key);
}

/**
 * Creates a request-scoped PostgREST client using only the public anon key and
 * the verified caller JWT. Direct table access and security-definer RPCs then
 * execute under `authenticated` RLS instead of the backend service role.
 */
export function createSupabaseRequestDatabase(accessToken) {
  if (typeof accessToken !== 'string' || accessToken.trim() === '') {
    throw new Error('A verified Supabase access token is required.');
  }
  const url = (process.env.SUPABASE_URL || env.supabaseUrl || '').trim();
  const anonKey = (process.env.SUPABASE_ANON_KEY || env.supabaseAnonKey || '').trim();
  if (!url || !anonKey) {
    throw new Error('Supabase request-scoped access is not configured.');
  }
  const client = createClient(url, anonKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
    global: {
      headers: { Authorization: `Bearer ${accessToken.trim()}` },
    },
  });
  return createSupabaseDatabase(client, { authenticatedRequest: true });
}

export function initializeSupabase(customClient = null) {
  if (customClient) {
    cachedSupabaseClient = customClient;
    cachedDb = createSupabaseDatabase(customClient);
    cachedAuth = createSupabaseAuth(customClient, {
      requestDatabaseFactory: () =>
        createSupabaseDatabase(customClient, { authenticatedRequest: true }),
    });
    return { client: cachedSupabaseClient, db: cachedDb, auth: cachedAuth };
  }

  if (cachedSupabaseClient && cachedDb && cachedAuth) {
    return { client: cachedSupabaseClient, db: cachedDb, auth: cachedAuth };
  }

  const url = (process.env.SUPABASE_URL || env.supabaseUrl || '').trim();
  const serviceRoleKey = (
    process.env.SUPABASE_SERVICE_ROLE_KEY ||
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

/** Returns the process-wide privileged client for tightly scoped admin tasks. */
export function getDb() {
  return initializeSupabase().db;
}

/** Returns the server-side Supabase Auth Admin API adapter. */
export function getAuth() {
  return initializeSupabase().auth;
}

/**
 * Creates or returns an anon-key-only database client for unauthenticated
 * public reads. It must never be used for owner/admin operations.
 */
export function initializePublicSupabase(customClient = null) {
  if (customClient) {
    cachedPublicSupabaseClient = customClient;
    cachedPublicDb = createSupabaseDatabase(customClient);
    return { client: cachedPublicSupabaseClient, db: cachedPublicDb };
  }
  if (cachedPublicSupabaseClient && cachedPublicDb) {
    return { client: cachedPublicSupabaseClient, db: cachedPublicDb };
  }

  const url = (process.env.SUPABASE_URL || env.supabaseUrl || '').trim();
  const anonKey = (process.env.SUPABASE_ANON_KEY || env.supabaseAnonKey || '').trim();
  if (!url || !anonKey) {
    throw new Error(
      '[backend] Public Supabase access is not configured: set SUPABASE_URL and SUPABASE_ANON_KEY.',
    );
  }
  cachedPublicSupabaseClient = createClient(url, anonKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });
  cachedPublicDb = createSupabaseDatabase(cachedPublicSupabaseClient);
  return { client: cachedPublicSupabaseClient, db: cachedPublicDb };
}

export function getPublicDb() {
  return initializePublicSupabase().db;
}
