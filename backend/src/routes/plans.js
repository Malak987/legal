import { Router } from 'express';
import { getPublicDb } from '../config/supabase.js';
import { requestDatabase } from '../utils/supabase_rpc.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { ok, created, notFound, parseListQuery } from '../utils/response.js';
import { validate, planSchema } from '../utils/validators.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { listDocs, getDocById, createDoc, updateDoc, deleteDoc } from '../utils/supabase_database.js';

const router = Router();
const COLLECTION = 'plans';

// GET /api/plans
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const q = parseListQuery(req);
    const result = await listDocs(getPublicDb(), COLLECTION, {
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
    const item = await getDocById(getPublicDb(), COLLECTION, req.params.id);
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
    const createdDoc = await createDoc(requestDatabase(req), COLLECTION, data);
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
    const updated = await updateDoc(requestDatabase(req), COLLECTION, req.params.id, data);
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
    const deleted = await deleteDoc(requestDatabase(req), COLLECTION, req.params.id);
    if (!deleted) return notFound(res, 'Plan not found');
    ok(res, { id: req.params.id }, 'Plan deleted');
  }),
);

export default router;
