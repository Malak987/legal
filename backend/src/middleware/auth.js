import { getAuth, getDb } from '../config/firebase.js';

/**
 * Extracts the bearer token from the Authorization header.
 */
function extractToken(req) {
  const header = req.headers.authorization || '';
  if (!header.startsWith('Bearer ')) return null;
  return header.slice('Bearer '.length).trim();
}

/**
 * Middleware: verifies a Firebase ID token and attaches the decoded user to req.
 *
 * The token is issued by Firebase Authentication on the client (the Flutter app
 * or the Flutter Web admin panel) after a successful sign-in.
 *
 * req.user = { uid, email, role, name, ... }
 */
export async function authenticate(req, res, next) {
  try {
    const token = extractToken(req);
    if (!token) {
      return res.status(401).json({
        success: false,
        message: 'Missing Authorization header (Bearer token required).',
      });
    }

    const decoded = await getAuth().verifyIdToken(token);

    // Load the user profile from Firestore (contains role, name, etc.)
    let profile = {};
    try {
      const snap = await getDb().collection('users').doc(decoded.uid).get();
      if (snap.exists) profile = snap.data() || {};
    } catch (_err) {
      // Firestore lookup is best-effort; fall back to token claims only.
    }

    req.user = {
      uid: decoded.uid,
      email: decoded.email || '',
      name: profile.name || decoded.name || '',
      role: profile.role || decoded.role || 'client',
      ...profile,
    };

    next();
  } catch (error) {
    return res.status(401).json({
      success: false,
      message: 'Invalid or expired token.',
      error: error?.message,
    });
  }
}

/**
 * Middleware factory: restricts a route to specific roles.
 * Usage: router.get('/x', authenticate, requireRole('admin'))
 */
export function requireRole(...roles) {
  return (req, res, next) => {
    if (!req.user) {
      return res
        .status(401)
        .json({ success: false, message: 'Authentication required.' });
    }
    if (roles.length && !roles.includes(req.user.role)) {
      return res.status(403).json({
        success: false,
        message: `Forbidden. Required role: ${roles.join(' or ')}.`,
      });
    }
    next();
  };
}

/**
 * True when the caller holds the `admin` role.
 */
export function isAdmin(req) {
  return req.user?.role === 'admin';
}

/**
 * Answers the standard 403 payload so every route reports denial identically.
 */
export function forbidden(res, message = 'Forbidden') {
  return res.status(403).json({ success: false, message });
}

/**
 * Middleware factory for `/:userId` style routes: the caller may only read
 * their own records unless they are an administrator.
 *
 * Usage: router.get('/:userId', authenticate, requireSelfOrAdmin(), ...)
 */
export function requireSelfOrAdmin(paramName = 'userId') {
  return (req, res, next) => {
    if (isAdmin(req)) return next();
    if (req.params[paramName] !== req.user?.uid) {
      return forbidden(res, 'Forbidden. You can only access your own records.');
    }
    next();
  };
}

/**
 * Resolves the owner id for a CREATE request.
 *
 * An administrator may create a record on behalf of another user (the admin
 * panel relies on this). Everybody else is always bound to `req.user.uid` —
 * a `userId` supplied in the request body is ignored, which is what stops a
 * client from attributing a record to somebody else.
 */
export function ownerIdFor(req) {
  const requested = req.body?.userId;
  return isAdmin(req) && requested ? requested : req.user.uid;
}

/**
 * Ownership test for an EXISTING record.
 *
 * A record without an owner id is treated as NOT owned: the previous
 * `record.userId && record.userId !== req.user.uid` test let any signed-in
 * user edit or delete ownerless documents.
 */
export function isOwner(record, req) {
  if (isAdmin(req)) return true;
  return Boolean(record?.userId) && record.userId === req.user.uid;
}

/**
 * Keeps a record's owner fixed during an UPDATE.
 *
 * Passing `userId` in the body must not let a normal caller hand their record
 * (or the record they are editing) to another account — reassignment stays an
 * administrator-only operation. Mutates and returns `data` for convenience.
 */
export function lockOwnerOnUpdate(data, existing, req) {
  if (isAdmin(req)) return data;
  if (existing?.userId === undefined) delete data.userId;
  else data.userId = existing.userId;
  return data;
}
