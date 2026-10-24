import { Router } from 'express';
import { requestDatabase, callUserRpc, rpcErrorToken, rpcRow } from '../utils/supabase_rpc.js';
import { authenticate, isAdmin, forbidden } from '../middleware/auth.js';
import { ok, created, notFound, badRequest } from '../utils/response.js';
import { validate, messageSchema } from '../utils/validators.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { getDocById, sortByDesc } from '../utils/supabase_database.js';

const router = Router();
const CHATS = 'chats';

function canAccessChat(chat, req) {
  return isAdmin(req) ||
    (Array.isArray(chat?.participants) && chat.participants.includes(req.user.uid));
}

// GET /api/chats?userId= — caller-scoped list, ordered in memory.
router.get(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const { userId } = req.query;
    const db = requestDatabase(req);
    const admin = isAdmin(req);
    const query = userId && admin
      ? db.collection(CHATS).where('participants', 'array-contains', userId)
      : admin
        ? db.collection(CHATS)
        : db.collection(CHATS).where('participants', 'array-contains', req.user.uid);
    const snap = await query.get();
    const chats = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    sortByDesc(chats, 'updatedAt');
    ok(res, chats);
  }),
);

// GET /api/chats/:id — metadata and messages are both subject to RLS.
router.get(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const db = requestDatabase(req);
    const chat = await getDocById(db, CHATS, req.params.id);
    if (!chat) return notFound(res, 'Chat not found');
    if (!canAccessChat(chat, req)) {
      return forbidden(res, 'Forbidden. You are not a participant of this chat.');
    }
    const msgSnap = await db.collection(CHATS)
      .doc(req.params.id)
      .collection('messages')
      .orderBy('createdAt', 'asc')
      .get();
    const messages = msgSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
    ok(res, { ...chat, messages });
  }),
);

// POST /api/chats { participants: [...] }; identity and participant roles are
// validated again inside the caller-JWT RPC before the transaction commits.
router.post(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const { participants } = req.body || {};
    if (!Array.isArray(participants) || participants.length < 2) {
      return badRequest(res, 'participants (array of >= 2 uids) is required');
    }
    if (!participants.every((uid) => typeof uid === 'string' && uid.trim())) {
      return badRequest(res, 'participants must be a list of user ids');
    }
    const uniqueParticipants = [...new Set(participants.map((uid) => uid.trim()))];
    if (uniqueParticipants.length < 2) {
      return badRequest(res, 'participants must contain at least 2 distinct users');
    }
    if (!isAdmin(req) && !uniqueParticipants.includes(req.user.uid)) {
      return forbidden(res, 'Forbidden. You must be one of the participants.');
    }

    try {
      const outcome = await callUserRpc(req, 'rpc_chat_create', {
        p_participants: uniqueParticipants,
        p_initial_message: null,
      });
      const chat = rpcRow(CHATS, outcome?.chat);
      if (!chat) throw new Error('Supabase chat RPC returned an unexpected result.');
      return created(res, chat, 'Chat created');
    } catch (error) {
      const token = rpcErrorToken(error);
      if (error.code === '42501') return forbidden(res, 'Forbidden. You cannot create this conversation.');
      if (error.code === '22023') return badRequest(res, `Invalid chat participants (${token || 'validation failed'}).`);
      throw error;
    }
  }),
);

// POST /api/chats/:id/messages — sender identity and last_message update are
// written atomically in PostgreSQL using auth.uid().
router.post(
  '/:id/messages',
  authenticate,
  asyncHandler(async (req, res) => {
    const chat = await getDocById(requestDatabase(req), CHATS, req.params.id);
    if (!chat) return notFound(res, 'Chat not found');
    if (!canAccessChat(chat, req)) {
      return forbidden(res, 'Forbidden. You are not a participant of this chat.');
    }
    const data = validate(messageSchema, req.body);
    try {
      const outcome = await callUserRpc(req, 'rpc_chat_send_message', {
        p_chat_id: req.params.id,
        p_text: data.text,
      });
      const message = rpcRow('messages', outcome);
      if (!message) throw new Error('Supabase chat message RPC returned an unexpected result.');
      return created(res, message, 'Message sent');
    } catch (error) {
      const token = rpcErrorToken(error);
      if (error.code === '42501') return forbidden(res, 'Forbidden. You are not a participant of this chat.');
      if (error.code === 'P0002' || token === 'CHAT_NOT_FOUND') return notFound(res, 'Chat not found');
      if (error.code === '22023') return badRequest(res, `Invalid chat message (${token || 'validation failed'}).`);
      throw error;
    }
  }),
);

// DELETE /api/chats/:id — RLS enforces participant/admin authorization.
router.delete(
  '/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const db = requestDatabase(req);
    const chat = await getDocById(db, CHATS, req.params.id);
    if (!chat) return notFound(res, 'Chat not found');
    if (!canAccessChat(chat, req)) {
      return forbidden(res, 'Forbidden. You are not a participant of this chat.');
    }
    await db.collection(CHATS).doc(req.params.id).delete();
    ok(res, { id: req.params.id }, 'Chat deleted');
  }),
);

export default router;
