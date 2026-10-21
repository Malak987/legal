/**
 * Authorization regression tests for the resources that used to resolve their
 * owner as `req.body.userId || req.user.uid`.
 *
 * That expression let a client attribute a brand-new record to somebody else,
 * and the matching list routes scoped `?userId=` only when it was absent, so
 * passing another user's id returned that user's records.
 *
 * Every "denied" assertion also checks the store, because a rejected request
 * must not change data.
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

before(startApp);
after(stopApp);

const OWNED = [
  {
    path: 'cases',
    body: { title: 'Contract review' },
    // `title` stays required on this route — pre-existing contract.
    patch: { title: 'Renamed case', status: 'Closed' },
    expect: { title: 'Renamed case', status: 'Closed' },
    records: [
      { id: 'rec-a', userId: 'client-1', title: 'A case' },
      { id: 'rec-b', userId: 'client-2', title: 'B case' },
      { id: 'rec-orphan', title: 'Ownerless case' },
    ],
  },
  {
    path: 'bookings',
    // WAVE 1.2: the price is derived server-side from the lawyer's rate, so a
    // booking needs a real lawyer document and a billable number of hours.
    body: { lawyerId: 'lawyer-1', date: '2026-11-01', time: '10:00', hours: 2 },
    extra: { lawyers: [{ id: 'lawyer-1', name: 'Lawyer One', priceValue: 150 }] },
    patch: { status: 'Cancelled' },
    expect: { status: 'Cancelled' },
    records: [
      { id: 'rec-a', userId: 'client-1', status: 'Pending' },
      { id: 'rec-b', userId: 'client-2', status: 'Pending' },
      { id: 'rec-orphan', status: 'Pending' },
    ],
  },
  {
    path: 'tasks',
    body: { title: 'Prepare memo' },
    // `title` stays required on this route — pre-existing contract.
    patch: { title: 'Updated memo', status: 'Done' },
    expect: { title: 'Updated memo', status: 'Done' },
    records: [
      { id: 'rec-a', userId: 'client-1', status: 'To Do' },
      { id: 'rec-b', userId: 'client-2', status: 'To Do' },
      { id: 'rec-orphan', status: 'To Do' },
    ],
  },
  {
    path: 'subscriptions',
    // WAVE 1.2: the plan title is read from the catalogue, so the plan must
    // exist. The created record starts as `Pending`, and cancelling is the one
    // transition a non-admin is allowed to make.
    body: { planId: 'plan-1' },
    extra: { plans: [{ id: 'plan-1', title: 'Basic', priceValue: 10 }] },
    patch: { status: 'Cancelled' },
    expect: { status: 'Cancelled' },
    records: [
      // WAVE 1.3: `rec-a` is Pending (an unactivated request) because an owner
      // may no longer hard-delete an ACTIVE subscription — see
      // subscriptions.test.js. The ownership assertions are unchanged.
      { id: 'rec-a', userId: 'client-1', status: 'Pending' },
      { id: 'rec-b', userId: 'client-2', status: 'Active' },
      { id: 'rec-orphan', status: 'Active' },
    ],
  },
];

for (const resource of OWNED) {
  const { path, body, patch, expect: expected, records, extra = {} } = resource;
  const BASE = `/api/${path}`;

  describe(`${path}: creation`, () => {
    beforeEach(() =>
      reset({
        collections: {
          users: users('client1', 'client2', 'admin1'),
          ...extra,
          [path]: records,
        },
      }),
    );

    it('binds a new record to the caller and ignores a forged userId', async () => {
      signIn('client1');

      const res = await post(BASE, {
        token: tokenFor('client1'),
        body: { ...body, userId: 'client-2' },
      });

      assert.equal(res.status, 201);
      assert.equal(res.body.data.userId, 'client-1');

      const stored = docs(path).filter((d) => d.id === res.body.data.id);
      assert.equal(stored.length, 1);
      assert.equal(stored[0].userId, 'client-1');
      // The spoofed owner gained nothing.
      assert.equal(docs(path).filter((d) => d.userId === 'client-2').length, 1);
    });

    it('lets an admin create a record for another user', async () => {
      signIn('admin1');

      const res = await post(BASE, {
        token: tokenFor('admin1'),
        body: { ...body, userId: 'client-2' },
      });

      assert.equal(res.status, 201);
      assert.equal(res.body.data.userId, 'client-2');
    });

    it('rejects an unauthenticated create', async () => {
      const res = await post(BASE, { body });

      assert.equal(res.status, 401);
      assert.equal(docs(path).length, records.length);
    });
  });

  describe(`${path}: reads`, () => {
    beforeEach(() =>
      reset({
        collections: {
          users: users('client1', 'client2', 'admin1'),
          ...extra,
          [path]: records,
        },
      }),
    );

    it('lets an owner read their record', async () => {
      signIn('client1');

      const res = await get(`${BASE}/rec-a`, { token: tokenFor('client1') });

      assert.equal(res.status, 200);
      assert.equal(res.body.data.id, 'rec-a');
    });

    it('denies reading another user\'s record', async () => {
      signIn('client1');

      const res = await get(`${BASE}/rec-b`, { token: tokenFor('client1') });

      assert.equal(res.status, 403);
      assert.equal(res.body.success, false);
    });

    it('denies an ownerless record to a non-admin', async () => {
      signIn('client1');

      const res = await get(`${BASE}/rec-orphan`, { token: tokenFor('client1') });

      assert.equal(res.status, 403);
    });

    it('lets an admin read any record', async () => {
      signIn('admin1');

      const res = await get(`${BASE}/rec-b`, { token: tokenFor('admin1') });

      assert.equal(res.status, 200);
      assert.equal(res.body.data.id, 'rec-b');
    });

    it('scopes the list to the caller even when ?userId= points elsewhere', async () => {
      signIn('client1');

      const res = await get(`${BASE}?userId=client-2`, { token: tokenFor('client1') });

      assert.equal(res.status, 200);
      assert.deepEqual(res.body.data.items.map((d) => d.id), ['rec-a']);
    });

    it('lets an admin filter the list by user', async () => {
      signIn('admin1');

      const res = await get(`${BASE}?userId=client-2`, { token: tokenFor('admin1') });

      assert.equal(res.status, 200);
      assert.deepEqual(res.body.data.items.map((d) => d.id), ['rec-b']);
    });
  });

  describe(`${path}: mutation`, () => {
    beforeEach(() =>
      reset({
        collections: {
          users: users('client1', 'client2', 'admin1'),
          ...extra,
          [path]: records,
        },
      }),
    );

    it('lets the owner update their record', async () => {
      signIn('client1');

      const res = await put(`${BASE}/rec-a`, {
        token: tokenFor('client1'),
        body: patch,
      });

      assert.equal(res.status, 200);
      assert.deepEqual(
        Object.fromEntries(Object.keys(expected).map((k) => [k, res.body.data[k]])),
        expected,
      );
    });

    it('denies updating another user\'s record and changes nothing', async () => {
      signIn('client1');
      const before = docs(path).find((d) => d.id === 'rec-b');

      const res = await put(`${BASE}/rec-b`, {
        token: tokenFor('client1'),
        body: patch,
      });

      assert.equal(res.status, 403);
      assert.deepEqual(docs(path).find((d) => d.id === 'rec-b'), before);
    });

    it('does not let an owner hand their record to another account', async () => {
      signIn('client1');

      const res = await put(`${BASE}/rec-a`, {
        token: tokenFor('client1'),
        body: { ...patch, userId: 'client-2' },
      });

      assert.equal(res.status, 200);
      assert.equal(res.body.data.userId, 'client-1');
      assert.equal(docs(path).find((d) => d.id === 'rec-a').userId, 'client-1');
    });

    it('lets an admin reassign a record through the update body', async () => {
      signIn('admin1');

      const res = await put(`${BASE}/rec-a`, {
        token: tokenFor('admin1'),
        body: { ...patch, userId: 'client-2' },
      });

      assert.equal(res.status, 200);
      assert.equal(res.body.data.userId, 'client-2');
    });

    it('denies deleting another user\'s record and keeps it', async () => {
      signIn('client1');

      const res = await del(`${BASE}/rec-b`, { token: tokenFor('client1') });

      assert.equal(res.status, 403);
      assert.ok(docs(path).some((d) => d.id === 'rec-b'));
    });

    it('denies mutating an ownerless record', async () => {
      signIn('client1');

      const update = await put(`${BASE}/rec-orphan`, {
        token: tokenFor('client1'),
        body: patch,
      });
      const remove = await del(`${BASE}/rec-orphan`, { token: tokenFor('client1') });

      assert.equal(update.status, 403);
      assert.equal(remove.status, 403);
      assert.ok(docs(path).some((d) => d.id === 'rec-orphan'));
    });

    it('lets the owner delete their record', async () => {
      signIn('client1');

      const res = await del(`${BASE}/rec-a`, { token: tokenFor('client1') });

      assert.equal(res.status, 200);
      assert.equal(docs(path).some((d) => d.id === 'rec-a'), false);
    });

    it('lets an admin update and delete any record', async () => {
      signIn('admin1');

      const update = await put(`${BASE}/rec-b`, {
        token: tokenFor('admin1'),
        body: patch,
      });
      assert.equal(update.status, 200);

      const remove = await del(`${BASE}/rec-orphan`, { token: tokenFor('admin1') });
      assert.equal(remove.status, 200);
      assert.equal(docs(path).some((d) => d.id === 'rec-orphan'), false);
    });

    it('answers 404 for a missing record', async () => {
      signIn('client1');

      const res = await get(`${BASE}/ghost`, { token: tokenFor('client1') });

      assert.equal(res.status, 404);
    });
  });
}

describe('reviews: author is taken from the token', () => {
  beforeEach(() =>
    reset({
      collections: {
        users: users('client1', 'client2'),
        reviews: [{ id: 'rev-1', userId: 'client-2', userName: 'Client Two', rating: 5, comment: 'ok' }],
      },
    }),
  );

  it('ignores a forged userId on create', async () => {
    signIn('client1');

    const res = await post('/api/reviews', {
      token: tokenFor('client1'),
      body: { userId: 'client-2', userName: 'Client Two', lawyerId: 'lawyer-1', rating: 4, comment: 'good' },
    });

    assert.equal(res.status, 201);
    assert.equal(res.body.data.userId, 'client-1');
    assert.equal(res.body.data.userName, 'Client One');
    assert.equal(docs('reviews').filter((r) => r.userId === 'client-2').length, 1);
  });

  it('keeps review moderation admin-only', async () => {
    signIn('client1');

    const res = await del('/api/reviews/rev-1', { token: tokenFor('client1') });

    assert.equal(res.status, 403);
    assert.ok(docs('reviews').some((r) => r.id === 'rev-1'));
  });
});

describe('earnings: per-user reads', () => {
  beforeEach(() =>
    reset({
      collections: {
        users: users('client1', 'lawyer1', 'admin1'),
        earnings: [
          { id: 'lawyer-1', userId: 'lawyer-1', total: 1200 },
          { id: 'lawyer-2', userId: 'lawyer-2', total: 300 },
        ],
      },
    }),
  );

  it('lets a lawyer read their own earnings', async () => {
    signIn('lawyer1');

    const res = await get('/api/earnings/lawyer-1', { token: tokenFor('lawyer1') });

    assert.equal(res.status, 200);
    assert.equal(res.body.data.total, 1200);
  });

  it('denies reading another lawyer\'s earnings', async () => {
    signIn('lawyer1');

    const res = await get('/api/earnings/lawyer-2', { token: tokenFor('lawyer1') });

    assert.equal(res.status, 403);
    assert.equal(res.body.success, false);
  });
});
