/**
 * Status-transition rules for records that carry money or service state.
 *
 * A record's status is a business fact, not a form field: a client must not be
 * able to mark their own booking "Completed" (which would release a payment or
 * inflate a lawyer's earnings) or flip a cancelled subscription back to
 * "Active". Administrators bypass every rule here — the admin panel manages
 * these state machines directly.
 *
 * Usage:
 *   if (!isAdmin(req) && !canTransition(BOOKING_TRANSITIONS, existing.status, next)) {
 *     return forbidden(res, '...');
 *   }
 */

/**
 * @param {Record<string, string[]>} map  from-status -> allowed next statuses
 * @param {string|undefined} from         current stored status
 * @param {string} to                     requested status
 * @returns {boolean}
 */
export function canTransition(map, from, to) {
  // A record with no recognisable status has no approved path out of it.
  const allowed = map[from];
  if (!Array.isArray(allowed)) return false;
  return allowed.includes(to);
}

/**
 * Bookings: a client may cancel, never complete or reactivate.
 * `Completed` and `Cancelled` are terminal for non-admins.
 */
export const BOOKING_TRANSITIONS = {
  Pending: ['Cancelled'],
  Active: ['Cancelled'],
  Completed: [],
  Cancelled: [],
};

/**
 * Bookings an administrator may move between (documented for completeness —
 * admins are not restricted, this map only describes the intended flow).
 */
export const BOOKING_ADMIN_TRANSITIONS = {
  Pending: ['Active', 'Completed', 'Cancelled'],
  Active: ['Completed', 'Cancelled'],
  Completed: [],
  Cancelled: [],
};

/**
 * Subscriptions: a client may cancel an unpaid or active plan, and nothing
 * else. Activation and expiry belong to the administrator / payment webhook.
 */
export const SUBSCRIPTION_TRANSITIONS = {
  Pending: ['Cancelled'],
  Active: ['Cancelled'],
  Expired: [],
  Cancelled: [],
};

/**
 * Fields a non-administrator may never write on these records.
 * Compared case-sensitively against the validated request body.
 */
export const FINANCIAL_FIELDS = ['totalPrice', 'balance', 'currency', 'priceValue'];
