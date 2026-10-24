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

function seed() {
  return {
    users: users('client1', 'client2', 'lawyer1', 'lawyer2', 'admin1'),
    lawyers: [
      { id: 'lawyer-record-1', userId: 'lawyer-1', name: 'Lawyer One', priceValue: 100 },
      { id: 'lawyer-record-2', userId: 'lawyer-2', name: 'Lawyer Two', priceValue: 120 },
    ],
    bookings: [
      {
        id: 'booking-assigned-1',
        userId: 'client-1',
        lawyerId: 'lawyer-record-1',
        lawyerName: 'Lawyer One',
        date: '2026-12-01',
        time: '09:00',
        hours: 1,
        totalPrice: 100,
        status: 'Pending',
      },
      {
        id: 'booking-assigned-2',
        userId: 'client-2',
        lawyerId: 'lawyer-record-2',
        lawyerName: 'Lawyer Two',
        date: '2026-12-02',
        time: '10:00',
        hours: 1,
        totalPrice: 120,
        status: 'Pending',
      },
    ],
  };
}

beforeEach(() => reset({ collections: seed() }));

describe('assigned lawyer booking access (route fixtures only)', () => {
  it('lists only bookings assigned through the linked lawyer row, ignoring caller filters', async () => {
    signIn('lawyer1');
    const response = await get(`${BASE}?userId=client-2&lawyerId=lawyer-record-2`, {
      token: tokenFor('lawyer1'),
    });
    assert.equal(response.status, 200, JSON.stringify(response.body));
    assert.deepEqual(response.body.data.items.map((item) => item.id), ['booking-assigned-1']);
  });

  it('allows reading an assigned booking and denies another lawyer\'s booking', async () => {
    signIn('lawyer1');
    const assigned = await get(`${BASE}/booking-assigned-1`, { token: tokenFor('lawyer1') });
    const other = await get(`${BASE}/booking-assigned-2`, { token: tokenFor('lawyer1') });
    assert.equal(assigned.status, 200, JSON.stringify(assigned.body));
    assert.equal(other.status, 403);
  });

  it('keeps booking writes unavailable to lawyers', async () => {
    signIn('lawyer1');
    const create = await post(BASE, {
      token: tokenFor('lawyer1'),
      body: {
        userId: 'client-1',
        lawyerId: 'lawyer-record-1',
        date: '2026-12-03',
        time: '11:00',
        hours: 1,
      },
    });
    const update = await put(`${BASE}/booking-assigned-1`, {
      token: tokenFor('lawyer1'),
      body: { status: 'Completed' },
    });
    const remove = await del(`${BASE}/booking-assigned-1`, { token: tokenFor('lawyer1') });
    assert.equal(create.status, 403);
    assert.equal(update.status, 403);
    assert.equal(remove.status, 403);
    assert.equal(docs('bookings').length, 2);
    assert.equal(docs('bookings').find((item) => item.id === 'booking-assigned-1').status, 'Pending');
  });
});
