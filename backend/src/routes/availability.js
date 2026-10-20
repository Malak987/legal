import { Router } from 'express';
import { getDb } from '../config/firebase.js';
import { authenticate } from '../middleware/auth.js';
import { ok, created, notFound, parseListQuery } from '../utils/response.js';
import { validate, availabilitySchema } from '../utils/validators.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { listDocs, getDocById, createDoc, updateDoc, deleteDoc } from '../utils/firestore.js';

const router = Router();
const COLLECTION = 'availability';

// GET /api/availability?lawyerId=
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const q = parseListQuery(req);
    const result = await listDocs(getDb(), COLLECTION, {
      search: q.search,
      searchFields: ['date', 'lawyerName'],
      filters: req.query.lawyerId ? { lawyerId: req.query.lawyerId } : {},
      page: q.page,
      limit: q.limit,
    });
    ok(res, result);
  }),
);

// GET /api/availability/:id
router.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const item = await getDocById(getDb(), COLLECTION, req.params.id);
    if (!item) return notFound(res, 'Availability not found');
    ok(res, item);
  }),
);

// POST /api/availability
router.post(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const data = validate(availabilitySchema, req.body);
    const createdDoc = await createDoc(getDb(), COLLECTION, data);
    created(res, createdDoc, 'Availability created');
  }),
);

// PUT /api/availability/:id
router.put(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const data = validate(availabilitySchema, req.body, { presence: 'optional' });
    const updated = await updateDoc(getDb(), COLLECTION, req.params.id, data);
    if (!updated) return notFound(res, 'Availability not found');
    ok(res, updated, 'Availability updated');
  }),
);

// DELETE /api/availability/:id
router.delete(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const deleted = await deleteDoc(getDb(), COLLECTION, req.params.id);
    if (!deleted) return notFound(res, 'Availability not found');
    ok(res, { id: req.params.id }, 'Availability deleted');
  }),
);

export default router;
