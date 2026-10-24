import { Router } from 'express';
import rateLimit from 'express-rate-limit';

import { getAuth } from '../config/supabase.js';
import { isLawyerSignupEnabled } from '../config/env.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { validate, lawyerSignupSchema } from '../utils/validators.js';

const router = Router();
const SIGNUP_MESSAGE =
  'If this registration can be completed, check the supplied email for a confirmation link.';

const lawyerSignupLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 5,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    message: 'Too many registration attempts. Please try again later.',
  },
});

// POST /api/auth/lawyer-signup
// Public signup is fail-closed by default. The trusted Auth adapter creates a
// new unconfirmed Auth user through the anon client and writes only
// app_metadata.signup_role after verifying that exact, new Auth UUID through
// the server-side Auth Admin API. The database trigger assigns `lawyer` after
// email confirmation. No client-supplied role or user/profile ID is accepted.
router.post(
  '/lawyer-signup',
  lawyerSignupLimiter,
  asyncHandler(async (req, res) => {
    if (!isLawyerSignupEnabled()) {
      return res.status(503).json({
        success: false,
        message: 'Lawyer registration is temporarily unavailable.',
      });
    }

    const input = validate(lawyerSignupSchema, req.body);
    try {
      await getAuth().createLawyerSignup(input);
      // The same response is returned for a duplicate address and a newly
      // accepted signup to avoid disclosing account existence.
      return res.status(202).json({ success: true, message: SIGNUP_MESSAGE });
    } catch (error) {
      // Auth provider errors can include the email address or internal details;
      // keep them out of API responses and logs.
      console.error('[lawyer-signup] request failed:', error?.code || 'unknown');
      return res.status(503).json({
        success: false,
        message: 'Registration could not be completed. Contact support if you already submitted the form.',
      });
    }
  }),
);

export default router;
