import Joi from 'joi';

/**
 * Reusable Joi validation schemas shared across routes.
 * Each route validates its body with `validate(schema, req.body)`.
 */

export const objectId = Joi.string().trim();

export const lawyerSchema = Joi.object({
  name: Joi.string().trim().min(2).max(120).required(),
  specialty: Joi.string().trim().max(120).allow('', null),
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

/**
 * Role change payload — admin-only, and restricted to real roles.
 * `admin` is included so administrators can promote other administrators.
 */
export const userRoleSchema = Joi.object({
  role: Joi.string().valid('client', 'lawyer', 'admin').required(),
});

export const caseSchema = Joi.object({
  userId: Joi.string().trim().allow('', null),
  title: Joi.string().trim().min(2).max(200).required(),
  description: Joi.string().trim().max(4000).allow('', null),
  clientName: Joi.string().trim().max(160).allow('', null),
  caseType: Joi.string().trim().max(120).allow('', null),
  priority: Joi.string().valid('High', 'Medium', 'Low').default('Medium'),
  status: Joi.string()
    .valid('Open', 'In Progress', 'Pending', 'Closed')
    .default('Open'),
  dueDate: Joi.string().trim().allow('', null),
});

export const taskSchema = Joi.object({
  userId: Joi.string().trim().allow('', null),
  caseId: Joi.string().trim().allow('', null),
  title: Joi.string().trim().min(2).max(200).required(),
  description: Joi.string().trim().max(4000).allow('', null),
  dueDate: Joi.string().trim().allow('', null),
  priority: Joi.string().valid('High', 'Medium', 'Low').default('Medium'),
  status: Joi.string()
    .valid('To Do', 'In Progress', 'Done')
    .default('To Do'),
});

export const BOOKING_STATUSES = ['Pending', 'Active', 'Completed', 'Cancelled'];

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
  date: Joi.string().trim().allow('', null),
  time: Joi.string().trim().allow('', null),
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
  date: Joi.string().trim().allow('', null),
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
