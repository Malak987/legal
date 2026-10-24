import { Router } from 'express';
import { requestDatabase } from '../utils/supabase_rpc.js';
import {
  authenticate,
  isOwner,
  forbidden,
  ownerIdFor,
  isAdmin,
  lockOwnerOnUpdate,
  requireRole,
} from '../middleware/auth.js';
import {
  ok,
  created,
  notFound,
  badRequest,
  conflict,
  parseListQuery,
  cleanObject,
} from '../utils/response.js';
import { validate, caseSchema, caseUpdateSchema } from '../utils/validators.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { listDocs, getDocById, createDoc, updateDoc, deleteDoc } from '../utils/supabase_database.js';
import { isAssignedLawyer, resolveOwnLawyerId } from '../utils/lawyer_identity.js';

const router = Router();
const COLLECTION = 'cases';
const USERS_COLLECTION = 'users';
const LAWYERS_COLLECTION = 'lawyers';
const CATEGORIES_COLLECTION = 'legalCategories';

/** Cases are owned by a client; the handling lawyer is a separate relation. */
const CASE_OWNER_ROLES = ['client'];

/** Validate that an administrator assigns a case to a real client or lawyer. */
async function resolveOwner(db, req) {
  if (!isAdmin(req)) return {};
  const requested = req.body?.userId;
  if (!requested) {
    return { error: 'userId is required: select a client or lawyer who will own this case.' };
  }
  const profile = await getDocById(db, USERS_COLLECTION, requested);
  if (!profile) return { error: `userId "${requested}" does not match an existing user.` };
  if (!CASE_OWNER_ROLES.includes(profile.role)) {
    return {
      error: `userId "${requested}" is not an eligible case owner ` +
        `(role: ${profile.role || 'unset'}; expected ${CASE_OWNER_ROLES.join(' or ')}).`,
    };
  }
  return {};
}

async function resolveAssignment(db, lawyerId, categoryId) {
  if (!lawyerId || !categoryId) {
    return { error: 'Select both a lawyer and legal category for this case.' };
  }
  const [lawyer, category] = await Promise.all([
    getDocById(db, LAWYERS_COLLECTION, lawyerId),
    getDocById(db, CATEGORIES_COLLECTION, categoryId),
  ]);
  if (!lawyer) return { error: `lawyerId "${lawyerId}" does not match an existing lawyer.` };
  if (!category) return { error: `categoryId "${categoryId}" does not match an existing legal category.` };
  if (lawyer.categoryId !== categoryId) {
    return { error: 'The selected lawyer is not assigned to the selected legal category.' };
  }
  return { lawyer, category };
}

function isForeignKeyViolation(error) {
  return error?.code === '23503' || /foreign key constraint/i.test(error?.message || '');
}

/** Fetches the public display names for one page of case relationships. */
async function labelsById(db, collection, ids) {
  const uniqueIds = [...new Set(ids.filter((id) => typeof id === 'string' && id))];
  if (uniqueIds.length === 0) return new Map();
  const snapshot = await db.collection(collection).where('id', 'in', uniqueIds).get();
  return new Map(snapshot.docs.map((doc) => [doc.id, doc.data()]));
}

async function enrichCaseRelations(db, cases) {
  const [categories, lawyers] = await Promise.all([
    labelsById(db, CATEGORIES_COLLECTION, cases.map((item) => item.categoryId)),
    labelsById(db, LAWYERS_COLLECTION, cases.map((item) => item.lawyerId)),
  ]);
  return cases.map((item) => ({
    ...item,
    categoryName: categories.get(item.categoryId)?.name || item.caseType || '',
    lawyerName: lawyers.get(item.lawyerId)?.name || '',
  }));
}

// GET /api/cases?userId=&status=&priority=&lawyerId=&categoryId=&search=
router.get(
  '/',
  authenticate,
  requireRole('client', 'lawyer', 'admin'),
  asyncHandler(async (req, res) => {
    const q = parseListQuery(req);
    const filters = cleanObject({
      userId: req.query.userId,
      status: req.query.status,
      priority: req.query.priority,
      lawyerId: req.query.lawyerId,
      categoryId: req.query.categoryId,
    });
    // Never trust a caller-supplied owner/assignment filter. Clients read only
    // their own records; lawyers read only rows assigned to their linked
    // lawyer catalogue row; admin/owner accounts may filter across all rows.
    if (!isAdmin(req) && req.user.role === 'client') {
      filters.userId = req.user.uid;
      delete filters.lawyerId;
    } else if (req.user.role === 'lawyer') {
      const lawyerId = await resolveOwnLawyerId(req);
      if (!lawyerId) {
        return forbidden(res, 'No unique lawyer profile is linked to this account.');
      }
      delete filters.userId;
      filters.lawyerId = lawyerId;
    }

    const db = requestDatabase(req);
    const result = await listDocs(db, COLLECTION, {
      search: q.search,
      searchFields: ['title', 'description', 'clientName', 'caseType'],
      filters,
      page: q.page,
      limit: q.limit,
    });
    result.items = await enrichCaseRelations(db, result.items);
    ok(res, result);
  }),
);

// GET /api/cases/:id
router.get(
  '/:id',
  authenticate,
  requireRole('client', 'lawyer', 'admin'),
  asyncHandler(async (req, res) => {
    const db = requestDatabase(req);
    const item = await getDocById(db, COLLECTION, req.params.id);
    if (!item) return notFound(res, 'Case not found');
    const canRead = isOwner(item, req) || await isAssignedLawyer(req, item.lawyerId);
    if (!canRead) {
      return forbidden(res);
    }
    const [enriched] = await enrichCaseRelations(db, [item]);
    ok(res, enriched);
  }),
);

// POST /api/cases
router.post(
  '/',
  authenticate,
  requireRole('client', 'admin'),
  asyncHandler(async (req, res) => {
    const db = requestDatabase(req);
    const owner = await resolveOwner(db, req);
    if (owner.error) return badRequest(res, owner.error);

    const data = validate(caseSchema, { ...req.body, userId: ownerIdFor(req) });
    const hasAssignment = Boolean(data.lawyerId || data.categoryId);
    if (hasAssignment) {
      const assignment = await resolveAssignment(db, data.lawyerId, data.categoryId);
      if (assignment.error) return badRequest(res, assignment.error);
      data.categoryId = assignment.category.id;
      data.lawyerId = assignment.lawyer.id;
      data.caseType = assignment.category.name;
    }
    try {
      const createdDoc = await createDoc(db, COLLECTION, data);
      return created(res, createdDoc, 'Case created');
    } catch (error) {
      if (isForeignKeyViolation(error)) {
        return conflict(res, 'The selected lawyer or category changed before the case could be saved. Refresh and try again.');
      }
      throw error;
    }
  }),
);

// PUT /api/cases/:id
router.put(
  '/:id',
  authenticate,
  requireRole('client', 'admin'),
  asyncHandler(async (req, res) => {
    const db = requestDatabase(req);
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

    const assignmentTouched = data.lawyerId !== undefined || data.categoryId !== undefined;
    if (assignmentTouched) {
      const assignment = await resolveAssignment(
        db,
        data.lawyerId ?? existing.lawyerId,
        data.categoryId ?? existing.categoryId,
      );
      if (assignment.error) return badRequest(res, assignment.error);
      data.lawyerId = assignment.lawyer.id;
      data.categoryId = assignment.category.id;
      data.caseType = assignment.category.name;
    }
    if (existing.categoryId && data.categoryId === undefined) {
      // Normalized category is authoritative for newly categorized cases.
      delete data.caseType;
    }

    // Ownership is immutable here: `userId` in the body cannot reassign a
    // record to another account (admin-only operation).
    lockOwnerOnUpdate(data, existing, req);

    // The verified caller's request-scoped PostgREST client is the live
    // contract for case reads/writes; the earlier local-only rpc_case_update
    // candidate is not present in the connected project's migration history.
    // Omit an unchanged owner so least-privilege column grants remain usable.
    if (data.userId === existing.userId) delete data.userId;
    if (Object.keys(data).length === 0) return ok(res, existing, 'Case unchanged');

    try {
      const updated = await updateDoc(db, COLLECTION, req.params.id, data);
      if (!updated) return notFound(res, 'Case not found');
      return ok(res, updated, 'Case updated');
    } catch (error) {
      if (isForeignKeyViolation(error)) {
        return conflict(res, 'The selected lawyer or category changed before the case could be saved. Refresh and try again.');
      }
      throw error;
    }
  }),
);

// DELETE /api/cases/:id
router.delete(
  '/:id',
  authenticate,
  requireRole('client', 'admin'),
  asyncHandler(async (req, res) => {
    const existing = await getDocById(requestDatabase(req), COLLECTION, req.params.id);
    if (!existing) return notFound(res, 'Case not found');
    if (!isOwner(existing, req)) {
      return forbidden(res);
    }
    await deleteDoc(requestDatabase(req), COLLECTION, req.params.id);
    ok(res, { id: req.params.id }, 'Case deleted');
  }),
);

export default router;
