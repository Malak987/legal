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

export const userSchema = Joi.object({
  name: Joi.string().trim().min(2).max(120).required(),
  email: Joi.string().email().required(),
  phone: Joi.string().trim().max(40).allow('', null),
  role: Joi.string().valid('client', 'lawyer', 'admin').default('client'),
  avatar: Joi.string().trim().allow('', null),
  address: Joi.string().trim().max(300).allow('', null),
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

export const bookingSchema = Joi.object({
  userId: Joi.string().trim().allow('', null),
  lawyerId: Joi.string().trim().allow('', null),
  lawyerName: Joi.string().trim().allow('', null),
  date: Joi.string().trim().allow('', null),
  time: Joi.string().trim().allow('', null),
  hours: Joi.number().min(1).max(12).optional(),
  totalPrice: Joi.number().min(0).optional(),
  status: Joi.string()
    .valid('Pending', 'Active', 'Completed', 'Cancelled')
    .default('Pending'),
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

export const subscriptionSchema = Joi.object({
  userId: Joi.string().trim().allow('', null),
  planId: Joi.string().trim().allow('', null),
  planTitle: Joi.string().trim().allow('', null),
  status: Joi.string().valid('Active', 'Expired', 'Cancelled').default('Active'),
});

export const notificationSchema = Joi.object({
  userId: Joi.string().trim().allow('', null),
  title: Joi.string().trim().min(1).max(200).required(),
  content: Joi.string().trim().max(1000).allow('', null),
  type: Joi.string().trim().max(60).allow('', null),
  read: Joi.boolean().optional(),
});

export const messageSchema = Joi.object({
  senderId: Joi.string().trim().allow('', null),
  senderName: Joi.string().trim().max(120).allow('', null),
  text: Joi.string().trim().min(1).max(4000).required(),
});

export const availabilitySchema = Joi.object({
  lawyerId: Joi.string().trim().allow('', null),
  lawyerName: Joi.string().trim().max(120).allow('', null),
  date: Joi.string().trim().allow('', null),
  slots: Joi.array().items(Joi.string()).optional(),
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
