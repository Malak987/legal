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
import { ok, created, notFound, badRequest, parseListQuery, cleanObject } from '../utils/response.js';
import { validate, subscriptionSchema } from '../utils/validators.js';
import { canTransition, SUBSCRIPTION_TRANSITIONS } from '../utils/stateTransitions.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { listDocs, getDocById, createDoc, updateDoc, deleteDoc } from '../utils/firestore.js';

const router = Router();
const COLLECTION = 'subscriptions';
const PLANS_COLLECTION = 'plans';

// GET /api/subscriptions?userId=&status=
router.get(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const q = parseListQuery(req);
    const filters = cleanObject({ userId: req.query.userId, status: req.query.status });
    // A non-admin is always scoped to their own records. The old test only
    // applied the scope when `?userId=` was absent, so passing somebody
    // else's id returned their records instead.
    if (!isAdmin(req)) filters.userId = req.user.uid;

    const result = await listDocs(getDb(), COLLECTION, {
      search: q.search,
      searchFields: ['planTitle'],
      filters,
      page: q.page,
      limit: q.limit,
    });
    ok(res, result);
  }),
);

// GET /api/subscriptions/:id
router.get(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const item = await getDocById(getDb(), COLLECTION, req.params.id);
    if (!item) return notFound(res, 'Subscription not found');
    if (!isOwner(item, req)) {
      return forbidden(res);
    }
    ok(res, item);
  }),
);

// POST /api/subscriptions
//
// A subscription always starts as `Pending`. Creating one must never grant a
// paid plan: activation requires an administrator (or, later, a verified
// payment result) — the client cannot buy entitlement by asking for it.
router.post(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const data = validate(subscriptionSchema, { ...req.body, userId: ownerIdFor(req) });

    // The plan title is display data derived from the catalogue, not from the
    // request: otherwise a client could label a cheap plan with a premium name.
    if (data.planId) {
      const plan = await getDocById(getDb(), PLANS_COLLECTION, data.planId);
      if (!plan) return badRequest(res, 'Unknown planId');
      data.planTitle = plan.title ?? '';
    } else if (!isAdmin(req)) {
      // A client-supplied title is not evidence that a plan was bought. Only an
      // administrator (who is trusted for manual records) may set one directly.
      delete data.planTitle;
    }

    if (!isAdmin(req)) {
      data.status = 'Pending';
    }

    const createdDoc = await createDoc(getDb(), COLLECTION, data);
    created(res, createdDoc, 'Subscription created');
  }),
);

// PUT /api/subscriptions/:id
router.put(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    // `noDefaults` keeps a field the caller did not send out of the update —
    // without it, PUT { planTitle } would silently reset `status` to its
    // schema default and reactivate an expired subscription.
    const data = validate(subscriptionSchema, req.body, {
      presence: 'optional',
      noDefaults: true,
    });

    const existing = await getDocById(getDb(), COLLECTION, req.params.id);
    if (!existing) return notFound(res, 'Subscription not found');
    if (!isOwner(existing, req)) {
      return forbidden(res);
    }

    if (!isAdmin(req)) {
      // Plan changes are commercial decisions (an upgrade costs money).
      if (data.planId !== undefined || data.planTitle !== undefined) {
        return forbidden(
          res,
          'Forbidden. Only an administrator can change the subscription plan.',
        );
      }
      if (data.status !== undefined) {
        if (!canTransition(SUBSCRIPTION_TRANSITIONS, existing.status, data.status)) {
          return forbidden(
            res,
            `Forbidden. Cannot change a ${existing.status ?? 'unspecified'} ` +
              `subscription to ${data.status}.`,
          );
        }
      }
    }

    // Authorised callers only from here: whenever the plan reference is
    // supplied it must exist, and the stored title is taken from that trusted
    // record. `planTitle` alone remains admin-only above, so a client can never
    // rename its way into a plan.
    if (data.planId !== undefined) {
      if (!data.planId) {
        return badRequest(res, 'planId cannot be empty');
      }
      const plan = await getDocById(getDb(), PLANS_COLLECTION, data.planId);
      if (!plan) return badRequest(res, 'Unknown planId');
      data.planTitle = plan.title ?? '';
    }

    // Ownership is immutable here: `userId` in the body cannot reassign a
    // record to another account (admin-only operation).
    lockOwnerOnUpdate(data, existing, req);

    const updated = await updateDoc(getDb(), COLLECTION, req.params.id, data);
    ok(res, updated, 'Subscription updated');
  }),
);

// DELETE /api/subscriptions/:id
router.delete(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const existing = await getDocById(getDb(), COLLECTION, req.params.id);
    if (!existing) return notFound(res, 'Subscription not found');
    if (!isOwner(existing, req)) {
      return forbidden(res);
    }

    // An Active subscription is financial history: deleting it would erase the
    // record of what the account was entitled to. Owners cancel instead; only
    // an administrator may hard-delete one.
    if (existing.status === 'Active' && !isAdmin(req)) {
      return forbidden(
        res,
        'Forbidden. Cancel the subscription instead of deleting an active one.',
      );
    }

    await deleteDoc(getDb(), COLLECTION, req.params.id);
    ok(res, { id: req.params.id }, 'Subscription deleted');
  }),
);

export default router;
