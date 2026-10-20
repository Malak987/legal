/**
 * Small helpers for consistent JSON responses and pagination.
 */

export function ok(res, data = null, message = 'OK') {
  return res.json({ success: true, message, data });
}

export function created(res, data = null, message = 'Created') {
  return res.status(201).json({ success: true, message, data });
}

export function badRequest(res, message = 'Bad request', errors = null) {
  return res.status(400).json({ success: false, message, errors });
}

export function notFound(res, message = 'Not found') {
  return res.status(404).json({ success: false, message });
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
 * Removes undefined/null values from an object (Firestore-safe).
 */
export function cleanObject(obj) {
  return Object.fromEntries(
    Object.entries(obj || {}).filter(
      ([, v]) => v !== undefined && v !== null && v !== '',
    ),
  );
}
