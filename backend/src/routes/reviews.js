import { Router } from 'express';
import { getDb } from '../config/firebase.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { ok, created, notFound, parseListQuery, cleanObject } from '../utils/response.js';
import { validate, reviewSchema } from '../utils/validators.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { listDocs, getDocById, createDoc, updateDoc, deleteDoc } from '../utils/firestore.js';

const router = Router();
const COLLECTION = 'reviews';

// GET /api/reviews?lawyerId=&userId=
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const q = parseListQuery(req);
    const result = await listDocs(getDb(), COLLECTION, {
      search: q.search,
      searchFields: ['comment', 'userName'],
      filters: cleanObject({ lawyerId: req.query.lawyerId, userId: req.query.userId }),
      sort: 'rating',
      order: 'desc',
      page: q.page,
      limit: q.limit,
    });
    ok(res, result);
  }),
);

// GET /api/reviews/:id
router.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const item = await getDocById(getDb(), COLLECTION, req.params.id);
    if (!item) return notFound(res, 'Review not found');
    ok(res, item);
  }),
);

// POST /api/reviews
router.post(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const data = validate(reviewSchema, {
      ...req.body,
      // A review is attributed to its author, never to a client-supplied id.
      userId: req.user.uid,
      userName: req.user.name,
    });
    const createdDoc = await createDoc(getDb(), COLLECTION, data);
    created(res, createdDoc, 'Review created');
  }),
);

// PUT /api/reviews/:id
router.put(
  '/:id',
  authenticate,
  requireRole('admin'),
  asyncHandler(async (req, res) => {
    const data = validate(reviewSchema, req.body, { presence: 'optional' });
    const updated = await updateDoc(getDb(), COLLECTION, req.params.id, data);
    if (!updated) return notFound(res, 'Review not found');
    ok(res, updated, 'Review updated');
  }),
);

// DELETE /api/reviews/:id  (admin only)
router.delete(
  '/:id',
  authenticate,
  requireRole('admin'),
  asyncHandler(async (req, res) => {
    const deleted = await deleteDoc(getDb(), COLLECTION, req.params.id);
    if (!deleted) return notFound(res, 'Review not found');
    ok(res, { id: req.params.id }, 'Review deleted');
  }),
);

export default router;
