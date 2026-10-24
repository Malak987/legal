/**
 * Small helpers for consistent JSON responses and pagination.
 */

export function ok(res, data = null, message = 'OK') {
  return res.json({ success: true, message, data });
}

export function created(res, data = null, message = 'Created', extra = null) {
  // `extra` is additive: existing callers pass three arguments and still get
  // exactly the same envelope. It carries optional metadata such as `warnings`.
  return res
    .status(201)
    .json({ success: true, message, data, ...(extra ?? {}) });
}

export function badRequest(res, message = 'Bad request', errors = null) {
  return res.status(400).json({ success: false, message, errors });
}

export function notFound(res, message = 'Not found') {
  return res.status(404).json({ success: false, message });
}

/**
 * 409 — the request is valid but conflicts with the current state of the
 * resource (duplicate idempotency key with a different payload, currency
 * mismatch, illegal status transition on an already-finalised record).
 */
export function conflict(res, message = 'Conflict', details = null) {
  return res.status(409).json({ success: false, message, ...(details ? { details } : {}) });
}

/**
 * Parses common list query params: page, limit, search, sort, order.
 */
export function parseListQuery(req, defaultLimit = 20, maxLimit = 100) {
  const page = Math.max(1, parseInt(req.query.page, 10) || 1);
  const limit = Math.min(
    maxLimit,
    Math.max(1, parseInt(req.query.limit, 10) || defaultLimit),
  );
  return {
    page,
    limit,
    offset: (page - 1) * limit,
    search: (req.query.search || '').toString().trim().toLowerCase(),
    sort: (req.query.sort || 'createdAt').toString(),
    order: (req.query.order || 'desc').toString().toLowerCase() === 'asc' ? 'asc' : 'desc',
  };
}

/**
 * Removes undefined/null values from an object (JSON-safe).
 */
export function cleanObject(obj) {
  return Object.fromEntries(
    Object.entries(obj || {}).filter(
      ([, v]) => v !== undefined && v !== null && v !== '',
    ),
  );
}
