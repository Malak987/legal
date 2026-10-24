import { Router } from 'express';
import { getPublicDb } from '../config/supabase.js';
import { callUserRpc, rpcErrorToken, rpcRow } from '../utils/supabase_rpc.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import {
  ok,
  created,
  notFound,
  badRequest,
  conflict,
  parseListQuery,
  cleanObject,
} from '../utils/response.js';
import {
  validate,
  reviewCreateSchema,
  reviewUpdateSchema,
} from '../utils/validators.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { listDocs, getDocById } from '../utils/supabase_database.js';

const router = Router();
const COLLECTION = 'reviews';

/** Remove author identifiers from public review responses. */
function publicReview(review) {
  if (!review) return review;
  const { userId: _authorId, ...rest } = review;
  return rest;
}

// GET /api/reviews?lawyerId=&userId= (public listing; author ids are stripped)
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const q = parseListQuery(req);
    const result = await listDocs(getPublicDb(), COLLECTION, {
      search: q.search,
      searchFields: ['comment', 'userName'],
      filters: cleanObject({ lawyerId: req.query.lawyerId, userId: req.query.userId }),
      sort: 'rating',
      order: 'desc',
      page: q.page,
      limit: q.limit,
    });
    ok(res, { ...result, items: result.items.map(publicReview) });
  }),
);

// GET /api/reviews/:id
router.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const item = await getDocById(getPublicDb(), COLLECTION, req.params.id);
    if (!item) return notFound(res, 'Review not found');
    ok(res, publicReview(item));
  }),
);

// POST /api/reviews — one review per author/lawyer, enforced in PostgreSQL.
router.post(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const data = validate(reviewCreateSchema, {
      ...req.body,
      userId: req.user.uid,
      userName: req.user.name,
    });
    try {
      const outcome = await callUserRpc(req, 'rpc_review_submit', {
        p_lawyer_id: data.lawyerId,
        p_rating: data.rating,
        p_comment: data.comment ?? '',
      });
      if (outcome?.error === 'DUPLICATE_REVIEW') {
        return conflict(res, 'You have already reviewed this lawyer.');
      }
      const saved = rpcRow(COLLECTION, outcome);
      if (!saved) throw new Error('Supabase review RPC returned an unexpected result.');
      return created(res, publicReview(saved), 'Review created');
    } catch (error) {
      const token = rpcErrorToken(error);
      if (error.code === '22023' || token === 'LAWYER_NOT_FOUND') {
        return badRequest(res, 'The review details or lawyer are invalid.');
      }
      throw error;
    }
  }),
);

// PUT /api/reviews/:id — administrator moderation (rating/comment only).
router.put(
  '/:id',
  authenticate,
  requireRole('admin'),
  asyncHandler(async (req, res) => {
    const data = validate(reviewUpdateSchema, req.body, { presence: 'optional' });
    try {
      const outcome = await callUserRpc(req, 'rpc_admin_review_moderate', {
        p_review_id: req.params.id,
        p_rating: data.rating ?? null,
        p_comment: data.comment ?? null,
      });
      const updated = rpcRow(COLLECTION, outcome);
      if (!updated) throw new Error('Supabase review moderation RPC returned an unexpected result.');
      return ok(res, publicReview(updated), 'Review updated');
    } catch (error) {
      const token = rpcErrorToken(error);
      if (error.code === 'P0002' || token === 'REVIEW_NOT_FOUND') return notFound(res, 'Review not found');
      if (error.code === '22023') return badRequest(res, `Invalid review update (${token || 'validation failed'}).`);
      throw error;
    }
  }),
);

// DELETE /api/reviews/:id (administrator only).
router.delete(
  '/:id',
  authenticate,
  requireRole('admin'),
  asyncHandler(async (req, res) => {
    try {
      await callUserRpc(req, 'rpc_admin_review_delete', { p_review_id: req.params.id });
      return ok(res, { id: req.params.id }, 'Review deleted');
    } catch (error) {
      const token = rpcErrorToken(error);
      if (error.code === 'P0002' || token === 'REVIEW_NOT_FOUND') return notFound(res, 'Review not found');
      throw error;
    }
  }),
);

export default router;
