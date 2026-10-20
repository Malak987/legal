import { Router } from 'express';
import { getDb } from '../config/firebase.js';
import { authenticate } from '../middleware/auth.js';
import { ok, created, notFound, parseListQuery, cleanObject } from '../utils/response.js';
import { validate, subscriptionSchema } from '../utils/validators.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { listDocs, getDocById, createDoc, updateDoc, deleteDoc } from '../utils/firestore.js';

const router = Router();
const COLLECTION = 'subscriptions';

// GET /api/subscriptions?userId=&status=
router.get(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const q = parseListQuery(req);
    const filters = cleanObject({ userId: req.query.userId, status: req.query.status });
    if (req.user.role !== 'admin' && !filters.userId) filters.userId = req.user.uid;

    const result = await listDocs(getDb(), COLLECTION, {
      search: q.search,
      searchFields: ['planTitle'],
      filters,
      page: q.page,
      limit: q.limit,
    });
    ok(res, result);
  }),
);

// GET /api/subscriptions/:id
router.get(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const item = await getDocById(getDb(), COLLECTION, req.params.id);
    if (!item) return notFound(res, 'Subscription not found');
    if (req.user.role !== 'admin' && item.userId && item.userId !== req.user.uid) {
      return res.status(403).json({ success: false, message: 'Forbidden' });
    }
    ok(res, item);
  }),
);

// POST /api/subscriptions
router.post(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const data = validate(subscriptionSchema, { ...req.body, userId: req.body.userId || req.user.uid });
    const createdDoc = await createDoc(getDb(), COLLECTION, data);
    created(res, createdDoc, 'Subscription created');
  }),
);

// PUT /api/subscriptions/:id
router.put(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const data = validate(subscriptionSchema, req.body, { presence: 'optional' });
    const existing = await getDocById(getDb(), COLLECTION, req.params.id);
    if (!existing) return notFound(res, 'Subscription not found');
    if (req.user.role !== 'admin' && existing.userId && existing.userId !== req.user.uid) {
      return res.status(403).json({ success: false, message: 'Forbidden' });
    }
    const updated = await updateDoc(getDb(), COLLECTION, req.params.id, data);
    ok(res, updated, 'Subscription updated');
  }),
);

// DELETE /api/subscriptions/:id
router.delete(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const existing = await getDocById(getDb(), COLLECTION, req.params.id);
    if (!existing) return notFound(res, 'Subscription not found');
    if (req.user.role !== 'admin' && existing.userId && existing.userId !== req.user.uid) {
      return res.status(403).json({ success: false, message: 'Forbidden' });
    }
    await deleteDoc(getDb(), COLLECTION, req.params.id);
    ok(res, { id: req.params.id }, 'Subscription deleted');
  }),
);

export default router;
