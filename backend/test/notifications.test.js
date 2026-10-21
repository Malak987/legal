/**
 * Authorization regression tests for the notifications routes.
 *
 * `GET /api/notifications` returned EVERY user's notifications to any
 * authenticated caller, and `PUT /:id/read`, `PUT /:id` and `DELETE /:id`
 * accepted any notification id — so one account could read, rewrite or delete
 * another account's notifications.
 */

import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  del,
  docs,
  get,
  post,
  put,
  reset,
  signIn,
  startApp,
  stopApp,
  tokenFor,
  users,
} from './helpers/harness.js';

const BASE = '/api/notifications';

before(startApp);
after(stopApp);

function seed() {
  return {
    users: users('client1', 'client2', 'admin1'),
    notifications: [
      { id: 'n-1', userId: 'client-1', title: 'Your case moved', content: 'a', read: false },
      { id: 'n-2', userId: 'client-1', title: 'Invoice due', content: 'b', read: false },
      { id: 'n-3', userId: 'client-2', title: 'Hearing date', content: 'c', read: false },
    ],
  };
}

describe('notifications: listing', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('denies a non-admin listing every notification', async () => {
    signIn('client1');

    const res = await get(BASE, { token: tokenFor('client1') });

    assert.equal(res.status, 403);
    assert.equal(res.body.success, false);
    assert.equal(res.body.data, undefined);
  });

  it('lets an admin list every notification', async () => {
    signIn('admin1');

    const res = await get(BASE, { token: tokenFor('admin1') });

    assert.equal(res.status, 200);
    const ids = res.body.data.items.map((n) => n.id).sort();
    assert.deepEqual(ids, ['n-1', 'n-2', 'n-3']);
  });

  it('lets a user list their own notifications', async () => {
    signIn('client1');

    const res = await get(`${BASE}/client-1`, { token: tokenFor('client1') });

    assert.equal(res.status, 200);
    assert.equal(res.body.data.items.length, 2);
    for (const n of res.body.data.items) assert.equal(n.userId, 'client-1');
  });

  it('denies a user listing another user\'s notifications', async () => {
    signIn('client1');

    const res = await get(`${BASE}/client-2`, { token: tokenFor('client1') });

    assert.equal(res.status, 403);
  });
});

describe('notifications: ownership on mutation', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('denies marking another user\'s notification as read', async () => {
    signIn('client2');

    const res = await put(`${BASE}/n-1/read`, {
      token: tokenFor('client2'),
      body: { read: true },
    });

    assert.equal(res.status, 403);
    assert.equal(docs('notifications').find((n) => n.id === 'n-1').read, false);
  });

  it('lets the owner mark their notification as read', async () => {
    signIn('client1');

    const res = await put(`${BASE}/n-1/read`, {
      token: tokenFor('client1'),
      body: { read: true },
    });

    assert.equal(res.status, 200);
    assert.equal(res.body.data.read, true);
    assert.equal(docs('notifications').find((n) => n.id === 'n-1').read, true);
  });

  it('denies editing another user\'s notification', async () => {
    signIn('client2');

    const res = await put(`${BASE}/n-2`, {
      token: tokenFor('client2'),
      body: { title: 'Overwritten' },
    });

    assert.equal(res.status, 403);
    assert.equal(docs('notifications').find((n) => n.id === 'n-2').title, 'Invoice due');
  });

  it('does not let the owner transfer a notification to another user', async () => {
    signIn('client1');

    const res = await put(`${BASE}/n-2`, {
      token: tokenFor('client1'),
      body: { title: 'Invoice due', userId: 'client-2' },
    });

    assert.equal(res.status, 200);
    assert.equal(res.body.data.userId, 'client-1');
    assert.equal(docs('notifications').find((n) => n.id === 'n-2').userId, 'client-1');
  });

  it('denies deleting another user\'s notification', async () => {
    signIn('client2');

    const res = await del(`${BASE}/n-1`, { token: tokenFor('client2') });

    assert.equal(res.status, 403);
    assert.ok(docs('notifications').some((n) => n.id === 'n-1'));
  });

  it('lets the owner delete their notification', async () => {
    signIn('client1');

    const res = await del(`${BASE}/n-1`, { token: tokenFor('client1') });

    assert.equal(res.status, 200);
    assert.equal(docs('notifications').some((n) => n.id === 'n-1'), false);
  });

  it('lets an admin delete any notification', async () => {
    signIn('admin1');

    const res = await del(`${BASE}/n-3`, { token: tokenFor('admin1') });

    assert.equal(res.status, 200);
    assert.equal(docs('notifications').some((n) => n.id === 'n-3'), false);
  });

  it('answers 404 consistently for a missing notification', async () => {
    signIn('client1');

    const read = await put(`${BASE}/ghost/read`, { token: tokenFor('client1'), body: {} });
    const edit = await put(`${BASE}/ghost`, { token: tokenFor('client1'), body: { title: 'x' } });
    const remove = await del(`${BASE}/ghost`, { token: tokenFor('client1') });

    assert.equal(read.status, 404);
    assert.equal(edit.status, 404);
    assert.equal(remove.status, 404);
    assert.equal(read.body.success, false);
    assert.equal(edit.body.success, false);
    assert.equal(remove.body.success, false);
  });
});

describe('notifications: creation', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('denies a non-admin creating a notification', async () => {
    signIn('client1');

    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: { userId: 'client-2', title: 'Spam', content: 'buy now' },
    });

    assert.equal(res.status, 403);
    assert.equal(docs('notifications').length, 3);
    assert.equal(docs('notifications').some((n) => n.title === 'Spam'), false);
  });

  it('lets an admin create a notification for a user', async () => {
    signIn('admin1');

    const res = await post(BASE, {
      token: tokenFor('admin1'),
      body: { userId: 'client-2', title: 'Reminder', content: 'hearing tomorrow' },
    });

    assert.equal(res.status, 201);
    assert.equal(res.body.data.userId, 'client-2');
    assert.equal(docs('notifications').some((n) => n.title === 'Reminder'), true);
  });

  it('rejects an unauthenticated caller', async () => {
    const res = await post(BASE, { body: { userId: 'client-1', title: 'x' } });

    assert.equal(res.status, 401);
    assert.equal(docs('notifications').length, 3);
  });
});
