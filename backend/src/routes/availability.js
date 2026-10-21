import { Router } from 'express';
import { getDb } from '../config/firebase.js';
import {
  authenticate,
  requireRole,
  isAdmin,
  forbidden,
} from '../middleware/auth.js';
import { ok, created, notFound, parseListQuery } from '../utils/response.js';
import {
  validate,
  availabilitySchema,
  availabilityCreateSchema,
} from '../utils/validators.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { listDocs, getDocById, createDoc, updateDoc, deleteDoc } from '../utils/firestore.js';

const router = Router();
const COLLECTION = 'availability';

/// Availability belongs to a lawyer, identified by `lawyerId`.
/// An administrator manages every slot; a lawyer manages only their own.
function canManageSlot(record, req) {
  if (isAdmin(req)) return true;
  return Boolean(record?.lawyerId) && record.lawyerId === req.user.uid;
}

/// Loads a slot and answers 404/403 consistently.
/// Returns `null` when the request has already been answered.
async function loadOwnedSlot(req, res) {
  const existing = await getDocById(getDb(), COLLECTION, req.params.id);
  if (!existing) {
    notFound(res, 'Availability not found');
    return null;
  }
  if (!canManageSlot(existing, req)) {
    forbidden(res, 'Forbidden. You can only manage your own availability.');
    return null;
  }
  return existing;
}

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

// POST /api/availability  (admin, or a lawyer for their own slots)
router.post(
  '/',
  authenticate,
  requireRole('admin', 'lawyer'),
  asyncHandler(async (req, res) => {
    // A lawyer can only create slots for themselves: the owner id is injected
    // before validation, so a forged `lawyerId` never reaches the store.
    const data = validate(availabilityCreateSchema, {
      ...req.body,
      lawyerId: isAdmin(req) ? req.body?.lawyerId : req.user.uid,
    });

    const createdDoc = await createDoc(getDb(), COLLECTION, data);
    created(res, createdDoc, 'Availability created');
  }),
);

// PUT /api/availability/:id  (admin, or the lawyer who owns the slot)
router.put(
  '/:id',
  authenticate,
  requireRole('admin', 'lawyer'),
  asyncHandler(async (req, res) => {
    const existing = await loadOwnedSlot(req, res);
    if (!existing) return;

    const data = validate(availabilitySchema, req.body, { presence: 'optional' });
    // Ownership is immutable: holding the `lawyer` role must not let a caller
    // reassign a slot to another lawyer.
    if (!isAdmin(req)) data.lawyerId = existing.lawyerId;

    const updated = await updateDoc(getDb(), COLLECTION, req.params.id, data);
    if (!updated) return notFound(res, 'Availability not found');
    ok(res, updated, 'Availability updated');
  }),
);

// DELETE /api/availability/:id  (admin, or the lawyer who owns the slot)
router.delete(
  '/:id',
  authenticate,
  requireRole('admin', 'lawyer'),
  asyncHandler(async (req, res) => {
    const existing = await loadOwnedSlot(req, res);
    if (!existing) return;

    const deleted = await deleteDoc(getDb(), COLLECTION, req.params.id);
    if (!deleted) return notFound(res, 'Availability not found');
    ok(res, { id: req.params.id }, 'Availability deleted');
  }),
);

export default router;
