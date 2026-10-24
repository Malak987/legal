import { Router } from 'express';
import { getPublicDb } from '../config/supabase.js';
import { requestDatabase } from '../utils/supabase_rpc.js';
import {
  authenticate,
  optionalAuthenticate,
  requireRole,
  isAdmin,
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
import { validate, lawyerSchema } from '../utils/validators.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import {
  listDocs,
  getDocById,
  createDoc,
  updateDoc,
  deleteDoc,
} from '../utils/supabase_database.js';

const router = Router();
const COLLECTION = 'lawyers';
const USERS_COLLECTION = 'users';
const CATEGORIES_COLLECTION = 'legalCategories';

function isForeignKeyViolation(error) {
  return error?.code === '23503' || /foreign key constraint/i.test(error?.message || '');
}

function presentLawyer(lawyer, req) {
  if (!lawyer) return lawyer;
  if (isAdmin(req)) return lawyer;
  const { userId: _privateUserId, ...publicLawyer } = lawyer;
  return publicLawyer;
}

async function validateCategory(db, data, { required = false } = {}) {
  const categoryId = typeof data.categoryId === 'string' ? data.categoryId.trim() : '';
  if (!categoryId) {
    if (required) return { error: 'categoryId is required; select a legal category.' };
    return { categoryId: null };
  }
  const category = await getDocById(db, CATEGORIES_COLLECTION, categoryId);
  if (!category) return { error: 'Select a legal category that exists.' };
  return { categoryId: category.id, category };
}

async function validateLawyerAccount(db, userId, currentLawyerId = null) {
  const id = typeof userId === 'string' ? userId.trim() : '';
  if (!id) return { userId: null };
  const user = await getDocById(db, USERS_COLLECTION, id);
  if (!user || user.role !== 'lawyer') {
    return { error: 'The linked account must be an existing lawyer account.' };
  }
  const matches = await db.collection(COLLECTION).where('userId', '==', id).get();
  const alreadyAssigned = matches.docs.some((doc) => doc.id !== currentLawyerId);
  if (alreadyAssigned) {
    return { error: 'This lawyer account is already linked to another lawyer profile.' };
  }
  return { userId: id };
}

// GET /api/lawyers?search=&categoryId=&isPopular=true&isTop=true&page=&limit=
router.get(
  '/',
  optionalAuthenticate,
  asyncHandler(async (req, res) => {
    const q = parseListQuery(req);
    const filters = cleanObject({
      isPopular: req.query.isPopular,
      isTop: req.query.isTop,
      categoryId: req.query.categoryId,
    });
    if (filters.isPopular !== undefined) filters.isPopular = filters.isPopular === 'true';
    if (filters.isTop !== undefined) filters.isTop = filters.isTop === 'true';

    // Admin reads are authenticated so their form can resolve the private
    // lawyer-to-user link. Anonymous and ordinary user responses use the
    // public projection and never return userId.
    const db = isAdmin(req) ? requestDatabase(req) : getPublicDb();
    const result = await listDocs(db, COLLECTION, {
      search: q.search,
      searchFields: ['name', 'specialty', 'location'],
      filters,
      sort: 'rating',
      order: 'desc',
      page: q.page,
      limit: q.limit,
    });
    ok(res, { ...result, items: result.items.map((row) => presentLawyer(row, req)) });
  }),
);

// GET /api/lawyers/:id
router.get(
  '/:id',
  optionalAuthenticate,
  asyncHandler(async (req, res) => {
    const db = isAdmin(req) ? requestDatabase(req) : getPublicDb();
    const lawyer = await getDocById(db, COLLECTION, req.params.id);
    if (!lawyer) return notFound(res, 'Lawyer not found');
    ok(res, presentLawyer(lawyer, req));
  }),
);

// POST /api/lawyers — existing admins only; registration cannot grant admin.
router.post(
  '/',
  authenticate,
  requireRole('admin'),
  asyncHandler(async (req, res) => {
    const data = validate(lawyerSchema, req.body);
    const db = requestDatabase(req);
    const category = await validateCategory(db, data, { required: true });
    if (category.error) return badRequest(res, category.error);
    const account = await validateLawyerAccount(db, data.userId);
    if (account.error) return badRequest(res, account.error);

    data.categoryId = category.categoryId;
    data.specialty = category.category.name;
    data.userId = account.userId;
    try {
      const createdDoc = await createDoc(db, COLLECTION, data);
      return created(res, presentLawyer(createdDoc, req), 'Lawyer created');
    } catch (error) {
      if (isForeignKeyViolation(error)) {
        return conflict(res, 'The selected category or account changed before the lawyer could be saved. Refresh and try again.');
      }
      throw error;
    }
  }),
);

// PUT /api/lawyers/:id — admin-only profile and relationship management.
router.put(
  '/:id',
  authenticate,
  requireRole('admin'),
  asyncHandler(async (req, res) => {
    const db = requestDatabase(req);
    const existing = await getDocById(db, COLLECTION, req.params.id);
    if (!existing) return notFound(res, 'Lawyer not found');
    const data = validate(lawyerSchema, req.body, { presence: 'optional', noDefaults: true });

    if (data.categoryId !== undefined) {
      const category = await validateCategory(db, data, { required: false });
      if (category.error) return badRequest(res, category.error);
      data.categoryId = category.categoryId;
      if (category.category) data.specialty = category.category.name;
    }
    if (data.userId !== undefined) {
      const account = await validateLawyerAccount(db, data.userId, existing.id);
      if (account.error) return badRequest(res, account.error);
      data.userId = account.userId;
    }

    try {
      const updated = await updateDoc(db, COLLECTION, req.params.id, data);
      if (!updated) return notFound(res, 'Lawyer not found');
      return ok(res, presentLawyer(updated, req), 'Lawyer updated');
    } catch (error) {
      if (isForeignKeyViolation(error)) {
        return conflict(res, 'The selected category or account changed before the lawyer could be saved. Refresh and try again.');
      }
      throw error;
    }
  }),
);

// DELETE /api/lawyers/:id — database foreign keys preserve booked matters.
router.delete(
  '/:id',
  authenticate,
  requireRole('admin'),
  asyncHandler(async (req, res) => {
    try {
      const deleted = await deleteDoc(requestDatabase(req), COLLECTION, req.params.id);
      if (!deleted) return notFound(res, 'Lawyer not found');
      return ok(res, { id: req.params.id }, 'Lawyer deleted');
    } catch (error) {
      if (isForeignKeyViolation(error)) {
        return conflict(res, 'This lawyer is referenced by a case, booking, or availability record and cannot be deleted.');
      }
      throw error;
    }
  }),
);

export default router;
