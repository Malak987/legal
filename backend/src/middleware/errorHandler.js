/**
 * Centralized error handler.
 */
export function notFoundHandler(req, res) {
  res.status(404).json({
    success: false,
    message: `Route not found: ${req.method} ${req.originalUrl}`,
  });
}

export function errorHandler(err, req, res, _next) {
  console.error('[Error]', err);

  // Joi validation errors
  if (err?.name === 'ValidationError' && err?.isJoi) {
    return res.status(400).json({
      success: false,
      message: 'Validation failed.',
      errors: err.details?.map((d) => d.message),
    });
  }

  const status = err.status || 500;
  const isProduction = process.env.NODE_ENV === 'production';

  // A 5xx means the server failed, not the caller. In production the client
  // gets a fixed message: driver errors, stack frames and internal identifiers
  // are for the logs, not for the response. 4xx messages are intentional and
  // are still returned as-is.
  const message =
    status >= 500 && isProduction
      ? 'Internal server error.'
      : err.message || 'Internal server error.';

  res.status(status).json({
    success: false,
    message,
    ...(!isProduction && { stack: err.stack }),
  });
}
