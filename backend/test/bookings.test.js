/**
 * Business-logic regression tests for bookings (Wave 1.2, F-02 / F-03 / F-09).
 *
 * The review proved:
 *   1. the client chose the price: `POST {hours: 12, totalPrice: 0}` was stored
 *      verbatim, so a booking cost whatever the client said;
 *   2. the client could set its own booking to `Completed`, skipping the
 *      service and (in a payment flow) releasing money;
 *   3. a partial `PUT` re-applied `status: 'Pending'` over the stored status.
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

const BASE = '/api/bookings';

before(startApp);
after(stopApp);

function seed(overrides = {}) {
  return {
    users: users('client1', 'client2', 'admin1'),
    lawyers: [
      { id: 'lawyer-150', name: 'Lawyer One', priceValue: 150 },
      { id: 'lawyer-free', name: 'Lawyer Unpriced' },
    ],
    bookings: [],
    ...overrides,
  };
}

const bookingOf = (id) => docs('bookings').find((b) => b.id === id);

describe('bookings 1.2: the price comes from the server', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('derives totalPrice from the lawyer rate and ignores the client price', async () => {
    signIn('client1');

    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: {
        lawyerId: 'lawyer-150',
        date: '2026-11-01',
        time: '10:00',
        hours: 3,
        totalPrice: 0,
      },
    });

    assert.equal(res.status, 201);
    assert.equal(res.body.data.totalPrice, 450, '3h x 150');
    assert.equal(bookingOf(res.body.data.id).totalPrice, 450);
  });

  it('ignores an inflated client price too', async () => {
    signIn('client1');

    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: {
        lawyerId: 'lawyer-150',
        date: '2026-11-01',
        time: '10:00',
        hours: 1,
        totalPrice: 999999,
      },
    });

    assert.equal(res.status, 201);
    assert.equal(bookingOf(res.body.data.id).totalPrice, 150);
  });

  it('keeps two-decimal arithmetic exact', async () => {
    reset({
      collections: seed({
        lawyers: [{ id: 'lawyer-99', name: 'Odd Rate', priceValue: 99.99 }],
      }),
    });
    signIn('client1');

    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: { lawyerId: 'lawyer-99', date: '2026-11-01', time: '09:00', hours: 3 },
    });

    assert.equal(res.status, 201);
    assert.equal(bookingOf(res.body.data.id).totalPrice, 299.97);
  });

  it('rejects a booking for an unknown lawyer', async () => {
    signIn('client1');

    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: { lawyerId: 'ghost', date: '2026-11-01', time: '10:00', hours: 1 },
    });

    assert.equal(res.status, 400);
    assert.equal(res.body.message, 'Lawyer not found');
    assert.equal(docs('bookings').length, 0);
  });

  it('rejects a lawyer with no configured rate instead of guessing', async () => {
    signIn('client1');

    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: { lawyerId: 'lawyer-free', date: '2026-11-01', time: '10:00', hours: 1 },
    });

    assert.equal(res.status, 400);
    assert.equal(res.body.message, 'Lawyer has no configured hourly rate');
    assert.equal(docs('bookings').length, 0);
  });

  it('requires a billable number of hours', async () => {
    signIn('client1');

    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: { lawyerId: 'lawyer-150', date: '2026-11-01', time: '10:00' },
    });

    assert.equal(res.status, 400);
    assert.equal(docs('bookings').length, 0);
  });

  it('rejects out-of-range hours', async () => {
    signIn('client1');

    for (const hours of [0, 13, 2.5]) {
      const res = await post(BASE, {
        token: tokenFor('client1'),
        body: { lawyerId: 'lawyer-150', date: '2026-11-01', time: '10:00', hours },
      });
      assert.equal(res.status, 400, `hours=${hours} must be rejected`);
    }
    assert.equal(docs('bookings').length, 0);
  });

  it('uses the lawyer name from the profile', async () => {
    signIn('client1');

    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: {
        lawyerId: 'lawyer-150',
        lawyerName: 'Impersonated QC',
        date: '2026-11-01',
        time: '10:00',
        hours: 1,
      },
    });

    assert.equal(res.status, 201);
    assert.equal(bookingOf(res.body.data.id).lawyerName, 'Lawyer One');
  });
});

describe('bookings 1.2: status transitions', () => {
  beforeEach(() =>
    reset({
      collections: seed({
        bookings: [
          {
            id: 'bk-pending', userId: 'client-1', status: 'Pending',
            lawyerId: 'lawyer-150', lawyerName: 'Lawyer One',
            date: '2026-11-01', time: '10:00', hours: 1, totalPrice: 150,
          },
          {
            id: 'bk-active', userId: 'client-1', status: 'Active',
            lawyerId: 'lawyer-150', lawyerName: 'Lawyer One',
            date: '2026-11-01', time: '11:00', hours: 1, totalPrice: 150,
          },
          {
            id: 'bk-done', userId: 'client-1', status: 'Completed',
            lawyerId: 'lawyer-150', lawyerName: 'Lawyer One',
            date: '2026-11-01', time: '12:00', hours: 1, totalPrice: 150,
          },
        ],
      }),
    }),
  );

  it('creates a booking as Pending even when the client asks for Completed', async () => {
    signIn('client1');

    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: {
        lawyerId: 'lawyer-150',
        date: '2026-11-01',
        time: '10:00',
        hours: 1,
        status: 'Completed',
      },
    });

    assert.equal(res.status, 201);
    assert.equal(bookingOf(res.body.data.id).status, 'Pending');
  });

  it('denies a client marking their booking Completed', async () => {
    signIn('client1');

    const res = await put(`${BASE}/bk-pending`, {
      token: tokenFor('client1'),
      body: { status: 'Completed' },
    });

    assert.equal(res.status, 403);
    assert.equal(bookingOf('bk-pending').status, 'Pending');
  });

  it('denies a client reactivating a completed booking', async () => {
    signIn('client1');

    const res = await put(`${BASE}/bk-done`, {
      token: tokenFor('client1'),
      body: { status: 'Active' },
    });

    assert.equal(res.status, 403);
    assert.equal(bookingOf('bk-done').status, 'Completed');
  });

  it('lets a client cancel a pending booking', async () => {
    signIn('client1');

    const res = await put(`${BASE}/bk-pending`, {
      token: tokenFor('client1'),
      body: { status: 'Cancelled' },
    });

    assert.equal(res.status, 200);
    assert.equal(bookingOf('bk-pending').status, 'Cancelled');
  });

  // WAVE 1.3: this replaced an older test that let a client reschedule freely.
  // The booking flow has no availability model, so a client-chosen new slot
  // cannot be validated — the safe answer is to refuse and let an administrator
  // reschedule (tested below).
  it('denies a client rescheduling, leaving the booking untouched', async () => {
    signIn('client1');

    const res = await put(`${BASE}/bk-pending`, {
      token: tokenFor('client1'),
      body: { date: '2026-12-24', time: '15:00' },
    });

    assert.equal(res.status, 403);
    const stored = bookingOf('bk-pending');
    assert.equal(stored.date, '2026-11-01');
    assert.equal(stored.time, '10:00');
    assert.equal(stored.totalPrice, 150);
    assert.equal(stored.status, 'Pending');
  });

  it('denies a client rewriting the lawyer display name', async () => {
    signIn('client1');

    const res = await put(`${BASE}/bk-pending`, {
      token: tokenFor('client1'),
      body: { lawyerName: 'Senior Partner (fake)' },
    });

    assert.equal(res.status, 403);
    assert.equal(bookingOf('bk-pending').lawyerName, 'Lawyer One');
  });

  it('lets an administrator reschedule and keeps the derived price', async () => {
    signIn('admin1');

    const res = await put(`${BASE}/bk-pending`, {
      token: tokenFor('admin1'),
      body: { date: '2026-12-24', time: '15:00' },
    });

    assert.equal(res.status, 200);
    assert.equal(bookingOf('bk-pending').date, '2026-12-24');
    assert.equal(bookingOf('bk-pending').totalPrice, 150);
    assert.equal(bookingOf('bk-pending').status, 'Pending');
  });

  it('recomputes the price when an administrator changes the lawyer', async () => {
    signIn('admin1');

    const res = await put(`${BASE}/bk-pending`, {
      token: tokenFor('admin1'),
      body: { lawyerId: 'lawyer-free' },
    });

    // `lawyer-free` has no configured rate, so the change is refused rather
    // than leaving a booking priced by the previous lawyer.
    assert.equal(res.status, 400);
    assert.equal(bookingOf('bk-pending').lawyerId, 'lawyer-150');
    assert.equal(bookingOf('bk-pending').totalPrice, 150);
  });

  it('reprices and renames when an administrator changes the hours', async () => {
    signIn('admin1');

    const res = await put(`${BASE}/bk-pending`, {
      token: tokenFor('admin1'),
      body: { hours: 2 },
    });

    assert.equal(res.status, 200);
    assert.equal(bookingOf('bk-pending').hours, 2);
    assert.equal(bookingOf('bk-pending').totalPrice, 300);
    assert.equal(bookingOf('bk-pending').lawyerName, 'Lawyer One');
  });

  it('denies a client changing the lawyer or the hours', async () => {
    signIn('client1');

    const lawyer = await put(`${BASE}/bk-pending`, {
      token: tokenFor('client1'),
      body: { lawyerId: 'lawyer-free' },
    });
    assert.equal(lawyer.status, 403);

    const hours = await put(`${BASE}/bk-pending`, {
      token: tokenFor('client1'),
      body: { hours: 12 },
    });
    assert.equal(hours.status, 403);

    assert.equal(bookingOf('bk-pending').status, 'Pending');
    assert.equal(bookingOf('bk-pending').totalPrice, 150);
  });

  it('lets an administrator move a booking through the full lifecycle', async () => {
    signIn('admin1');

    for (const status of ['Active', 'Completed']) {
      const res = await put(`${BASE}/bk-pending`, {
        token: tokenFor('admin1'),
        body: { status },
      });
      assert.equal(res.status, 200);
      assert.equal(bookingOf('bk-pending').status, status);
    }
  });
});

describe('bookings 1.2: partial updates keep untouched fields', () => {
  beforeEach(() =>
    reset({
      collections: seed({
        bookings: [
          { id: 'bk-active', userId: 'client-1', status: 'Active', totalPrice: 300, hours: 2 },
        ],
      }),
    }),
  );

  it('does not reset the status to Pending on an unrelated update', async () => {
    signIn('admin1');

    const res = await put(`${BASE}/bk-active`, {
      token: tokenFor('admin1'),
      body: { time: '16:00' },
    });

    assert.equal(res.status, 200);
    assert.equal(bookingOf('bk-active').status, 'Active', 'status must survive');
    assert.equal(bookingOf('bk-active').hours, 2);
    assert.equal(bookingOf('bk-active').totalPrice, 300);
  });

  it('does not write a default status when the body is empty', async () => {
    signIn('admin1');

    const res = await put(`${BASE}/bk-active`, {
      token: tokenFor('admin1'),
      body: {},
    });

    assert.equal(res.status, 200);
    assert.equal(bookingOf('bk-active').status, 'Active');
  });
});

describe('bookings 1.2: ownership still holds', () => {
  beforeEach(() =>
    reset({
      collections: seed({
        bookings: [
          { id: 'bk-a', userId: 'client-1', status: 'Pending', totalPrice: 150 },
          { id: 'bk-b', userId: 'client-2', status: 'Pending', totalPrice: 150 },
        ],
      }),
    }),
  );

  it('denies one client cancelling another client\'s booking', async () => {
    signIn('client1');

    const res = await put(`${BASE}/bk-b`, {
      token: tokenFor('client1'),
      body: { status: 'Cancelled' },
    });

    assert.equal(res.status, 403);
    assert.equal(bookingOf('bk-b').status, 'Pending');
  });

  it('denies reading or deleting another client\'s booking', async () => {
    signIn('client1');

    const read = await get(`${BASE}/bk-b`, { token: tokenFor('client1') });
    const remove = await del(`${BASE}/bk-b`, { token: tokenFor('client1') });

    assert.equal(read.status, 403);
    assert.equal(remove.status, 403);
    assert.ok(bookingOf('bk-b'));
  });
});
