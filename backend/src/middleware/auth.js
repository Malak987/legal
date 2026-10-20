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
