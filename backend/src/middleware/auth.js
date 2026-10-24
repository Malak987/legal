import { getAuth } from '../config/supabase.js';

/** Extracts the bearer token from an Authorization header. */
function extractToken(req) {
  const header = req.headers.authorization || '';
  if (!header.startsWith('Bearer ')) return null;
  return header.slice('Bearer '.length).trim();
}

/**
 * Verifies a Supabase access token and creates a request-scoped PostgREST
 * database client. Data routes use the caller JWT so PostgreSQL RLS—not the
 * process-wide service role—decides the accessible rows and columns.
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

    const auth = getAuth();
    const decoded = await auth.verifyIdToken(token);
    let requestDb;
    try {
      requestDb = auth.createRequestDatabase(token);
    } catch {
      return res.status(503).json({
        success: false,
        message: 'Authenticated Supabase data access is not configured.',
      });
    }

    req.supabaseDb = requestDb;
    req.user = {
      uid: decoded.uid,
      authUserId: decoded.authUserId,
      email: decoded.email || '',
      name: decoded.name || '',
      role: decoded.role,
      email_verified: decoded.email_verified === true,
    };
    return next();
  } catch (error) {
    // Do not return token/signature or provider internals to the client.
    console.error('[auth] Supabase token verification failed:', error?.message);
    return res.status(401).json({
      success: false,
      message: 'Invalid or expired Supabase access token.',
    });
  }
}

/** Allows anonymous catalogue reads while authenticating any supplied bearer. */
export function optionalAuthenticate(req, res, next) {
  if (!extractToken(req)) return next();
  return authenticate(req, res, next);
}

/** Restricts a route to specific server-verified application roles. */
export function requireRole(...roles) {
  return (req, res, next) => {
    if (!req.user) {
      return res
        .status(401)
        .json({ success: false, message: 'Authentication required.' });
    }
    // `owner` is a trusted, separately provisioned superset of `admin`.
    // This alias never grants `owner` to a client-supplied role or payload.
    const roleAllowed =
      roles.includes(req.user.role) ||
      (req.user.role === 'owner' && roles.includes('admin'));
    if (roles.length && !roleAllowed) {
      return res.status(403).json({
        success: false,
        message: `Forbidden. Required role: ${roles.join(' or ')}.`,
      });
    }
    return next();
  };
}

export function isAdmin(req) {
  return req.user?.role === 'admin' || req.user?.role === 'owner';
}

export function forbidden(res, message = 'Forbidden') {
  return res.status(403).json({ success: false, message });
}

/** Caller may access their own `/:userId` records unless they are an admin. */
export function requireSelfOrAdmin(paramName = 'userId') {
  return (req, res, next) => {
    if (isAdmin(req)) return next();
    if (req.params[paramName] !== req.user?.uid) {
      return forbidden(res, 'Forbidden. You can only access your own records.');
    }
    return next();
  };
}

/** Admins may choose an owner; other roles are always bound to their profile. */
export function ownerIdFor(req) {
  const requested = req.body?.userId;
  return isAdmin(req) && requested ? requested : req.user.uid;
}

/** Ownerless rows are never owned by a non-admin. */
export function isOwner(record, req) {
  if (isAdmin(req)) return true;
  return req.user?.role === 'client' &&
    Boolean(record?.userId) && record.userId === req.user.uid;
}

/** Keeps owner assignment fixed for non-admin updates. */
export function lockOwnerOnUpdate(data, existing, req) {
  if (isAdmin(req)) return data;
  if (existing?.userId === undefined) delete data.userId;
  else data.userId = existing.userId;
  return data;
}
