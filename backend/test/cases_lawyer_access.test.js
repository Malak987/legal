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

const BASE = '/api/cases';

before(startApp);
after(stopApp);

function seed() {
  return {
    users: users('client1', 'client2', 'lawyer1', 'lawyer2', 'admin1'),
    lawyers: [
      { id: 'lawyer-record-1', userId: 'lawyer-1', name: 'Lawyer One' },
      { id: 'lawyer-record-2', userId: 'lawyer-2', name: 'Lawyer Two' },
    ],
    cases: [
      {
        id: 'case-assigned-1',
        userId: 'client-1',
        lawyerId: 'lawyer-record-1',
        title: 'Assigned to lawyer one',
        status: 'Open',
        priority: 'Medium',
      },
      {
        id: 'case-assigned-2',
        userId: 'client-2',
        lawyerId: 'lawyer-record-2',
        title: 'Assigned to lawyer two',
        status: 'Open',
        priority: 'Medium',
      },
      {
        id: 'case-unassigned',
        userId: 'client-1',
        title: 'No assigned lawyer',
        status: 'Open',
        priority: 'Medium',
      },
    ],
  };
}

beforeEach(() => reset({ collections: seed() }));

describe('assigned lawyer case access (route fixtures only)', () => {
  it('lists only cases assigned through the linked lawyer row, ignoring caller filters', async () => {
    signIn('lawyer1');
    const response = await get(`${BASE}?userId=client-2&lawyerId=lawyer-record-2`, {
      token: tokenFor('lawyer1'),
    });
    assert.equal(response.status, 200, JSON.stringify(response.body));
    assert.deepEqual(response.body.data.items.map((item) => item.id), ['case-assigned-1']);
  });

  it('allows a lawyer to read one assigned case, but not an unassigned or other-lawyer case', async () => {
    signIn('lawyer1');
    const assigned = await get(`${BASE}/case-assigned-1`, { token: tokenFor('lawyer1') });
    const other = await get(`${BASE}/case-assigned-2`, { token: tokenFor('lawyer1') });
    const unassigned = await get(`${BASE}/case-unassigned`, { token: tokenFor('lawyer1') });
    assert.equal(assigned.status, 200, JSON.stringify(assigned.body));
    assert.equal(other.status, 403);
    assert.equal(unassigned.status, 403);
  });

  it('does not grant lawyers case creation, updates, or deletion', async () => {
    signIn('lawyer1');
    const create = await post(BASE, {
      token: tokenFor('lawyer1'),
      body: { title: 'Attempted lawyer case', userId: 'client-1' },
    });
    const update = await put(`${BASE}/case-assigned-1`, {
      token: tokenFor('lawyer1'),
      body: { status: 'Closed' },
    });
    const remove = await del(`${BASE}/case-assigned-1`, { token: tokenFor('lawyer1') });
    assert.equal(create.status, 403);
    assert.equal(update.status, 403);
    assert.equal(remove.status, 403);
    assert.equal(docs('cases').find((item) => item.id === 'case-assigned-1').status, 'Open');
  });
});
