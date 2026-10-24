/**
 * Business-logic regression tests for subscriptions (Wave 1.2, F-01 / F-09).
 *
 * These tests enforce the current safe contract:
 *   1. New subscriptions start Pending, and no client/admin request may mark
 *      one Active without a verified payment-provider workflow.
 *   2. Plan identity/title are catalog-derived and not writable through the
 *      current route; partial/empty updates cannot reset stored status.
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

const BASE = '/api/subscriptions';

before(startApp);
after(stopApp);

function seed(overrides = {}) {
  return {
    users: users('client1', 'client2', 'admin1'),
    plans: [
      { id: 'plan-basic', title: 'Basic', priceValue: 29 },
      { id: 'plan-pro', title: 'Pro', priceValue: 199 },
    ],
    subscriptions: [],
    ...overrides,
  };
}

const subOf = (id) => docs('subscriptions').find((s) => s.id === id);

describe('subscriptions 1.2: self-activation is impossible', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('creates a subscription in Pending, never Active', async () => {
    signIn('client1');

    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: { planId: 'plan-pro' },
    });

    assert.equal(res.status, 201);
    assert.equal(res.body.data.status, 'Pending');
    assert.equal(subOf(res.body.data.id).status, 'Pending');
  });

  it('rejects a client asking for paid activation without verified payment', async () => {
    signIn('client1');

    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: { planId: 'plan-pro', status: 'Active' },
    });

    assert.equal(res.status, 403);
    assert.match(res.body.message, /verified payment-provider workflow/);
    assert.equal(docs('subscriptions').length, 0);
  });

  it('takes the plan title from the catalogue, not the request', async () => {
    signIn('client1');

    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: { planId: 'plan-basic', planTitle: 'Pro (unlocked)' },
    });

    assert.equal(res.status, 201);
    assert.equal(subOf(res.body.data.id).planTitle, 'Basic');
  });

  it('rejects an unknown plan without writing anything', async () => {
    signIn('client1');

    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: { planId: 'plan-does-not-exist' },
    });

    assert.equal(res.status, 400);
    assert.equal(docs('subscriptions').length, 0);
  });

  it('does not let an administrator activate a paid plan without verified payment', async () => {
    signIn('admin1');

    const res = await post(BASE, {
      token: tokenFor('admin1'),
      body: { userId: 'client-2', planId: 'plan-pro', status: 'Active' },
    });

    assert.equal(res.status, 403);
    assert.match(res.body.message, /verified payment-provider workflow/);
    assert.equal(docs('subscriptions').length, 0);
  });
});

describe('subscriptions 1.2: status is not client-writable', () => {
  beforeEach(() =>
    reset({
      collections: seed({
        subscriptions: [
          { id: 'sub-expired', userId: 'client-1', planId: 'plan-basic', status: 'Expired' },
          { id: 'sub-active', userId: 'client-1', planId: 'plan-pro', status: 'Active' },
          { id: 'sub-pending', userId: 'client-1', planId: 'plan-basic', status: 'Pending' },
        ],
      }),
    }),
  );

  it('denies an expired subscription being reactivated by its owner', async () => {
    signIn('client1');

    const res = await put(`${BASE}/sub-expired`, {
      token: tokenFor('client1'),
      body: { status: 'Active' },
    });

    assert.equal(res.status, 403);
    assert.equal(subOf('sub-expired').status, 'Expired');
  });

  it('denies a pending subscription being activated by its owner', async () => {
    signIn('client1');

    const res = await put(`${BASE}/sub-pending`, {
      token: tokenFor('client1'),
      body: { status: 'Active' },
    });

    assert.equal(res.status, 403);
    assert.equal(subOf('sub-pending').status, 'Pending');
  });

  it('denies marking a subscription expired by its owner', async () => {
    signIn('client1');

    const res = await put(`${BASE}/sub-active`, {
      token: tokenFor('client1'),
      body: { status: 'Expired' },
    });

    assert.equal(res.status, 403);
    assert.equal(subOf('sub-active').status, 'Active');
  });

  it('lets the owner cancel an active subscription', async () => {
    signIn('client1');

    const res = await put(`${BASE}/sub-active`, {
      token: tokenFor('client1'),
      body: { status: 'Cancelled' },
    });

    assert.equal(res.status, 200);
    assert.equal(subOf('sub-active').status, 'Cancelled');
  });

  it('denies an owner moving a cancelled subscription anywhere', async () => {
    signIn('client1');
    await put(`${BASE}/sub-active`, {
      token: tokenFor('client1'),
      body: { status: 'Cancelled' },
    });

    const res = await put(`${BASE}/sub-active`, {
      token: tokenFor('client1'),
      body: { status: 'Active' },
    });

    assert.equal(res.status, 403);
    assert.equal(subOf('sub-active').status, 'Cancelled');
  });

  it('denies an owner switching to a cheaper plan', async () => {
    signIn('client1');

    const res = await put(`${BASE}/sub-active`, {
      token: tokenFor('client1'),
      body: { planId: 'plan-basic' },
    });

    assert.equal(res.status, 403);
    assert.equal(subOf('sub-active').planId, 'plan-pro');
  });

  it('denies unverified admin status changes and preserves the existing states', async () => {
    signIn('admin1');

    const activated = await put(`${BASE}/sub-expired`, {
      token: tokenFor('admin1'),
      body: { status: 'Active' },
    });
    assert.equal(activated.status, 403);
    assert.equal(subOf('sub-expired').status, 'Expired');

    const expired = await put(`${BASE}/sub-active`, {
      token: tokenFor('admin1'),
      body: { status: 'Expired' },
    });
    assert.equal(expired.status, 403);
    assert.equal(subOf('sub-active').status, 'Active');
  });
});

describe('subscriptions 1.2: partial updates keep untouched fields', () => {
  beforeEach(() =>
    reset({
      collections: seed({
        subscriptions: [
          { id: 'sub-expired', userId: 'client-1', planId: 'plan-basic', planTitle: 'Basic', status: 'Expired' },
        ],
      }),
    }),
  );

  it('rejects an admin plan-title edit and keeps the Expired state and derived title', async () => {
    signIn('admin1');

    const res = await put(`${BASE}/sub-expired`, {
      token: tokenFor('admin1'),
      body: { planTitle: 'Basic (renamed)' },
    });

    assert.equal(res.status, 403);
    assert.equal(subOf('sub-expired').planTitle, 'Basic');
    assert.equal(subOf('sub-expired').status, 'Expired');
  });

  it('does not write a default status when the body is empty (admin)', async () => {
    signIn('admin1');

    const res = await put(`${BASE}/sub-expired`, {
      token: tokenFor('admin1'),
      body: {},
    });

    assert.equal(res.status, 200);
    assert.equal(subOf('sub-expired').status, 'Expired');
    assert.equal(subOf('sub-expired').planId, 'plan-basic');
  });
});

describe('subscriptions 1.2: ownership and deletion', () => {
  beforeEach(() =>
    reset({
      collections: seed({
        subscriptions: [
          { id: 'sub-a', userId: 'client-1', planId: 'plan-basic', status: 'Pending' },
          { id: 'sub-b', userId: 'client-2', planId: 'plan-basic', status: 'Pending' },
        ],
      }),
    }),
  );

  it('denies updating another user\'s subscription', async () => {
    signIn('client1');

    const res = await put(`${BASE}/sub-b`, {
      token: tokenFor('client1'),
      body: { status: 'Cancelled' },
    });

    assert.equal(res.status, 403);
    assert.equal(subOf('sub-b').status, 'Pending');
  });

  it('denies deleting another user\'s subscription', async () => {
    signIn('client1');

    const res = await del(`${BASE}/sub-b`, { token: tokenFor('client1') });

    assert.equal(res.status, 403);
    assert.ok(subOf('sub-b'));
  });

  it('denies reading another user\'s subscription', async () => {
    signIn('client1');

    const res = await get(`${BASE}/sub-b`, { token: tokenFor('client1') });

    assert.equal(res.status, 403);
  });

  it('rejects transferring a subscription to another account', async () => {
    signIn('client1');

    const res = await put(`${BASE}/sub-a`, {
      token: tokenFor('client1'),
      body: { userId: 'client-2' },
    });

    assert.equal(res.status, 403);
    assert.equal(subOf('sub-a').userId, 'client-1');
  });
});

/* =====================================================================
 * WAVE 1.3 — plan integrity, deletion, and the admin workflow
 * ===================================================================*/

describe('subscriptions 1.3: the plan reference is the only source of a title', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('requires a catalog plan instead of creating from a client-supplied title', async () => {
    signIn('client1');

    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: { planTitle: 'Premium Plan (free)' },
    });

    assert.equal(res.status, 400);
    assert.match(res.body.message, /planId is required/);
    assert.equal(docs('subscriptions').length, 0);
  });

  it('rejects any client plan change without changing the stored plan', async () => {
    reset({
      collections: seed({
        subscriptions: [
          { id: 'sub-1', userId: 'client-1', planId: 'plan-basic', planTitle: 'Basic', status: 'Pending' },
        ],
      }),
    });
    signIn('admin1');

    const res = await put(`${BASE}/sub-1`, {
      token: tokenFor('admin1'),
      body: { planId: 'plan-does-not-exist' },
    });

    assert.equal(res.status, 403);
    const stored = subOf('sub-1');
    assert.equal(stored.planId, 'plan-basic');
    assert.equal(stored.planTitle, 'Basic');
    assert.equal(stored.status, 'Pending');
  });

  it('rejects an admin plan change until an approved billing workflow exists', async () => {
    reset({
      collections: seed({
        subscriptions: [
          { id: 'sub-1', userId: 'client-1', planId: 'plan-basic', planTitle: 'Basic', status: 'Pending' },
        ],
      }),
    });
    signIn('admin1');

    const res = await put(`${BASE}/sub-1`, {
      token: tokenFor('admin1'),
      body: { planId: 'plan-pro', planTitle: 'Basic (lying)' },
    });

    assert.equal(res.status, 403);
    assert.equal(subOf('sub-1').planId, 'plan-basic');
    assert.equal(subOf('sub-1').planTitle, 'Basic');
    assert.equal(subOf('sub-1').status, 'Pending', 'status is untouched');
  });

  it('rejects an empty planId instead of silently detaching the plan', async () => {
    reset({
      collections: seed({
        subscriptions: [
          { id: 'sub-1', userId: 'client-1', planId: 'plan-basic', planTitle: 'Basic', status: 'Pending' },
        ],
      }),
    });
    signIn('admin1');

    const res = await put(`${BASE}/sub-1`, {
      token: tokenFor('admin1'),
      body: { planId: '' },
    });

    assert.equal(res.status, 403);
    assert.equal(subOf('sub-1').planId, 'plan-basic');
  });
});

describe('subscriptions 1.3: an active subscription is financial history', () => {
  beforeEach(() =>
    reset({
      collections: seed({
        subscriptions: [
          { id: 'sub-pending', userId: 'client-1', planId: 'plan-basic', planTitle: 'Basic', status: 'Pending' },
          { id: 'sub-active', userId: 'client-1', planId: 'plan-pro', planTitle: 'Pro', status: 'Active' },
        ],
      }),
    }),
  );

  it('denies an owner deleting an active subscription', async () => {
    signIn('client1');

    const res = await del(`${BASE}/sub-active`, { token: tokenFor('client1') });

    assert.equal(res.status, 403);
    assert.ok(subOf('sub-active'), 'the record must survive');
  });

  it('still lets an owner delete an unactivated request', async () => {
    signIn('client1');

    const res = await del(`${BASE}/sub-pending`, { token: tokenFor('client1') });

    assert.equal(res.status, 200);
    assert.equal(subOf('sub-pending'), undefined);
  });

  it('lets an owner cancel an active subscription instead', async () => {
    signIn('client1');

    const res = await put(`${BASE}/sub-active`, {
      token: tokenFor('client1'),
      body: { status: 'Cancelled' },
    });

    assert.equal(res.status, 200);
    assert.equal(subOf('sub-active').status, 'Cancelled');
  });

  it('retains an active subscription even when an administrator requests deletion', async () => {
    signIn('admin1');

    const res = await del(`${BASE}/sub-active`, { token: tokenFor('admin1') });

    assert.equal(res.status, 403);
    assert.equal(subOf('sub-active').status, 'Active');
  });
});
