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
import {
  ok,
  created,
  notFound,
  badRequest,
  parseListQuery,
  cleanObject,
} from '../utils/response.js';
import { validate, caseSchema, caseUpdateSchema } from '../utils/validators.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { listDocs, getDocById, createDoc, updateDoc, deleteDoc } from '../utils/firestore.js';

const router = Router();
const COLLECTION = 'cases';
const USERS_COLLECTION = 'users';

/**
 * Roles that may own a case.
 *
 * An administrator is deliberately excluded: a case belongs to a service user
 * (client, or the lawyer handling their own matter). "Owned by an admin" is the
 * exact symptom of the admin panel creating a case without a client id — see
 * `resolveOwner` below and the Phase 1 report.
 */
const CASE_OWNER_ROLES = ['client', 'lawyer'];

/// Machine-readable marker on a creation that has no client yet.
const CASE_WITHOUT_CLIENT = 'CASE_WITHOUT_CLIENT';

/**
 * Validates the owner an administrator is assigning a case to.
 *
 * Only administrators can choose an owner: `ownerIdFor()` binds every other
 * caller to their own uid and ignores a `userId` in the body (the ownership
 * tests assert that a forged id is ignored, not rejected — so this helper must
 * not turn that 201 into a 403).
 *
 * Returns `{ error }` (→ 400) or `{ warning }` (→ 201 plus a `warnings` entry).
 */
async function resolveOwner(db, req) {
  const requested = req.body?.userId;
  const admin = isAdmin(req);

  if (!admin) return {}; // owner is always req.user.uid; nothing to validate

  if (!requested) {
    // Backward compatibility: the admin panel has no client picker yet, so it
    // posts cases without a `userId`. Rejecting that would break the only
    // working admin flow; silently attributing the case to the administrator
    // would hide a data defect. It is therefore accepted AND reported.
    return { warning: CASE_WITHOUT_CLIENT };
  }

  const profile = await getDocById(db, USERS_COLLECTION, requested);
  if (!profile) {
    return { error: `userId "${requested}" does not match an existing user.` };
  }
  if (!CASE_OWNER_ROLES.includes(profile.role)) {
    return {
      error:
        `userId "${requested}" is not an eligible case owner ` +
        `(role: ${profile.role || 'unset'}; expected ${CASE_OWNER_ROLES.join(' or ')}).`,
    };
  }
  return {};
}

// GET /api/cases?userId=&status=&priority=&search=
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
      searchFields: ['title', 'description', 'clientName', 'caseType'],
      filters,
      page: q.page,
      limit: q.limit,
    });
    ok(res, result);
  }),
);

// GET /api/cases/:id
router.get(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const item = await getDocById(getDb(), COLLECTION, req.params.id);
    if (!item) return notFound(res, 'Case not found');
    if (!isOwner(item, req)) {
      return forbidden(res);
    }
    ok(res, item);
  }),
);

// POST /api/cases
router.post(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const db = getDb();
    const owner = await resolveOwner(db, req);
    if (owner.error) return badRequest(res, owner.error);

    const data = validate(caseSchema, { ...req.body, userId: ownerIdFor(req) });
    const createdDoc = await createDoc(db, COLLECTION, data);

    if (!owner.warning) return created(res, createdDoc, 'Case created');

    // Ids only — no profile contents in the log.
    console.log(
      `[cases] admin_created_without_client actor=${req.user.uid} ` +
        `case=${createdDoc.id} owner=${createdDoc.userId} ` +
        `note="admin panel has no client picker yet; see Phase 1 report"`,
    );
    return created(res, createdDoc, 'Case created', { warnings: [owner.warning] });
  }),
);

// PUT /api/cases/:id
router.put(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const db = getDb();
    const existing = await getDocById(db, COLLECTION, req.params.id);
    if (!existing) return notFound(res, 'Case not found');
    if (!isOwner(existing, req)) {
      return forbidden(res);
    }

    // Ownership is checked before validation so a non-owner learns nothing
    // about the payload schema of a record they may not touch.
    const body = { ...(req.body || {}) };

    // `dueDate` used to be free text, so stored records may hold values that
    // no longer validate. An UNCHANGED value is dropped from the update (it is
    // not rewritten, and editing an unrelated field keeps working); a NEW value
    // must be a real `YYYY-MM-DD` date.
    if (body.dueDate !== undefined && body.dueDate === existing.dueDate) {
      delete body.dueDate;
    }

    // `noDefaults` is what stops a partial update from re-applying the schema
    // defaults (`status: 'Open'`, `priority: 'Medium'`) over the stored values;
    // `caseUpdateSchema` is what makes every field, including `title`, optional.
    const data = validate(caseUpdateSchema, body, {
      presence: 'optional',
      noDefaults: true,
    });

    if (isAdmin(req) && data.userId !== undefined) {
      if (data.userId === '') {
        // An empty id is not a request to clear ownership: that would leave the
        // record unreachable by any client. Ignore it instead of orphaning it.
        delete data.userId;
      } else if (data.userId !== existing.userId) {
        const owner = await resolveOwner(db, req);
        if (owner.error) return badRequest(res, owner.error);
      }
    }

    // Ownership is immutable here: `userId` in the body cannot reassign a
    // record to another account (admin-only operation).
    lockOwnerOnUpdate(data, existing, req);

    const updated = await updateDoc(db, COLLECTION, req.params.id, data);
    ok(res, updated, 'Case updated');
  }),
);

// DELETE /api/cases/:id
router.delete(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const existing = await getDocById(getDb(), COLLECTION, req.params.id);
    if (!existing) return notFound(res, 'Case not found');
    if (!isOwner(existing, req)) {
      return forbidden(res);
    }
    await deleteDoc(getDb(), COLLECTION, req.params.id);
    ok(res, { id: req.params.id }, 'Case deleted');
  }),
);

export default router;
