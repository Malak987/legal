import { Router } from 'express';
import { getDb } from '../config/firebase.js';
import { authenticate } from '../middleware/auth.js';
import { ok, created, notFound, badRequest } from '../utils/response.js';
import { validate, messageSchema } from '../utils/validators.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { getDocById, createDoc, serverTimestamp } from '../utils/firestore.js';

const router = Router();
const CHATS = 'chats';

/// Normalises a Firestore Timestamp, `Date`, ISO string or epoch-millis value
/// to milliseconds so the list can be ordered in memory.
///
/// Missing/unparseable values become `0` rather than `NaN`, which keeps those
/// documents in the result set instead of silently dropping them.
function toMillis(value) {
  if (value === null || value === undefined) return 0;
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'number') return Number.isFinite(value) ? value : 0;
  // Serialised Firestore Timestamp ({ _seconds, _nanoseconds }).
  if (typeof value === 'object' && typeof value._seconds === 'number') {
    return value._seconds * 1000 + Math.floor((value._nanoseconds ?? 0) / 1e6);
  }
  const parsed = Date.parse(value);
  return Number.isNaN(parsed) ? 0 : parsed;
}

/// Newest conversation first; conversations without a timestamp sort last.
function byUpdatedAtDesc(a, b) {
  return toMillis(b.updatedAt) - toMillis(a.updatedAt);
}

// GET /api/chats?userId=  -> list chats the user participates in
router.get(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const { userId } = req.query;
    const coll = getDb().collection(CHATS);
    const isAdmin = req.user.role === 'admin';

    // Firestore needs a COMPOSITE index to combine an `array-contains` filter
    // with `orderBy` on a different field. That index is not deployed in this
    // project, so the previous
    //   where('participants','array-contains',x).orderBy('updatedAt','desc')
    // was rejected with `9 FAILED_PRECONDITION` and the admin panel rendered a
    // 500. Every branch below is either a plain collection read or a single
    // `array-contains` filter, both served by the automatic single-field index;
    // ordering is applied in memory — the same strategy `utils/firestore.js`
    // already documents for this codebase.
    //
    // NOTE ON SIZE: this endpoint has never been paginated and the response
    // shape must stay a bare list (`data: [...]` — see `listDataOf` in the
    // admin panel), so no page/limit is introduced here. It reads at most the
    // `chats` collection itself (one document per client<->lawyer
    // conversation; the seed creates one). If that collection ever grows into
    // the tens of thousands, add pagination as a separate, response-shape
    // compatible change.
    //
    // Errors are NOT swallowed: a genuine Firestore failure still reaches
    // `asyncHandler` -> `errorHandler` and is reported to the client as a 500.
    let query;
    if (userId && isAdmin) {
      // Only an administrator may ask for somebody else's conversations.
      query = coll.where('participants', 'array-contains', userId);
    } else if (isAdmin) {
      // An administrator moderates every conversation but is a participant in
      // none of them, so filtering by their own uid always returned [].
      query = coll;
    } else {
      // Non-admins always see their own conversations, even if they try to
      // pass ?userId= for another account.
      query = coll.where('participants', 'array-contains', req.user.uid);
    }

    const snap = await query.get();
    const chats = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    chats.sort(byUpdatedAtDesc);

    ok(res, chats);
  }),
);

// GET /api/chats/:id  -> chat metadata + messages
router.get(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const chat = await getDocById(getDb(), CHATS, req.params.id);
    if (!chat) return notFound(res, 'Chat not found');
    if (!chat.participants.includes(req.user.uid) && req.user.role !== 'admin') {
      return res.status(403).json({ success: false, message: 'Forbidden' });
    }
    const msgSnap = await getDb()
      .collection(CHATS)
      .doc(req.params.id)
      .collection('messages')
      .orderBy('createdAt', 'asc')
      .get();
    const messages = msgSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
    ok(res, { ...chat, messages });
  }),
);

// POST /api/chats  { participants: [...], participantNames: {...} }
router.post(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const { participants, participantNames } = req.body || {};
    if (!Array.isArray(participants) || participants.length < 2) {
      return badRequest(res, 'participants (array of >= 2 uids) is required');
    }
    const ref = await getDb().collection(CHATS).add({
      participants,
      participantNames: participantNames || {},
      lastMessage: '',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    const snap = await ref.get();
    created(res, { id: snap.id, ...snap.data() }, 'Chat created');
  }),
);

// POST /api/chats/:id/messages  { senderId, senderName, text }
router.post(
  '/:id/messages',
  authenticate,
  asyncHandler(async (req, res) => {
    const chat = await getDocById(getDb(), CHATS, req.params.id);
    if (!chat) return notFound(res, 'Chat not found');

    const data = validate(messageSchema, req.body);
    const ref = await getDb()
      .collection(CHATS)
      .doc(req.params.id)
      .collection('messages')
      .add({ ...data, createdAt: serverTimestamp() });

    await getDb().collection(CHATS).doc(req.params.id).update({
      lastMessage: data.text,
      updatedAt: serverTimestamp(),
    });

    const snap = await ref.get();
    created(res, { id: snap.id, ...snap.data() }, 'Message sent');
  }),
);

// DELETE /api/chats/:id
router.delete(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const chat = await getDocById(getDb(), CHATS, req.params.id);
    if (!chat) return notFound(res, 'Chat not found');
    await getDb().collection(CHATS).doc(req.params.id).delete();
    ok(res, { id: req.params.id }, 'Chat deleted');
  }),
);

export default router;
