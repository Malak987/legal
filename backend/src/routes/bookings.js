import { Router } from 'express';
import { getDb } from '../config/firebase.js';
import { authenticate } from '../middleware/auth.js';
import { ok, created, notFound, parseListQuery, cleanObject } from '../utils/response.js';
import { validate, bookingSchema } from '../utils/validators.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { listDocs, getDocById, createDoc, updateDoc, deleteDoc } from '../utils/firestore.js';

const router = Router();
const COLLECTION = 'bookings';

// GET /api/bookings?userId=&status=&lawyerId=
router.get(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const q = parseListQuery(req);
    const filters = cleanObject({
      userId: req.query.userId,
      status: req.query.status,
      lawyerId: req.query.lawyerId,
    });
    if (req.user.role !== 'admin' && !filters.userId) filters.userId = req.user.uid;

    const result = await listDocs(getDb(), COLLECTION, {
      search: q.search,
      searchFields: ['lawyerName', 'date', 'time'],
      filters,
      page: q.page,
      limit: q.limit,
    });
    ok(res, result);
  }),
);

// GET /api/bookings/:id
router.get(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const item = await getDocById(getDb(), COLLECTION, req.params.id);
    if (!item) return notFound(res, 'Booking not found');
    if (req.user.role !== 'admin' && item.userId && item.userId !== req.user.uid) {
      return res.status(403).json({ success: false, message: 'Forbidden' });
    }
    ok(res, item);
  }),
);

// POST /api/bookings
router.post(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const data = validate(bookingSchema, { ...req.body, userId: req.body.userId || req.user.uid });
    const createdDoc = await createDoc(getDb(), COLLECTION, data);
    created(res, createdDoc, 'Booking created');
  }),
);

// PUT /api/bookings/:id  (used to change status: Active / Completed / Cancelled)
router.put(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const data = validate(bookingSchema, req.body, { presence: 'optional' });
    const existing = await getDocById(getDb(), COLLECTION, req.params.id);
    if (!existing) return notFound(res, 'Booking not found');
    if (req.user.role !== 'admin' && existing.userId && existing.userId !== req.user.uid) {
      return res.status(403).json({ success: false, message: 'Forbidden' });
    }
    const updated = await updateDoc(getDb(), COLLECTION, req.params.id, data);
    ok(res, updated, 'Booking updated');
  }),
);

// DELETE /api/bookings/:id
router.delete(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const existing = await getDocById(getDb(), COLLECTION, req.params.id);
    if (!existing) return notFound(res, 'Booking not found');
    if (req.user.role !== 'admin' && existing.userId && existing.userId !== req.user.uid) {
      return res.status(403).json({ success: false, message: 'Forbidden' });
    }
    await deleteDoc(getDb(), COLLECTION, req.params.id);
    ok(res, { id: req.params.id }, 'Booking deleted');
  }),
);

export default router;
