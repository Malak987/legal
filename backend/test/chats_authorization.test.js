/**
 * Authorization regression tests for the chats routes.
 *
 * PR #4 fixed the admin 500 (composite-index query). This file locks that fix
 * in place AND covers the remaining hole: `POST /:id/messages` and
 * `DELETE /:id` only required a valid token, so any signed-in user could post
 * into, or delete, a conversation they were not part of.
 */

import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  del,
  docs,
  get,
  post,
  queries,
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

const at = (iso) => ({ toMillis: () => Date.parse(iso) });

function seed() {
  return {
    users: users('client1', 'client2', 'lawyer1', 'lawyer2', 'admin1'),
    chats: [
      {
        id: 'chat-1',
        participants: ['client-1', 'lawyer-1'],
        participantNames: { 'client-1': 'Client One', 'lawyer-1': 'Lawyer One' },
        lastMessage: '',
        createdAt: at('2026-01-01T09:00:00Z'),
        updatedAt: at('2026-01-02T09:00:00Z'),
      },
      {
        id: 'chat-2',
        participants: ['client-2', 'lawyer-1'],
        participantNames: {},
        lastMessage: '',
        createdAt: at('2026-01-01T09:00:00Z'),
        updatedAt: at('2026-01-05T09:00:00Z'),
      },
      {
        id: 'chat-3',
        participants: ['client-2', 'admin-1'],
        participantNames: {},
        lastMessage: '',
        createdAt: at('2026-01-01T09:00:00Z'),
        updatedAt: at('2026-01-03T09:00:00Z'),
      },
    ],
    'chats/chat-1/messages': [
      { id: 'm-1', senderId: 'client-1', senderName: 'Client One', text: 'hello' },
    ],
    'chats/chat-2/messages': [],
    'chats/chat-3/messages': [],
  };
}

describe('chats: posting messages', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('denies a non-participant and writes no message', async () => {
    signIn('client2');

    const res = await post(`${BASE}/chat-1/messages`, {
      token: tokenFor('client2'),
      body: { senderId: 'client-2', senderName: 'Client Two', text: 'intrusion' },
    });

    assert.equal(res.status, 403);
    assert.equal(res.body.success, false);
    assert.equal(docs('chats/chat-1/messages').length, 1);
    assert.equal(docs('chats').find((c) => c.id === 'chat-1').lastMessage, '');
  });

  it('lets a participant post a message', async () => {
    signIn('client1');

    const res = await post(`${BASE}/chat-1/messages`, {
      token: tokenFor('client1'),
      body: { senderId: 'client-1', senderName: 'Client One', text: 'still here?' },
    });

    assert.equal(res.status, 201);
    assert.equal(res.body.data.text, 'still here?');
    assert.equal(docs('chats/chat-1/messages').length, 2);
    assert.equal(docs('chats').find((c) => c.id === 'chat-1').lastMessage, 'still here?');
  });

  it('lets an admin post into any conversation', async () => {
    signIn('admin1');

    const res = await post(`${BASE}/chat-1/messages`, {
      token: tokenFor('admin1'),
      body: { senderId: 'admin-1', senderName: 'Admin One', text: 'moderation note' },
    });

    assert.equal(res.status, 201);
  });

  it('answers 404 for an unknown conversation', async () => {
    signIn('client1');

    const res = await post(`${BASE}/ghost/messages`, {
      token: tokenFor('client1'),
      body: { senderId: 'client-1', senderName: 'Client One', text: 'hi' },
    });

    assert.equal(res.status, 404);
  });
});

describe('chats: deletion', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('denies a non-participant and keeps the conversation', async () => {
    signIn('client2');

    const res = await del(`${BASE}/chat-1`, { token: tokenFor('client2') });

    assert.equal(res.status, 403);
    assert.equal(res.body.success, false);
    assert.ok(docs('chats').some((c) => c.id === 'chat-1'));
  });

  it('lets a participant delete the conversation', async () => {
    signIn('lawyer1');

    const res = await del(`${BASE}/chat-1`, { token: tokenFor('lawyer1') });

    assert.equal(res.status, 200);
    assert.equal(docs('chats').some((c) => c.id === 'chat-1'), false);
  });

  it('lets an admin delete any conversation', async () => {
    signIn('admin1');

    const res = await del(`${BASE}/chat-2`, { token: tokenFor('admin1') });

    assert.equal(res.status, 200);
    assert.equal(docs('chats').some((c) => c.id === 'chat-2'), false);
  });
});

describe('chats: creation', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('denies opening a conversation the caller is not part of', async () => {
    signIn('client1');

    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: { participants: ['client-2', 'lawyer-2'] },
    });

    assert.equal(res.status, 403);
    assert.equal(docs('chats').length, 3);
  });

  it('lets a client open a conversation they participate in', async () => {
    signIn('client1');

    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: { participants: ['client-1', 'lawyer-2'] },
    });

    assert.equal(res.status, 201);
    assert.deepEqual(res.body.data.participants, ['client-1', 'lawyer-2']);
    assert.equal(docs('chats').length, 4);
  });

  it('lets an admin open a conversation on behalf of others', async () => {
    signIn('admin1');

    const res = await post(BASE, {
      token: tokenFor('admin1'),
      body: { participants: ['client-1', 'lawyer-2'] },
    });

    assert.equal(res.status, 201);
  });
});

describe('chats: PR #4 behaviour is preserved', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('shows every conversation to an admin, newest first', async () => {
    signIn('admin1');

    const res = await get(BASE, { token: tokenFor('admin1') });

    assert.equal(res.status, 200);
    assert.deepEqual(res.body.data.map((c) => c.id), ['chat-2', 'chat-3', 'chat-1']);
  });

  it('never issues an array-contains + orderBy query', async () => {
    signIn('client1');

    await get(BASE, { token: tokenFor('client1') });

    const chatQueries = queries().filter((q) => q.collection === 'chats');
    assert.ok(chatQueries.length > 0);
    for (const query of chatQueries) {
      assert.equal(
        query.where.length > 0 && query.orderBy.length > 0,
        false,
        'composite index would be required',
      );
    }
  });

  it('scopes a non-admin list to their own conversations, even with ?userId=', async () => {
    signIn('client2');

    const res = await get(`${BASE}?userId=client-1`, { token: tokenFor('client2') });

    assert.equal(res.status, 200);
    assert.deepEqual(res.body.data.map((c) => c.id), ['chat-2', 'chat-3']);
  });

  it('lets an admin read any conversation with its messages', async () => {
    signIn('admin1');

    const res = await get(`${BASE}/chat-1`, { token: tokenFor('admin1') });

    assert.equal(res.status, 200);
    assert.equal(res.body.data.messages.length, 1);
  });

  it('denies a non-participant reading a conversation', async () => {
    signIn('client1');

    const res = await get(`${BASE}/chat-2`, { token: tokenFor('client1') });

    assert.equal(res.status, 403);
  });
});
