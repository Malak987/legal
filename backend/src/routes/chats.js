import { Router } from 'express';
import { getDb } from '../config/firebase.js';
import { authenticate, isAdmin, forbidden } from '../middleware/auth.js';
import { ok, created, notFound, badRequest } from '../utils/response.js';
import { validate, messageSchema } from '../utils/validators.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import {
  getDocById,
  serverTimestamp,
  sortByDesc,
} from '../utils/firestore.js';

const router = Router();
const CHATS = 'chats';

/// Authorization rule shared by every per-conversation route.
///
/// A caller may touch a conversation only when they are one of its
/// participants. Administrators moderate every conversation but are a
/// participant in none of them, so they are allowed explicitly.
function canAccessChat(chat, req) {
  if (isAdmin(req)) return true;
  return Array.isArray(chat?.participants) && chat.participants.includes(req.user.uid);
}

/// Sender identity is always taken from the verified token, never from the
/// request body: a participant must not be able to post as somebody else.
///
/// The display name falls back to a neutral label rather than the e-mail
/// address, so no contact detail leaks into a conversation it was not in.
function senderIdentity(req) {
  const name = typeof req.user?.name === 'string' ? req.user.name.trim() : '';
  return { senderId: req.user.uid, senderName: name || 'User' };
}

/**
 * Builds the `participantNames` map from the users collection.
 *
 * The client used to supply this map itself, and the admin panel renders its
 * first value as the conversation title — so a client could make their chat
 * appear as "App Administrator". Names are now read from the trusted profile
 * documents; a participant with no profile simply has no entry (the panel then
 * falls back to its generic "Chat" title).
 */
async function resolveParticipantNames(participants) {
  const db = getDb();
  const entries = await Promise.all(
    participants.map(async (uid) => {
      const profile = await getDocById(db, 'users', uid);
      const name = typeof profile?.name === 'string' ? profile.name.trim() : '';
      return name ? [uid, name] : null;
    }),
  );
  return Object.fromEntries(entries.filter(Boolean));
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
    sortByDesc(chats, 'updatedAt');

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
    if (!canAccessChat(chat, req)) {
      return forbidden(res, 'Forbidden. You are not a participant of this chat.');
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

// POST /api/chats  { participants: [...] }
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

    // Duplicate ids would make one participant count twice (and a "chat with
    // yourself" pass the >= 2 check).
    const uniqueParticipants = [...new Set(participants.map((uid) => uid.trim()))];
    if (uniqueParticipants.length < 2) {
      return badRequest(res, 'participants must contain at least 2 distinct users');
    }

    // The caller must be one of the participants: this stops a client from
    // opening a conversation they are not part of, or from silently adding
    // themselves to somebody else's chat by crafting the participants array.
    // Administrators are exempt — they open conversations on behalf of others.
    if (!isAdmin(req) && !uniqueParticipants.includes(req.user.uid)) {
      return forbidden(
        res,
        'Forbidden. You must be one of the participants.',
      );
    }

    // Display names come from the user profiles, never from the request body.
    const participantNames = await resolveParticipantNames(uniqueParticipants);

    const ref = await getDb().collection(CHATS).add({
      participants: uniqueParticipants,
      participantNames,
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
    if (!canAccessChat(chat, req)) {
      return forbidden(res, 'Forbidden. You are not a participant of this chat.');
    }

    // `senderId` / `senderName` in the body are stripped by the schema; the
    // stored identity comes from the token instead.
    const data = validate(messageSchema, req.body);
    const ref = await getDb()
      .collection(CHATS)
      .doc(req.params.id)
      .collection('messages')
      .add({ ...data, ...senderIdentity(req), createdAt: serverTimestamp() });

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
    if (!canAccessChat(chat, req)) {
      return forbidden(res, 'Forbidden. You are not a participant of this chat.');
    }
    await getDb().collection(CHATS).doc(req.params.id).delete();
    ok(res, { id: req.params.id }, 'Chat deleted');
  }),
);

export default router;
