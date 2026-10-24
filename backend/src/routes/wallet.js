import { Router } from 'express';
import { fromDbRow } from '../config/supabase.js';
import { requestDatabase, callUserRpc } from '../utils/supabase_rpc.js';
import {
  authenticate,
  requireSelfOrAdmin,
  isAdmin,
  forbidden,
} from '../middleware/auth.js';
import { ok, created, badRequest, conflict, notFound } from '../utils/response.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { getDocById, sortByDesc } from '../utils/supabase_database.js';

const router = Router();
const TX_COLLECTION = 'wallet_transactions';
const WALLET_COLLECTION = 'wallets';
const TX_HISTORY_LIMIT = 20;
const CURRENCY = 'USD';
const MAX_TRANSACTION_AMOUNT = 1_000_000;
const MAX_IDEMPOTENCY_KEY_LENGTH = 128;

function normalizeAmount(raw) {
  if (typeof raw !== 'number' || !Number.isFinite(raw)) return null;
  if (raw <= 0 || raw > MAX_TRANSACTION_AMOUNT) return null;
  const cents = Math.round(raw * 100);
  if (cents <= 0 || Math.abs(raw * 100 - cents) > 1e-6) return null;
  return cents / 100;
}

function readIdempotencyKey(req) {
  const fromBody = req.body?.idempotencyKey;
  const fromHeader = req.get('Idempotency-Key');
  if (fromBody !== undefined && typeof fromBody !== 'string') {
    return { error: 'idempotencyKey must be a string' };
  }
  const raw = (typeof fromBody === 'string' ? fromBody.trim() : '') ||
    (typeof fromHeader === 'string' ? fromHeader.trim() : '');
  if (!raw) return { key: null };
  if (raw.length > MAX_IDEMPOTENCY_KEY_LENGTH) {
    return { error: `idempotencyKey must be at most ${MAX_IDEMPOTENCY_KEY_LENGTH} characters` };
  }
  return { key: raw };
}

// GET /api/wallet/:userId -> balance + recent transactions.
router.get(
  '/:userId',
  authenticate,
  requireSelfOrAdmin('userId'),
  asyncHandler(async (req, res) => {
    const { userId } = req.params;
    const db = requestDatabase(req);
    const wallet = await getDocById(db, WALLET_COLLECTION, userId);
    // RLS restricts the underlying query to the current user's rows (or all
    // rows for the verified admin role); sorting/limiting is only presentation.
    const txSnap = await db.collection(TX_COLLECTION).where('userId', '==', userId).get();
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

// POST /api/wallet/transactions. Credits require an administrator; enabling
// real top-ups also requires a verified payment-provider webhook.
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
        `amount must be a positive number up to ${MAX_TRANSACTION_AMOUNT} with at most 2 decimal places`,
      );
    }
    if (!isAdmin(req) && req.user.uid !== userId) {
      return forbidden(res, 'Forbidden. You can only transact on your own wallet.');
    }
    if (type === 'credit' && !isAdmin(req)) {
      return forbidden(res, 'Forbidden. Only an administrator can credit a wallet.');
    }

    const keyResult = readIdempotencyKey(req);
    if (keyResult.error) return badRequest(res, keyResult.error);

    let outcome;
    try {
      outcome = await callUserRpc(req, 'rpc_wallet_mutate', {
        p_user_id: userId,
        p_type: type,
        p_amount: normalizedAmount,
        p_description: typeof description === 'string' ? description.slice(0, 300) : '',
        p_idempotency_id: keyResult.key,
      });
    } catch (error) {
      if (error.code === '42501') {
        return forbidden(res, 'Forbidden. This wallet operation is not authorized.');
      }
      throw error;
    }

    if (outcome?.error === 'UNKNOWN_USER') return notFound(res, 'User not found');
    if (outcome?.error === 'INSUFFICIENT_FUNDS') return badRequest(res, 'Insufficient balance');
    if (outcome?.error === 'CURRENCY_MISMATCH') {
      return conflict(res, `Wallet currency is ${outcome.currency}, not ${CURRENCY}. Refusing to mix currencies.`);
    }
    if (outcome?.error === 'IDEMPOTENCY_KEY_MISMATCH') {
      return conflict(res, 'idempotencyKey was already used for a different transaction.');
    }
    if (outcome?.error === 'INVALID_TRANSACTION') return badRequest(res, 'Invalid wallet transaction.');
    if (outcome?.error === 'IDEMPOTENCY_KEY_TOO_LONG') {
      return badRequest(res, `idempotencyKey must be at most ${MAX_IDEMPOTENCY_KEY_LENGTH} characters`);
    }
    if (!outcome || typeof outcome.balance === 'undefined' || !outcome.transaction) {
      throw new Error('Supabase wallet RPC returned an unexpected result.');
    }

    const rawTransaction = outcome.transaction;
    const transaction = {
      id: String(rawTransaction.id),
      ...fromDbRow('wallet_transactions', rawTransaction),
    };
    const responseBody = { balance: Number(outcome.balance), transaction };
    if (outcome.replayed) return ok(res, responseBody, 'Duplicate request ignored');
    return created(res, responseBody, 'Transaction added');
  }),
);

export default router;
