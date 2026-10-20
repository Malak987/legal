import { Router } from 'express';
import { getDb, getAuth } from '../config/firebase.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { ok, created, notFound, parseListQuery, cleanObject } from '../utils/response.js';
import { validate, userSchema } from '../utils/validators.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { listDocs, getDocById, createDoc, updateDoc, deleteDoc } from '../utils/firestore.js';

const router = Router();
const COLLECTION = 'users';

// GET /api/users?search=&role=admin&page=&limit=   (admin only)
router.get(
  '/',
  authenticate,
  requireRole('admin'),
  asyncHandler(async (req, res) => {
    const q = parseListQuery(req);
    const result = await listDocs(getDb(), COLLECTION, {
      search: q.search,
      searchFields: ['name', 'email', 'phone'],
      filters: cleanObject({ role: req.query.role }),
      page: q.page,
      limit: q.limit,
    });
    ok(res, result);
  }),
);

// GET /api/users/:id  (admin, or the user themselves)
router.get(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    if (req.user.role !== 'admin' && req.user.uid !== req.params.id) {
      return res.status(403).json({ success: false, message: 'Forbidden' });
    }
    const user = await getDocById(getDb(), COLLECTION, req.params.id);
    if (!user) return notFound(res, 'User not found');
    ok(res, user);
  }),
);

// PUT /api/users/:id  (admin, or the user themselves)
router.put(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    if (req.user.role !== 'admin' && req.user.uid !== req.params.id) {
      return res.status(403).json({ success: false, message: 'Forbidden' });
    }
    const data = validate(userSchema, req.body, { presence: 'optional' });
    const updated = await updateDoc(getDb(), COLLECTION, req.params.id, data);
    if (!updated) return notFound(res, 'User not found');
    ok(res, updated, 'User updated');
  }),
);

// DELETE /api/users/:id  (admin only) — also removes the Firebase Auth user
router.delete(
  '/:id',
  authenticate,
  requireRole('admin'),
  asyncHandler(async (req, res) => {
    const deleted = await deleteDoc(getDb(), COLLECTION, req.params.id);
    if (!deleted) return notFound(res, 'User not found');
    try {
      await getAuth().deleteUser(req.params.id);
    } catch (_e) {
      // Auth user may not exist; ignore.
    }
    ok(res, { id: req.params.id }, 'User deleted');
  }),
);

export default router;
