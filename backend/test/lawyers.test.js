/**
 * Authorization regression tests for the lawyer-profile routes (Wave 1.1).
 *
 * The independent review proved that any lawyer could rewrite ANY lawyer
 * document — `PUT /api/lawyers/:id` was guarded by `requireRole('admin',
 * 'lawyer')` with no ownership check at all, so a lawyer could raise their own
 * `rating`/`isTop`/`isPopular`, or sabotage a colleague's profile.
 *
 * A lawyer document has no `uid`/`userId` field (`seed.js` creates them with
 * auto-generated ids), so there is no reliable link between an account and a
 * profile and no ownership test to write. Mutations are therefore admin-only
 * until such a link is designed. Reads stay public, as before.
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

const BASE = '/api/lawyers';

before(startApp);
after(stopApp);

function seed() {
  return {
    users: users('client1', 'lawyer1', 'lawyer2', 'admin1'),
    legalCategories: [
      { id: 'category-criminal', name: 'Criminal Law', slug: 'criminal-law' },
    ],
    lawyers: [
      { id: 'law-A', name: 'Lawyer A', specialty: 'Tax', rating: 3, isTop: false, isPopular: false },
      { id: 'law-B', name: 'Lawyer B', specialty: 'Family', rating: 4, isTop: false, isPopular: false },
    ],
  };
}

const lawyerDoc = (id) => docs('lawyers').find((l) => l.id === id);

describe('lawyers 1.1: a lawyer cannot touch another profile', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('denies editing another lawyer\'s document and changes nothing', async () => {
    signIn('lawyer1');
    const before = lawyerDoc('law-B');

    const res = await put(`${BASE}/law-B`, {
      token: tokenFor('lawyer1'),
      body: { name: 'Hijacked', specialty: 'Anything' },
    });

    assert.equal(res.status, 403);
    assert.equal(res.body.success, false);
    assert.deepEqual(lawyerDoc('law-B'), before);
  });

  it('denies deleting another lawyer\'s document', async () => {
    signIn('lawyer1');

    const res = await del(`${BASE}/law-B`, { token: tokenFor('lawyer1') });

    assert.equal(res.status, 403);
    assert.ok(lawyerDoc('law-B'));
  });
});

describe('lawyers 1.1: trusted fields are not lawyer-writable', () => {
  beforeEach(() => reset({ collections: seed() }));

  for (const field of ['rating', 'isTop', 'isPopular']) {
    it(`denies a lawyer raising ${field}`, async () => {
      signIn('lawyer1');
      const before = lawyerDoc('law-A');

      const res = await put(`${BASE}/law-A`, {
        token: tokenFor('lawyer1'),
        body: { [field]: field === 'rating' ? 5 : true },
      });

      assert.equal(res.status, 403);
      assert.deepEqual(lawyerDoc('law-A'), before, `${field} must be unchanged`);
    });
  }

  it('denies a lawyer rewriting every trusted field at once', async () => {
    signIn('lawyer1');
    const before = lawyerDoc('law-B');

    const res = await put(`${BASE}/law-B`, {
      token: tokenFor('lawyer1'),
      body: { rating: 5, isTop: true, isPopular: true },
    });

    assert.equal(res.status, 403);
    assert.deepEqual(lawyerDoc('law-B'), before);
  });
});

describe('lawyers 1.1: bypass attempts', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('rejects a lawyer using their own uid as the document id', async () => {
    signIn('lawyer1');

    const res = await put(`${BASE}/lawyer-1`, {
      token: tokenFor('lawyer1'),
      body: { name: 'Self promoted', rating: 5, isTop: true },
    });

    // Authorisation is decided before the document is even looked up, so the
    // answer does not depend on whether that id exists.
    assert.equal(res.status, 403);
    assert.equal(docs('lawyers').length, 2);
  });

  it('rejects hidden extra fields even when the visible ones are harmless', async () => {
    signIn('lawyer1');
    const before = lawyerDoc('law-A');

    const res = await put(`${BASE}/law-A`, {
      token: tokenFor('lawyer1'),
      body: { name: 'Lawyer A', isTop: true, isPopular: true, rating: 5 },
    });

    assert.equal(res.status, 403);
    assert.deepEqual(lawyerDoc('law-A'), before);
  });

  it('rejects a lawyer creating a new profile', async () => {
    signIn('lawyer1');

    const res = await post(BASE, {
      token: tokenFor('lawyer1'),
      body: { name: 'Ghost Lawyer', rating: 5, isTop: true },
    });

    assert.equal(res.status, 403);
    assert.equal(docs('lawyers').length, 2);
  });
});

describe('lawyers 1.1: unauthorized roles', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('denies a client creating a lawyer', async () => {
    signIn('client1');

    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: { name: 'Fake Lawyer' },
    });

    assert.equal(res.status, 403);
    assert.equal(docs('lawyers').length, 2);
  });

  it('denies a client deleting a lawyer', async () => {
    signIn('client1');

    const res = await del(`${BASE}/law-A`, { token: tokenFor('client1') });

    assert.equal(res.status, 403);
    assert.ok(lawyerDoc('law-A'));
  });

  it('denies an unauthenticated create or delete', async () => {
    const created = await post(BASE, { body: { name: 'Anonymous' } });
    const removed = await del(`${BASE}/law-A`);

    assert.equal(created.status, 401);
    assert.equal(removed.status, 401);
    assert.equal(docs('lawyers').length, 2);
  });
});

describe('lawyers 1.1: administrative operations still work', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('lets an admin edit a lawyer profile', async () => {
    signIn('admin1');

    const res = await put(`${BASE}/law-A`, {
      token: tokenFor('admin1'),
      body: { name: 'Lawyer A (verified)', specialty: 'Corporate', rating: 5, isTop: true },
    });

    assert.equal(res.status, 200);
    assert.equal(res.body.data.name, 'Lawyer A (verified)');
    assert.equal(res.body.data.rating, 5);
    assert.equal(res.body.data.isTop, true);
    assert.equal(lawyerDoc('law-A').specialty, 'Corporate');
  });

  it('lets an admin create a lawyer', async () => {
    signIn('admin1');

    const res = await post(BASE, {
      token: tokenFor('admin1'),
      body: { name: 'Lawyer C', categoryId: 'category-criminal' },
    });

    assert.equal(res.status, 201);
    assert.equal(docs('lawyers').length, 3);
  });

  it('lets an admin delete a lawyer', async () => {
    signIn('admin1');

    const res = await del(`${BASE}/law-B`, { token: tokenFor('admin1') });

    assert.equal(res.status, 200);
    assert.equal(lawyerDoc('law-B'), undefined);
  });

  it('answers 404 for an admin updating a missing lawyer', async () => {
    signIn('admin1');

    const res = await put(`${BASE}/ghost`, {
      token: tokenFor('admin1'),
      body: { name: 'Nobody' },
    });

    assert.equal(res.status, 404);
  });
});

describe('lawyers 1.1: reads are unchanged', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('serves the public list without a token', async () => {
    const res = await get(BASE);

    assert.equal(res.status, 200);
    assert.equal(res.body.data.items.length, 2);
  });

  it('serves a single public profile without a token', async () => {
    const res = await get(`${BASE}/law-A`);

    assert.equal(res.status, 200);
    assert.equal(res.body.data.id, 'law-A');
  });
});
