import { Router } from 'express';
import { getDb } from '../config/firebase.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { ok, created, notFound, parseListQuery, cleanObject } from '../utils/response.js';
import { validate, lawyerSchema } from '../utils/validators.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { listDocs, getDocById, createDoc, updateDoc, deleteDoc } from '../utils/firestore.js';

const router = Router();
const COLLECTION = 'lawyers';

// GET /api/lawyers?search=&isPopular=true&isTop=true&page=&limit=
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const q = parseListQuery(req);
    const filters = cleanObject({
      isPopular: req.query.isPopular,
      isTop: req.query.isTop,
    });
    // Firestore stores booleans as real booleans; normalize query strings.
    if (filters.isPopular !== undefined) filters.isPopular = filters.isPopular === 'true';
    if (filters.isTop !== undefined) filters.isTop = filters.isTop === 'true';

    const result = await listDocs(getDb(), COLLECTION, {
      search: q.search,
      searchFields: ['name', 'specialty', 'location'],
      filters,
      sort: 'rating',
      order: 'desc',
      page: q.page,
      limit: q.limit,
    });
    ok(res, result);
  }),
);

// GET /api/lawyers/:id
router.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const lawyer = await getDocById(getDb(), COLLECTION, req.params.id);
    if (!lawyer) return notFound(res, 'Lawyer not found');
    ok(res, lawyer);
  }),
);

// POST /api/lawyers  (admin only)
//
// WHY NOT `lawyer` ANY MORE: a lawyer document carries no reference to the
// account that owns it. `seed.js` creates them with auto-generated ids
// (`collection('lawyers').doc()`), the document schema has no `uid`/`userId`
// field, and `req.params.id` is therefore NOT a Firebase uid. Without that
// link there is no way to tell "my profile" from "somebody else's profile",
// so the previous `requireRole('admin','lawyer')` let any lawyer create or
// rewrite any other lawyer's public record — including `rating`, `isTop` and
// `isPopular`. Until an ownership link is designed, mutations are admin-only.
router.post(
  '/',
  authenticate,
  requireRole('admin'),
  asyncHandler(async (req, res) => {
    const data = validate(lawyerSchema, req.body);
    const createdDoc = await createDoc(getDb(), COLLECTION, data);
    created(res, createdDoc, 'Lawyer created');
  }),
);

// PUT /api/lawyers/:id  (admin only)
router.put(
  '/:id',
  authenticate,
  requireRole('admin'),
  asyncHandler(async (req, res) => {
    const data = validate(lawyerSchema, req.body, { presence: 'optional' });
    const updated = await updateDoc(getDb(), COLLECTION, req.params.id, data);
    if (!updated) return notFound(res, 'Lawyer not found');
    ok(res, updated, 'Lawyer updated');
  }),
);

// DELETE /api/lawyers/:id  (admin only)
router.delete(
  '/:id',
  authenticate,
  requireRole('admin'),
  asyncHandler(async (req, res) => {
    const deleted = await deleteDoc(getDb(), COLLECTION, req.params.id);
    if (!deleted) return notFound(res, 'Lawyer not found');
    ok(res, { id: req.params.id }, 'Lawyer deleted');
  }),
);

export default router;
