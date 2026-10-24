import { Router } from 'express';
import { getPublicDb } from '../config/supabase.js';
import { requestDatabase } from '../utils/supabase_rpc.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import {
  ok,
  created,
  notFound,
  badRequest,
  conflict,
  parseListQuery,
} from '../utils/response.js';
import {
  validate,
  legalCategorySchema,
  legalCategoryUpdateSchema,
} from '../utils/validators.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import {
  listDocs,
  getDocById,
  createDoc,
  updateDoc,
  deleteDoc,
} from '../utils/supabase_database.js';

const router = Router();
const COLLECTION = 'legalCategories';

/** Generate a stable Unicode-aware slug; uniqueness is enforced in PostgreSQL. */
function slugify(value) {
  return String(value ?? '')
    .normalize('NFKD')
    .replace(/\p{M}+/gu, '')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 160)
    .replace(/-+$/g, '');
}

function isUniqueViolation(error) {
  return error?.code === '23505' || /duplicate key|unique constraint/i.test(error?.message || '');
}

function isForeignKeyViolation(error) {
  return error?.code === '23503' || /foreign key constraint/i.test(error?.message || '');
}

function validCategoryId(id) {
  return typeof id === 'string' && id.trim().length > 0 && id.length <= 160;
}

// GET /api/categories?search=&page=&limit=
// Legal categories are public catalogue data; the table's SELECT policy
// controls this read, and no profile or private lawyer fields are returned.
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const query = parseListQuery(req);
    const result = await listDocs(getPublicDb(), COLLECTION, {
      search: query.search,
      searchFields: ['name', 'slug'],
      sort: 'name',
      order: 'asc',
      page: query.page,
      limit: query.limit,
    });
    ok(res, result);
  }),
);

// GET /api/categories/:id
router.get(
  '/:id',
  asyncHandler(async (req, res) => {
    if (!validCategoryId(req.params.id)) return badRequest(res, 'Invalid category ID.');
    const category = await getDocById(getPublicDb(), COLLECTION, req.params.id);
    if (!category) return notFound(res, 'Legal category not found');
    ok(res, category);
  }),
);

// POST /api/categories — only an already-provisioned administrator may write.
router.post(
  '/',
  authenticate,
  requireRole('admin'),
  asyncHandler(async (req, res) => {
    const data = validate(legalCategorySchema, req.body);
    data.slug = slugify(data.slug || data.name);
    if (!data.slug) return badRequest(res, 'Category name must produce a valid slug.');

    try {
      const category = await createDoc(requestDatabase(req), COLLECTION, data);
      return created(res, category, 'Legal category created');
    } catch (error) {
      if (isUniqueViolation(error)) {
        return conflict(res, 'A legal category with this name or slug already exists.');
      }
      throw error;
    }
  }),
);

// PUT /api/categories/:id — rename/slug edits are reflected in linked display
// fields by the database trigger; the category ID and relationships stay stable.
router.put(
  '/:id',
  authenticate,
  requireRole('admin'),
  asyncHandler(async (req, res) => {
    if (!validCategoryId(req.params.id)) return badRequest(res, 'Invalid category ID.');
    const db = requestDatabase(req);
    const existing = await getDocById(db, COLLECTION, req.params.id);
    if (!existing) return notFound(res, 'Legal category not found');

    const data = validate(legalCategoryUpdateSchema, req.body, {
      presence: 'optional',
      noDefaults: true,
    });
    if (data.name !== undefined && data.slug === undefined) {
      data.slug = slugify(data.name);
    } else if (data.slug !== undefined) {
      data.slug = slugify(data.slug);
    }
    if (data.slug !== undefined && !data.slug) {
      return badRequest(res, 'Category name or slug must produce a valid slug.');
    }

    try {
      const updated = await updateDoc(db, COLLECTION, req.params.id, data);
      if (!updated) return notFound(res, 'Legal category not found');
      return ok(res, updated, 'Legal category updated');
    } catch (error) {
      if (isUniqueViolation(error)) {
        return conflict(res, 'A legal category with this name or slug already exists.');
      }
      throw error;
    }
  }),
);

// DELETE /api/categories/:id — referenced categories are protected by RESTRICT
// foreign keys; no lawyer or case is cascaded or silently de-categorized.
router.delete(
  '/:id',
  authenticate,
  requireRole('admin'),
  asyncHandler(async (req, res) => {
    if (!validCategoryId(req.params.id)) return badRequest(res, 'Invalid category ID.');
    try {
      const deleted = await deleteDoc(requestDatabase(req), COLLECTION, req.params.id);
      if (!deleted) return notFound(res, 'Legal category not found');
      return ok(res, { id: req.params.id }, 'Legal category deleted');
    } catch (error) {
      if (isForeignKeyViolation(error)) {
        return conflict(res, 'This category is assigned to one or more lawyers or cases.');
      }
      throw error;
    }
  }),
);

export default router;
