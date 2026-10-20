import { Router } from 'express';
import { getDb, admin } from '../config/firebase.js';
import { authenticate } from '../middleware/auth.js';
import { ok, created, notFound, badRequest, parseListQuery } from '../utils/response.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { getDocById, createDoc, serverTimestamp } from '../utils/firestore.js';

const router = Router();
const TX_COLLECTION = 'wallet_transactions';
const WALLET_COLLECTION = 'wallets';

// GET /api/wallet/:userId  -> balance + recent transactions
router.get(
  '/:userId',
  authenticate,
  asyncHandler(async (req, res) => {
    const { userId } = req.params;
    if (req.user.role !== 'admin' && req.user.uid !== userId) {
      return res.status(403).json({ success: false, message: 'Forbidden' });
    }

    const wallet = await getDocById(getDb(), WALLET_COLLECTION, userId);
    const txSnap = await getDb()
      .collection(TX_COLLECTION)
      .where('userId', '==', userId)
      .orderBy('createdAt', 'desc')
      .limit(20)
      .get();
    const transactions = txSnap.docs.map((d) => ({ id: d.id, ...d.data() }));

    ok(res, {
      balance: wallet?.balance ?? 0,
      currency: wallet?.currency ?? 'USD',
      transactions,
    });
  }),
);

// POST /api/wallet/transactions  { userId, type, amount, description }
router.post(
  '/transactions',
  authenticate,
  asyncHandler(async (req, res) => {
    const { userId, type, amount, description } = req.body || {};
    if (!userId || !['credit', 'debit'].includes(type) || typeof amount !== 'number') {
      return badRequest(res, 'userId, type (credit|debit) and numeric amount are required');
    }
    if (req.user.role !== 'admin' && req.user.uid !== userId) {
      return res.status(403).json({ success: false, message: 'Forbidden' });
    }

    const walletRef = getDb().collection(WALLET_COLLECTION).doc(userId);
    const walletSnap = await walletRef.get();
    const current = walletSnap.exists ? walletSnap.data().balance ?? 0 : 0;
    const balance = type === 'credit' ? current + amount : current - amount;

    if (balance < 0) {
      return badRequest(res, 'Insufficient balance');
    }

    await walletRef.set(
      { userId, balance, currency: 'USD', updatedAt: serverTimestamp() },
      { merge: true },
    );

    const tx = await createDoc(getDb(), TX_COLLECTION, {
      userId,
      type,
      amount,
      description: description || '',
      balance,
    });

    created(res, { balance, transaction: tx }, 'Transaction added');
  }),
);

export default router;
