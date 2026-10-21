import { Router } from 'express';
import { getDb } from '../config/firebase.js';
import {
  authenticate,
  isOwner,
  forbidden,
  ownerIdFor,
  isAdmin,
  lockOwnerOnUpdate,
} from '../middleware/auth.js';
import { ok, created, notFound, parseListQuery, cleanObject } from '../utils/response.js';
import { validate, taskSchema } from '../utils/validators.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { listDocs, getDocById, createDoc, updateDoc, deleteDoc } from '../utils/firestore.js';

const router = Router();
const COLLECTION = 'tasks';

// GET /api/tasks?userId=&status=&priority=
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
    // A non-admin is always scoped to their own records. The old test only
    // applied the scope when `?userId=` was absent, so passing somebody
    // else's id returned their records instead.
    if (!isAdmin(req)) filters.userId = req.user.uid;

    const result = await listDocs(getDb(), COLLECTION, {
      search: q.search,
      searchFields: ['title', 'description'],
      filters,
      page: q.page,
      limit: q.limit,
    });
    ok(res, result);
  }),
);

// GET /api/tasks/:id
router.get(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const item = await getDocById(getDb(), COLLECTION, req.params.id);
    if (!item) return notFound(res, 'Task not found');
    if (!isOwner(item, req)) {
      return forbidden(res);
    }
    ok(res, item);
  }),
);

// POST /api/tasks
router.post(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const data = validate(taskSchema, { ...req.body, userId: ownerIdFor(req) });
    const createdDoc = await createDoc(getDb(), COLLECTION, data);
    created(res, createdDoc, 'Task created');
  }),
);

// PUT /api/tasks/:id
router.put(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const data = validate(taskSchema, req.body, { presence: 'optional' });
    const existing = await getDocById(getDb(), COLLECTION, req.params.id);
    if (!existing) return notFound(res, 'Task not found');
    if (!isOwner(existing, req)) {
      return forbidden(res);
    }
    // Ownership is immutable here: `userId` in the body cannot reassign a
    // record to another account (admin-only operation).
    lockOwnerOnUpdate(data, existing, req);

    const updated = await updateDoc(getDb(), COLLECTION, req.params.id, data);
    ok(res, updated, 'Task updated');
  }),
);

// DELETE /api/tasks/:id
router.delete(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const existing = await getDocById(getDb(), COLLECTION, req.params.id);
    if (!existing) return notFound(res, 'Task not found');
    if (!isOwner(existing, req)) {
      return forbidden(res);
    }
    await deleteDoc(getDb(), COLLECTION, req.params.id);
    ok(res, { id: req.params.id }, 'Task deleted');
  }),
);

export default router;
