/**
 * Regression tests for message-sender identity (Wave 1.1).
 *
 * The independent review proved that a participant could post a message that
 * the server stored with `senderId: 'admin-1'` and an arbitrary `senderName`,
 * because `messageSchema` accepted both fields and the handler persisted them
 * verbatim. The sender is now derived from the verified token.
 *
 * The participant check itself is covered by `chats_authorization.test.js`;
 * the PR #4 index/500 fix is covered by `chats.test.js`. Both are re-run
 * unmodified by `npm test`.
 */

import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  docs,
  get,
  post,
  reset,
  signIn,
  startApp,
  stopApp,
  tokenFor,
  users,
} from './helpers/harness.js';

const BASE = '/api/chats';

before(startApp);
after(stopApp);

function seed() {
  return {
    users: users('client1', 'lawyer1', 'admin1'),
    chats: [
      {
        id: 'chat-1',
        participants: ['client-1', 'lawyer-1'],
        participantNames: { 'client-1': 'Client One', 'lawyer-1': 'Lawyer One' },
        lastMessage: '',
      },
      {
        id: 'chat-2',
        participants: ['client-1', 'admin-1'],
        participantNames: {},
        lastMessage: '',
      },
    ],
    'chats/chat-1/messages': [],
    'chats/chat-2/messages': [],
  };
}

const messagesOf = (chatId) => docs(`chats/${chatId}/messages`);

describe('chats 1.1: the sender comes from the token', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('stores the caller as sender for an ordinary message', async () => {
    signIn('client1');

    const res = await post(`${BASE}/chat-1/messages`, {
      token: tokenFor('client1'),
      body: { text: 'hello' },
    });

    assert.equal(res.status, 201);
    assert.equal(res.body.data.senderId, 'client-1');
    assert.equal(res.body.data.senderName, 'Client One');
    assert.equal(res.body.data.text, 'hello');

    const stored = messagesOf('chat-1');
    assert.equal(stored.length, 1);
    assert.equal(stored[0].senderId, 'client-1');
    assert.equal(stored[0].senderName, 'Client One');
  });

  it('ignores a forged senderId naming the administrator', async () => {
    signIn('client1');

    const res = await post(`${BASE}/chat-1/messages`, {
      token: tokenFor('client1'),
      body: { senderId: 'admin-1', senderName: 'Admin One', text: 'authorised by admin' },
    });

    assert.equal(res.status, 201);
    assert.equal(res.body.data.senderId, 'client-1', 'the token wins');
    assert.notEqual(res.body.data.senderId, 'admin-1');

    const stored = messagesOf('chat-1')[0];
    assert.equal(stored.senderId, 'client-1');
    assert.notEqual(stored.senderId, 'admin-1');
    assert.equal(stored.text, 'authorised by admin', 'message text is still delivered');
  });

  it('ignores a forged senderName only', async () => {
    signIn('client1');

    const res = await post(`${BASE}/chat-1/messages`, {
      token: tokenFor('client1'),
      body: { senderName: 'Administrator', text: 'hi' },
    });

    assert.equal(res.status, 201);
    assert.equal(res.body.data.senderName, 'Client One');
    assert.notEqual(messagesOf('chat-1')[0].senderName, 'Administrator');
  });

  it('never stores another participant\'s identity', async () => {
    signIn('lawyer1');

    await post(`${BASE}/chat-1/messages`, {
      token: tokenFor('lawyer1'),
      body: { senderId: 'client-1', senderName: 'Client One', text: 'from the lawyer' },
    });

    const stored = messagesOf('chat-1')[0];
    assert.equal(stored.senderId, 'lawyer-1');
    assert.equal(stored.senderName, 'Lawyer One');
  });

  it('falls back to a neutral label when the profile has no name', async () => {
    reset({
      collections: {
        // A verified application profile may have a blank display name.
        users: [
          { id: 'ghost-1', uid: 'ghost-1', name: '', email: 'ghost@example.com', role: 'client' },
        ],
        chats: [
          { id: 'chat-1', participants: ['ghost-1', 'lawyer-1'], participantNames: {}, lastMessage: '' },
        ],
        'chats/chat-1/messages': [],
      },
    });
    // A token whose decoded claims carry no `name` either.
    signIn('client1');
    globalThis.__fx.user = { uid: 'ghost-1', role: 'client', name: '', token: tokenFor('client1') };
    globalThis.__fx.user.token = 'token-ghost-1';

    const res = await post(`${BASE}/chat-1/messages`, {
      token: 'token-ghost-1',
      body: { text: 'anonymous' },
    });

    assert.equal(res.status, 201);
    assert.equal(res.body.data.senderId, 'ghost-1');
    assert.equal(res.body.data.senderName, 'User', 'no e-mail or uid leaks as the name');
  });
});

describe('chats 1.1: participation is still enforced', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('denies a non-participant and leaves the conversation untouched', async () => {
    signIn('lawyer1');
    const before = { ...docs('chats').find((c) => c.id === 'chat-2') };

    const res = await post(`${BASE}/chat-2/messages`, {
      token: tokenFor('lawyer1'),
      body: { senderId: 'admin-1', senderName: 'Admin One', text: 'intrusion' },
    });

    assert.equal(res.status, 403);
    assert.equal(messagesOf('chat-2').length, 0);
    assert.deepEqual(docs('chats').find((c) => c.id === 'chat-2'), before);
  });

  it('does not update lastMessage when the sender is rejected', async () => {
    signIn('lawyer1');

    await post(`${BASE}/chat-1/messages`, {
      token: tokenFor('lawyer1'),
      body: { text: 'legitimate' },
    });
    const before = docs('chats').find((c) => c.id === 'chat-2').lastMessage;

    await post(`${BASE}/chat-2/messages`, {
      token: tokenFor('lawyer1'),
      body: { text: 'rejected' },
    });

    assert.equal(docs('chats').find((c) => c.id === 'chat-2').lastMessage, before);
  });
});

describe('chats 1.1: response shape keeps working for the admin panel', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('returns the stored sender fields when the conversation is read back', async () => {
    signIn('client1');

    await post(`${BASE}/chat-1/messages`, {
      token: tokenFor('client1'),
      body: { text: 'first' },
    });

    signIn('admin1');
    const res = await get(`${BASE}/chat-1`, { token: tokenFor('admin1') });

    assert.equal(res.status, 200);
    assert.equal(res.body.data.messages.length, 1);

    const message = res.body.data.messages[0];
    // The panel renders `senderName` and compares `senderId` to the viewer uid.
    assert.equal(message.senderId, 'client-1');
    assert.equal(message.senderName, 'Client One');
    assert.equal(message.text, 'first');
    assert.equal(message.lastMessage, undefined);
    assert.equal(res.body.data.lastMessage, 'first');
  });

  it('keeps the message envelope { success, message, data } unchanged', async () => {
    signIn('client1');

    const res = await post(`${BASE}/chat-1/messages`, {
      token: tokenFor('client1'),
      body: { text: 'envelope' },
    });

    assert.equal(res.status, 201);
    assert.equal(res.body.success, true);
    assert.equal(typeof res.body.message, 'string');
    assert.equal(typeof res.body.data.id, 'string');
    assert.equal(res.body.data.text, 'envelope');
  });

  it('rejects an empty message', async () => {
    signIn('client1');

    const res = await post(`${BASE}/chat-1/messages`, {
      token: tokenFor('client1'),
      body: { text: '   ' },
    });

    assert.equal(res.status, 400);
    assert.equal(messagesOf('chat-1').length, 0);
  });
});

/* =====================================================================
 * WAVE 1.2 — participantNames are derived, not supplied (F-08)
 *
 * `POST /chats` used to store the client's `participantNames` map verbatim,
 * and the admin panel renders its first value as the conversation title. A
 * client could therefore make their chat appear as "App Administrator".
 * ===================================================================*/

describe('chats 1.2: participant names come from the profiles', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('ignores a forged administrator name and stores the real one', async () => {
    signIn('client1');

    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: {
        participants: ['client-1', 'lawyer-1'],
        participantNames: { 'client-1': 'App Administrator', 'lawyer-1': 'Support Team' },
      },
    });

    assert.equal(res.status, 201);
    assert.deepEqual(res.body.data.participantNames, {
      'client-1': 'Client One',
      'lawyer-1': 'Lawyer One',
    });

    const stored = docs('chats').find((c) => c.id === res.body.data.id);
    assert.equal(stored.participantNames['client-1'], 'Client One');
    // The value the admin panel would render as the chat title.
    assert.equal(stored.participantNames['client-1'], 'Client One');
    assert.notEqual(stored.participantNames['client-1'], 'App Administrator');
  });

  it('rejects a participant with no application profile and writes nothing', async () => {
    signIn('client1');

    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: { participants: ['client-1', 'ghost-9'] },
    });

    assert.equal(res.status, 400);
    assert.match(res.body.message, /CHAT_PARTICIPANT_NOT_FOUND/);
    assert.equal(docs('chats').length, 2);
  });

  it('rejects duplicate participants instead of treating them as two people', async () => {
    signIn('client1');

    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: { participants: ['client-1', 'client-1'] },
    });

    assert.equal(res.status, 400);
    assert.equal(docs('chats').length, 2);
  });

  it('rejects a participants list containing non-strings', async () => {
    signIn('client1');

    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: { participants: ['client-1', { uid: 'lawyer-1' }] },
    });

    assert.equal(res.status, 400);
    assert.equal(docs('chats').length, 2);
  });

  it('still lets an admin open a conversation for two other users', async () => {
    signIn('admin1');

    const res = await post(BASE, {
      token: tokenFor('admin1'),
      body: { participants: ['client-1', 'lawyer-1'] },
    });

    assert.equal(res.status, 201);
    assert.deepEqual(res.body.data.participantNames, {
      'client-1': 'Client One',
      'lawyer-1': 'Lawyer One',
    });
  });
});
