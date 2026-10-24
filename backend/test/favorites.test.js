/**
 * Authorization regression tests for the favorites routes.
 *
 * `POST /api/favorites` took `userId` straight from the request body, so a
 * caller could add favourites to somebody else's list, and `DELETE /:id`
 * deleted by id with no ownership check.
 */

import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  del,
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

const BASE = '/api/favorites';

before(startApp);
after(stopApp);

function seed() {
  return {
    users: users('client1', 'client2', 'admin1'),
    lawyers: [
      { id: 'lawyer-1', name: 'Lawyer One', priceValue: 100 },
      { id: 'lawyer-2', name: 'Lawyer Two', priceValue: 120 },
      { id: 'lawyer-9', name: 'Lawyer Nine', priceValue: 150 },
    ],
    favorites: [
      { id: 'f-1', userId: 'client-1', lawyerId: 'lawyer-1' },
      { id: 'f-2', userId: 'client-2', lawyerId: 'lawyer-2' },
    ],
  };
}

describe('favorites: creation is bound to the caller', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('ignores a forged userId and stores the authenticated owner', async () => {
    signIn('client1');

    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: { userId: 'client-2', lawyerId: 'lawyer-9' },
    });

    assert.equal(res.status, 201);
    assert.equal(res.body.data.userId, 'client-1');

    const stored = docs('favorites').filter((f) => f.lawyerId === 'lawyer-9');
    assert.equal(stored.length, 1);
    assert.equal(stored[0].userId, 'client-1');
    // Nothing was written under the spoofed owner.
    assert.equal(docs('favorites').filter((f) => f.userId === 'client-2').length, 1);
  });

  it('returns the existing row instead of duplicating it', async () => {
    signIn('client1');

    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: { lawyerId: 'lawyer-1' },
    });

    assert.equal(res.status, 200);
    assert.equal(res.body.data.id, 'f-1');
    assert.equal(docs('favorites').filter((f) => f.lawyerId === 'lawyer-1').length, 1);
  });

  it('rejects a request without lawyerId', async () => {
    signIn('client1');

    const res = await post(BASE, { token: tokenFor('client1'), body: { userId: 'client-1' } });

    assert.equal(res.status, 400);
    assert.equal(docs('favorites').length, 2);
  });

  it('rejects an unauthenticated caller', async () => {
    const res = await post(BASE, { body: { lawyerId: 'lawyer-3' } });

    assert.equal(res.status, 401);
    assert.equal(docs('favorites').length, 2);
  });
});

describe('favorites: reads', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('lets a user list their own favorites', async () => {
    signIn('client1');

    const res = await get(`${BASE}/client-1`, { token: tokenFor('client1') });

    assert.equal(res.status, 200);
    assert.equal(res.body.data.length, 1);
    assert.equal(res.body.data[0].id, 'f-1');
  });

  it('denies listing another user\'s favorites', async () => {
    signIn('client1');

    const res = await get(`${BASE}/client-2`, { token: tokenFor('client1') });

    assert.equal(res.status, 403);
    assert.equal(res.body.success, false);
  });

  it('lets an admin list any user\'s favorites', async () => {
    signIn('admin1');

    const res = await get(`${BASE}/client-2`, { token: tokenFor('admin1') });

    assert.equal(res.status, 200);
    assert.equal(res.body.data[0].id, 'f-2');
  });
});

describe('favorites: deletion', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('denies deleting another user\'s favorite and keeps the row', async () => {
    signIn('client1');

    const res = await del(`${BASE}/f-2`, { token: tokenFor('client1') });

    assert.equal(res.status, 403);
    assert.ok(docs('favorites').some((f) => f.id === 'f-2'));
  });

  it('lets the owner delete their favorite', async () => {
    signIn('client1');

    const res = await del(`${BASE}/f-1`, { token: tokenFor('client1') });

    assert.equal(res.status, 200);
    assert.equal(docs('favorites').some((f) => f.id === 'f-1'), false);
  });

  it('answers 404 for a missing favorite', async () => {
    signIn('client1');

    const res = await del(`${BASE}/ghost`, { token: tokenFor('client1') });

    assert.equal(res.status, 404);
    assert.equal(res.body.success, false);
  });

  it('denies a favorite without an owner to non-admins', async () => {
    reset({
      collections: {
        users: users('client1'),
        favorites: [{ id: 'f-orphan', lawyerId: 'lawyer-1' }],
      },
    });
    signIn('client1');

    const res = await del(`${BASE}/f-orphan`, { token: tokenFor('client1') });

    assert.equal(res.status, 403);
    assert.ok(docs('favorites').some((f) => f.id === 'f-orphan'));
  });
});
