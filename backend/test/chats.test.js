/**
 * Regression tests for the current Supabase-backed GET /api/chats contract.
 *
 * The shared harness installs fixture-backed Auth, public-read, and RPC seams
 * while leaving the real routes, authorization middleware, and error handler in
 * place. No hosted Firebase or Supabase project is contacted.
 */

import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';

import {
  get,
  queries,
  reset,
  setFailure,
  signIn,
  startApp,
  stopApp,
  tokenFor,
  users,
} from './helpers/harness.js';

const BASE = '/api/chats';

before(startApp);
after(stopApp);

const at = (millis) => ({ toMillis: () => millis });

function seed() {
  return {
    users: users('admin1', 'client1', 'client2'),
    chats: [
      {
        id: 'chat-1',
        participants: ['client-1', 'lawyer-1'],
        participantNames: { 'client-1': 'Client One', 'lawyer-1': 'Lawyer One' },
        lastMessage: 'oldest',
        updatedAt: at(1_000),
      },
      {
        id: 'chat-2',
        participants: ['client-2', 'lawyer-2'],
        participantNames: { 'client-2': 'Client Two', 'lawyer-2': 'Lawyer Two' },
        lastMessage: 'newest',
        updatedAt: at(3_000),
      },
      {
        id: 'chat-3',
        participants: ['client-2', 'lawyer-1'],
        participantNames: { 'client-2': 'Client Two', 'lawyer-1': 'Lawyer One' },
        lastMessage: 'middle',
        updatedAt: at(2_000),
      },
      {
        // No updatedAt: the item must remain present and sort last.
        id: 'chat-4',
        participants: ['client-2', 'lawyer-3'],
        participantNames: {},
        lastMessage: 'no timestamp',
      },
    ],
  };
}

const chatQueries = () => queries().filter((query) => query.collection === 'chats');

describe('GET /api/chats: authentication is preserved', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('rejects a request without a bearer token before reading chats', async () => {
    const response = await get(BASE);

    assert.equal(response.status, 401);
    assert.equal(response.body.success, false);
    assert.match(response.body.message, /Missing Authorization header/);
    assert.equal(chatQueries().length, 0);
  });

  it('rejects an invalid token before reading chats', async () => {
    signIn('client1');
    const response = await get(BASE, { token: 'not-a-valid-test-token' });

    assert.equal(response.status, 401);
    assert.equal(response.body.success, false);
    assert.equal(chatQueries().length, 0);
  });
});

describe('GET /api/chats: administrator', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('lists every conversation newest first and retains records without timestamps', async () => {
    signIn('admin1');
    const response = await get(BASE, { token: tokenFor('admin1') });

    assert.equal(response.status, 200);
    assert.equal(response.body.success, true);
    assert.deepEqual(
      response.body.data.map((chat) => chat.id),
      ['chat-2', 'chat-3', 'chat-1', 'chat-4'],
    );
  });

  it('does not filter the administrator list by the administrator UID', async () => {
    signIn('admin1');
    await get(BASE, { token: tokenFor('admin1') });

    const [query] = chatQueries();
    assert.ok(query);
    assert.deepEqual(query.where, []);
  });

  it('allows an administrator to narrow the list by participant', async () => {
    signIn('admin1');
    const response = await get(`${BASE}?userId=client-1`, { token: tokenFor('admin1') });

    assert.equal(response.status, 200);
    assert.deepEqual(response.body.data.map((chat) => chat.id), ['chat-1']);
    assert.deepEqual(chatQueries()[0].where, [
      { field: 'participants', op: 'array-contains', value: 'client-1' },
    ]);
  });
});

describe('GET /api/chats: non-administrator', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('lists only conversations the caller participates in', async () => {
    signIn('client1');
    const response = await get(BASE, { token: tokenFor('client1') });

    assert.equal(response.status, 200);
    assert.deepEqual(response.body.data.map((chat) => chat.id), ['chat-1']);
    assert.deepEqual(chatQueries()[0].where, [
      { field: 'participants', op: 'array-contains', value: 'client-1' },
    ]);
  });

  it('ignores a caller-supplied userId that would expose another account', async () => {
    signIn('client1');
    const response = await get(`${BASE}?userId=client-2`, { token: tokenFor('client1') });

    assert.equal(response.status, 200);
    assert.deepEqual(response.body.data.map((chat) => chat.id), ['chat-1']);
    assert.deepEqual(chatQueries()[0].where, [
      { field: 'participants', op: 'array-contains', value: 'client-1' },
    ]);
  });
});

describe('GET /api/chats: query and error behavior', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('filters on the caller/selected participant and sorts in memory', async () => {
    for (const account of ['admin1', 'client1']) {
      reset({ collections: seed() });
      signIn(account);
      await get(BASE, { token: tokenFor(account) });

      for (const query of chatQueries()) {
        assert.equal(query.orderBy.length, 0, 'the adapter route sorts after the scoped read');
      }
    }
  });

  it('surfaces a database read failure as 500 instead of masking it', async () => {
    signIn('admin1');
    setFailure(new Error('Simulated PostgREST read failure'));
    const response = await get(BASE, { token: tokenFor('admin1') });

    assert.equal(response.status, 500);
    assert.equal(response.body.success, false);
    assert.match(response.body.message, /Simulated PostgREST read failure/);
  });
});
