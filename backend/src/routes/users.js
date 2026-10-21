import { Router } from 'express';
import { getDb, getAuth } from '../config/firebase.js';
import {
  authenticate,
  requireRole,
  requireSelfOrAdmin,
  isAdmin,
  forbidden,
} from '../middleware/auth.js';
import { ok, created, notFound, badRequest, parseListQuery, cleanObject } from '../utils/response.js';
import { validate, userSchema, userRoleSchema } from '../utils/validators.js';
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
  requireSelfOrAdmin('id'),
  asyncHandler(async (req, res) => {
    const user = await getDocById(getDb(), COLLECTION, req.params.id);
    if (!user) return notFound(res, 'User not found');
    ok(res, user);
  }),
);

// PUT /api/users/:id  (admin, or the user themselves)
//
// Only profile fields are writable: `role` is not part of `userSchema`, so a
// `role` sent in the body is stripped by Joi and never reaches Firestore.
// That is what blocks self-escalation to `admin`.
router.put(
  '/:id',
  authenticate,
  requireSelfOrAdmin('id'),
  asyncHandler(async (req, res) => {
    const data = validate(userSchema, req.body, { presence: 'optional' });

    // Defence in depth: even if the schema changes later, a non-admin can
    // never write a role or take over another identity.
    if (!isAdmin(req)) {
      delete data.role;
      delete data.uid;
      delete data.userId;
    }

    const existing = await getDocById(getDb(), COLLECTION, req.params.id);
    if (!existing) return notFound(res, 'User not found');

    if (!isAdmin(req)) {
      // Changing the sign-in address from an ordinary session would let
      // whoever holds a token re-point the account at their own mailbox, and a
      // typo would lock the user out. Keep the stored address unless an
      // administrator changes it.
      if (data.email !== undefined && data.email !== existing.email) {
        return forbidden(
          res,
          'Forbidden. Ask an administrator to change the sign-in email.',
        );
      }
      delete data.email;
    }

    // Firebase Authentication and the profile must not drift: the email in the
    // document is what the panel shows, while the email in Auth is what the
    // user signs in with. Update Auth first, because it is the authority, and
    // roll it back if the profile write fails.
    const emailChanged =
      typeof data.email === 'string' && data.email && data.email !== existing.email;

    if (emailChanged) {
      try {
        await getAuth().updateUser(req.params.id, { email: data.email });
      } catch (error) {
        console.error('[users] auth email update failed:', error?.message);
        return badRequest(
          res,
          'Could not update the sign-in email. Check the address and try again.',
        );
      }
    }

    let updated;
    try {
      updated = await updateDoc(getDb(), COLLECTION, req.params.id, data);
    } catch (error) {
      if (emailChanged) {
        try {
          await getAuth().updateUser(req.params.id, { email: existing.email });
        } catch (revertError) {
          console.error('[users] auth email rollback failed:', revertError?.message);
        }
      }
      throw error;
    }

    if (!updated) return notFound(res, 'User not found');
    ok(res, updated, 'User updated');
  }),
);

// PATCH /api/users/:id/role  (admin only)
//
// Role changes are deliberately separate from the profile update above so the
// privilege boundary is explicit and auditable.
router.patch(
  '/:id/role',
  authenticate,
  requireRole('admin'),
  asyncHandler(async (req, res) => {
    const { role } = validate(userRoleSchema, req.body);

    const existing = await getDocById(getDb(), COLLECTION, req.params.id);
    if (!existing) return notFound(res, 'User not found');

    const updated = await updateDoc(getDb(), COLLECTION, req.params.id, { role });
    if (!updated) return notFound(res, 'User not found');

    // Audit trail for a sensitive change. Ids only — never profile contents.
    // TODO(persistence): move this to a dedicated `audit_logs` collection once
    // that collection is provisioned, so the trail survives a restart.
    console.log(
      `[audit] role_change actor=${req.user.uid} target=${req.params.id} ` +
        `from=${existing.role ?? 'unset'} to=${role} at=${new Date().toISOString()}`,
    );

    ok(res, updated, `Role updated to ${role}`);
  }),
);

// DELETE /api/users/:id  (admin only) — also removes the Firebase Auth user
router.delete(
  '/:id',
  authenticate,
  requireRole('admin'),
  asyncHandler(async (req, res) => {
    // Guard against an administrator removing their own account and locking
    // themselves (and the admin panel) out.
    if (req.params.id === req.user.uid) {
      return forbidden(res, 'You cannot delete your own account.');
    }

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
