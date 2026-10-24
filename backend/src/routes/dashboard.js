import { Router } from 'express';
import { callUserRpc } from '../utils/supabase_rpc.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { ok } from '../utils/response.js';
import { asyncHandler } from '../utils/asyncHandler.js';

const router = Router();

// GET /api/dashboard/stats (admin only). The aggregate RPC verifies the role
// again in PostgreSQL and does not grant service_role access to the route.
router.get(
  '/stats',
  authenticate,
  requireRole('admin'),
  asyncHandler(async (req, res) => {
    const stats = await callUserRpc(req, 'rpc_dashboard_stats');
    ok(res, {
      users: stats.users,
      lawyers: stats.lawyers,
      cases: stats.cases,
      bookings: stats.bookings,
      reviews: stats.reviews,
      plans: stats.plans,
      subscriptions: stats.subscriptions,
      bookingsByStatus: {
        active: stats.activeBookings,
        completed: stats.completedBookings,
        cancelled: stats.cancelledBookings,
      },
      totalWalletBalance: stats.walletBalance,
      generatedAt: new Date().toISOString(),
    });
  }),
);

export default router;
