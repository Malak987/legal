import { Router } from 'express';
import { toDbRow } from '../config/supabase.js';
import { requestDatabase, callUserRpc, rpcErrorToken, rpcRow } from '../utils/supabase_rpc.js';
import {
  authenticate,
  requireRole,
  requireSelfOrAdmin,
  isOwner,
  forbidden,
  lockOwnerOnUpdate,
} from '../middleware/auth.js';
import { ok, created, notFound, badRequest, parseListQuery } from '../utils/response.js';
import { validate, notificationSchema } from '../utils/validators.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { listDocs, getDocById, createDoc, deleteDoc } from '../utils/supabase_database.js';

const router = Router();
const COLLECTION = 'notifications';

/// Loads a notification and answers 404/403 consistently.
/// Returns `null` when the request has already been answered.
async function loadOwnedNotification(req, res) {
  const existing = await getDocById(requestDatabase(req), COLLECTION, req.params.id);
  if (!existing) {
    notFound(res, 'Notification not found');
    return null;
  }
  if (!isOwner(existing, req)) {
    forbidden(res, 'Forbidden. You can only modify your own notifications.');
    return null;
  }
  return existing;
}

// GET /api/notifications/:userId  -> one user's notifications
router.get(
  '/:userId',
  authenticate,
  requireSelfOrAdmin('userId'),
  asyncHandler(async (req, res) => {
    const { userId } = req.params;
    const q = parseListQuery(req);
    const result = await listDocs(requestDatabase(req), COLLECTION, {
      search: q.search,
      searchFields: ['title', 'content'],
      filters: { userId },
      page: q.page,
      limit: q.limit,
    });
    ok(res, result);
  }),
);

// GET /api/notifications  -> notifications across ALL users (admin only)
//
// This route is what the admin panel's Notifications screen uses. It returns
// every user's notifications, so it must not be reachable by a normal account.
router.get(
  '/',
  authenticate,
  requireRole('admin'),
  asyncHandler(async (req, res) => {
    const q = parseListQuery(req);
    const result = await listDocs(requestDatabase(req), COLLECTION, {
      search: q.search,
      searchFields: ['title', 'content'],
      filters: req.query.userId ? { userId: req.query.userId } : {},
      page: q.page,
      limit: q.limit,
    });
    ok(res, result);
  }),
);

// POST /api/notifications  (admin only)
//
// A notification is always addressed to somebody, so letting any signed-in
// account create one lets them spam other users. Only administrators may
// create notifications; a `userId` in the body selects the recipient.
router.post(
  '/',
  authenticate,
  requireRole('admin'),
  asyncHandler(async (req, res) => {
    const data = validate(notificationSchema, req.body);
    const createdDoc = await createDoc(requestDatabase(req), COLLECTION, data);
    created(res, createdDoc, 'Notification created');
  }),
);

// PUT /api/notifications/:id/read  { read: true }
router.put(
  '/:id/read',
  authenticate,
  asyncHandler(async (req, res) => {
    const existing = await loadOwnedNotification(req, res);
    if (!existing) return;

    const read = req.body?.read !== false;
    try {
      const outcome = await callUserRpc(req, 'rpc_notification_update', {
        p_notification_id: req.params.id,
        p_changes: { read },
      });
      const updated = rpcRow(COLLECTION, outcome);
      if (!updated) throw new Error('Supabase notification RPC returned an unexpected result.');
      return ok(res, updated, 'Notification updated');
    } catch (error) {
      const token = rpcErrorToken(error);
      if (error.code === 'P0002' || token === 'NOTIFICATION_NOT_FOUND') return notFound(res, 'Notification not found');
      if (error.code === '42501') return forbidden(res, 'Forbidden. You can only modify your own notifications.');
      if (error.code === '22023') return badRequest(res, `Invalid notification update (${token || 'validation failed'}).`);
      throw error;
    }
  }),
);

// PUT /api/notifications/:id
router.put(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const existing = await loadOwnedNotification(req, res);
    if (!existing) return;

    const data = validate(notificationSchema, req.body, { presence: 'optional' });
    // Ownership is immutable: a `userId` in the body must never move a
    // notification to another account.
    lockOwnerOnUpdate(data, existing, req);

    const changes = toDbRow(COLLECTION, data);
    delete changes.id;
    if (changes.user_id === existing.userId) delete changes.user_id;
    if (Object.keys(changes).length === 0) return ok(res, existing, 'Notification unchanged');
    try {
      const outcome = await callUserRpc(req, 'rpc_notification_update', {
        p_notification_id: req.params.id,
        p_changes: changes,
      });
      const updated = rpcRow(COLLECTION, outcome);
      if (!updated) throw new Error('Supabase notification RPC returned an unexpected result.');
      return ok(res, updated, 'Notification updated');
    } catch (error) {
      const token = rpcErrorToken(error);
      if (error.code === 'P0002' || token === 'NOTIFICATION_NOT_FOUND') return notFound(res, 'Notification not found');
      if (error.code === '42501') return forbidden(res, 'Forbidden. This notification change is not authorized.');
      if (error.code === '22023') return badRequest(res, `Invalid notification update (${token || 'validation failed'}).`);
      throw error;
    }
  }),
);

// DELETE /api/notifications/:id
router.delete(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const existing = await loadOwnedNotification(req, res);
    if (!existing) return;

    const deleted = await deleteDoc(requestDatabase(req), COLLECTION, req.params.id);
    if (!deleted) return notFound(res, 'Notification not found');
    ok(res, { id: req.params.id }, 'Notification deleted');
  }),
);

export default router;
