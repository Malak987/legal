import { Router } from 'express';
import { requestDatabase, callUserRpc, rpcErrorToken, rpcRow } from '../utils/supabase_rpc.js';
import {
  authenticate,
  requireRole,
  requireSelfOrAdmin,
  isAdmin,
  forbidden,
} from '../middleware/auth.js';
import {
  ok,
  notFound,
  badRequest,
  conflict,
  parseListQuery,
  cleanObject,
} from '../utils/response.js';
import { validate, userUpdateSchema, userRoleSchema } from '../utils/validators.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { listDocs, getDocById, updateDoc } from '../utils/supabase_database.js';

const router = Router();
const COLLECTION = 'users';

// GET /api/users?search=&role=&page=&limit= (admin only)
router.get(
  '/',
  authenticate,
  requireRole('admin'),
  asyncHandler(async (req, res) => {
    const q = parseListQuery(req);
    const result = await listDocs(requestDatabase(req), COLLECTION, {
      search: q.search,
      searchFields: ['name', 'email', 'phone'],
      filters: cleanObject({ role: req.query.role }),
      page: q.page,
      limit: q.limit,
    });
    ok(res, result);
  }),
);

// GET /api/users/me — application profile linked to this verified Auth UUID.
router.get(
  '/me',
  authenticate,
  asyncHandler(async (req, res) => {
    const profile = await getDocById(requestDatabase(req), COLLECTION, req.user.uid);
    if (!profile) return notFound(res, 'No profile is linked to this Supabase Auth account.');
    ok(res, profile);
  }),
);

// The former profile-creation endpoint is intentionally non-mutating. New
// profiles are created by the trusted auth.users trigger after email confirm.
router.post(
  '/me',
  authenticate,
  asyncHandler(async (_req, res) =>
    res.status(409).json({
      success: false,
      message: 'Profile creation is managed by the Supabase Auth lifecycle.',
    }),
  ),
);

// GET /api/users/:id (administrator, or the user themselves)
router.get(
  '/:id',
  authenticate,
  requireSelfOrAdmin('id'),
  asyncHandler(async (req, res) => {
    const user = await getDocById(requestDatabase(req), COLLECTION, req.params.id);
    if (!user) return notFound(res, 'User not found');
    ok(res, user);
  }),
);

// PUT /api/users/:id (administrator, or the user themselves). Auth identity,
// email, role and ownership are server-managed; profile edits cannot alter them.
router.put(
  '/:id',
  authenticate,
  requireSelfOrAdmin('id'),
  asyncHandler(async (req, res) => {
    const data = validate(userUpdateSchema, req.body, { presence: 'optional' });
    const existing = await getDocById(requestDatabase(req), COLLECTION, req.params.id);
    if (!existing) return notFound(res, 'User not found');

    if (data.email !== undefined && data.email !== existing.email) {
      return badRequest(
        res,
        'Sign-in email changes must use Supabase Auth’s verified email-change flow.',
      );
    }
    delete data.email;
    delete data.role;
    delete data.uid;
    delete data.userId;
    delete data.authUserId;
    if (Object.keys(data).length === 0) return conflict(res, 'No editable profile fields were supplied.');

    const updated = await updateDoc(requestDatabase(req), COLLECTION, req.params.id, data);
    if (!updated) return notFound(res, 'User not found');
    ok(res, updated, 'User updated');
  }),
);

// PATCH /api/users/:id/role (existing administrator only). The security-
// definer RPC re-checks auth.uid(), the stored admin role and last-admin rule.
router.patch(
  '/:id/role',
  authenticate,
  requireRole('admin'),
  asyncHandler(async (req, res) => {
    const { role } = validate(userRoleSchema, req.body);
    const existing = await getDocById(requestDatabase(req), COLLECTION, req.params.id);
    if (!existing) return notFound(res, 'User not found');
    if (existing.role === 'owner') {
      return forbidden(res, 'Owner role changes are reserved for trusted provisioning.');
    }

    let updated;
    try {
      const outcome = await callUserRpc(req, 'rpc_admin_set_user_role', {
        p_user_id: req.params.id,
        p_role: role,
      });
      updated = rpcRow(COLLECTION, outcome);
    } catch (error) {
      const token = rpcErrorToken(error);
      if (error.code === 'P0002' || token === 'USER_NOT_FOUND') return notFound(res, 'User not found');
      if (error.code === '42501') return forbidden(res, 'Forbidden. The last administrator cannot be demoted.');
      if (error.code === '22023') return badRequest(res, 'Invalid role');
      throw error;
    }
    if (!updated) return notFound(res, 'User not found');

    console.log(
      `[audit] role_change actor=${req.user.uid} target=${req.params.id} ` +
        `from=${existing.role ?? 'unset'} to=${role} at=${new Date().toISOString()}`,
    );
    ok(res, updated, `Role updated to ${role}`);
  }),
);

// Account deletion is deliberately disabled: no approved retention workflow
// currently defines how to preserve booked matters, payments, and audit history.
router.delete(
  '/:id',
  authenticate,
  requireRole('admin'),
  asyncHandler(async (req, res) => {
    if (req.params.id === req.user.uid) {
      return forbidden(res, 'You cannot delete your own account.');
    }
    return forbidden(
      res,
      'Account deletion is disabled until an approved data-retention workflow exists.',
    );
  }),
);

export default router;
