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
  updateDoc,
  serverTimestamp,
} from '../utils/firestore.js';
import { formatClockTime, parseClockTime } from '../utils/scheduling.js';
import {
  BOOKINGS_COLLECTION,
  createReservedBooking,
  findOverlap,
  loadAdvertisedSlots,
  lockRefs,
  planReservation,
  releaseLocks,
} from '../utils/bookingReservation.js';

const router = Router();
const COLLECTION = BOOKINGS_COLLECTION;
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
//
// The appointment is reserved atomically: the booking document and one
// reservation document per occupied slot are written in a single Firestore
// transaction. Two requests for the same slot address the same reservation
// document, so the SDK's conflict detection — not a read-then-write check —
// is what lets exactly one of them through.
router.post(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const data = validate(bookingCreateSchema, { ...req.body, userId: ownerIdFor(req) });

    // Price first: "this lawyer does not exist" and "this lawyer has no rate"
    // stay the answers they always were, rather than turning into an
    // availability error because no schedule exists for an unknown lawyer.
    const priced = await priceBooking(getDb(), {
      lawyerId: data.lawyerId,
      hours: data.hours,
    });
    if (priced.error) return badRequest(res, priced.error);

    const startMinutes = parseClockTime(data.time);
    if (startMinutes === null) {
      return badRequest(
        res,
        'time is required and must be a time of day, for example 09:00 or 9:00 am.',
      );
    }

    const db = getDb();
    const advertised = await loadAdvertisedSlots(db, data.lawyerId, data.date);
    const plan = planReservation({
      advertised,
      startMinutes,
      hours: data.hours,
      lawyerId: data.lawyerId,
      date: data.date,
    });
    if (plan.error) return badRequest(res, plan.error);

    // The server is the only source of price and of the starting status.
    data.totalPrice = priced.totalPrice;
    data.lawyerName = priced.lawyer.name ?? data.lawyerName ?? '';
    data.time = formatClockTime(startMinutes);
    if (!isAdmin(req)) {
      data.status = 'Pending';
    }

    const outcome = await createReservedBooking(db, {
      data,
      lawyerId: data.lawyerId,
      date: data.date,
      startMinutes,
      hours: data.hours,
      locks: plan.locks,
    });

    if (outcome.status !== 'created') {
      return conflict(res, outcome.message);
    }

    // Read the stored document back so the response keeps the exact shape
    // `createDoc()` produced (`{ id, ...data, createdAt, updatedAt }`).
    const saved = await getDocById(db, COLLECTION, outcome.id);
    created(res, saved, 'Booking created');
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

    const db = getDb();
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

    // ---- Cancelling releases the slot -------------------------------------
    //
    // `Cancelled` is terminal and means the appointment did not happen, so
    // holding the reservation afterwards would strand the slot forever. The
    // status write and the release are one transaction: a crash between them
    // cannot leave a cancelled booking still occupying its slot.
    if (cancelling) {
      const bookingRef = db.collection(COLLECTION).doc(existing.id);
      await db.runTransaction(async (tx) => {
        await releaseLocks(tx, db, existing.slotKeys);
        tx.update(bookingRef, {
          ...data,
          status: 'Cancelled',
          slotKeys: [],
          updatedAt: serverTimestamp(),
        });
      });
      return ok(res, await getDocById(db, COLLECTION, existing.id), 'Booking updated');
    }

    // ---- Rescheduling re-reserves -----------------------------------------
    //
    // Without this an administrator could move an appointment onto a slot
    // somebody else already holds, which is the same double-booking the create
    // path refuses.
    if (isAdmin(req) && scheduleChanged && nextStart !== null) {
      const advertised = await loadAdvertisedSlots(db, nextLawyerId, nextDate);

      // A row with no lawyer or no date (legacy / hand-written) has no schedule
      // to check. Refusing the edit would make such a row unrepairable, so the
      // change is allowed and remains unguarded — documented in the README.
      if (advertised !== null) {
        const plan = planReservation({
          advertised,
          startMinutes: nextStart,
          hours: nextHours,
          lawyerId: nextLawyerId,
          date: nextDate,
        });
        if (plan.error) return badRequest(res, plan.error);

        const locks = lockRefs(db, plan.locks);
        const previousIds = new Set(existing.slotKeys ?? []);
        const bookingRef = db.collection(COLLECTION).doc(existing.id);

        const outcome = await db.runTransaction(async (tx) => {
          for (const lock of locks) {
            const snap = await tx.get(lock.ref);
            if (!snap.exists) continue;
            // A reservation this booking already holds is not a conflict with
            // itself; anything else is somebody else's appointment.
            if (snap.data()?.bookingId !== existing.id) {
              return {
                status: 'taken',
                message: `The ${lock.slot} slot is already booked. Choose another time.`,
              };
            }
          }

          const clash = await findOverlap(tx, db, {
            lawyerId: nextLawyerId,
            date: nextDate,
            startMinutes: nextStart,
            hours: nextHours,
            ignoreId: existing.id,
          });
          if (clash) {
            return {
              status: 'conflict',
              message:
                `That appointment overlaps an existing booking at ${clash.time ?? 'another time'}. ` +
                'Choose a different slot or a shorter duration.',
            };
          }

          // Release the slots this booking no longer occupies...
          const keptIds = new Set(locks.map((lock) => lock.id));
          await releaseLocks(
            tx,
            db,
            [...previousIds].filter((id) => !keptIds.has(id)),
          );
          // ...and take the new ones.
          for (const lock of locks) {
            tx.set(lock.ref, {
              lawyerId: nextLawyerId,
              date: nextDate,
              slot: lock.slot,
              bookingId: existing.id,
              userId: existing.userId,
              createdAt: serverTimestamp(),
            });
          }

          tx.update(bookingRef, {
            ...data,
            time: formatClockTime(nextStart),
            slotKeys: locks.map((lock) => lock.id),
            updatedAt: serverTimestamp(),
          });
          return { status: 'updated' };
        });

        if (outcome.status !== 'updated') {
          return conflict(res, outcome.message);
        }
        return ok(res, await getDocById(db, COLLECTION, existing.id), 'Booking updated');
      }
    }

    const updated = await updateDoc(db, COLLECTION, req.params.id, data);
    ok(res, updated, 'Booking updated');
  }),
);

// DELETE /api/bookings/:id
//
// The reservation documents are removed with the booking in one transaction,
// so a deleted appointment always frees its slot.
router.delete(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const db = getDb();
    const existing = await getDocById(db, COLLECTION, req.params.id);
    if (!existing) return notFound(res, 'Booking not found');
    if (!isOwner(existing, req)) {
      return forbidden(res);
    }

    const bookingRef = db.collection(COLLECTION).doc(existing.id);
    await db.runTransaction(async (tx) => {
      await releaseLocks(tx, db, existing.slotKeys);
      tx.delete(bookingRef);
    });

    ok(res, { id: req.params.id }, 'Booking deleted');
  }),
);

export default router;
