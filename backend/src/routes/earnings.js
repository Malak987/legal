import { Router } from 'express';
import { getDb } from '../config/firebase.js';
import { authenticate } from '../middleware/auth.js';
import { ok, notFound } from '../utils/response.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { getDocById } from '../utils/firestore.js';

const router = Router();
const COLLECTION = 'earnings';

// GET /api/earnings/:userId
router.get(
  '/:userId',
  authenticate,
  asyncHandler(async (req, res) => {
    const { userId } = req.params;
    if (req.user.role !== 'admin' && req.user.uid !== userId) {
      return res.status(403).json({ success: false, message: 'Forbidden' });
    }
    const earnings = await getDocById(getDb(), COLLECTION, userId);
    if (!earnings) return notFound(res, 'No earnings record found');
    ok(res, earnings);
  }),
);

export default router;
