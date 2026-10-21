import { Router } from 'express';
import { getDb } from '../config/firebase.js';
import {
  authenticate,
  requireSelfOrAdmin,
  isOwner,
  forbidden,
} from '../middleware/auth.js';
import { ok, created, notFound, badRequest } from '../utils/response.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { getDocById, createDoc, deleteDoc } from '../utils/firestore.js';

const router = Router();
const COLLECTION = 'favorites';

// GET /api/favorites/:userId
router.get(
  '/:userId',
  authenticate,
  requireSelfOrAdmin('userId'),
  asyncHandler(async (req, res) => {
    const { userId } = req.params;
    const snap = await getDb()
      .collection(COLLECTION)
      .where('userId', '==', userId)
      .get();
    const favorites = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    ok(res, favorites);
  }),
);

// POST /api/favorites  { lawyerId }
router.post(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const { lawyerId } = req.body || {};
    if (!lawyerId) {
      return badRequest(res, 'lawyerId is required');
    }

    // The owner is always the authenticated user. A `userId` in the body used
    // to be trusted, which let a client add favourites to somebody else's
    // list; it is now ignored.
    const userId = req.user.uid;

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
    const existing = await getDocById(getDb(), COLLECTION, req.params.id);
    if (!existing) return notFound(res, 'Favorite not found');
    if (!isOwner(existing, req)) {
      return forbidden(res, 'Forbidden. You can only remove your own favorites.');
    }

    const deleted = await deleteDoc(getDb(), COLLECTION, req.params.id);
    if (!deleted) return notFound(res, 'Favorite not found');
    ok(res, { id: req.params.id }, 'Removed from favorites');
  }),
);

export default router;
