/**
 * Scheduling primitives shared by the booking routes.
 *
 * WHY THIS EXISTS
 * ---------------
 * `POST /api/bookings` used to accept any `date`/`time` string and store it,
 * so a client could reserve 03:00 on a Sunday the lawyer never offered, and two
 * clients could hold the same slot. Availability was a separate, purely
 * cosmetic collection that nothing consulted.
 *
 * WHAT THE EXISTING SCHEMA CAN AND CANNOT EXPRESS
 * -----------------------------------------------
 * `availability/{id}` = { lawyerId, lawyerName, date: 'YYYY-MM-DD',
 *                         slots: ['09:00', '10:30', ...] }
 *
 * A slot is a **start time only**. The schema has no per-slot length, no end
 * time, no timezone, and no notion of a day being closed. `bookings` has
 * `hours` (1..12) but `availability` has nothing to compare it against.
 *
 * The only duration semantics that can be justified from those fields are:
 *
 *   * a booking must start at a slot the lawyer actually advertises;
 *   * a booking occupies every advertised slot whose start falls inside
 *     [start, start + hours) — an appointment that runs from 09:00 for two
 *     hours makes the 10:00 slot unusable as well.
 *
 * Nothing here invents an opening time, a closing time, a slot length or a
 * timezone, because the data model does not contain one. A booking that ends
 * after the last advertised start is therefore allowed: the model cannot say
 * when the lawyer stops working.
 *
 * TIME FORMAT
 * -----------
 * The repository contains both conventions: `src/seed.js` writes
 * `'08:30 am'` while the tests and the bookings API use 24-hour `'09:00'`.
 * Rather than pick a winner and break half the data, both are accepted and
 * every value is normalised to 24-hour `HH:MM` before it is stored or compared.
 */

import { createHash } from 'node:crypto';

/** Collection holding one document per reserved (lawyer, date, slot). */
export const SLOT_LOCK_COLLECTION = 'bookingSlots';

/** `09:00`, `9:00`, `9:00am`, `09:00 AM`, `1:30 p.m.` */
const CLOCK_PATTERN = /^(\d{1,2}):(\d{2})(?:\s*([ap])\.?m\.?)?$/i;

/**
 * Parses a clock time into minutes since midnight.
 *
 * Returns `null` for anything that is not a real time of day, which is what
 * lets the validators reject `25:00`, `09:75` or `noon`.
 */
export function parseClockTime(value) {
  if (typeof value !== 'string') return null;
  const match = CLOCK_PATTERN.exec(value.trim());
  if (!match) return null;

  let hours = Number(match[1]);
  const minutes = Number(match[2]);
  const meridiem = match[3]?.toLowerCase();

  if (!Number.isInteger(hours) || !Number.isInteger(minutes) || minutes > 59) {
    return null;
  }

  if (meridiem) {
    // 12-hour clock: 12 am is 00:00 and 12 pm is 12:00.
    if (hours < 1 || hours > 12) return null;
    if (meridiem === 'p' && hours !== 12) hours += 12;
    if (meridiem === 'a' && hours === 12) hours = 0;
  } else if (hours > 23) {
    return null;
  }

  return hours * 60 + minutes;
}

/** Minutes since midnight -> canonical `HH:MM` (24-hour). */
export function formatClockTime(minutes) {
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return `${String(hours).padStart(2, '0')}:${String(rest).padStart(2, '0')}`;
}

/**
 * True for a real `YYYY-MM-DD` calendar date.
 *
 * Mirrors `isoCalendarDate` in `utils/validators.js`: `2026-02-30` is rejected
 * because the UTC round-trip does not reproduce the same day.
 */
export function isIsoCalendarDate(value) {
  if (typeof value !== 'string') return false;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [year, month, day] = value.split('-').map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  return (
    date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day
  );
}

/**
 * The advertised start times of one day, sorted and de-duplicated, in minutes.
 *
 * Values that cannot be parsed are dropped: a hand-written `'morning'` slot
 * must not take the whole day down, and it also must not be bookable.
 */
export function slotMinutes(slots) {
  if (!Array.isArray(slots)) return [];
  const minutes = new Set();
  for (const slot of slots) {
    const parsed = parseClockTime(slot);
    if (parsed !== null) minutes.add(parsed);
  }
  return [...minutes].sort((a, b) => a - b);
}

/**
 * The advertised slots an appointment starting at `startMinutes` occupies.
 *
 * The interval is half-open, so a one-hour booking at 09:00 does not consume
 * the 10:00 slot. `hours` is the booking's own duration — the only duration
 * the schema provides.
 */
export function consumedSlotMinutes(advertised, startMinutes, hours) {
  const end = startMinutes + hours * 60;
  return advertised.filter((slot) => slot >= startMinutes && slot < end);
}

/**
 * Deterministic id of the reservation document for one slot.
 *
 * Two requests for the same (lawyer, date, slot) derive the same stable key;
 * PostgreSQL's unique (lawyer_id, date, slot) constraint arbitrates concurrent
 * reservations inside the booking RPC.
 */
export function slotLockId(lawyerId, date, minutes) {
  return createHash('sha256')
    .update(`${lawyerId}\u0000${date}\u0000${minutes}`)
    .digest('hex');
}

/** Slot lock ids for a booking's occupied slots. */
export function slotLockIds(lawyerId, date, minutes) {
  return minutes.map((minute) => slotLockId(lawyerId, date, minute));
}

/**
 * `[start, end)` of an existing booking, in minutes, or `null` when its
 * `time`/`hours` cannot be read.
 *
 * An unreadable row is treated as "not blocking" rather than as a permanent
 * block: the API cannot create such a row (both fields are validated), and a
 * legacy one must not make the whole day unbookable.
 */
export function bookingInterval(booking) {
  const start = parseClockTime(booking?.time);
  if (start === null) return null;
  const hours = Number(booking?.hours);
  if (!Number.isFinite(hours) || hours <= 0) return null;
  return { start, end: start + hours * 60 };
}

/** Half-open interval overlap. */
export function intervalsOverlap(a, b) {
  if (!a || !b) return false;
  return a.start < b.end && b.start < a.end;
}

/**
 * A booking stops blocking its slot once it is cancelled.
 *
 * `Cancelled` is terminal in `BOOKING_TRANSITIONS` and means the appointment
 * did not happen, so holding the slot afterwards would strand it forever.
 * Every other status — including `Completed` — keeps the record of a real
 * appointment.
 */
export function isBlocking(booking) {
  return booking?.status !== 'Cancelled';
}
