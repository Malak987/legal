import { Router } from 'express';
import { getDb } from '../config/firebase.js';
import { authenticate } from '../middleware/auth.js';
import { ok, created, notFound, badRequest } from '../utils/response.js';
import { validate, messageSchema } from '../utils/validators.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { getDocById, createDoc, serverTimestamp } from '../utils/firestore.js';

const router = Router();
const CHATS = 'chats';

// GET /api/chats?userId=  -> list chats the user participates in
router.get(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const { userId } = req.query;
    const target = userId || req.user.uid;
    const snap = await getDb()
      .collection(CHATS)
      .where('participants', 'array-contains', target)
      .orderBy('updatedAt', 'desc')
      .get();
    const chats = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
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
