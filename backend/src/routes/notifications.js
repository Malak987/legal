import { Router } from 'express';
import { getDb } from '../config/firebase.js';
import { authenticate } from '../middleware/auth.js';
import { ok, created, notFound, parseListQuery } from '../utils/response.js';
import { validate, notificationSchema } from '../utils/validators.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { listDocs, getDocById, createDoc, updateDoc, deleteDoc, serverTimestamp } from '../utils/firestore.js';

const router = Router();
const COLLECTION = 'notifications';

// GET /api/notifications/:userId
router.get(
  '/:userId',
  authenticate,
  asyncHandler(async (req, res) => {
    const { userId } = req.params;
    if (req.user.role !== 'admin' && req.user.uid !== userId) {
      return res.status(403).json({ success: false, message: 'Forbidden' });
    }
    const q = parseListQuery(req);
    const result = await listDocs(getDb(), COLLECTION, {
      search: q.search,
      searchFields: ['title', 'content'],
      filters: { userId },
      page: q.page,
      limit: q.limit,
    });
    ok(res, result);
  }),
);

// GET /api/notifications  (admin sees all)
router.get(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const q = parseListQuery(req);
    const result = await listDocs(getDb(), COLLECTION, {
      search: q.search,
      searchFields: ['title', 'content'],
      filters: req.query.userId ? { userId: req.query.userId } : {},
      page: q.page,
      limit: q.limit,
    });
    ok(res, result);
  }),
);

// POST /api/notifications
router.post(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const data = validate(notificationSchema, req.body);
    const createdDoc = await createDoc(getDb(), COLLECTION, data);
    created(res, createdDoc, 'Notification created');
  }),
);

// PUT /api/notifications/:id/read  { read: true }
router.put(
  '/:id/read',
  authenticate,
  asyncHandler(async (req, res) => {
    const read = req.body?.read !== false;
    const updated = await updateDoc(getDb(), COLLECTION, req.params.id, { read });
    if (!updated) return notFound(res, 'Notification not found');
    ok(res, updated, 'Notification updated');
  }),
);

// PUT /api/notifications/:id
router.put(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const data = validate(notificationSchema, req.body, { presence: 'optional' });
    const updated = await updateDoc(getDb(), COLLECTION, req.params.id, data);
    if (!updated) return notFound(res, 'Notification not found');
    ok(res, updated, 'Notification updated');
  }),
);

// DELETE /api/notifications/:id
router.delete(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const deleted = await deleteDoc(getDb(), COLLECTION, req.params.id);
    if (!deleted) return notFound(res, 'Notification not found');
    ok(res, { id: req.params.id }, 'Notification deleted');
  }),
);

export default router;
