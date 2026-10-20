import { Router } from 'express';
import { getDb } from '../config/firebase.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { ok, created, notFound, parseListQuery } from '../utils/response.js';
import { validate, planSchema } from '../utils/validators.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { listDocs, getDocById, createDoc, updateDoc, deleteDoc } from '../utils/firestore.js';

const router = Router();
const COLLECTION = 'plans';

// GET /api/plans
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const q = parseListQuery(req);
    const result = await listDocs(getDb(), COLLECTION, {
      search: q.search,
      searchFields: ['title'],
      sort: 'priceValue',
      order: 'asc',
      page: q.page,
      limit: q.limit,
    });
    ok(res, result);
  }),
);

// GET /api/plans/:id
router.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const item = await getDocById(getDb(), COLLECTION, req.params.id);
    if (!item) return notFound(res, 'Plan not found');
    ok(res, item);
  }),
);

// POST /api/plans  (admin)
router.post(
  '/',
  authenticate,
  requireRole('admin'),
  asyncHandler(async (req, res) => {
    const data = validate(planSchema, req.body);
    const createdDoc = await createDoc(getDb(), COLLECTION, data);
    created(res, createdDoc, 'Plan created');
  }),
);

// PUT /api/plans/:id  (admin)
router.put(
  '/:id',
  authenticate,
  requireRole('admin'),
  asyncHandler(async (req, res) => {
    const data = validate(planSchema, req.body, { presence: 'optional' });
    const updated = await updateDoc(getDb(), COLLECTION, req.params.id, data);
    if (!updated) return notFound(res, 'Plan not found');
    ok(res, updated, 'Plan updated');
  }),
);

// DELETE /api/plans/:id  (admin)
router.delete(
  '/:id',
  authenticate,
  requireRole('admin'),
  asyncHandler(async (req, res) => {
    const deleted = await deleteDoc(getDb(), COLLECTION, req.params.id);
    if (!deleted) return notFound(res, 'Plan not found');
    ok(res, { id: req.params.id }, 'Plan deleted');
  }),
);

export default router;
