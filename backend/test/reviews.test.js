/**
 * Wave 1.3 — reviews.
 *
 * Three findings are covered here:
 *   1. the public review endpoints exposed the author's Firebase uid;
 *   2. any authenticated account could post unlimited reviews for the same
 *      lawyer, moving its average at will;
 *   3. an admin update could rewrite the author of a review.
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

const BASE = '/api/reviews';

before(startApp);
after(stopApp);

function seed(overrides = {}) {
  return {
    users: users('client1', 'client2', 'lawyer1', 'admin1'),
    lawyers: [{ id: 'lawyer-1', name: 'Lawyer One', priceValue: 150 }],
    reviews: [],
    ...overrides,
  };
}

const reviewOf = (id) => docs('reviews').find((r) => r.id === id);

describe('reviews 1.3: author identifiers stay private', () => {
  beforeEach(() =>
    reset({
      collections: seed({
        reviews: [
          { id: 'rev-1', userId: 'client-1', userName: 'Client One', lawyerId: 'lawyer-1', rating: 5, comment: 'Great' },
        ],
      }),
    }),
  );

  it('does not return userId from the public list', async () => {
    const res = await get(BASE, {});

    assert.equal(res.status, 200);
    assert.equal(res.body.data.items.length, 1);
    assert.equal(res.body.data.items[0].userId, undefined);
    assert.equal(res.body.data.items[0].userName, 'Client One', 'the display name stays');
  });

  it('does not return userId from the public detail endpoint', async () => {
    const res = await get(`${BASE}/rev-1`, {});

    assert.equal(res.status, 200);
    assert.equal(res.body.data.userId, undefined);
    assert.equal(res.body.data.comment, 'Great');
  });

  it('still filters by userId when the client asks for it', async () => {
    const res = await get(`${BASE}?userId=client-2`, {});

    assert.equal(res.status, 200);
    assert.equal(res.body.data.items.length, 0);

    const own = await get(`${BASE}?userId=client-1`, {});
    assert.equal(own.body.data.items.length, 1);
    assert.equal(own.body.data.items[0].userId, undefined);
  });

  it('caps the page size at 100 no matter what the caller asks for', async () => {
    reset({
      collections: seed({
        reviews: Array.from({ length: 120 }, (_, i) => ({
          id: `rev-${i}`,
          userId: 'client-1',
          userName: 'Client One',
          lawyerId: 'lawyer-1',
          rating: 5,
          comment: `Review ${i}`,
        })),
      }),
    });

    const res = await get(`${BASE}?limit=10000`, {});

    assert.equal(res.status, 200);
    assert.equal(res.body.data.items.length, 100);
    assert.equal(res.body.data.total, 120);
  });
});

describe('reviews 1.3: one review per author and lawyer', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('rejects a second review by the same author for the same lawyer', async () => {
    signIn('client1');
    const body = { lawyerId: 'lawyer-1', rating: 5, comment: 'Excellent' };

    const first = await post(BASE, { token: tokenFor('client1'), body });
    const second = await post(BASE, { token: tokenFor('client1'), body: { ...body, rating: 1 } });

    assert.equal(first.status, 201);
    assert.equal(second.status, 409);
    assert.equal(docs('reviews').length, 1, 'no duplicate was written');
    assert.equal(docs('reviews')[0].rating, 5, 'the stored review is unchanged');
  });

  it('lets different authors review the same lawyer', async () => {
    const body = { lawyerId: 'lawyer-1', rating: 4, comment: 'Good' };

    signIn('client1');
    const a = await post(BASE, { token: tokenFor('client1'), body });
    signIn('client2');
    const b = await post(BASE, { token: tokenFor('client2'), body });

    assert.equal(a.status, 201);
    assert.equal(b.status, 201);
    assert.equal(docs('reviews').length, 2);
  });

  it('lets one author review two different lawyers', async () => {
    reset({
      collections: seed({
        lawyers: [
          { id: 'lawyer-1', name: 'Lawyer One', priceValue: 150 },
          { id: 'lawyer-2', name: 'Lawyer Two', priceValue: 120 },
        ],
      }),
    });
    signIn('client1');

    const a = await post(BASE, { token: tokenFor('client1'), body: { lawyerId: 'lawyer-1', rating: 5, comment: 'A' } });
    const b = await post(BASE, { token: tokenFor('client1'), body: { lawyerId: 'lawyer-2', rating: 4, comment: 'B' } });

    assert.equal(a.status, 201);
    assert.equal(b.status, 201);
    assert.equal(docs('reviews').length, 2);
  });

  it('rejects a review with no lawyer', async () => {
    signIn('client1');

    const missing = await post(BASE, {
      token: tokenFor('client1'),
      body: { rating: 5, comment: 'No target' },
    });
    const empty = await post(BASE, {
      token: tokenFor('client1'),
      body: { lawyerId: '', rating: 5, comment: 'No target' },
    });

    assert.equal(missing.status, 400);
    assert.equal(empty.status, 400);
    assert.equal(docs('reviews').length, 0);
  });

  it('keeps the author bound to the token even when the id matches an existing review', async () => {
    signIn('client1');
    await post(BASE, { token: tokenFor('client1'), body: { lawyerId: 'lawyer-1', rating: 5, comment: 'Mine' } });

    signIn('client2');
    const res = await post(BASE, {
      token: tokenFor('client2'),
      body: { lawyerId: 'lawyer-1', userId: 'client-1', userName: 'Client One', rating: 1, comment: 'Forged' },
    });

    assert.equal(res.status, 201, "client2's own review is a separate record");
    assert.equal(res.body.data.userId, 'client-2');
    assert.equal(docs('reviews').filter((r) => r.userId === 'client-2').length, 1);
    const mine = docs('reviews').find((r) => r.userId === 'client-1');
    assert.equal(mine.comment, 'Mine', 'the first review was not overwritten');
  });
});

describe('reviews 1.3: moderation cannot rewrite authorship', () => {
  beforeEach(() =>
    reset({
      collections: seed({
        reviews: [
          { id: 'rev-1', userId: 'client-1', userName: 'Client One', lawyerId: 'lawyer-1', rating: 5, comment: 'Great' },
        ],
      }),
    }),
  );

  it('ignores userId/userName on an admin update', async () => {
    signIn('admin1');

    const res = await put(`${BASE}/rev-1`, {
      token: tokenFor('admin1'),
      body: { rating: 2, comment: 'Edited', userId: 'client-2', userName: 'Somebody Else' },
    });

    assert.equal(res.status, 200);
    const stored = reviewOf('rev-1');
    assert.equal(stored.userId, 'client-1');
    assert.equal(stored.userName, 'Client One');
    assert.equal(stored.rating, 2);
    assert.equal(stored.comment, 'Edited');
  });

  it('still denies moderation to ordinary users', async () => {
    signIn('client1');

    const res = await put(`${BASE}/rev-1`, {
      token: tokenFor('client1'),
      body: { rating: 1 },
    });

    assert.equal(res.status, 403);
    assert.equal(reviewOf('rev-1').rating, 5);
  });

  it('still lets an admin delete a review', async () => {
    signIn('admin1');

    const res = await del(`${BASE}/rev-1`, { token: tokenFor('admin1') });

    assert.equal(res.status, 200);
    assert.equal(reviewOf('rev-1'), undefined);
  });
});
