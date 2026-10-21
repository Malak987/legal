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
import { validate, bookingSchema, bookingCreateSchema } from '../utils/validators.js';
import { canTransition, BOOKING_TRANSITIONS } from '../utils/stateTransitions.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { listDocs, getDocById, createDoc, updateDoc, deleteDoc } from '../utils/firestore.js';

const router = Router();
const COLLECTION = 'bookings';
const LAWYERS_COLLECTION = 'lawyers';

// Fields that define the appointment. Clients cannot rewrite them after
// creation; administrators can, and get the price recomputed when they do.
const CLIENT_IMMUTABLE_FIELDS = ['lawyerId', 'lawyerName', 'date', 'time', 'hours'];

// GET /api/bookings?userId=&status=&lawyerId=
router.get(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const q = parseListQuery(req);
    const filters = cleanObject({
      userId: req.query.userId,
      status: req.query.status,
      lawyerId: req.query.lawyerId,
    });
    // A non-admin is always scoped to their own records. The old test only
    // applied the scope when `?userId=` was absent, so passing somebody
    // else's id returned their records instead.
    if (!isAdmin(req)) filters.userId = req.user.uid;

    const result = await listDocs(getDb(), COLLECTION, {
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
  asyncHandler(async (req, res) => {
    const item = await getDocById(getDb(), COLLECTION, req.params.id);
    if (!item) return notFound(res, 'Booking not found');
    if (!isOwner(item, req)) {
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

// POST /api/bookings
router.post(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const data = validate(bookingCreateSchema, { ...req.body, userId: ownerIdFor(req) });

    const priced = await priceBooking(getDb(), {
      lawyerId: data.lawyerId,
      hours: data.hours,
    });
    if (priced.error) return badRequest(res, priced.error);

    // The server is the only source of price and of the starting status.
    data.totalPrice = priced.totalPrice;
    data.lawyerName = priced.lawyer.name ?? data.lawyerName ?? '';
    if (!isAdmin(req)) {
      data.status = 'Pending';
    }

    const createdDoc = await createDoc(getDb(), COLLECTION, data);
    created(res, createdDoc, 'Booking created');
  }),
);

// PUT /api/bookings/:id  (used to change status: Active / Completed / Cancelled)
router.put(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    // `noDefaults` stops a partial update from writing the schema default
    // `status: 'Pending'` over the record's real status.
    const data = validate(bookingSchema, req.body, {
      presence: 'optional',
      noDefaults: true,
    });

    const existing = await getDocById(getDb(), COLLECTION, req.params.id);
    if (!existing) return notFound(res, 'Booking not found');
    if (!isOwner(existing, req)) {
      return forbidden(res);
    }

    if (!isAdmin(req)) {
      // A client may only CANCEL. Everything that defines the appointment —
      // who, when, how long, at what price — is fixed at creation: the server
      // derives the price from the lawyer's rate, and there is no availability
      // model here that could validate a reschedule, so accepting a new
      // date/time would let a client move a booking to a slot nobody approved.
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
      const priced = await priceBooking(getDb(), {
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

    const updated = await updateDoc(getDb(), COLLECTION, req.params.id, data);
    ok(res, updated, 'Booking updated');
  }),
);

// DELETE /api/bookings/:id
router.delete(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const existing = await getDocById(getDb(), COLLECTION, req.params.id);
    if (!existing) return notFound(res, 'Booking not found');
    if (!isOwner(existing, req)) {
      return forbidden(res);
    }
    await deleteDoc(getDb(), COLLECTION, req.params.id);
    ok(res, { id: req.params.id }, 'Booking deleted');
  }),
);

export default router;
