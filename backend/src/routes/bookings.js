import { Router } from 'express';
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
import { validate, bookingSchema, bookingCreateSchema } from '../utils/validators.js';
import { canTransition, BOOKING_TRANSITIONS } from '../utils/stateTransitions.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import {
  listDocs,
  getDocById,
} from '../utils/supabase_database.js';
import { formatClockTime, parseClockTime } from '../utils/scheduling.js';
import {
  callUserRpc,
  requestDatabase,
  rpcErrorToken,
  rpcRow,
} from '../utils/supabase_rpc.js';
import { BOOKINGS_COLLECTION } from '../utils/bookingReservation.js';
import { isAssignedLawyer, resolveOwnLawyerId } from '../utils/lawyer_identity.js';

const router = Router();
const COLLECTION = BOOKINGS_COLLECTION;
const LAWYERS_COLLECTION = 'lawyers';

// Fields that define the appointment. Clients cannot rewrite them after
// creation; administrators can, and get the price recomputed when they do.
const CLIENT_IMMUTABLE_FIELDS = ['lawyerId', 'lawyerName', 'date', 'time', 'hours'];

function bookingRpcErrorResponse(res, error) {
  const token = error?.error || rpcErrorToken(error);
  const code = error?.code;
  if (code === '42501' || ['NOT_BOOKING_OWNER', 'ADMIN_REQUIRED', 'BOOKING_CANNOT_BE_CANCELLED'].includes(token)) {
    return forbidden(res, 'Forbidden. This booking operation is not authorized.');
  }
  if (code === 'P0002' || token === 'BOOKING_NOT_FOUND') {
    return notFound(res, 'Booking not found');
  }
  if (token === 'IDEMPOTENCY_KEY_MISMATCH') {
    return conflict(res, 'Idempotency-Key was already used for a different booking.');
  }
  if (token === 'NO_AVAILABILITY') {
    return badRequest(res, 'The lawyer has published no availability on that date. Choose another date.');
  }
  if (token === 'TIME_NOT_AVAILABLE') {
    return badRequest(res, 'That time is not offered by this lawyer. Choose an available slot.');
  }
  if (['BOOKING_OVERLAP', 'LEGACY_BOOKING_REVIEW_REQUIRED', 'BOOKING_SLOT_TAKEN', 'SLOT_TAKEN'].includes(token)) {
    return conflict(res, token === 'LEGACY_BOOKING_REVIEW_REQUIRED'
      ? 'An existing booking needs operator review before this slot can be reserved.'
      : 'The requested time slot is no longer available. Choose another time.');
  }
  if (code === '22023' || ['INVALID_BOOKING_DURATION', 'INVALID_BOOKING_TIME', 'INVALID_BOOKING_DATE', 'IDEMPOTENCY_KEY_TOO_LONG', 'LAWYER_NOT_FOUND', 'LAWYER_RATE_NOT_CONFIGURED'].includes(token)) {
    const messages = {
      INVALID_BOOKING_DURATION: 'hours must be between 1 and 12.',
      INVALID_BOOKING_TIME: 'The requested time is invalid.',
      INVALID_BOOKING_DATE: 'The requested date is invalid.',
      IDEMPOTENCY_KEY_TOO_LONG: 'Idempotency-Key must be at most 128 characters.',
      LAWYER_NOT_FOUND: 'Lawyer not found',
      LAWYER_RATE_NOT_CONFIGURED: 'Lawyer has no configured hourly rate',
    };
    return badRequest(res, messages[token] || 'Invalid booking request.');
  }
  return null;
}

// GET /api/bookings?userId=&status=&lawyerId=
router.get(
  '/',
  authenticate,
  requireRole('client', 'lawyer', 'admin'),
  asyncHandler(async (req, res) => {
    const q = parseListQuery(req);
    const filters = cleanObject({
      userId: req.query.userId,
      status: req.query.status,
      lawyerId: req.query.lawyerId,
    });
    // Scope clients to their own bookings and lawyers to their assigned
    // catalogue row. Query-string owner/lawyer IDs never broaden access.
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

    const result = await listDocs(requestDatabase(req), COLLECTION, {
      search: q.search,
      searchFields: ['lawyerName', 'date', 'time'],
      filters,
      page: q.page,
      limit: q.limit,
    });
    ok(res, result);
  }),
);

// GET /api/bookings/:id
router.get(
  '/:id',
  authenticate,
  requireRole('client', 'lawyer', 'admin'),
  asyncHandler(async (req, res) => {
    const item = await getDocById(requestDatabase(req), COLLECTION, req.params.id);
    if (!item) return notFound(res, 'Booking not found');
    const canRead = isOwner(item, req) || await isAssignedLawyer(req, item.lawyerId);
    if (!canRead) {
      return forbidden(res);
    }
    ok(res, item);
  }),
);

/**
 * Prices a booking from trusted data only.
 *
 * The rate comes from the lawyer document (`priceValue`, the same field the
 * seed and the admin panel maintain) and is multiplied by the requested hours.
 * Nothing the client sends is used as a price. Returns `{ error }` when the
 * lawyer is unknown or has no configured rate, because silently booking at a
 * guessed price would be worse than refusing.
 */
async function priceBooking(db, { lawyerId, hours }) {
  const lawyer = await getDocById(db, LAWYERS_COLLECTION, lawyerId);
  if (!lawyer) return { error: 'Lawyer not found' };

  const rate = lawyer.priceValue;
  if (typeof rate !== 'number' || !Number.isFinite(rate) || rate < 0) {
    return { error: 'Lawyer has no configured hourly rate' };
  }

  // Two-decimal money arithmetic in integer cents.
  const totalPrice = Math.round(rate * hours * 100) / 100;
  return { lawyer, rate, totalPrice };
}

// POST /api/bookings. PostgreSQL RPC validates the trusted lawyer rate and
// availability, then reserves the booking and every occupied slot atomically.
router.post(
  '/',
  authenticate,
  requireRole('client', 'admin'),
  asyncHandler(async (req, res) => {
    const data = validate(bookingCreateSchema, { ...req.body, userId: ownerIdFor(req) });
    const startMinutes = parseClockTime(data.time);
    if (startMinutes === null) {
      return badRequest(
        res,
        'time is required and must be a time of day, for example 09:00 or 9:00 am.',
      );
    }

    const idempotencyKey = String(req.get('Idempotency-Key') || '').trim();
    if (idempotencyKey.length > 128) {
      return badRequest(res, 'Idempotency-Key must be at most 128 characters.');
    }

    let outcome;
    try {
      outcome = await callUserRpc(req, 'rpc_create_booking', {
        p_lawyer_id: data.lawyerId,
        p_date: data.date,
        p_time: formatClockTime(startMinutes),
        p_hours: data.hours,
        p_idempotency_key: idempotencyKey || null,
        p_user_id: data.userId,
      });
    } catch (error) {
      const mapped = bookingRpcErrorResponse(res, error);
      if (mapped) return mapped;
      throw error;
    }

    if (outcome?.error) {
      const mapped = bookingRpcErrorResponse(res, outcome);
      if (mapped) return mapped;
      throw new Error(`Supabase booking RPC returned an unknown error: ${outcome.error}`);
    }
    const saved = rpcRow('bookings', outcome?.booking);
    if (!saved) throw new Error('Supabase booking RPC returned an unexpected result.');
    if (outcome.replayed) return ok(res, saved, 'Duplicate request ignored');
    return created(res, saved, 'Booking created');
  }),
);

// PUT /api/bookings/:id  (used to change status: Active / Completed / Cancelled)
router.put(
  '/:id',
  authenticate,
  requireRole('client', 'admin'),
  asyncHandler(async (req, res) => {
    // `noDefaults` stops a partial update from writing the schema default
    // `status: 'Pending'` over the record's real status.
    const data = validate(bookingSchema, req.body, {
      presence: 'optional',
      noDefaults: true,
    });
    // Empty/null time is the legacy API's "unchanged" sentinel, not a new
    // schedule value.
    if (data.time === '' || data.time === null) delete data.time;

    const db = requestDatabase(req);
    const existing = await getDocById(db, COLLECTION, req.params.id);
    if (!existing) return notFound(res, 'Booking not found');
    if (!isOwner(existing, req)) {
      return forbidden(res);
    }

    if (!isAdmin(req)) {
      // A client may only CANCEL. Everything that defines the appointment —
      // who, when, how long, at what price — is fixed at creation: the server
      // derives the price from the lawyer's rate, and a reschedule has to go
      // through the availability check an administrator is allowed to make.
      const attempted = CLIENT_IMMUTABLE_FIELDS.filter(
        (field) => data[field] !== undefined,
      );
      if (attempted.length) {
        return forbidden(
          res,
          `Forbidden. Only an administrator can change ${attempted.join(', ')}.`,
        );
      }
      if (data.status !== undefined) {
        if (!canTransition(BOOKING_TRANSITIONS, existing.status, data.status)) {
          return forbidden(
            res,
            `Forbidden. Cannot change a ${existing.status ?? 'unspecified'} ` +
              `booking to ${data.status}.`,
          );
        }
      }
    } else if (data.lawyerId !== undefined || data.hours !== undefined) {
      // An administrator may reschedule or rebook, but the derived fields must
      // be recomputed: changing the lawyer (or the hours) would otherwise keep
      // the previous lawyer's price and name on the record.
      const priced = await priceBooking(db, {
        lawyerId: data.lawyerId ?? existing.lawyerId,
        hours: data.hours ?? existing.hours,
      });
      if (priced.error) return badRequest(res, priced.error);
      data.totalPrice = priced.totalPrice;
      data.lawyerName = priced.lawyer.name ?? data.lawyerName ?? '';
    }

    // Ownership is immutable here: `userId` in the body cannot reassign a
    // record to another account (admin-only operation).
    lockOwnerOnUpdate(data, existing, req);

    const nextStatus = data.status ?? existing.status;
    const cancelling = nextStatus === 'Cancelled' && existing.status !== 'Cancelled';

    const nextLawyerId = data.lawyerId ?? existing.lawyerId;
    const nextDate = data.date ?? existing.date;
    const nextHours = data.hours ?? existing.hours;
    const nextStart = parseClockTime(data.time ?? existing.time);
    const scheduleChanged =
      nextLawyerId !== existing.lawyerId ||
      nextDate !== existing.date ||
      nextHours !== existing.hours ||
      nextStart !== parseClockTime(existing.time);

    if (data.userId !== undefined && data.userId !== existing.userId) {
      return badRequest(res, 'Booking ownership cannot be reassigned.');
    }
    if (data.lawyerName !== undefined && data.lawyerName !== existing.lawyerName) {
      return badRequest(res, 'Lawyer name is derived from the lawyer profile and cannot be changed directly.');
    }
    if (cancelling && scheduleChanged) {
      return badRequest(res, 'Cancel and reschedule are separate booking operations.');
    }
    if (scheduleChanged && data.status !== undefined && data.status !== existing.status) {
      return badRequest(res, 'Update booking status and reschedule in separate requests.');
    }

    if (cancelling) {
      try {
        const outcome = await callUserRpc(req, 'rpc_cancel_booking', {
          p_booking_id: existing.id,
        });
        return ok(res, rpcRow('bookings', outcome), 'Booking updated');
      } catch (error) {
        const mapped = bookingRpcErrorResponse(res, error);
        if (mapped) return mapped;
        throw error;
      }
    }

    if (scheduleChanged) {
      if (!isAdmin(req)) return forbidden(res, 'Only an administrator can reschedule a booking.');
      if (nextStart === null) return badRequest(res, 'A valid booking time is required.');
      try {
        const outcome = await callUserRpc(req, 'rpc_admin_reschedule_booking', {
          p_booking_id: existing.id,
          p_lawyer_id: nextLawyerId,
          p_date: nextDate,
          p_time: formatClockTime(nextStart),
          p_hours: nextHours,
        });
        if (outcome?.error) {
          const mapped = bookingRpcErrorResponse(res, outcome);
          if (mapped) return mapped;
          throw new Error(`Supabase reschedule RPC returned an unknown error: ${outcome.error}`);
        }
        return ok(res, rpcRow('bookings', outcome), 'Booking updated');
      } catch (error) {
        const mapped = bookingRpcErrorResponse(res, error);
        if (mapped) return mapped;
        throw error;
      }
    }

    if (data.status !== undefined && data.status !== existing.status) {
      if (!isAdmin(req)) return forbidden(res, 'Only an administrator can set this booking status.');
      try {
        const outcome = await callUserRpc(req, 'rpc_admin_set_booking_status', {
          p_booking_id: existing.id,
          p_status: data.status,
        });
        return ok(res, rpcRow('bookings', outcome), 'Booking updated');
      } catch (error) {
        const mapped = bookingRpcErrorResponse(res, error);
        if (mapped) return mapped;
        throw error;
      }
    }

    if (Object.keys(data).some((field) => !['userId'].includes(field))) {
      return badRequest(res, 'No supported booking changes were supplied.');
    }
    return ok(res, existing, 'Booking unchanged');
  }),
);


// DELETE /api/bookings/:id
//
// The Postgres RPC removes the booking and its reservation rows atomically.
router.delete(
  '/:id',
  authenticate,
  requireRole('client', 'admin'),
  asyncHandler(async (req, res) => {
    const db = requestDatabase(req);
    const existing = await getDocById(db, COLLECTION, req.params.id);
    if (!existing) return notFound(res, 'Booking not found');
    if (!isOwner(existing, req)) {
      return forbidden(res);
    }

    try {
      const outcome = await callUserRpc(req, 'rpc_delete_booking', {
        p_booking_id: existing.id,
      });
      return ok(res, { id: String(outcome?.id || existing.id) }, 'Booking deleted');
    } catch (error) {
      const mapped = bookingRpcErrorResponse(res, error);
      if (mapped) return mapped;
      throw error;
    }
  }),
);

export default router;
