import { Router } from 'express';
import { getPublicDb } from '../config/supabase.js';
import { requestDatabase } from '../utils/supabase_rpc.js';
import {
  authenticate,
  requireRole,
  isAdmin,
  forbidden,
} from '../middleware/auth.js';
import { ok, created, notFound, badRequest, parseListQuery } from '../utils/response.js';
import {
  validate,
  availabilitySchema,
  availabilityCreateSchema,
} from '../utils/validators.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { listDocs, getDocById, createDoc, updateDoc, deleteDoc } from '../utils/supabase_database.js';
import { resolveOwnLawyerId } from '../utils/lawyer_identity.js';

const router = Router();
const COLLECTION = 'availability';

/// Availability belongs to a lawyer, identified by `lawyerId`.
/// An administrator manages every slot; a lawyer manages only their own.
async function canManageSlot(record, req) {
  if (isAdmin(req)) return true;
  const lawyerId = await resolveOwnLawyerId(req);
  return Boolean(lawyerId && record?.lawyerId) && record.lawyerId === lawyerId;
}

/// Loads a slot and answers 404/403 consistently.
/// Returns `null` when the request has already been answered.
async function loadOwnedSlot(req, res) {
  const existing = await getDocById(requestDatabase(req), COLLECTION, req.params.id);
  if (!existing) {
    notFound(res, 'Availability not found');
    return null;
  }
  if (!(await canManageSlot(existing, req))) {
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
    const result = await listDocs(getPublicDb(), COLLECTION, {
      search: q.search,
      searchFields: ['date', 'lawyerName'],
      filters: req.query.lawyerId ? { lawyerId: req.query.lawyerId } : {},
      page: q.page,
      limit: q.limit,
    });
    ok(res, result);
  }),
);

// GET /api/availability/mine — authenticated lawyer's own schedule only.
router.get(
  '/mine',
  authenticate,
  requireRole('lawyer'),
  asyncHandler(async (req, res) => {
    const lawyerId = await resolveOwnLawyerId(req);
    if (!lawyerId) {
      return forbidden(res, 'No unique lawyer profile is linked to this account.');
    }
    const q = parseListQuery(req);
    const result = await listDocs(requestDatabase(req), COLLECTION, {
      search: q.search,
      searchFields: ['date', 'lawyerName'],
      filters: { lawyerId },
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
    const item = await getDocById(getPublicDb(), COLLECTION, req.params.id);
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
    // A lawyer can only create slots for their linked catalogue row. The row
    // ID is resolved from the verified application profile, never from an Auth
    // UUID equality assumption or caller-supplied `lawyerId`.
    const lawyerId = isAdmin(req)
      ? req.body?.lawyerId
      : await resolveOwnLawyerId(req);
    if (!isAdmin(req) && !lawyerId) {
      return forbidden(res, 'No unique lawyer profile is linked to this account.');
    }
    const data = validate(availabilityCreateSchema, {
      ...req.body,
      lawyerId,
    });

    const createdDoc = await createDoc(requestDatabase(req), COLLECTION, data);
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

    const updated = await updateDoc(requestDatabase(req), COLLECTION, req.params.id, data);
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

    const deleted = await deleteDoc(requestDatabase(req), COLLECTION, req.params.id);
    if (!deleted) return notFound(res, 'Availability not found');
    ok(res, { id: req.params.id }, 'Availability deleted');
  }),
);

export default router;
