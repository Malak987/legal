import { Router } from 'express';
import { toDbRow } from '../config/supabase.js';
import { requestDatabase, callUserRpc, rpcErrorToken, rpcRow } from '../utils/supabase_rpc.js';
import {
  authenticate,
  isOwner,
  forbidden,
  ownerIdFor,
  isAdmin,
  lockOwnerOnUpdate,
} from '../middleware/auth.js';
import { ok, created, notFound, badRequest, parseListQuery, cleanObject } from '../utils/response.js';
import { validate, taskSchema, taskUpdateSchema } from '../utils/validators.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { listDocs, getDocById, createDoc, updateDoc, deleteDoc } from '../utils/supabase_database.js';

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

    const result = await listDocs(requestDatabase(req), COLLECTION, {
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
    const item = await getDocById(requestDatabase(req), COLLECTION, req.params.id);
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
    const createdDoc = await createDoc(requestDatabase(req), COLLECTION, data);
    created(res, createdDoc, 'Task created');
  }),
);

// PUT /api/tasks/:id
router.put(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    // `noDefaults` is what stops a partial update from re-applying the schema
    // defaults (`status: 'Pending'`, `priority: 'Medium'`) over the stored
    // values. Same root cause as `PUT /api/cases/:id`.
    const data = validate(taskUpdateSchema, req.body, {
      presence: 'optional',
      noDefaults: true,
    });
    const existing = await getDocById(requestDatabase(req), COLLECTION, req.params.id);
    if (!existing) return notFound(res, 'Task not found');
    if (!isOwner(existing, req)) {
      return forbidden(res);
    }
    // Ownership is immutable here: `userId` in the body cannot reassign a
    // record to another account (admin-only operation).
    lockOwnerOnUpdate(data, existing, req);

    if (data.userId !== undefined && data.userId !== existing.userId) {
      return forbidden(res, 'Task ownership cannot be reassigned.');
    }
    const changes = toDbRow(COLLECTION, data);
    delete changes.id;
    delete changes.user_id;
    if (Object.keys(changes).length === 0) return ok(res, existing, 'Task unchanged');
    try {
      const outcome = await callUserRpc(req, 'rpc_task_update', {
        p_task_id: req.params.id,
        p_changes: changes,
      });
      const updated = rpcRow(COLLECTION, outcome);
      if (!updated) throw new Error('Supabase task RPC returned an unexpected result.');
      return ok(res, updated, 'Task updated');
    } catch (error) {
      const token = rpcErrorToken(error);
      if (error.code === '42501') return forbidden(res, 'Forbidden. This task change is not authorized.');
      if (error.code === 'P0002' || token === 'TASK_NOT_FOUND') return notFound(res, 'Task not found');
      if (error.code === '22023') return badRequest(res, `Invalid task update (${token || 'validation failed'}).`);
      throw error;
    }
  }),
);

// DELETE /api/tasks/:id
router.delete(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const existing = await getDocById(requestDatabase(req), COLLECTION, req.params.id);
    if (!existing) return notFound(res, 'Task not found');
    if (!isOwner(existing, req)) {
      return forbidden(res);
    }
    await deleteDoc(requestDatabase(req), COLLECTION, req.params.id);
    ok(res, { id: req.params.id }, 'Task deleted');
  }),
);

export default router;
