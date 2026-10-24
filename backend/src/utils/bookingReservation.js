/**
 * Availability lookup and atomic slot reservation for bookings.
 *
 * Split out of `routes/bookings.js` so the concurrency guarantee can be
 * exercised directly, two transactions at a time, instead of hoping two HTTP
 * requests happen to overlap. The route composes these functions; nothing here
 * touches Express or reads configuration.
 *
 * CONCURRENCY MODEL
 * -----------------
 * One document per (lawyer, date, slot) in `bookingSlots`, with an id derived
 * from those three values (`slotLockId`). Every request that wants the slot
 * addresses the same document, so Firestore's read-version conflict detection
 * decides the winner — two requests that both read "not reserved" cannot both
 * commit, and the loser is retried automatically and then sees the winner's
 * document.
 *
 * The alternative — a `where(...)` query inside the transaction — is NOT a
 * uniqueness guarantee: Firestore gives queries no phantom protection, and the
 * project's test harness documents that it deliberately does not model it
 * either. The query in `findOverlap` is therefore only a second line of defence
 * for rows that predate these reservation documents.
 */

import { serverTimestamp } from './supabase_database.js';
import {
  SLOT_LOCK_COLLECTION,
  bookingInterval,
  consumedSlotMinutes,
  formatClockTime,
  intervalsOverlap,
  isBlocking,
  slotLockId,
  slotMinutes,
} from './scheduling.js';

export const BOOKINGS_COLLECTION = 'bookings';
const AVAILABILITY_COLLECTION = 'availability';

/** Statuses a booking can be in; kept in step with `validators.BOOKING_STATUSES`. */
export const CANCELLED = 'Cancelled';

/**
 * The start times a lawyer advertises on one date.
 *
 * Availability is stored as one document per day (`{ lawyerId, date, slots }`),
 * and nothing enforces one document per day, so every document for that lawyer
 * and date is merged. Unparseable slot strings are dropped by `slotMinutes`.
 *
 * ONLY a single equality filter is used: `where('lawyerId','==').where('date',
 * '==')` needs a composite index, and this project deliberately deploys none
 * (same reason `utils/firestore.js` filters in memory). The date is matched in
 * memory, over the (small) set of that lawyer's rows.
 *
 * Returns `null` when the caller did not identify a lawyer and a date — the
 * schedule is unknowable then, which is different from "publishes nothing"
 * (`[]`).
 */
export async function loadAdvertisedSlots(db, lawyerId, date) {
  if (!lawyerId || !date) return null;

  const snap = await db
    .collection(AVAILABILITY_COLLECTION)
    .where('lawyerId', '==', lawyerId)
    .get();

  const slots = [];
  for (const doc of snap.docs) {
    const data = doc.data() ?? {};
    if (data.date !== date) continue;
    if (Array.isArray(data.slots)) slots.push(...data.slots);
  }
  return slotMinutes(slots);
}

/**
 * Answers the reservation question for one requested appointment.
 *
 * Returns either `{ error }` (the request cannot be honoured at all) or
 * `{ minutes, locks }` describing the slots it occupies and the deterministic
 * reservation documents that guard them.
 */
export function planReservation({ advertised, startMinutes, hours, lawyerId, date }) {
  if (advertised === null) {
    return { error: 'A lawyer and a date are required to book an appointment.' };
  }
  if (advertised.length === 0) {
    return {
      error:
        'The lawyer has published no availability on that date. ' +
        'Choose one of the dates the lawyer offers.',
    };
  }
  if (!advertised.includes(startMinutes)) {
    const offered = advertised.map(formatClockTime).join(', ');
    return {
      error: `That time is not offered by this lawyer. Available slots: ${offered}.`,
    };
  }

  const minutes = consumedSlotMinutes(advertised, startMinutes, hours);
  const locks = minutes.map((minute) => ({
    minute,
    slot: formatClockTime(minute),
    id: slotLockId(lawyerId, date, minute),
  }));
  return { minutes, locks };
}

/** Reservation document references for a set of planned locks. */
export function lockRefs(db, locks) {
  return locks.map((lock) => ({
    ...lock,
    ref: db.collection(SLOT_LOCK_COLLECTION).doc(lock.id),
  }));
}

/**
 * Blocking bookings for the same lawyer that overlap the requested interval.
 *
 * Second line of defence, not the concurrency guarantee: a query inside a
 * transaction gets no phantom protection, so two simultaneous requests can
 * both see nothing here. It exists to catch rows that predate the reservation
 * documents — a booking written by the seed script or by hand has no locks and
 * would otherwise be invisible.
 */
export async function findOverlap(tx, db, { lawyerId, date, startMinutes, hours, ignoreId }) {
  const wanted = { start: startMinutes, end: startMinutes + hours * 60 };

  const snap = await tx.get(
    db.collection(BOOKINGS_COLLECTION).where('lawyerId', '==', lawyerId),
  );

  for (const doc of snap.docs) {
    const row = { id: doc.id, ...doc.data() };
    if (row.id === ignoreId) continue;
    if (row.date !== date) continue;
    if (!isBlocking(row)) continue;
    if (intervalsOverlap(bookingInterval(row), wanted)) return row;
  }
  return null;
}

/** Deletes a booking's reservation documents (they may already be gone). */
export async function releaseLocks(tx, db, lockIds) {
  for (const id of lockIds ?? []) {
    tx.delete(db.collection(SLOT_LOCK_COLLECTION).doc(id));
  }
}

/**
 * Writes a booking and its reservation documents in ONE transaction.
 *
 * All or nothing: if any write fails, neither the booking nor its reservation
 * exists, so a crash cannot strand a slot (reserved but unbooked) or leave a
 * booking with no reservation (bookable twice).
 *
 * `data` must already contain the trusted fields the route derived — owner,
 * price, lawyer name, status and the canonical `time`. The caller owns
 * validation; this function only enforces the slot.
 *
 * @returns {Promise<{status: 'created'|'taken'|'conflict', message?: string, id?: string}>}
 */
export async function createReservedBooking(
  db,
  { data, lawyerId, date, startMinutes, hours, locks },
) {
  const bookingRef = db.collection(BOOKINGS_COLLECTION).doc();
  const guarded = lockRefs(db, locks);

  const outcome = await db.runTransaction(async (tx) => {
    // 1. Is any occupied slot already reserved? These are the reads the commit
    //    validates, which is what makes the check atomic.
    for (const lock of guarded) {
      const snap = await tx.get(lock.ref);
      if (snap.exists) {
        return {
          status: 'taken',
          message: `The ${lock.slot} slot has just been booked. Choose another time.`,
        };
      }
    }

    // 2. Rows without reservation documents (seed data, hand-written records).
    const clash = await findOverlap(tx, db, {
      lawyerId,
      date,
      startMinutes,
      hours,
    });
    if (clash) {
      return {
        status: 'conflict',
        message:
          `That appointment overlaps an existing booking at ${clash.time ?? 'another time'}. ` +
          'Choose a different slot or a shorter duration.',
      };
    }

    // 3. Reserve: booking + one document per occupied slot.
    tx.set(bookingRef, {
      ...data,
      slotKeys: guarded.map((lock) => lock.id),
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    for (const lock of guarded) {
      tx.set(lock.ref, {
        lawyerId,
        date,
        slot: lock.slot,
        bookingId: bookingRef.id,
        userId: data.userId,
        createdAt: serverTimestamp(),
      });
    }
    return { status: 'created', id: bookingRef.id };
  });

  return outcome;
}
