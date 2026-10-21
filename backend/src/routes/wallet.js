import { createHash, randomUUID } from 'node:crypto';

import { Router } from 'express';
import { getDb } from '../config/firebase.js';
import {
  authenticate,
  requireSelfOrAdmin,
  isAdmin,
  forbidden,
} from '../middleware/auth.js';
import { ok, created, badRequest, conflict, notFound } from '../utils/response.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import {
  getDocById,
  serverTimestamp,
  sortByDesc,
} from '../utils/firestore.js';

const router = Router();
const TX_COLLECTION = 'wallet_transactions';
const WALLET_COLLECTION = 'wallets';
const IDEMPOTENCY_COLLECTION = 'wallet_idempotency';
const USERS_COLLECTION = 'users';
const TX_HISTORY_LIMIT = 20;

// Money rules. The wallet is a single USD ledger, so the currency's minor unit
// is the cent: amounts may carry at most two decimals and everything is
// computed in integer cents to avoid binary floating-point drift.
const CURRENCY = 'USD';
const MINOR_UNITS_PER_UNIT = 100;
const MAX_TRANSACTION_AMOUNT = 1_000_000;

// Longest accepted idempotency key. Longer input is REJECTED with 400 rather
// than silently truncated: a truncated key would make two different client
// operations look identical, which for money is worse than a hard failure.
const MAX_IDEMPOTENCY_KEY_LENGTH = 128;

/**
 * Validates a monetary amount and returns it rounded to the currency's minor
 * unit, or `null` when it is not a usable amount.
 *
 * Rejects: non-numbers, `NaN`/`Infinity`, zero, negatives, values above the
 * cap, and amounts with more precision than the currency supports.
 */
function normalizeAmount(raw) {
  if (typeof raw !== 'number' || !Number.isFinite(raw)) return null;
  if (raw <= 0) return null;
  if (raw > MAX_TRANSACTION_AMOUNT) return null;

  const cents = Math.round(raw * MINOR_UNITS_PER_UNIT);
  if (cents <= 0) return null;
  // More than two decimals — refuse rather than silently round money away.
  if (Math.abs(raw * MINOR_UNITS_PER_UNIT - cents) > 1e-6) return null;
  return cents / MINOR_UNITS_PER_UNIT;
}

const toCents = (units) => Math.round(Number(units ?? 0) * MINOR_UNITS_PER_UNIT);

/**
 * Reads an optional idempotency key from the body or the standard header.
 *
 * The body wins only when it actually carries a value: an empty or blank
 * `idempotencyKey` falls back to the `Idempotency-Key` header instead of
 * silently switching idempotency off for a request that did supply a header.
 *
 * Returns `{ key }` on success, `{ error }` when the supplied value is not
 * usable, and `{ key: null }` when neither source carried one.
 */
function readIdempotencyKey(req) {
  const fromBody = req.body?.idempotencyKey;
  const fromHeader = req.get('Idempotency-Key');

  if (fromBody !== undefined && typeof fromBody !== 'string') {
    return { error: 'idempotencyKey must be a string' };
  }

  const bodyKey = typeof fromBody === 'string' ? fromBody.trim() : '';
  const headerKey = typeof fromHeader === 'string' ? fromHeader.trim() : '';
  const raw = bodyKey || headerKey;
  if (!raw) return { key: null };

  if (raw.length > MAX_IDEMPOTENCY_KEY_LENGTH) {
    return {
      error: `idempotencyKey must be at most ${MAX_IDEMPOTENCY_KEY_LENGTH} characters`,
    };
  }
  return { key: raw };
}

/**
 * Deterministic document id for an idempotency record.
 *
 * Firestore transactions only guarantee uniqueness on DOCUMENTS they read — a
 * `where('idempotencyKey','==',…)` lookup inside a transaction gets no phantom
 * protection, so two concurrent requests could both "not find" the key and
 * both write. Hashing the owner and the key into a document id makes the
 * guarantee structural: both requests address the SAME document, and
 * Firestore's conflict detection on that read is sufficient.
 *
 * The owner is part of the hash, so one user's key can never collide with (or
 * probe) another's.
 */
function idempotencyDocId(userId, key) {
  return createHash('sha256').update(`${userId}\u0000${key}`).digest('hex');
}

// GET /api/wallet/:userId  -> balance + recent transactions
router.get(
  '/:userId',
  authenticate,
  requireSelfOrAdmin('userId'),
  asyncHandler(async (req, res) => {
    const { userId } = req.params;

    const wallet = await getDocById(getDb(), WALLET_COLLECTION, userId);

    // Firestore needs a COMPOSITE index to combine `where('userId','==')` with
    // `orderBy('createdAt','desc')`, and that index is not deployed for this
    // project — the query was rejected with `9 FAILED_PRECONDITION` and the
    // route answered 500. The filter stays server-side (never fetch another
    // user's transactions and filter in the client); only the ordering and the
    // limit move into memory.
    const txSnap = await getDb()
      .collection(TX_COLLECTION)
      .where('userId', '==', userId)
      .get();

    const transactions = sortByDesc(
      txSnap.docs.map((d) => ({ id: d.id, ...d.data() })),
      'createdAt',
    ).slice(0, TX_HISTORY_LIMIT);

    ok(res, {
      balance: wallet?.balance ?? 0,
      currency: wallet?.currency ?? CURRENCY,
      transactions,
    });
  }),
);

// POST /api/wallet/transactions  { userId, type, amount, description?, idempotencyKey? }
//
// Only an administrator may CREDIT a wallet. The client saying `type: 'credit'`,
// or owning the wallet it targets, is not evidence that money was received —
// that requires a verified payment result produced by the server, which does
// not exist yet (see the report: real top-ups need a provider webhook).
//
// A user may still DEBIT (spend from) their own wallet, which can never create
// money, and an administrator may move funds for any account.
router.post(
  '/transactions',
  authenticate,
  asyncHandler(async (req, res) => {
    const { userId, type, amount, description } = req.body || {};

    if (!userId || !['credit', 'debit'].includes(type)) {
      return badRequest(res, 'userId and type (credit|debit) are required');
    }

    const normalizedAmount = normalizeAmount(amount);
    if (normalizedAmount === null) {
      return badRequest(
        res,
        `amount must be a positive number up to ${MAX_TRANSACTION_AMOUNT} ` +
          `with at most 2 decimal places`,
      );
    }

    if (!isAdmin(req) && req.user.uid !== userId) {
      return forbidden(res, 'Forbidden. You can only transact on your own wallet.');
    }

    // Crediting is a privileged operation: without a verified payment result
    // there is nothing that distinguishes a legitimate top-up from free money.
    if (type === 'credit' && !isAdmin(req)) {
      return forbidden(res, 'Forbidden. Only an administrator can credit a wallet.');
    }

    const keyResult = readIdempotencyKey(req);
    if (keyResult.error) {
      return badRequest(res, keyResult.error);
    }
    const rawKey = keyResult.key;

    const db = getDb();
    const walletRef = db.collection(WALLET_COLLECTION).doc(userId);
    // A wallet must belong to a real account. Without this check an admin typo
    // creates an orphan balance that no user can ever see but that still counts
    // towards the dashboard total.
    const userRef = db.collection(USERS_COLLECTION).doc(userId);
    const transactionId = randomUUID();
    const transactionRef = db.collection(TX_COLLECTION).doc(transactionId);
    // Deterministic id: the SAME (owner, key) pair always maps to the same
    // document, so Firestore's per-document conflict detection — not an
    // unindexed query — is what makes the operation idempotent.
    const idempotencyRef = rawKey
      ? db.collection(IDEMPOTENCY_COLLECTION).doc(idempotencyDocId(userId, rawKey))
      : null;
    const idempotencyKeyHash = idempotencyRef ? idempotencyRef.id : null;

    const outcome = await db.runTransaction(async (tx) => {
      const userSnap = await tx.get(userRef);
      if (!userSnap.exists) {
        return { status: 'unknown_user' };
      }

      const walletSnap = await tx.get(walletRef);
      const walletData = walletSnap.exists ? walletSnap.data() ?? {} : null;
      const current = walletData?.balance ?? 0;
      const currentCents = toCents(current);

      // Never reinterpret an existing balance in another currency: adding
      // "10" to a wallet denominated in EGP would silently relabel money.
      const existingCurrency = walletData?.currency;
      if (existingCurrency && existingCurrency !== CURRENCY) {
        return { status: 'currency_mismatch', currency: existingCurrency };
      }

      if (idempotencyRef) {
        const idempotencySnap = await tx.get(idempotencyRef);
        if (idempotencySnap.exists) {
          const previous = idempotencySnap.data() ?? {};

          // Same key, different operation → refuse. Replaying the first
          // result would tell the caller that a 500 credit "succeeded".
          const sameOperation =
            previous.userId === userId &&
            previous.type === type &&
            previous.amount === normalizedAmount &&
            previous.currency === CURRENCY;

          if (!sameOperation) {
            return {
              status: 'idempotency_conflict',
              previous: {
                type: previous.type,
                amount: previous.amount,
                currency: previous.currency,
              },
            };
          }

          return {
            status: 'duplicate',
            balance: previous.balance,
            transaction: previous.transaction,
          };
        }
      }

      const deltaCents = Math.round(normalizedAmount * MINOR_UNITS_PER_UNIT);
      const nextCents =
        type === 'credit' ? currentCents + deltaCents : currentCents - deltaCents;

      if (nextCents < 0) {
        return { status: 'insufficient' };
      }

      const balance = nextCents / MINOR_UNITS_PER_UNIT;
      const record = {
        userId,
        type,
        amount: normalizedAmount,
        description: typeof description === 'string' ? description.slice(0, 300) : '',
        balance,
        currency: CURRENCY,
        ...(idempotencyKeyHash ? { idempotencyKeyHash } : {}),
      };
      const transaction = { id: transactionId, ...record };

      // Balance, ledger row and idempotency record are one atomic unit: either
      // all land or none of them do.
      tx.set(
        walletRef,
        {
          userId,
          balance,
          currency: CURRENCY,
          ...(walletData ? {} : { createdAt: serverTimestamp() }),
          updatedAt: serverTimestamp(),
        },
        { merge: true },
      );
      // `updatedAt` keeps the document shape `createDoc()` used to produce.
      tx.set(transactionRef, {
        ...record,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });

      if (idempotencyRef) {
        tx.set(idempotencyRef, {
          userId,
          type,
          amount: normalizedAmount,
          currency: CURRENCY,
          balance,
          transaction,
          createdAt: serverTimestamp(),
        });
      }

      return { status: 'created', balance, transaction };
    });

    if (outcome.status === 'unknown_user') {
      return notFound(res, 'User not found');
    }
    if (outcome.status === 'insufficient') {
      return badRequest(res, 'Insufficient balance');
    }
    if (outcome.status === 'currency_mismatch') {
      return conflict(
        res,
        `Wallet currency is ${outcome.currency}, not ${CURRENCY}. ` +
          'Refusing to mix currencies.',
      );
    }
    if (outcome.status === 'idempotency_conflict') {
      return conflict(
        res,
        'idempotencyKey was already used for a different transaction.',
        outcome.previous,
      );
    }
    if (outcome.status === 'duplicate') {
      return ok(
        res,
        { balance: outcome.balance, transaction: outcome.transaction },
        'Duplicate request ignored',
      );
    }
    return created(
      res,
      { balance: outcome.balance, transaction: outcome.transaction },
      'Transaction added',
    );
  }),
);

export default router;
