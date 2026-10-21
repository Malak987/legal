/**
 * Authorization regression tests for the availability routes.
 *
 * `POST`, `PUT` and `DELETE` only required a valid token: any client could
 * create slots, rewrite a lawyer's schedule, or delete another lawyer's
 * availability outright.
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

const BASE = '/api/availability';

before(startApp);
after(stopApp);

function seed() {
  return {
    users: users('client1', 'lawyer1', 'lawyer2', 'admin1'),
    availability: [
      { id: 'slot-1', lawyerId: 'lawyer-1', lawyerName: 'Lawyer One', date: '2026-11-02', slots: ['09:00'] },
      { id: 'slot-2', lawyerId: 'lawyer-2', lawyerName: 'Lawyer Two', date: '2026-11-03', slots: ['10:00'] },
    ],
  };
}

describe('availability: creation', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('denies a client creating availability', async () => {
    signIn('client1');

    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: { lawyerId: 'lawyer-1', date: '2026-12-01', slots: ['09:00'] },
    });

    assert.equal(res.status, 403);
    assert.equal(docs('availability').length, 2);
  });

  it('binds a lawyer-created slot to that lawyer, ignoring a forged lawyerId', async () => {
    signIn('lawyer1');

    const res = await post(BASE, {
      token: tokenFor('lawyer1'),
      body: { lawyerId: 'lawyer-2', lawyerName: 'Lawyer Two', date: '2026-12-01', slots: ['09:00'] },
    });

    assert.equal(res.status, 201);
    assert.equal(res.body.data.lawyerId, 'lawyer-1');

    const created = docs('availability').find((a) => a.id === res.body.data.id);
    assert.equal(created.lawyerId, 'lawyer-1');
    // lawyer-2's schedule is untouched.
    assert.deepEqual(
      docs('availability').filter((a) => a.lawyerId === 'lawyer-2').map((a) => a.id),
      ['slot-2'],
    );
  });

  it('lets a lawyer create their own slot', async () => {
    signIn('lawyer1');

    const res = await post(BASE, {
      token: tokenFor('lawyer1'),
      body: { lawyerId: 'lawyer-1', date: '2026-12-05', slots: ['08:00', '11:00'] },
    });

    assert.equal(res.status, 201);
    assert.equal(res.body.data.date, '2026-12-05');
    assert.equal(docs('availability').length, 3);
  });

  it('lets an admin create a slot for a lawyer', async () => {
    signIn('admin1');

    const res = await post(BASE, {
      token: tokenFor('admin1'),
      body: { lawyerId: 'lawyer-2', date: '2026-12-06', slots: ['12:00'] },
    });

    assert.equal(res.status, 201);
    assert.equal(res.body.data.lawyerId, 'lawyer-2');
  });

  it('rejects a slot without a date', async () => {
    signIn('lawyer1');

    const res = await post(BASE, {
      token: tokenFor('lawyer1'),
      body: { lawyerId: 'lawyer-1', slots: ['09:00'] },
    });

    assert.equal(res.status, 400);
    assert.equal(docs('availability').length, 2);
  });

  it('rejects an unauthenticated caller', async () => {
    const res = await post(BASE, { body: { lawyerId: 'lawyer-1', date: '2026-12-01' } });

    assert.equal(res.status, 401);
    assert.equal(docs('availability').length, 2);
  });
});

describe('availability: updates', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('denies a lawyer editing another lawyer\'s slot', async () => {
    signIn('lawyer1');

    const res = await put(`${BASE}/slot-2`, {
      token: tokenFor('lawyer1'),
      body: { slots: ['23:00'] },
    });

    assert.equal(res.status, 403);
    assert.deepEqual(docs('availability').find((a) => a.id === 'slot-2').slots, ['10:00']);
  });

  it('denies a client editing any slot', async () => {
    signIn('client1');

    const res = await put(`${BASE}/slot-1`, {
      token: tokenFor('client1'),
      body: { slots: ['00:00'] },
    });

    assert.equal(res.status, 403);
    assert.deepEqual(docs('availability').find((a) => a.id === 'slot-1').slots, ['09:00']);
  });

  it('lets a lawyer update their own slot', async () => {
    signIn('lawyer1');

    const res = await put(`${BASE}/slot-1`, {
      token: tokenFor('lawyer1'),
      body: { slots: ['14:00', '15:00'] },
    });

    assert.equal(res.status, 200);
    assert.deepEqual(res.body.data.slots, ['14:00', '15:00']);
  });

  it('does not let a lawyer reassign their slot to another lawyer', async () => {
    signIn('lawyer1');

    const res = await put(`${BASE}/slot-1`, {
      token: tokenFor('lawyer1'),
      body: { lawyerId: 'lawyer-2', slots: ['09:00'] },
    });

    assert.equal(res.status, 200);
    assert.equal(res.body.data.lawyerId, 'lawyer-1');
    assert.equal(docs('availability').find((a) => a.id === 'slot-1').lawyerId, 'lawyer-1');
  });

  it('lets an admin update any slot', async () => {
    signIn('admin1');

    const res = await put(`${BASE}/slot-2`, {
      token: tokenFor('admin1'),
      body: { slots: ['16:00'] },
    });

    assert.equal(res.status, 200);
    assert.deepEqual(docs('availability').find((a) => a.id === 'slot-2').slots, ['16:00']);
  });

  it('answers 404 for a missing slot', async () => {
    signIn('lawyer1');

    const res = await put(`${BASE}/ghost`, { token: tokenFor('lawyer1'), body: { slots: [] } });

    assert.equal(res.status, 404);
  });
});

describe('availability: deletion', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('denies a lawyer deleting another lawyer\'s slot', async () => {
    signIn('lawyer1');

    const res = await del(`${BASE}/slot-2`, { token: tokenFor('lawyer1') });

    assert.equal(res.status, 403);
    assert.ok(docs('availability').some((a) => a.id === 'slot-2'));
  });

  it('lets a lawyer delete their own slot', async () => {
    signIn('lawyer1');

    const res = await del(`${BASE}/slot-1`, { token: tokenFor('lawyer1') });

    assert.equal(res.status, 200);
    assert.equal(docs('availability').some((a) => a.id === 'slot-1'), false);
  });

  it('lets an admin delete any slot', async () => {
    signIn('admin1');

    const res = await del(`${BASE}/slot-2`, { token: tokenFor('admin1') });

    assert.equal(res.status, 200);
  });
});

describe('availability: public reads stay public', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('serves the availability list without a token', async () => {
    const res = await get(BASE);

    assert.equal(res.status, 200);
    assert.equal(res.body.data.items.length, 2);
  });

  it('serves a single slot without a token', async () => {
    const res = await get(`${BASE}/slot-1`);

    assert.equal(res.status, 200);
    assert.equal(res.body.data.lawyerId, 'lawyer-1');
  });
});
