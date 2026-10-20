import { Router } from 'express';
import { getDb, admin } from '../config/firebase.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { ok } from '../utils/response.js';
import { asyncHandler } from '../utils/asyncHandler.js';

const router = Router();

async function count(collection, filters = {}) {
  let snap = await getDb().collection(collection).get();
  let docs = snap.docs.map((d) => d.data());
  for (const [k, v] of Object.entries(filters)) {
    if (v !== undefined) docs = docs.filter((d) => d[k] === v);
  }
  return docs.length;
}

// GET /api/dashboard/stats  (admin only)
router.get(
  '/stats',
  authenticate,
  requireRole('admin'),
  asyncHandler(async (_req, res) => {
    const db = getDb();

    const [
      totalUsers,
      totalLawyers,
      totalCases,
      totalBookings,
      totalReviews,
      totalPlans,
      totalSubscriptions,
      activeBookings,
      completedBookings,
      cancelledBookings,
    ] = await Promise.all([
      count('users'),
      count('lawyers'),
      count('cases'),
      count('bookings'),
      count('reviews'),
      count('plans'),
      count('subscriptions'),
      count('bookings', { status: 'Active' }),
      count('bookings', { status: 'Completed' }),
      count('bookings', { status: 'Cancelled' }),
    ]);

    // Sum of wallet balances across users (financial overview)
    const wallets = await db.collection('wallets').get();
    const totalWalletBalance = wallets.docs.reduce(
      (sum, d) => sum + (d.data().balance ?? 0),
      0,
    );

    ok(res, {
      users: totalUsers,
      lawyers: totalLawyers,
      cases: totalCases,
      bookings: totalBookings,
      reviews: totalReviews,
      plans: totalPlans,
      subscriptions: totalSubscriptions,
      bookingsByStatus: {
        active: activeBookings,
        completed: completedBookings,
        cancelled: cancelledBookings,
      },
      totalWalletBalance,
      generatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }),
);

export default router;
