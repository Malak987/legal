/**
 * Availability-driven booking: coverage, conflicts and concurrency.
 *
 * `POST /api/bookings` used to accept any `date`/`time` string and store it,
 * without ever consulting the `availability` collection — so a client could
 * book 03:00 on a day the lawyer had not offered, and two clients could hold
 * the same slot. These tests pin the rules that replaced that:
 *
 *   1. a booking must start on an advertised slot;
 *   2. it occupies every advertised slot inside [start, start + hours);
 *   3. a blocking booking (anything except `Cancelled`) keeps its slots;
 *   4. cancelling or deleting releases them;
 *   5. two simultaneous requests for one slot cannot both succeed.
 *
 * The concurrency guarantee is structural: one deterministic reservation
 * document per (lawyer, date, slot) in `bookingSlots`, written in the same
 * transaction as the booking (see `utils/scheduling.js`). The harness models
 * Firestore's read-version conflict detection and its retry, so the concurrent
 * test below exercises the real mechanism rather than a read-then-write check.
 */

import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

import {
  del,
  docs,
  failWritesTo as failWritesToCollection,
  post,
  put,
  reset,
  signIn,
  startApp,
  stopApp,
  stubModule,
  tokenFor,
  users,
} from './helpers/harness.js';

const BASE = '/api/bookings';
const DATE = '2026-11-02';

before(startApp);
after(stopApp);

function seed(overrides = {}) {
  return {
    users: users('client1', 'client2', 'admin1'),
    lawyers: [
      { id: 'lawyer-1', name: 'Lawyer One', priceValue: 200 },
      { id: 'lawyer-unpriced', name: 'No Rate' },
    ],
    availability: [
      {
        id: 'av-day',
        lawyerId: 'lawyer-1',
        lawyerName: 'Lawyer One',
        date: DATE,
        // Deliberately a mix of conventions: the seed writes '09:00 am' and
        // the rest of the API writes '10:00'. Both must be understood.
        slots: ['09:00 am', '10:00', '11:00', '12:00'],
      },
      {
        id: 'av-next-day',
        lawyerId: 'lawyer-1',
        lawyerName: 'Lawyer One',
        date: '2026-11-03',
        slots: ['09:00', '10:00'],
      },
    ],
    bookings: [],
    bookingSlots: [],
    ...overrides,
  };
}

/**
 * A POST over its own TCP connection.
 *
 * `fetch` (and therefore the harness's `request`) reuses one keep-alive
 * connection, which serialises two "parallel" calls: the second request only
 * starts after the first response. That would make a concurrency test pass
 * against a non-atomic implementation. `agent: false` opens a separate socket
 * per request, so the two handlers really do interleave.
 */
function postInParallel(base, { token, body }) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify(body);
    const url = new URL(`${base}${BASE}`);
    const req = http.request(
      {
        hostname: url.hostname,
        port: url.port,
        path: url.pathname,
        method: 'POST',
        agent: false,
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(payload),
          Authorization: `Bearer ${token}`,
        },
      },
      (res) => {
        let text = '';
        res.on('data', (chunk) => { text += chunk; });
        res.on('end', () => {
          let parsed = null;
          try { parsed = text ? JSON.parse(text) : null; } catch (_e) { parsed = null; }
          resolve({ status: res.statusCode, body: parsed });
        });
      },
    );
    req.on('error', reject);
    req.end(payload);
  });
}

const bookingOf = (id) => docs('bookings').find((b) => b.id === id);
const lockFor = (slot) => docs('bookingSlots').filter((l) => l.slot === slot);

function bookSlot({
  as = 'client1',
  token = tokenFor('client1'),
  lawyerId = 'lawyer-1',
  date = DATE,
  time = '10:00',
  hours = 1,
  extra = {},
} = {}) {
  signIn(as);
  return post(BASE, {
    token,
    body: { lawyerId, date, time, hours, ...extra },
  });
}

describe('booking availability: coverage', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('creates a booking on an advertised slot and reserves it', async () => {
    const res = await bookSlot();

    assert.equal(res.status, 201);
    const stored = bookingOf(res.body.data.id);
    assert.equal(stored.status, 'Pending');
    assert.equal(stored.totalPrice, 200, 'price comes from the lawyer rate');

    // The 12-hour seed convention is normalised on the way in.
    const nine = await bookSlot({ time: '9:00 am' });
    assert.equal(nine.status, 201);
    assert.equal(bookingOf(nine.body.data.id).time, '09:00');

    // One reservation document per occupied advertised slot.
    assert.deepEqual(
      docs('bookingSlots').map((l) => l.slot).sort(),
      ['09:00', '10:00'],
    );
  });

  it('refuses a time the lawyer does not offer', async () => {
    const res = await bookSlot({ time: '03:00' });

    assert.equal(res.status, 400);
    assert.match(res.body.message, /not offered/i);
    // The caller receives a stable, non-provider-specific retry message; the
    // authenticated RPC does not disclose the full availability projection.
    assert.equal(res.body.message, 'That time is not offered by this lawyer. Choose an available slot.');
    assert.equal(docs('bookings').length, 0);
  });

  it('refuses a date with no published availability', async () => {
    const res = await bookSlot({ date: '2026-12-01' });

    assert.equal(res.status, 400);
    assert.match(res.body.message, /no availability/i);
    assert.equal(docs('bookings').length, 0);
  });

  it('merges every availability document for the same day', async () => {
    reset({
      collections: seed({
        availability: [
          {
            id: 'av-morning',
            lawyerId: 'lawyer-1',
            date: DATE,
            slots: ['09:00'],
          },
          {
            id: 'av-afternoon',
            lawyerId: 'lawyer-1',
            date: DATE,
            slots: ['14:00'],
          },
        ],
      }),
    });

    const res = await bookSlot({ time: '14:00' });
    assert.equal(res.status, 201);
  });

  it('ignores an availability document belonging to another lawyer', async () => {
    reset({
      collections: seed({
        availability: [
          {
            id: 'av-other',
            lawyerId: 'lawyer-2',
            date: DATE,
            slots: ['10:00'],
          },
        ],
      }),
    });

    const res = await bookSlot({ time: '10:00' });
    assert.equal(res.status, 400);
  });
});

describe('booking availability: conflicts', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('refuses a slot that is already booked', async () => {
    const first = await bookSlot();
    assert.equal(first.status, 201);

    const second = await bookSlot({ as: 'client2', token: tokenFor('client2') });

    assert.equal(second.status, 409);
    assert.equal(second.body.message, 'The requested time slot is no longer available. Choose another time.');
    assert.equal(docs('bookings').length, 1);
    assert.equal(lockFor('10:00').length, 1);
  });

  it('treats a longer appointment as occupying the slots it spans', async () => {
    // 09:00 for two hours covers 09:00 and 10:00.
    const long = await bookSlot({ time: '09:00', hours: 2 });
    assert.equal(long.status, 201);
    assert.deepEqual(
      lockFor('10:00').map((l) => l.slot),
      ['10:00'],
      'the second hour reserves the 10:00 slot',
    );

    const clash = await bookSlot({ time: '10:00' });
    assert.equal(clash.status, 409);

    // A slot beyond the appointment is still free.
    const after = await bookSlot({ time: '11:00' });
    assert.equal(after.status, 201);
  });

  it('refuses to extend an appointment over a booked slot', async () => {
    assert.equal((await bookSlot({ time: '09:00' })).status, 201);
    assert.equal((await bookSlot({ time: '10:00' })).status, 201);

    // Starting at 09:00 for two hours would now overlap the 10:00 booking, and
    // the 09:00 slot itself is taken as well.
    const res = await bookSlot({ time: '09:00', hours: 2 });
    assert.equal(res.status, 409);
  });

  it('blocks a legacy booking that has no reservation document', async () => {
    reset({
      collections: seed({
        bookings: [
          {
            id: 'legacy',
            userId: 'client-2',
            lawyerId: 'lawyer-1',
            date: DATE,
            time: '10:00',
            hours: 1,
            status: 'Pending',
            totalPrice: 200,
          },
        ],
      }),
    });

    const res = await bookSlot();
    assert.equal(res.status, 409);
    assert.equal(res.body.message, 'The requested time slot is no longer available. Choose another time.');
  });
});

describe('booking availability: cancellation releases the slot', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('frees the slot when the client cancels', async () => {
    const created = await bookSlot();
    assert.equal(created.status, 201);
    const bookingId = created.body.data.id;
    assert.equal(lockFor('10:00').length, 1);

    const cancelled = await put(`${BASE}/${bookingId}`, {
      token: tokenFor('client1'),
      body: { status: 'Cancelled' },
    });
    assert.equal(cancelled.status, 200);
    assert.equal(cancelled.body.data.slotKeys.length, 0);
    assert.equal(docs('bookingSlots').length, 0, 'reservation is released');

    // Somebody else can now take the slot.
    const rebooked = await bookSlot({ as: 'client2', token: tokenFor('client2') });
    assert.equal(rebooked.status, 201);
  });

  it('does not let a cancelled booking block an overlapping one', async () => {
    const long = await bookSlot({ time: '09:00', hours: 2 });
    await put(`${BASE}/${long.body.data.id}`, {
      token: tokenFor('client1'),
      body: { status: 'Cancelled' },
    });

    const res = await bookSlot({ time: '10:00' });
    assert.equal(res.status, 201);
  });

  it('frees the slot when the booking is deleted', async () => {
    const created = await bookSlot();
    const removed = await del(`${BASE}/${created.body.data.id}`, {
      token: tokenFor('client1'),
    });

    assert.equal(removed.status, 200);
    assert.equal(docs('bookingSlots').length, 0);
    assert.equal((await bookSlot({ time: '10:00' })).status, 201);
  });

  it('keeps the slot of a completed booking', async () => {
    const created = await bookSlot();
    signIn('admin1');
    await put(`${BASE}/${created.body.data.id}`, {
      token: tokenFor('admin1'),
      body: { status: 'Completed' },
    });

    assert.equal(lockFor('10:00').length, 1);
    signIn('client1');
    assert.equal((await bookSlot({ time: '10:00' })).status, 409);
  });
});

describe('booking availability: concurrency', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('lets exactly one of two simultaneous requests take a slot', async () => {
    // NOTE: the harness models a single authenticated caller (`fx.user`), so
    // both requests are issued as the same client. What is being raced is the
    // slot, which is what the reservation document protects.
    signIn('client1');
    const base = await startApp();
    const body = { lawyerId: 'lawyer-1', date: DATE, time: '10:00', hours: 1 };

    const [a, b] = await Promise.all([
      postInParallel(base, { token: tokenFor('client1'), body }),
      postInParallel(base, { token: tokenFor('client1'), body }),
    ]);

    const statuses = [a.status, b.status].sort();
    assert.deepEqual(statuses, [201, 409], 'one winner, one conflict');
    assert.equal(docs('bookings').length, 1, 'only one booking exists');
    assert.equal(lockFor('10:00').length, 1, 'only one reservation exists');

    // Whether the loser observes the already-committed reservation or loses
    // the version conflict and retries depends on how the two handlers
    // interleave, so that timing is not asserted here. The deterministic proof
    // of atomicity is the "reservation atomicity" suite below, which starts
    // both transactions in the same tick.
    assert.ok(
      globalThis.__fx.txAttempts >= 2,
      'both requests must use a transaction',
    );
  });

  it('lets two different slots be booked simultaneously', async () => {
    signIn('client1');

    const base = await startApp();
    const [a, b] = await Promise.all([
      postInParallel(base, {
        token: tokenFor('client1'),
        body: { lawyerId: 'lawyer-1', date: DATE, time: '10:00', hours: 1 },
      }),
      postInParallel(base, {
        token: tokenFor('client1'),
        body: { lawyerId: 'lawyer-1', date: DATE, time: '11:00', hours: 1 },
      }),
    ]);

    assert.equal(a.status, 201);
    assert.equal(b.status, 201);
    assert.equal(docs('bookingSlots').length, 2);
  });
});

describe('booking availability: invalid input', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('rejects an impossible calendar date', async () => {
    const res = await bookSlot({ date: '2026-02-30' });

    assert.equal(res.status, 400);
    assert.match(res.body.message, /Validation failed/i);
  });

  it('rejects a timestamp where a date is expected', async () => {
    const res = await bookSlot({ date: '2026-11-02T09:00:00Z' });
    assert.equal(res.status, 400);
  });

  it('rejects an unparseable time', async () => {
    for (const time of ['noon', '25:00', '09:75', '']) {
      const res = await bookSlot({ time });
      assert.equal(res.status, 400, `time ${JSON.stringify(time)} must fail`);
    }
  });

  it('rejects a non-integer or out-of-range duration', async () => {
    for (const hours of [0, 13, 1.5, 'two']) {
      const res = await bookSlot({ hours });
      assert.equal(res.status, 400, `hours ${JSON.stringify(hours)} must fail`);
    }
  });

  it('keeps the existing answers for an unknown or unpriced lawyer', async () => {
    const unknown = await bookSlot({ lawyerId: 'ghost' });
    assert.equal(unknown.status, 400);
    assert.match(unknown.body.message, /Lawyer not found/i);

    const unpriced = await bookSlot({ lawyerId: 'lawyer-unpriced' });
    assert.equal(unpriced.status, 400);
    assert.match(unpriced.body.message, /no configured hourly rate/i);
    assert.equal(docs('bookings').length, 0);
  });

  it('requires authentication', async () => {
    const res = await post(BASE, {
      body: { lawyerId: 'lawyer-1', date: DATE, time: '10:00', hours: 1 },
    });
    assert.equal(res.status, 401);
    assert.equal(docs('bookings').length, 0);
  });
});

describe('booking availability: price and identity stay server-side', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('ignores a client-supplied price', async () => {
    const res = await bookSlot({ extra: { totalPrice: 1 } });

    assert.equal(res.status, 201);
    assert.equal(bookingOf(res.body.data.id).totalPrice, 200);
  });

  it('ignores a client-supplied owner', async () => {
    const res = await bookSlot({ extra: { userId: 'client-2' } });

    assert.equal(res.status, 201);
    assert.equal(bookingOf(res.body.data.id).userId, 'client-1');
  });

  it('never stores a reservation against another account', async () => {
    const res = await bookSlot({ extra: { userId: 'client-2' } });
    const locks = docs('bookingSlots');

    assert.equal(locks.length, 1);
    assert.equal(locks[0].userId, 'client-1');
  });
});

describe('booking availability: administrator rescheduling', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('moves the reservation when the appointment is rescheduled', async () => {
    const created = await bookSlot({ time: '10:00' });
    const id = created.body.data.id;

    signIn('admin1');
    const moved = await put(`${BASE}/${id}`, {
      token: tokenFor('admin1'),
      body: { time: '11:00' },
    });

    assert.equal(moved.status, 200);
    assert.deepEqual(
      docs('bookingSlots').map((l) => l.slot),
      ['11:00'],
      'the old reservation is released and the new one taken',
    );

    // The vacated slot is bookable again, the new one is not.
    assert.equal((await bookSlot({ time: '10:00' })).status, 201);
    assert.equal((await bookSlot({ time: '11:00' })).status, 409);
  });

  it('refuses a reschedule onto a slot somebody else holds', async () => {
    const mine = await bookSlot({ time: '09:00' });
    assert.equal((await bookSlot({ as: 'client2', token: tokenFor('client2'), time: '10:00' })).status, 201);

    signIn('admin1');
    const res = await put(`${BASE}/${mine.body.data.id}`, {
      token: tokenFor('admin1'),
      body: { time: '10:00' },
    });

    assert.equal(res.status, 409);
    const stored = bookingOf(mine.body.data.id);
    assert.equal(stored.time, '09:00', 'the refused move changed nothing');
    assert.equal(lockFor('09:00').length, 1);
  });

  it('refuses a reschedule outside the published schedule', async () => {
    const created = await bookSlot({ time: '10:00' });

    signIn('admin1');
    const res = await put(`${BASE}/${created.body.data.id}`, {
      token: tokenFor('admin1'),
      body: { time: '03:00' },
    });

    assert.equal(res.status, 400);
    assert.equal(bookingOf(created.body.data.id).time, '10:00');
  });

  it('re-reserves when the duration grows', async () => {
    const created = await bookSlot({ time: '09:00', hours: 1 });

    signIn('admin1');
    const res = await put(`${BASE}/${created.body.data.id}`, {
      token: tokenFor('admin1'),
      body: { hours: 2 },
    });

    assert.equal(res.status, 200);
    assert.deepEqual(
      docs('bookingSlots').map((l) => l.slot).sort(),
      ['09:00', '10:00'],
    );
  });

  it('refuses to grow an appointment over a slot already held', async () => {
    const created = await bookSlot({ time: '09:00', hours: 1 });
    assert.equal((await bookSlot({ as: 'client2', token: tokenFor('client2'), time: '10:00' })).status, 201);

    signIn('admin1');
    const res = await put(`${BASE}/${created.body.data.id}`, {
      token: tokenFor('admin1'),
      body: { hours: 2 },
    });

    assert.equal(res.status, 409);
    assert.equal(bookingOf(created.body.data.id).hours, 1);
  });
});

describe('booking availability: reservation atomicity', () => {
  /**
   * Two transactions started in the same tick, both wanting the same slot.
   *
   * This is the property the HTTP-level test above cannot reliably reach: two
   * requests over the wire almost never overlap inside their transaction, so
   * that test would also pass against a non-atomic implementation. Here both
   * transactions read the reservation document before either commits, which is
   * exactly the interleaving Firestore's conflict detection has to resolve.
   */
  async function reservationModule() {
    return stubModule('utils/bookingReservation.js');
  }

  beforeEach(() => reset({ collections: seed() }));

  it('rejects the second of two overlapping reservations', async () => {
    const reservation = await reservationModule();
    const { getDb } = await stubModule('config/firebase.js');
    const db = getDb();

    const advertised = await reservation.loadAdvertisedSlots(db, 'lawyer-1', DATE);
    const plan = reservation.planReservation({
      advertised,
      startMinutes: 600, // 10:00
      hours: 1,
      lawyerId: 'lawyer-1',
      date: DATE,
    });
    assert.equal(plan.error, undefined);

    const data = {
      userId: 'client-1',
      lawyerId: 'lawyer-1',
      date: DATE,
      time: '10:00',
      hours: 1,
      status: 'Pending',
      totalPrice: 200,
    };
    const attempt = () =>
      reservation.createReservedBooking(db, {
        data,
        lawyerId: 'lawyer-1',
        date: DATE,
        startMinutes: 600,
        hours: 1,
        locks: plan.locks,
      });

    const results = await Promise.all([attempt(), attempt()]);

    assert.deepEqual(
      results.map((r) => r.status).sort(),
      ['created', 'taken'],
      'exactly one reservation wins',
    );
    assert.equal(docs('bookings').length, 1);
    assert.equal(lockFor('10:00').length, 1);
    assert.ok(
      globalThis.__fx.txAttempts >= 3,
      'the losing transaction must have been retried after the conflict',
    );
  });

  it('creates neither the booking nor the lock when a write fails', async () => {
    const reservation = await reservationModule();
    const { getDb } = await stubModule('config/firebase.js');
    const db = getDb();

    failWritesToCollection('bookingSlots');

    const plan = reservation.planReservation({
      advertised: [600],
      startMinutes: 600,
      hours: 1,
      lawyerId: 'lawyer-1',
      date: DATE,
    });

    await assert.rejects(
      reservation.createReservedBooking(db, {
        data: { userId: 'client-1', lawyerId: 'lawyer-1', date: DATE, time: '10:00', hours: 1 },
        lawyerId: 'lawyer-1',
        date: DATE,
        startMinutes: 600,
        hours: 1,
        locks: plan.locks,
      }),
    );

    assert.equal(docs('bookings').length, 0, 'the booking write is rolled back');
    assert.equal(docs('bookingSlots').length, 0);
  });
});
