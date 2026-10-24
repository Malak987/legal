import { Router } from 'express';
import { requestDatabase, callUserRpc, rpcErrorToken, rpcRow } from '../utils/supabase_rpc.js';
import {
  authenticate,
  isOwner,
  forbidden,
  ownerIdFor,
  isAdmin,
} from '../middleware/auth.js';
import { ok, created, notFound, badRequest, parseListQuery, cleanObject } from '../utils/response.js';
import { validate, subscriptionSchema } from '../utils/validators.js';
import { canTransition, SUBSCRIPTION_TRANSITIONS } from '../utils/stateTransitions.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { listDocs, getDocById } from '../utils/supabase_database.js';

const router = Router();
const COLLECTION = 'subscriptions';
const PLANS_COLLECTION = 'plans';

router.get(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const q = parseListQuery(req);
    const filters = cleanObject({ userId: req.query.userId, status: req.query.status });
    if (!isAdmin(req)) filters.userId = req.user.uid;
    const result = await listDocs(requestDatabase(req), COLLECTION, {
      search: q.search,
      searchFields: ['planTitle'],
      filters,
      page: q.page,
      limit: q.limit,
    });
    ok(res, result);
  }),
);

router.get(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const item = await getDocById(requestDatabase(req), COLLECTION, req.params.id);
    if (!item) return notFound(res, 'Subscription not found');
    if (!isOwner(item, req)) return forbidden(res);
    ok(res, item);
  }),
);

// A subscription always starts Pending. Paid activation is not available until
// a verified billing-provider workflow exists.
router.post(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const data = validate(subscriptionSchema, { ...req.body, userId: ownerIdFor(req) });
    if (!data.planId) return badRequest(res, 'planId is required to create a subscription');
    const plan = await getDocById(requestDatabase(req), PLANS_COLLECTION, data.planId);
    if (!plan) return badRequest(res, 'Unknown planId');
    if (data.status && data.status !== 'Pending') {
      return forbidden(res, 'Paid subscription activation requires a verified payment-provider workflow.');
    }
    try {
      const outcome = await callUserRpc(req, 'rpc_subscription_create', {
        p_plan_id: data.planId,
        p_user_id: data.userId || req.user.uid,
      });
      const subscription = rpcRow(COLLECTION, outcome);
      if (!subscription) throw new Error('Supabase subscription RPC returned an unexpected result.');
      return created(res, subscription, 'Subscription created');
    } catch (error) {
      const token = rpcErrorToken(error);
      if (error.code === '42501') return forbidden(res, 'Forbidden. You cannot create this subscription.');
      if (error.code === '22023') return badRequest(res, `Invalid subscription (${token || 'validation failed'}).`);
      throw error;
    }
  }),
);

router.put(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const data = validate(subscriptionSchema, req.body, { presence: 'optional', noDefaults: true });
    const existing = await getDocById(requestDatabase(req), COLLECTION, req.params.id);
    if (!existing) return notFound(res, 'Subscription not found');
    if (!isOwner(existing, req)) return forbidden(res);

    if (data.userId !== undefined && data.userId !== existing.userId) {
      return forbidden(res, 'Subscription ownership cannot be reassigned.');
    }
    if (data.planId !== undefined || data.planTitle !== undefined) {
      return forbidden(res, 'Subscription plan changes require an approved billing workflow.');
    }
    if (data.status === undefined) return ok(res, existing, 'Subscription unchanged');
    if (data.status !== 'Cancelled') {
      return forbidden(res, 'Paid subscription status changes require a verified payment-provider workflow.');
    }
    if (!canTransition(SUBSCRIPTION_TRANSITIONS, existing.status, data.status)) {
      return forbidden(res, `Forbidden. Cannot change a ${existing.status ?? 'unspecified'} subscription to ${data.status}.`);
    }

    try {
      const outcome = await callUserRpc(req, 'rpc_subscription_cancel', {
        p_subscription_id: req.params.id,
      });
      const updated = rpcRow(COLLECTION, outcome);
      if (!updated) throw new Error('Supabase subscription cancellation RPC returned an unexpected result.');
      return ok(res, updated, 'Subscription cancelled');
    } catch (error) {
      const token = rpcErrorToken(error);
      if (error.code === 'P0002' || token === 'SUBSCRIPTION_NOT_FOUND') return notFound(res, 'Subscription not found');
      if (error.code === '42501') return forbidden(res, 'Forbidden. This subscription cannot be cancelled.');
      if (error.code === '22023') return badRequest(res, `Invalid subscription update (${token || 'validation failed'}).`);
      throw error;
    }
  }),
);

router.delete(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const existing = await getDocById(requestDatabase(req), COLLECTION, req.params.id);
    if (!existing) return notFound(res, 'Subscription not found');
    if (!isOwner(existing, req)) return forbidden(res);
    if (existing.status === 'Active') {
      return forbidden(res, 'Active subscriptions are financial history and cannot be deleted.');
    }
    try {
      await callUserRpc(req, 'rpc_subscription_delete', { p_subscription_id: req.params.id });
      return ok(res, { id: req.params.id }, 'Subscription deleted');
    } catch (error) {
      const token = rpcErrorToken(error);
      if (error.code === 'P0002' || token === 'SUBSCRIPTION_NOT_FOUND') return notFound(res, 'Subscription not found');
      if (error.code === '42501') return forbidden(res, 'Forbidden. This subscription cannot be deleted.');
      throw error;
    }
  }),
);

export default router;
