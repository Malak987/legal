import { Router } from 'express';
import { requestDatabase, callUserRpc, rpcRow } from '../utils/supabase_rpc.js';
import {
  authenticate,
  requireSelfOrAdmin,
  isOwner,
  forbidden,
} from '../middleware/auth.js';
import { ok, created, notFound, badRequest } from '../utils/response.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { getDocById, deleteDoc } from '../utils/supabase_database.js';

const router = Router();
const COLLECTION = 'favorites';

// GET /api/favorites/:userId
router.get(
  '/:userId',
  authenticate,
  requireSelfOrAdmin('userId'),
  asyncHandler(async (req, res) => {
    const { userId } = req.params;
    const snap = await requestDatabase(req)
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

    const existing = await requestDatabase(req)
      .collection(COLLECTION)
      .where('userId', '==', userId)
      .where('lawyerId', '==', lawyerId)
      .limit(1)
      .get();
    if (!existing.empty) {
      return ok(res, { id: existing.docs[0].id, ...existing.docs[0].data() }, 'Already favorited');
    }
    try {
      const outcome = await callUserRpc(req, 'rpc_favorite_add', {
        p_lawyer_id: lawyerId,
      });
      const favorite = rpcRow(COLLECTION, outcome);
      if (!favorite) throw new Error('Supabase favorite RPC returned an unexpected result.');
      return created(res, favorite, 'Added to favorites');
    } catch (error) {
      if (error.code === '42501') return forbidden(res, 'Forbidden. You can only add favorites for yourself.');
      if (error.code === '23503') return badRequest(res, 'lawyerId does not identify an available lawyer');
      throw error;
    }
  }),
);

// DELETE /api/favorites/:id
router.delete(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const existing = await getDocById(requestDatabase(req), COLLECTION, req.params.id);
    if (!existing) return notFound(res, 'Favorite not found');
    if (!isOwner(existing, req)) {
      return forbidden(res, 'Forbidden. You can only remove your own favorites.');
    }

    const deleted = await deleteDoc(requestDatabase(req), COLLECTION, req.params.id);
    if (!deleted) return notFound(res, 'Favorite not found');
    ok(res, { id: req.params.id }, 'Removed from favorites');
  }),
);

export default router;
