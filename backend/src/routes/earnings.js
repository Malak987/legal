import { Router } from 'express';
import { requestDatabase } from '../utils/supabase_rpc.js';
import { authenticate, requireSelfOrAdmin } from '../middleware/auth.js';
import { ok, notFound } from '../utils/response.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { getDocById } from '../utils/supabase_database.js';

const router = Router();
const COLLECTION = 'earnings';

// GET /api/earnings/:userId
router.get(
  '/:userId',
  authenticate,
  requireSelfOrAdmin('userId'),
  asyncHandler(async (req, res) => {
    const { userId } = req.params;
    const earnings = await getDocById(requestDatabase(req), COLLECTION, userId);
    if (!earnings) return notFound(res, 'No earnings record found');
    ok(res, earnings);
  }),
);

export default router;
