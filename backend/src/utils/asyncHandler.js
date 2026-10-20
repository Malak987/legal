/**
 * Wraps an async route handler so rejected promises reach the error handler.
 */
export function asyncHandler(fn) {
  return (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
}
