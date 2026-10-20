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
  res.status(status).json({
    success: false,
    message: err.message || 'Internal server error.',
    ...(process.env.NODE_ENV !== 'production' && { stack: err.stack }),
  });
}
