import { Router } from 'express';
import { getDb } from '../config/firebase.js';
import { authenticate } from '../middleware/auth.js';
import { ok, created, notFound } from '../utils/response.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { getDocById, createDoc, deleteDoc } from '../utils/firestore.js';

const router = Router();
const COLLECTION = 'favorites';

// GET /api/favorites/:userId
router.get(
  '/:userId',
  authenticate,
  asyncHandler(async (req, res) => {
    const { userId } = req.params;
    if (req.user.role !== 'admin' && req.user.uid !== userId) {
      return res.status(403).json({ success: false, message: 'Forbidden' });
    }
    const snap = await getDb()
      .collection(COLLECTION)
      .where('userId', '==', userId)
      .get();
    const favorites = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    ok(res, favorites);
  }),
);

// POST /api/favorites  { userId, lawyerId }
router.post(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const { userId, lawyerId } = req.body || {};
    if (!userId || !lawyerId) {
      return res.status(400).json({ success: false, message: 'userId and lawyerId are required' });
    }
    const existing = await getDb()
      .collection(COLLECTION)
      .where('userId', '==', userId)
      .where('lawyerId', '==', lawyerId)
      .limit(1)
      .get();
    if (!existing.empty) {
      return ok(res, { id: existing.docs[0].id, ...existing.docs[0].data() }, 'Already favorited');
    }
    const createdDoc = await createDoc(getDb(), COLLECTION, { userId, lawyerId });
    created(res, createdDoc, 'Added to favorites');
  }),
);

// DELETE /api/favorites/:id
router.delete(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const deleted = await deleteDoc(getDb(), COLLECTION, req.params.id);
    if (!deleted) return notFound(res, 'Favorite not found');
    ok(res, { id: req.params.id }, 'Removed from favorites');
  }),
);

export default router;
