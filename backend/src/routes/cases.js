import { Router } from 'express';
import { getDb } from '../config/firebase.js';
import { authenticate } from '../middleware/auth.js';
import { ok, created, notFound, parseListQuery, cleanObject } from '../utils/response.js';
import { validate, caseSchema } from '../utils/validators.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { listDocs, getDocById, createDoc, updateDoc, deleteDoc } from '../utils/firestore.js';

const router = Router();
const COLLECTION = 'cases';

// GET /api/cases?userId=&status=&priority=&search=
router.get(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const q = parseListQuery(req);
    const filters = cleanObject({
      userId: req.query.userId,
      status: req.query.status,
      priority: req.query.priority,
    });
    // If a non-admin user requests, restrict to their own cases.
    if (req.user.role !== 'admin' && !filters.userId) filters.userId = req.user.uid;

    const result = await listDocs(getDb(), COLLECTION, {
      search: q.search,
      searchFields: ['title', 'description', 'clientName', 'caseType'],
      filters,
      page: q.page,
      limit: q.limit,
    });
    ok(res, result);
  }),
);

// GET /api/cases/:id
router.get(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const item = await getDocById(getDb(), COLLECTION, req.params.id);
    if (!item) return notFound(res, 'Case not found');
    if (req.user.role !== 'admin' && item.userId && item.userId !== req.user.uid) {
      return res.status(403).json({ success: false, message: 'Forbidden' });
    }
    ok(res, item);
  }),
);

// POST /api/cases
router.post(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const data = validate(caseSchema, { ...req.body, userId: req.body.userId || req.user.uid });
    const createdDoc = await createDoc(getDb(), COLLECTION, data);
    created(res, createdDoc, 'Case created');
  }),
);

// PUT /api/cases/:id
router.put(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const data = validate(caseSchema, req.body, { presence: 'optional' });
    const existing = await getDocById(getDb(), COLLECTION, req.params.id);
    if (!existing) return notFound(res, 'Case not found');
    if (req.user.role !== 'admin' && existing.userId && existing.userId !== req.user.uid) {
      return res.status(403).json({ success: false, message: 'Forbidden' });
    }
    const updated = await updateDoc(getDb(), COLLECTION, req.params.id, data);
    ok(res, updated, 'Case updated');
  }),
);

// DELETE /api/cases/:id
router.delete(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const existing = await getDocById(getDb(), COLLECTION, req.params.id);
    if (!existing) return notFound(res, 'Case not found');
    if (req.user.role !== 'admin' && existing.userId && existing.userId !== req.user.uid) {
      return res.status(403).json({ success: false, message: 'Forbidden' });
    }
    await deleteDoc(getDb(), COLLECTION, req.params.id);
    ok(res, { id: req.params.id }, 'Case deleted');
  }),
);

export default router;
