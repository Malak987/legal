/*
 * Test-only Supabase boundary installed into the temporary source copy by
 * harness.js. It leaves the real Express authentication/authorization
 * middleware and the real route code in place. Only the external Auth, public
 * PostgREST read, and caller-RPC boundaries are supplied by explicit test
 * fixtures; no production configuration or authorization code is changed.
 */

import { createHash } from 'node:crypto';
import { getAuth as getFixtureAuth, getDb as getFixtureDb } from './firebase.js';
import { fromDbRow, toDbRow } from './supabase.js';
import {
  createReservedBooking,
  loadAdvertisedSlots,
  planReservation,
} from '../utils/bookingReservation.js';
import {
  bookingInterval,
  formatClockTime,
  intervalsOverlap,
  parseClockTime,
} from '../utils/scheduling.js';

// Preserve every non-network adapter export (table specs, field conversion,
// document database constructor, and serializers) for the real route modules.
export * from './supabase.js';

function fx() {
  return (globalThis.__fx ??= {});
}

function requireFixtureCaller(token) {
  const caller = fx().user;
  if (!caller || typeof token !== 'string' || caller.token !== token) {
    throw new Error('A valid test-issued bearer token is required.');
  }
  return caller;
}

function rpcError(code, message, details = '') {
  const error = new Error(message);
  error.code = code;
  error.details = details;
  return error;
}

function isAdminRole(role) {
  return role === 'admin' || role === 'owner';
}

function records(table) {
  const state = fx();
  state.collections ??= {};
  state.collections[table] ??= [];
  return state.collections[table];
}

async function getRecord(db, table, id) {
  const snapshot = await db.collection(table).doc(id).get();
  return snapshot.exists ? { id: snapshot.id, ...(snapshot.data() || {}) } : null;
}

async function addRecord(db, table, value) {
  const ref = await db.collection(table).add(value);
  const snapshot = await ref.get();
  return { id: ref.id, ...(snapshot.data() || {}) };
}

function databaseRow(table, record) {
  return record ? toDbRow(table, record, record.id) : null;
}

function now() {
  return new Date().toISOString();
}

function getProfile(db, id) {
  return getRecord(db, 'users', id);
}

async function rpcCreateBooking(db, parameters, caller) {
  const lawyerId = parameters.p_lawyer_id;
  const date = parameters.p_date;
  const hours = Number(parameters.p_hours);
  const userId = parameters.p_user_id || caller.uid;
  if (!isAdminRole(caller.role) && userId !== caller.uid) {
    throw rpcError('42501', 'NOT_BOOKING_OWNER');
  }

  const lawyer = await getRecord(db, 'lawyers', lawyerId);
  if (!lawyer) return { error: 'LAWYER_NOT_FOUND' };
  if (typeof lawyer.priceValue !== 'number' || !Number.isFinite(lawyer.priceValue) || lawyer.priceValue < 0) {
    return { error: 'LAWYER_RATE_NOT_CONFIGURED' };
  }
  const startMinutes = parseClockTime(parameters.p_time);
  if (startMinutes === null) return { error: 'INVALID_BOOKING_TIME' };

  const advertised = await loadAdvertisedSlots(db, lawyerId, date);
  const plan = planReservation({ advertised, startMinutes, hours, lawyerId, date });
  if (plan.error) {
    return { error: advertised?.length ? 'TIME_NOT_AVAILABLE' : 'NO_AVAILABILITY' };
  }

  const booking = {
    userId,
    lawyerId,
    lawyerName: lawyer.name || '',
    date,
    time: formatClockTime(startMinutes),
    hours,
    totalPrice: Math.round(lawyer.priceValue * hours * 100) / 100,
    status: 'Pending',
  };
  const outcome = await createReservedBooking(db, {
    data: booking,
    lawyerId,
    date,
    startMinutes,
    hours,
    locks: plan.locks,
  });
  if (outcome.status !== 'created') {
    return { error: outcome.status === 'taken' ? 'SLOT_TAKEN' : 'BOOKING_OVERLAP' };
  }
  const saved = await getRecord(db, 'bookings', outcome.id);
  return { booking: databaseRow('bookings', saved), replayed: false };
}

async function changeBooking(db, id, changes, { caller, release = false } = {}) {
  const booking = await getRecord(db, 'bookings', id);
  if (!booking) throw rpcError('P0002', 'BOOKING_NOT_FOUND', 'BOOKING_NOT_FOUND');
  if (!isAdminRole(caller.role) && booking.userId !== caller.uid) {
    throw rpcError('42501', 'NOT_BOOKING_OWNER', 'NOT_BOOKING_OWNER');
  }
  const ref = db.collection('bookings').doc(id);
  await db.runTransaction(async (tx) => {
    const fresh = await tx.get(ref);
    if (!fresh.exists) throw rpcError('P0002', 'BOOKING_NOT_FOUND', 'BOOKING_NOT_FOUND');
    const current = fresh.data() || {};
    if (release) {
      for (const lockId of current.slotKeys || []) {
        tx.delete(db.collection('bookingSlots').doc(lockId));
      }
    }
    tx.update(ref, { ...changes, updatedAt: now() });
  });
  return databaseRow('bookings', await getRecord(db, 'bookings', id));
}

async function rpcDeleteBooking(db, parameters, caller) {
  const id = parameters.p_booking_id;
  const booking = await getRecord(db, 'bookings', id);
  if (!booking) throw rpcError('P0002', 'BOOKING_NOT_FOUND', 'BOOKING_NOT_FOUND');
  if (!isAdminRole(caller.role) && booking.userId !== caller.uid) {
    throw rpcError('42501', 'NOT_BOOKING_OWNER', 'NOT_BOOKING_OWNER');
  }
  const bookingRef = db.collection('bookings').doc(id);
  await db.runTransaction(async (tx) => {
    const current = await tx.get(bookingRef);
    if (!current.exists) throw rpcError('P0002', 'BOOKING_NOT_FOUND', 'BOOKING_NOT_FOUND');
    for (const lockId of current.data()?.slotKeys || []) {
      tx.delete(db.collection('bookingSlots').doc(lockId));
    }
    tx.delete(bookingRef);
  });
  return { id };
}

async function rpcAdminRescheduleBooking(db, parameters, caller) {
  if (!isAdminRole(caller.role)) throw rpcError('42501', 'ADMIN_REQUIRED', 'ADMIN_REQUIRED');
  const id = parameters.p_booking_id;
  const existing = await getRecord(db, 'bookings', id);
  if (!existing) throw rpcError('P0002', 'BOOKING_NOT_FOUND', 'BOOKING_NOT_FOUND');
  const lawyerId = parameters.p_lawyer_id;
  const date = parameters.p_date;
  const hours = Number(parameters.p_hours);
  const startMinutes = parseClockTime(parameters.p_time);
  const lawyer = await getRecord(db, 'lawyers', lawyerId);
  if (!lawyer) return { error: 'LAWYER_NOT_FOUND' };
  if (typeof lawyer.priceValue !== 'number' || !Number.isFinite(lawyer.priceValue) || lawyer.priceValue < 0) {
    return { error: 'LAWYER_RATE_NOT_CONFIGURED' };
  }
  const advertised = await loadAdvertisedSlots(db, lawyerId, date);
  const plan = planReservation({ advertised, startMinutes, hours, lawyerId, date });
  if (plan.error) return { error: advertised?.length ? 'TIME_NOT_AVAILABLE' : 'NO_AVAILABILITY' };

  const bookingRef = db.collection('bookings').doc(id);
  let transactionOutcome;
  await db.runTransaction(async (tx) => {
    const fresh = await tx.get(bookingRef);
    if (!fresh.exists) throw rpcError('P0002', 'BOOKING_NOT_FOUND', 'BOOKING_NOT_FOUND');
    const current = { id, ...(fresh.data() || {}) };
    const newIds = new Set(plan.locks.map((lock) => lock.id));

    for (const lock of plan.locks) {
      const lockRef = db.collection('bookingSlots').doc(lock.id);
      const held = await tx.get(lockRef);
      if (held.exists && held.data()?.bookingId !== id) {
        transactionOutcome = { error: 'SLOT_TAKEN' };
        return;
      }
    }

    const bookingSnapshot = await db.collection('bookings').get();
    const wanted = { start: startMinutes, end: startMinutes + hours * 60 };
    for (const document of bookingSnapshot.docs) {
      const row = { id: document.id, ...(document.data() || {}) };
      if (row.id === id || row.lawyerId !== lawyerId || row.date !== date || row.status === 'Cancelled') continue;
      if (intervalsOverlap(bookingInterval(row), wanted)) {
        transactionOutcome = { error: 'BOOKING_OVERLAP' };
        return;
      }
    }

    for (const oldId of current.slotKeys || []) {
      if (!newIds.has(oldId)) tx.delete(db.collection('bookingSlots').doc(oldId));
    }
    for (const lock of plan.locks) {
      tx.set(db.collection('bookingSlots').doc(lock.id), {
        lawyerId,
        date,
        slot: lock.slot,
        bookingId: id,
        userId: current.userId,
        createdAt: now(),
      });
    }
    tx.update(bookingRef, {
      lawyerId,
      lawyerName: lawyer.name || '',
      date,
      time: formatClockTime(startMinutes),
      hours,
      totalPrice: Math.round(lawyer.priceValue * hours * 100) / 100,
      slotKeys: [...newIds],
      updatedAt: now(),
    });
    transactionOutcome = { saved: true };
  });
  if (transactionOutcome?.error) return transactionOutcome;
  return databaseRow('bookings', await getRecord(db, 'bookings', id));
}

async function rpcWalletMutate(db, parameters, caller) {
  const userId = parameters.p_user_id;
  const type = parameters.p_type;
  const amount = Number(parameters.p_amount);
  const description = String(parameters.p_description || '').slice(0, 300);
  const rawKey = typeof parameters.p_idempotency_id === 'string' && parameters.p_idempotency_id
    ? parameters.p_idempotency_id
    : null;
  if (!userId || !['credit', 'debit'].includes(type) || !Number.isFinite(amount) || amount <= 0) {
    return { error: 'INVALID_TRANSACTION' };
  }
  if (!isAdminRole(caller.role) && (caller.uid !== userId || type === 'credit')) {
    throw rpcError('42501', 'WALLET_OPERATION_NOT_AUTHORIZED');
  }

  const userRef = db.collection('users').doc(userId);
  const walletRef = db.collection('wallets').doc(userId);
  const digest = rawKey
    ? createHash('sha256').update(`${userId}\u0000${rawKey}`).digest('hex')
    : null;
  const idempotencyRef = digest ? db.collection('wallet_idempotency').doc(digest) : null;
  const transactionRef = db.collection('wallet_transactions').doc();
  let outcome;

  await db.runTransaction(async (tx) => {
    const user = await tx.get(userRef);
    if (!user.exists) {
      outcome = { error: 'UNKNOWN_USER' };
      return;
    }
    const wallet = await tx.get(walletRef);
    const previousWallet = wallet.exists ? wallet.data() || {} : {};
    const currency = previousWallet.currency || 'USD';
    if (currency !== 'USD') {
      outcome = { error: 'CURRENCY_MISMATCH', currency };
      return;
    }

    const currentCents = Math.round(Number(previousWallet.balance || 0) * 100);
    if (idempotencyRef) {
      const previous = await tx.get(idempotencyRef);
      if (previous.exists) {
        const old = previous.data() || {};
        if (old.type !== type || Number(old.amount) !== amount || old.currency !== 'USD') {
          outcome = { error: 'IDEMPOTENCY_KEY_MISMATCH' };
          return;
        }
        outcome = {
          balance: Number(old.balance),
          transaction: old.transaction,
          replayed: true,
        };
        return;
      }
    }

    const deltaCents = Math.round(amount * 100);
    const balanceCents = type === 'credit' ? currentCents + deltaCents : currentCents - deltaCents;
    if (balanceCents < 0) {
      outcome = { error: 'INSUFFICIENT_FUNDS' };
      return;
    }
    const balance = balanceCents / 100;
    const timestamp = now();
    const transaction = {
      id: transactionRef.id,
      userId,
      type,
      amount,
      description,
      balance,
      currency: 'USD',
      ...(digest ? { idempotencyKeyHash: digest } : {}),
      createdAt: timestamp,
    };
    const rawTransaction = databaseRow('wallet_transactions', transaction);
    const nextWallet = {
      ...previousWallet,
      id: userId,
      userId,
      balance,
      currency: 'USD',
      createdAt: previousWallet.createdAt || timestamp,
      updatedAt: timestamp,
    };

    tx.set(walletRef, nextWallet);
    tx.set(transactionRef, transaction);
    if (idempotencyRef) {
      tx.set(idempotencyRef, {
        id: digest,
        userId,
        type,
        amount,
        currency: 'USD',
        balance,
        transaction: rawTransaction,
        createdAt: timestamp,
      });
    }
    outcome = { balance, transaction: rawTransaction, replayed: false };
  });
  return outcome;
}

async function rpcTaskUpdate(db, parameters, caller) {
  const id = parameters.p_task_id;
  const existing = await getRecord(db, 'tasks', id);
  if (!existing) throw rpcError('P0002', 'TASK_NOT_FOUND', 'TASK_NOT_FOUND');
  if (!isAdminRole(caller.role) && existing.userId !== caller.uid) {
    throw rpcError('42501', 'TASK_UPDATE_NOT_AUTHORIZED');
  }
  const rawChanges = parameters.p_changes || {};
  const changes = fromDbRow('tasks', rawChanges);
  if (!Object.hasOwn(rawChanges, 'due_date') && !Object.hasOwn(rawChanges, 'dueDate')) {
    delete changes.dueDate;
  }
  delete changes.id;
  await db.collection('tasks').doc(id).update({ ...changes, updatedAt: now() });
  return databaseRow('tasks', await getRecord(db, 'tasks', id));
}

async function rpcNotificationUpdate(db, parameters, caller) {
  const id = parameters.p_notification_id;
  const existing = await getRecord(db, 'notifications', id);
  if (!existing) throw rpcError('P0002', 'NOTIFICATION_NOT_FOUND', 'NOTIFICATION_NOT_FOUND');
  if (!isAdminRole(caller.role) && existing.userId !== caller.uid) {
    throw rpcError('42501', 'NOTIFICATION_UPDATE_NOT_AUTHORIZED');
  }
  const changes = fromDbRow('notifications', parameters.p_changes || {});
  delete changes.id;
  if (!isAdminRole(caller.role) && changes.userId !== undefined && changes.userId !== existing.userId) {
    throw rpcError('42501', 'NOTIFICATION_OWNER_CHANGE_FORBIDDEN');
  }
  await db.collection('notifications').doc(id).update({ ...changes, updatedAt: now() });
  return databaseRow('notifications', await getRecord(db, 'notifications', id));
}

async function rpcSubscriptionCreate(db, parameters, caller) {
  const userId = parameters.p_user_id || caller.uid;
  if (!isAdminRole(caller.role) && userId !== caller.uid) {
    throw rpcError('42501', 'SUBSCRIPTION_OWNER_REQUIRED');
  }
  const user = await getProfile(db, userId);
  if (!user) return { error: 'UNKNOWN_USER' };
  const plan = await getRecord(db, 'plans', parameters.p_plan_id);
  if (!plan) return { error: 'UNKNOWN_PLAN' };
  const subscription = await addRecord(db, 'subscriptions', {
    userId,
    planId: plan.id,
    planTitle: plan.title,
    status: 'Pending',
    startDate: new Date().toISOString().slice(0, 10),
    endDate: null,
    createdAt: now(),
    updatedAt: now(),
  });
  return databaseRow('subscriptions', subscription);
}

async function rpcSubscriptionCancel(db, parameters, caller) {
  const id = parameters.p_subscription_id;
  const subscription = await getRecord(db, 'subscriptions', id);
  if (!subscription) throw rpcError('P0002', 'SUBSCRIPTION_NOT_FOUND', 'SUBSCRIPTION_NOT_FOUND');
  if (!isAdminRole(caller.role) && subscription.userId !== caller.uid) {
    throw rpcError('42501', 'SUBSCRIPTION_OWNER_REQUIRED');
  }
  await db.collection('subscriptions').doc(id).update({ status: 'Cancelled', updatedAt: now() });
  return databaseRow('subscriptions', await getRecord(db, 'subscriptions', id));
}

async function rpcSubscriptionDelete(db, parameters, caller) {
  const id = parameters.p_subscription_id;
  const subscription = await getRecord(db, 'subscriptions', id);
  if (!subscription) throw rpcError('P0002', 'SUBSCRIPTION_NOT_FOUND', 'SUBSCRIPTION_NOT_FOUND');
  if (!isAdminRole(caller.role) && subscription.userId !== caller.uid) {
    throw rpcError('42501', 'SUBSCRIPTION_OWNER_REQUIRED');
  }
  if (subscription.status === 'Active' && !isAdminRole(caller.role)) {
    throw rpcError('42501', 'ACTIVE_SUBSCRIPTION_DELETE_FORBIDDEN');
  }
  await db.collection('subscriptions').doc(id).delete();
  return { id };
}

async function rpcChatCreate(db, parameters, caller) {
  const participants = parameters.p_participants;
  if (!Array.isArray(participants) || participants.length < 2 || new Set(participants).size !== participants.length) {
    throw rpcError('22023', 'Invalid chat participants', 'CHAT_PARTICIPANTS_INVALID');
  }
  if (!isAdminRole(caller.role) && !participants.includes(caller.uid)) {
    throw rpcError('42501', 'CHAT_CREATE_NOT_AUTHORIZED', 'CHAT_CREATE_NOT_AUTHORIZED');
  }
  const participantNames = {};
  for (const participantId of participants) {
    const profile = await getProfile(db, participantId);
    if (!profile) throw rpcError('22023', 'Chat participant not found', 'CHAT_PARTICIPANT_NOT_FOUND');
    participantNames[participantId] = profile.name || '';
  }
  const chat = await addRecord(db, 'chats', {
    participants,
    participantNames,
    lastMessage: '',
    createdAt: now(),
    updatedAt: now(),
  });
  return { chat: databaseRow('chats', chat) };
}

async function rpcChatSendMessage(db, parameters, caller) {
  const chatId = parameters.p_chat_id;
  const chat = await getRecord(db, 'chats', chatId);
  if (!chat) throw rpcError('P0002', 'CHAT_NOT_FOUND', 'CHAT_NOT_FOUND');
  if (!isAdminRole(caller.role) && !chat.participants?.includes(caller.uid)) {
    throw rpcError('42501', 'CHAT_PARTICIPANT_REQUIRED');
  }
  const profile = await getProfile(db, caller.uid);
  const messageText = String(parameters.p_text || '').trim();
  if (!messageText) throw rpcError('22023', 'Message text is required', 'MESSAGE_TEXT_REQUIRED');

  const chatRef = db.collection('chats').doc(chatId);
  const messageRef = db.collection(`chats/${chatId}/messages`).doc();
  const message = {
    senderId: caller.uid,
    senderName: profile?.name || caller.name || 'User',
    text: messageText,
    createdAt: now(),
  };
  await db.runTransaction(async (tx) => {
    const fresh = await tx.get(chatRef);
    if (!fresh.exists) throw rpcError('P0002', 'CHAT_NOT_FOUND', 'CHAT_NOT_FOUND');
    tx.set(messageRef, message);
    tx.update(chatRef, { lastMessage: messageText, updatedAt: now() });
  });
  return databaseRow('messages', { id: messageRef.id, chatId, ...message });
}

async function rpcFavoriteAdd(db, parameters, caller) {
  const lawyer = await getRecord(db, 'lawyers', parameters.p_lawyer_id);
  if (!lawyer) throw rpcError('23503', 'lawyerId does not identify an available lawyer');
  const favorite = await addRecord(db, 'favorites', {
    userId: caller.uid,
    lawyerId: lawyer.id,
    createdAt: now(),
  });
  return databaseRow('favorites', favorite);
}

async function recalculateRating(db, lawyerId) {
  const lawyer = await getRecord(db, 'lawyers', lawyerId);
  if (!lawyer) return;
  const ratings = records('reviews')
    .filter((review) => review.lawyerId === lawyerId)
    .map((review) => Number(review.rating))
    .filter((rating) => Number.isFinite(rating));
  const rating = ratings.length
    ? Math.round((ratings.reduce((sum, value) => sum + value, 0) / ratings.length) * 10) / 10
    : 0;
  await db.collection('lawyers').doc(lawyerId).update({ rating, updatedAt: now() });
}

async function rpcReviewSubmit(db, parameters, caller) {
  const lawyer = await getRecord(db, 'lawyers', parameters.p_lawyer_id);
  if (!lawyer) throw rpcError('22023', 'LAWYER_NOT_FOUND', 'LAWYER_NOT_FOUND');
  const prior = records('reviews').find(
    (review) => review.userId === caller.uid && review.lawyerId === parameters.p_lawyer_id,
  );
  if (prior) return { error: 'DUPLICATE_REVIEW' };
  const profile = await getProfile(db, caller.uid);
  const review = await addRecord(db, 'reviews', {
    userId: caller.uid,
    userName: profile?.name || caller.name || '',
    lawyerId: parameters.p_lawyer_id,
    rating: Number(parameters.p_rating),
    comment: String(parameters.p_comment || ''),
    createdAt: now(),
    updatedAt: now(),
  });
  await recalculateRating(db, parameters.p_lawyer_id);
  return databaseRow('reviews', review);
}

async function rpcAdminReviewModerate(db, parameters, caller) {
  if (!isAdminRole(caller.role)) throw rpcError('42501', 'ADMIN_REQUIRED');
  const id = parameters.p_review_id;
  const review = await getRecord(db, 'reviews', id);
  if (!review) throw rpcError('P0002', 'REVIEW_NOT_FOUND', 'REVIEW_NOT_FOUND');
  const changes = {};
  if (parameters.p_rating !== null && parameters.p_rating !== undefined) changes.rating = Number(parameters.p_rating);
  if (parameters.p_comment !== null && parameters.p_comment !== undefined) changes.comment = String(parameters.p_comment);
  await db.collection('reviews').doc(id).update({ ...changes, updatedAt: now() });
  const updated = await getRecord(db, 'reviews', id);
  await recalculateRating(db, review.lawyerId);
  return databaseRow('reviews', updated);
}

async function rpcAdminReviewDelete(db, parameters, caller) {
  if (!isAdminRole(caller.role)) throw rpcError('42501', 'ADMIN_REQUIRED');
  const id = parameters.p_review_id;
  const review = await getRecord(db, 'reviews', id);
  if (!review) throw rpcError('P0002', 'REVIEW_NOT_FOUND', 'REVIEW_NOT_FOUND');
  await db.collection('reviews').doc(id).delete();
  await recalculateRating(db, review.lawyerId);
  return { id };
}

async function rpcAdminSetUserRole(db, parameters, caller) {
  if (!isAdminRole(caller.role)) throw rpcError('42501', 'ADMIN_REQUIRED');
  const id = parameters.p_user_id;
  const user = await getRecord(db, 'users', id);
  if (!user) throw rpcError('P0002', 'USER_NOT_FOUND', 'USER_NOT_FOUND');
  const role = parameters.p_role;
  if (user.role === 'owner' && role !== 'owner') {
    throw rpcError('42501', 'OWNER_ROLE_TRUSTED_ONLY', 'OWNER_ROLE_TRUSTED_ONLY');
  }
  if (user.role === 'admin' && role !== 'admin' && records('users').filter((item) => item.role === 'admin').length <= 1) {
    throw rpcError('42501', 'LAST_ADMIN_REQUIRED', 'LAST_ADMIN_REQUIRED');
  }
  await db.collection('users').doc(id).update({ role, updatedAt: now() });
  return databaseRow('users', await getRecord(db, 'users', id));
}

function rpcDashboardStats() {
  const all = (name) => records(name);
  const bookings = all('bookings');
  return {
    users: all('users').length,
    lawyers: all('lawyers').length,
    cases: all('cases').length,
    bookings: bookings.length,
    reviews: all('reviews').length,
    plans: all('plans').length,
    subscriptions: all('subscriptions').length,
    activeBookings: bookings.filter((booking) => booking.status === 'Active').length,
    completedBookings: bookings.filter((booking) => booking.status === 'Completed').length,
    cancelledBookings: bookings.filter((booking) => booking.status === 'Cancelled').length,
    walletBalance: all('wallets').reduce((sum, wallet) => sum + Number(wallet.balance || 0), 0),
  };
}

const defaultRpcHandlers = {
  rpc_create_booking: rpcCreateBooking,
  rpc_cancel_booking: async (db, parameters, caller) => {
    const booking = await getRecord(db, 'bookings', parameters.p_booking_id);
    if (!booking) throw rpcError('P0002', 'BOOKING_NOT_FOUND', 'BOOKING_NOT_FOUND');
    if (booking.status === 'Completed' || booking.status === 'Cancelled') {
      throw rpcError('42501', 'BOOKING_CANNOT_BE_CANCELLED', 'BOOKING_CANNOT_BE_CANCELLED');
    }
    return changeBooking(db, parameters.p_booking_id, { status: 'Cancelled', slotKeys: [] }, { caller, release: true });
  },
  rpc_admin_reschedule_booking: rpcAdminRescheduleBooking,
  rpc_admin_set_booking_status: async (db, parameters, caller) => {
    if (!isAdminRole(caller.role)) throw rpcError('42501', 'ADMIN_REQUIRED', 'ADMIN_REQUIRED');
    return changeBooking(
      db,
      parameters.p_booking_id,
      {
        status: parameters.p_status,
        ...(parameters.p_status === 'Cancelled' ? { slotKeys: [] } : {}),
      },
      { caller, release: parameters.p_status === 'Cancelled' },
    );
  },
  rpc_delete_booking: rpcDeleteBooking,
  rpc_wallet_mutate: rpcWalletMutate,
  rpc_task_update: rpcTaskUpdate,
  rpc_notification_update: rpcNotificationUpdate,
  rpc_subscription_create: rpcSubscriptionCreate,
  rpc_subscription_cancel: rpcSubscriptionCancel,
  rpc_subscription_delete: rpcSubscriptionDelete,
  rpc_chat_create: rpcChatCreate,
  rpc_chat_send_message: rpcChatSendMessage,
  rpc_favorite_add: rpcFavoriteAdd,
  rpc_review_submit: rpcReviewSubmit,
  rpc_admin_review_moderate: rpcAdminReviewModerate,
  rpc_admin_review_delete: rpcAdminReviewDelete,
  rpc_admin_set_user_role: rpcAdminSetUserRole,
  rpc_dashboard_stats: async (_db, _parameters, caller) => {
    if (!isAdminRole(caller.role)) throw rpcError('42501', 'ADMIN_REQUIRED');
    return rpcDashboardStats();
  },
};

/**
 * Returns the fixture verifier and an in-memory caller database. The database
 * marker is only present after the token fixture is accepted by the real
 * middleware. Route authorization remains real; test-only RPC handlers model
 * the request/response contract while PGlite tests exercise the local SQL.
 */
export function getAuth() {
  const fixtureAuth = getFixtureAuth();
  return {
    ...fixtureAuth,
    async createLawyerSignup(input) {
      const state = fx();
      state.lawyerSignupCalls ??= [];
      state.lawyerSignupCalls.push(structuredClone(input));
      const handler = state.lawyerSignupHandler;
      if (typeof handler === 'function') return handler(structuredClone(input));
      return { accepted: true };
    },
    createRequestDatabase(token) {
      const caller = requireFixtureCaller(token);
      const requestDb = Object.create(getFixtureDb());
      Object.defineProperties(requestDb, {
        _isAuthenticatedRequest: { value: true, enumerable: false },
        rpcAsUser: {
          value: async (functionName, parameters = {}) => {
            const state = fx();
            state.rpcCalls ??= [];
            state.rpcCalls.push({
              functionName,
              parameters: structuredClone(parameters),
              uid: caller.uid,
            });
            const handler = state.rpcHandlers?.[functionName] || defaultRpcHandlers[functionName];
            if (typeof handler !== 'function') {
              throw new Error(`No test RPC handler registered for ${functionName}.`);
            }
            return handler(getFixtureDb(), parameters, caller);
          },
          enumerable: false,
        },
      });
      return requestDb;
    },
  };
}

/** Anonymous catalogue routes use the isolated fixture store, never a network client. */
export function getPublicDb() {
  return getFixtureDb();
}

/** Test helper for asserting API-safe SQL row construction when needed. */
export { fromDbRow, toDbRow };
