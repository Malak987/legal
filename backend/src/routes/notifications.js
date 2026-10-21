import { Router } from 'express';
import { getDb } from '../config/firebase.js';
import {
  authenticate,
  requireRole,
  requireSelfOrAdmin,
  isOwner,
  forbidden,
  lockOwnerOnUpdate,
} from '../middleware/auth.js';
import { ok, created, notFound, parseListQuery } from '../utils/response.js';
import { validate, notificationSchema } from '../utils/validators.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { listDocs, getDocById, createDoc, updateDoc, deleteDoc, serverTimestamp } from '../utils/firestore.js';

const router = Router();
const COLLECTION = 'notifications';

/// Loads a notification and answers 404/403 consistently.
/// Returns `null` when the request has already been answered.
async function loadOwnedNotification(req, res) {
  const existing = await getDocById(getDb(), COLLECTION, req.params.id);
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
    const createdDoc = await createDoc(getDb(), COLLECTION, data);
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
    const existing = await loadOwnedNotification(req, res);
    if (!existing) return;

    const data = validate(notificationSchema, req.body, { presence: 'optional' });
    // Ownership is immutable: a `userId` in the body must never move a
    // notification to another account.
    lockOwnerOnUpdate(data, existing, req);

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
    const existing = await loadOwnedNotification(req, res);
    if (!existing) return;

    const deleted = await deleteDoc(getDb(), COLLECTION, req.params.id);
    if (!deleted) return notFound(res, 'Notification not found');
    ok(res, { id: req.params.id }, 'Notification deleted');
  }),
);

export default router;
