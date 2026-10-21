import { createHash } from 'node:crypto';

import { Router } from 'express';
import { getDb } from '../config/firebase.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import {
  ok,
  created,
  notFound,
  badRequest,
  conflict,
  parseListQuery,
  cleanObject,
} from '../utils/response.js';
import {
  validate,
  reviewSchema,
  reviewCreateSchema,
  reviewUpdateSchema,
} from '../utils/validators.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import {
  listDocs,
  getDocById,
  createDoc,
  updateDoc,
  deleteDoc,
  serverTimestamp,
} from '../utils/firestore.js';

const router = Router();
const COLLECTION = 'reviews';

/**
 * Public shape of a review.
 *
 * `userId` is the author's Firebase uid. It is not needed to render a review
 * (the display name is stored separately) and it lets any anonymous caller
 * build a map of "who reviewed which lawyer", so it never leaves the server.
 */
function publicReview(review) {
  if (!review) return review;
  const { userId: _authorId, ...rest } = review;
  return rest;
}

/**
 * Deterministic id for one user's review of one lawyer.
 *
 * A plain "query, then insert" check would let two concurrent requests both
 * see no review and both write, so the uniqueness guarantee is structural —
 * the same (author, lawyer) pair always addresses the same document, which
 * Firestore's transaction conflict detection can then protect.
 */
function reviewDocId(userId, lawyerId) {
  return createHash('sha256').update(`${userId}\u0000${lawyerId}`).digest('hex');
}

// GET /api/reviews?lawyerId=&userId=  (public listing, author ids stripped)
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const q = parseListQuery(req);
    const result = await listDocs(getDb(), COLLECTION, {
      search: q.search,
      searchFields: ['comment', 'userName'],
      filters: cleanObject({ lawyerId: req.query.lawyerId, userId: req.query.userId }),
      sort: 'rating',
      order: 'desc',
      page: q.page,
      limit: q.limit,
    });

    // A `userId` filter is still honoured (it is how a client asks for "my
    // reviews"), but the identifier is not echoed back in the results.
    ok(res, { ...result, items: result.items.map(publicReview) });
  }),
);

// GET /api/reviews/:id
router.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const item = await getDocById(getDb(), COLLECTION, req.params.id);
    if (!item) return notFound(res, 'Review not found');
    ok(res, publicReview(item));
  }),
);

// POST /api/reviews
//
// One review per (author, lawyer). Without this an authenticated account could
// post unlimited five-star reviews and move a lawyer's average at will.
router.post(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const data = validate(reviewCreateSchema, {
      ...req.body,
      // A review is attributed to its author, never to a client-supplied id.
      userId: req.user.uid,
      userName: req.user.name,
    });

    const db = getDb();
    const reviewId = reviewDocId(req.user.uid, data.lawyerId);
    const ref = db.collection(COLLECTION).doc(reviewId);

    const outcome = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (snap.exists) return { status: 'duplicate' };

      tx.set(ref, {
        ...data,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
      return { status: 'created' };
    });

    if (outcome.status === 'duplicate') {
      return conflict(res, 'You have already reviewed this lawyer.');
    }

    // The author is the caller, so returning their own id here leaks nothing
    // and keeps the create response useful for the client that just posted it.
    const saved = await getDocById(db, COLLECTION, reviewId);
    created(res, saved, 'Review created');
  }),
);

// PUT /api/reviews/:id  (admin moderation: rating and comment only)
router.put(
  '/:id',
  authenticate,
  requireRole('admin'),
  asyncHandler(async (req, res) => {
    // Authorship is provenance, not content: an administrator edits the rating
    // or the wording, never who wrote the review.
    const data = validate(reviewUpdateSchema, req.body, { presence: 'optional' });
    const updated = await updateDoc(getDb(), COLLECTION, req.params.id, data);
    if (!updated) return notFound(res, 'Review not found');
    ok(res, publicReview(updated), 'Review updated');
  }),
);

// DELETE /api/reviews/:id  (admin only)
router.delete(
  '/:id',
  authenticate,
  requireRole('admin'),
  asyncHandler(async (req, res) => {
    const deleted = await deleteDoc(getDb(), COLLECTION, req.params.id);
    if (!deleted) return notFound(res, 'Review not found');
    ok(res, { id: req.params.id }, 'Review deleted');
  }),
);

export default router;
