import Joi from 'joi';

import { formatClockTime, parseClockTime } from './scheduling.js';

/**
 * Reusable Joi validation schemas shared across routes.
 * Each route validates its body with `validate(schema, req.body)`.
 */

export const objectId = Joi.string().trim();

/**
 * A calendar date in `YYYY-MM-DD` form.
 *
 * Joi's built-in `isoDate()` was not enough: it validates the *shape* only, so
 * `2026-02-30` (not a real date) and full timestamps like
 * `2026-11-30T10:00:00Z` both passed. A case deadline has no time-of-day, so
 * the value is kept to a date-only string and checked against the calendar.
 *
 * Empty values stay allowed: `dueDate` is optional and clients that have
 * nothing to set send `""` (see `AppRepository.createCase`).
 */
const ISO_DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

export const isoCalendarDate = Joi.string()
  .trim()
  .allow('', null)
  .custom((value, helpers) => {
    if (value === '' || value === null || value === undefined) return value;
    if (!ISO_DATE_PATTERN.test(value)) return helpers.error('string.isoDate');

    const [year, month, day] = value.split('-').map(Number);
    // Round-trip through UTC: `Date.UTC(2026, 1, 30)` silently rolls over to
    // 2 March, so an identical round-trip is what proves the date exists.
    const date = new Date(Date.UTC(year, month - 1, day));
    const isReal =
      date.getUTCFullYear() === year &&
      date.getUTCMonth() === month - 1 &&
      date.getUTCDate() === day;

    return isReal ? value : helpers.error('string.isoDate');
  }, 'ISO calendar date')
  .messages({
    'string.isoDate':
      '{{#label}} must be a real calendar date in YYYY-MM-DD format (for example 2026-11-30)',
  });

export const lawyerSignupSchema = Joi.object({
  name: Joi.string().trim().min(2).max(120).required(),
  email: Joi.string().trim().lowercase().email().max(254).required(),
  password: Joi.string().min(8).max(128).required(),
});

export const legalCategorySchema = Joi.object({
  name: Joi.string().trim().min(2).max(120).required(),
  slug: Joi.string().trim().max(160).allow('', null),
});

export const legalCategoryUpdateSchema = legalCategorySchema
  .fork(['name'], (schema) => schema.optional())
  .min(1);

export const lawyerSchema = Joi.object({
  userId: Joi.string().trim().allow('', null),
  categoryId: Joi.string().trim().allow('', null),
  name: Joi.string().trim().min(2).max(120).required(),
  specialty: Joi.string().trim().max(120).allow('', null),
  experience: Joi.string().trim().max(80).allow('', null),
  price: Joi.string().trim().max(40).allow('', null),
  priceValue: Joi.number().min(0).optional(),
  image: Joi.string().trim().allow('', null),
  rating: Joi.number().min(0).max(5).optional(),
  location: Joi.string().trim().max(160).allow('', null),
  bio: Joi.string().trim().max(2000).allow('', null),
  isPopular: Joi.boolean().optional(),
  isTop: Joi.boolean().optional(),
});

/**
 * Fields a user may change on their own profile.
 *
 * `role` is deliberately NOT part of this schema. It used to be accepted
 * here, and because `PUT /api/users/:id` allows the caller to edit their own
 * document, any signed-in user could escalate themselves to `admin` with a
 * single request. Joi runs with `stripUnknown`, so a `role` in the request
 * body is now silently dropped instead of being written.
 *
 * Changing a role goes through `userRoleSchema` on the admin-only route.
 */
export const userSchema = Joi.object({
  name: Joi.string().trim().min(2).max(120).required(),
  email: Joi.string().email().required(),
  phone: Joi.string().trim().max(40).allow('', null),
  avatar: Joi.string().trim().allow('', null),
  address: Joi.string().trim().max(300).allow('', null),
});

export const userUpdateSchema = userSchema.fork(['name', 'email'], (schema) =>
  schema.optional(),
);

/**
 * Payload for provisioning the CALLER'S OWN profile (`POST /api/users/me`).
 *
 * Deliberately narrower than `userSchema`:
 *  - no `role`: the route writes `role: 'client'` itself, so a body can never
 *    grant `admin` or `lawyer`. `stripUnknown` also drops any attempt.
 *  - no `email`: the address is taken from the verified ID token, so a caller
 *    cannot register a profile that claims somebody else's mailbox.
 *  - no `uid`/`userId`: the document id is the verified uid, never input.
 */
export const profileProvisionSchema = Joi.object({
  name: Joi.string().trim().min(2).max(120).required(),
  phone: Joi.string().trim().max(40).allow('', null),
  avatar: Joi.string().trim().allow('', null),
  address: Joi.string().trim().max(300).allow('', null),
});

/**
 * Role change payload — admin-only, and restricted to real roles.
 * `admin` is included so administrators can promote other administrators.
 */
export const userRoleSchema = Joi.object({
  role: Joi.string().valid('client', 'lawyer', 'admin').required(),
});

/**
 * Case payload (creation).
 *
 * `status` and `priority` carry schema defaults, which is correct for a CREATE
 * and destructive for a partial UPDATE: Joi re-applies a default to any field
 * the caller omitted. `PUT /api/cases/:id` therefore validates with
 * `noDefaults: true` — see `routes/cases.js`.
 */
export const caseSchema = Joi.object({
  userId: Joi.string().trim().allow('', null),
  lawyerId: Joi.string().trim().allow('', null),
  categoryId: Joi.string().trim().allow('', null),
  title: Joi.string().trim().min(2).max(200).required(),
  description: Joi.string().trim().max(4000).allow('', null),
  clientName: Joi.string().trim().max(160).allow('', null),
  caseType: Joi.string().trim().max(120).allow('', null),
  priority: Joi.string().valid('High', 'Medium', 'Low').default('Medium'),
  status: Joi.string()
    .valid('Open', 'In Progress', 'Pending', 'Closed')
    .default('Open'),
  dueDate: isoCalendarDate,
});

/**
 * Case payload (update).
 *
 * `caseSchema` + `presence: 'optional'` is NOT enough for a partial update:
 * `presence` only supplies a default for keys that do not declare their own,
 * so an explicit `title.required()` keeps rejecting a body that omits it — and
 * "change only the status" is a legitimate partial update.
 *
 * Derived with `fork` rather than duplicated so the two schemas can never drift
 * apart. Defaults are suppressed at validation time with `noDefaults: true`.
 */
export const caseUpdateSchema = caseSchema.fork(['title'], (schema) =>
  schema.optional(),
);

export const taskSchema = Joi.object({
  userId: Joi.string().trim().allow('', null),
  title: Joi.string().trim().min(2).max(200).required(),
  description: Joi.string().trim().max(4000).allow('', null),
  dueDate: isoCalendarDate,
  priority: Joi.string().valid('High', 'Medium', 'Low').default('Medium'),
  status: Joi.string()
    .valid('Pending', 'In Progress', 'Completed', 'Cancelled')
    .default('Pending'),
});

export const taskUpdateSchema = taskSchema.fork(['title'], (schema) => schema.optional());

export const BOOKING_STATUSES = ['Pending', 'Confirmed', 'Active', 'Completed', 'Cancelled'];

/**
 * A time of day, normalised to 24-hour `HH:MM`.
 *
 * `date` and `time` used to be free text, so `'noon'`, `'25:00'` and
 * `'2026-11-01T10:00'` were all stored verbatim. The value is now parsed and
 * rewritten, which is also what makes the stored `time` comparable with the
 * slot strings in the `availability` collection: the repository contains both
 * `'09:00'` (tests, bookings) and `'09:00 am'` (seed), and both are accepted.
 *
 * An empty value stays allowed because a partial PUT may legitimately send
 * `time: ''` to mean "unchanged"; `POST` rejects it separately, since a booking
 * with no time is meaningless.
 */
export const clockTime = Joi.string()
  .trim()
  .allow('', null)
  .custom((value, helpers) => {
    if (value === '' || value === null || value === undefined) return value;
    const minutes = parseClockTime(value);
    if (minutes === null) return helpers.error('string.clockTime');
    return formatClockTime(minutes);
  }, 'clock time')
  .messages({
    'string.clockTime':
      '{{#label}} must be a time of day, for example 09:00 or 9:00 am',
  });

/**
 * Booking payload.
 *
 * `totalPrice` is NOT accepted: the server derives it from the lawyer's
 * configured hourly rate (`lawyers.priceValue`) and the requested `hours`.
 * It is still returned in responses so existing clients keep working.
 */
export const bookingSchema = Joi.object({
  userId: Joi.string().trim().allow('', null),
  lawyerId: Joi.string().trim().allow('', null),
  lawyerName: Joi.string().trim().allow('', null),
  // A real calendar date, not a free string: `2026-02-30` and
  // `2026-11-01T10:00` are both refused (see `isoCalendarDate`).
  date: isoCalendarDate,
  time: clockTime,
  hours: Joi.number().integer().min(1).max(12).optional(),
  status: Joi.string()
    .valid(...BOOKING_STATUSES)
    .default('Pending'),
});

/** Creation requires a lawyer and a billable number of hours. */
export const bookingCreateSchema = bookingSchema.keys({
  lawyerId: Joi.string().trim().required(),
  hours: Joi.number().integer().min(1).max(12).required(),
});

export const reviewSchema = Joi.object({
  userId: Joi.string().trim().allow('', null),
  userName: Joi.string().trim().max(120).allow('', null),
  lawyerId: Joi.string().trim().allow('', null),
  rating: Joi.number().min(1).max(5).required(),
  comment: Joi.string().trim().max(2000).required(),
});

/**
 * A review must point at a lawyer.
 *
 * `userId`/`userName` are overwritten from the verified token before this
 * schema sees the payload, so they cannot be forged.
 */
export const reviewCreateSchema = reviewSchema.keys({
  lawyerId: Joi.string().trim().required(),
});

/** Admins moderate the content of a review, never its authorship. */
export const reviewUpdateSchema = Joi.object({
  rating: Joi.number().min(1).max(5).optional(),
  comment: Joi.string().trim().max(2000).optional(),
});

export const planSchema = Joi.object({
  title: Joi.string().trim().min(2).max(80).required(),
  price: Joi.string().trim().max(40).allow('', null),
  priceValue: Joi.number().min(0).optional(),
  color: Joi.string().trim().allow('', null),
  features: Joi.array().items(Joi.string()).optional(),
  isPopular: Joi.boolean().optional(),
});

export const SUBSCRIPTION_STATUSES = ['Pending', 'Active', 'Expired', 'Cancelled'];

/**
 * Subscription payload.
 *
 * `Pending` is the starting state: an account cannot activate a paid plan by
 * creating it. Only an administrator may move a subscription to `Active`.
 */
export const subscriptionSchema = Joi.object({
  userId: Joi.string().trim().allow('', null),
  planId: Joi.string().trim().allow('', null),
  planTitle: Joi.string().trim().allow('', null),
  status: Joi.string().valid(...SUBSCRIPTION_STATUSES).default('Pending'),
});

export const notificationSchema = Joi.object({
  userId: Joi.string().trim().allow('', null),
  title: Joi.string().trim().min(1).max(200).required(),
  content: Joi.string().trim().max(1000).allow('', null),
  type: Joi.string().trim().max(60).allow('', null),
  read: Joi.boolean().optional(),
});

/**
 * Chat message payload.
 *
 * `senderId` and `senderName` are deliberately NOT accepted here: the sender
 * is derived on the server from the verified token (`req.user`). A client that
 * sends them has the values stripped, so a participant can no longer post a
 * message that appears to come from an administrator or from another member of
 * the conversation.
 */
export const messageSchema = Joi.object({
  text: Joi.string().trim().min(1).max(4000).required(),
});

export const availabilitySchema = Joi.object({
  lawyerId: Joi.string().trim().allow('', null),
  lawyerName: Joi.string().trim().max(120).allow('', null),
  date: isoCalendarDate,
  slots: Joi.array().items(Joi.string()).optional(),
});

/**
 * Creation payload for an availability slot.
 *
 * `lawyerId` and `date` are required here (they were optional in
 * `availabilitySchema`, which allowed a slot with no owner and no date).
 * Updates still use the permissive schema so a single field can be patched.
 */
export const availabilityCreateSchema = availabilitySchema.keys({
  lawyerId: Joi.string().trim().required(),
  date: Joi.string().trim().required(),
});

/**
 * Validates `data` against a Joi schema. Throws a Joi error on failure.
 */
export function validate(schema, data, options = {}) {
  const { error, value } = schema.validate(data, {
    abortEarly: false,
    stripUnknown: true,
    ...options,
  });
  if (error) throw error;
  return value;
}
