/**
 * Phase 1 regression tests for the cases contract.
 *
 * The audit proved five defects on this route, all reproduced here first:
 *
 *   F-04  a partial `PUT` re-applied the schema defaults, so omitting `status`
 *         or `priority` silently reset them to `Open` / `Medium`;
 *   F-05  an administrator could create a case for a user id that does not
 *         exist, producing an orphan record;
 *   F-03  an administrator creating a case without a `userId` got a case owned
 *         by the administrator, with nothing in the response saying so;
 *   F-06  `dueDate` accepted any string ("sometime next tuesday", 2026-02-30);
 *   F-07  two identical `POST`s created two cases (no idempotency).
 *
 * F-07 is documented as a follow-up rather than fixed here: there is no
 * idempotency infrastructure for cases, and adding a new collection or a
 * required client-supplied key would not be backward compatible.
 *
 * Everything below is written against the real routes, the real auth
 * middleware and the real error handler, with an in-memory Firestore double.
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

const BASE = '/api/cases';
const TASKS = '/api/tasks';

before(startApp);
after(stopApp);

function seed(overrides = {}) {
  return {
    // client1/client2 are eligible owners, admin1 is not, and `ghost-uid`
    // exists in no collection at all.
    users: users('client1', 'client2', 'lawyer1', 'admin1'),
    lawyers: [
      { id: 'lawyer-record-1', userId: 'lawyer-1', name: 'Lawyer One' },
      { id: 'lawyer-record-2', userId: 'lawyer-2', name: 'Lawyer Two' },
    ],
    cases: [],
    ...overrides,
  };
}

const caseOf = (id) => docs('cases').find((c) => c.id === id);

/** Creates a case as client1 and returns the stored document id. */
async function createCase(body = { title: 'Contract review' }) {
  signIn('client1');
  const res = await post(BASE, { token: tokenFor('client1'), body });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return res.body.data.id;
}

const stored = (overrides = {}) => ({
  id: 'case-1',
  userId: 'client-1',
  title: 'Original title',
  status: 'In Progress',
  priority: 'High',
  dueDate: '2026-11-30',
  ...overrides,
});

// ---------------------------------------------------------------------------
// 1. Partial updates must not reset omitted fields to schema defaults
// ---------------------------------------------------------------------------

describe('cases 1.1: a partial update keeps the fields it did not send', () => {
  beforeEach(() => reset({ collections: seed({ cases: [stored()] }) }));

  it('keeps status and priority when only the title changes', async () => {
    signIn('client1');

    const res = await put(`${BASE}/case-1`, {
      token: tokenFor('client1'),
      body: { title: 'Renamed case' },
    });

    assert.equal(res.status, 200);
    assert.equal(res.body.data.title, 'Renamed case');
    // The defect: these used to come back as 'Open' and 'Medium'.
    assert.equal(res.body.data.status, 'In Progress');
    assert.equal(res.body.data.priority, 'High');

    const saved = caseOf('case-1');
    assert.equal(saved.status, 'In Progress');
    assert.equal(saved.priority, 'High');
  });

  it('keeps the title and priority when only the status changes', async () => {
    signIn('client1');

    const res = await put(`${BASE}/case-1`, {
      token: tokenFor('client1'),
      body: { status: 'Closed' },
    });

    assert.equal(res.status, 200);
    assert.equal(res.body.data.status, 'Closed');
    assert.equal(res.body.data.priority, 'High');
    assert.equal(res.body.data.title, 'Original title');
  });

  it('still applies the defaults on CREATE', async () => {
    reset({ collections: seed() });

    const id = await createCase({ title: 'No status given' });

    assert.equal(caseOf(id).status, 'Open');
    assert.equal(caseOf(id).priority, 'Medium');
  });

  it('accepts an explicit status and priority on CREATE', async () => {
    reset({ collections: seed() });

    const id = await createCase({
      title: 'Explicit values',
      status: 'In Progress',
      priority: 'High',
    });

    assert.equal(caseOf(id).status, 'In Progress');
    assert.equal(caseOf(id).priority, 'High');
  });
});

describe('tasks 1.1: the same defaults bug, fixed the same way', () => {
  beforeEach(() =>
    reset({
      collections: seed({
        tasks: [
          { id: 'task-1', userId: 'client-1', title: 'File motion', status: 'In Progress', priority: 'High' },
        ],
      }),
    }),
  );

  it('keeps status and priority when only the title changes', async () => {
    signIn('client1');

    const res = await put(`${TASKS}/task-1`, {
      token: tokenFor('client1'),
      body: { title: 'File motion (revised)' },
    });

    assert.equal(res.status, 200);
    assert.equal(res.body.data.status, 'In Progress');
    assert.equal(res.body.data.priority, 'High');
  });

  it('still applies the defaults on CREATE', async () => {
    signIn('client1');

    const res = await post(TASKS, {
      token: tokenFor('client1'),
      body: { title: 'New task' },
    });

    assert.equal(res.status, 201);
    assert.equal(res.body.data.status, 'Pending');
    assert.equal(res.body.data.priority, 'Medium');
  });
});

describe('tasks 1.2: status values match the migrated database/mobile contract', () => {
  beforeEach(() =>
    reset({
      collections: seed({
        tasks: [
          { id: 'task-1', userId: 'client-1', title: 'File motion', status: 'Pending', priority: 'High' },
        ],
      }),
    }),
  );

  for (const status of ['Pending', 'In Progress', 'Completed', 'Cancelled']) {
    it(`accepts ${status}`, async () => {
      signIn('client1');
      const res = await put(`${TASKS}/task-1`, {
        token: tokenFor('client1'),
        body: { title: 'File motion', status },
      });
      assert.equal(res.status, 200, JSON.stringify(res.body));
      assert.equal(res.body.data.status, status);
    });
  }

  for (const status of ['To Do', 'Done']) {
    it(`rejects legacy status ${status}`, async () => {
      signIn('client1');
      const res = await put(`${TASKS}/task-1`, {
        token: tokenFor('client1'),
        body: { title: 'File motion', status },
      });
      assert.equal(res.status, 400, JSON.stringify(res.body));
      assert.equal(docs('tasks').find((task) => task.id === 'task-1').status, 'Pending');
    });
  }
});

// ---------------------------------------------------------------------------
// 2. dueDate / status / priority validation
// ---------------------------------------------------------------------------

describe('cases 1.2: dueDate must be a real YYYY-MM-DD date', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('accepts a valid calendar date', async () => {
    const id = await createCase({ title: 'Dated case', dueDate: '2026-11-30' });
    assert.equal(caseOf(id).dueDate, '2026-11-30');
  });

  it('accepts an omitted, empty or null dueDate', async () => {
    const omitted = await createCase({ title: 'No date' });
    assert.equal(caseOf(omitted).dueDate, undefined);

    // Pre-existing behaviour, kept on purpose: `dueDate` was
    // `Joi.string().trim().allow('', null)`, so an empty string was accepted and
    // stored verbatim (the legacy mobile client sends ""). Phase 1 must not turn
    // that into a 400 and must not invent a date for it either.
    // `createCase` already asserts the 201.
    const empty = await createCase({ title: 'Empty date', dueDate: '' });
    assert.equal(caseOf(empty).dueDate, '', 'the empty string is stored as-is');

    const nulled = await createCase({ title: 'Null date', dueDate: null });
    assert.equal(caseOf(nulled).dueDate, null, 'null is accepted and stored as-is');
  });

  it('rejects free text', async () => {
    signIn('client1');
    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: { title: 'Free text date', dueDate: 'sometime next tuesday' },
    });

    assert.equal(res.status, 400);
    assert.equal(res.body.success, false);
    assert.equal(res.body.message, 'Validation failed.');
    assert.match(res.body.errors.join(' '), /dueDate/);
    assert.equal(docs('cases').length, 0, 'nothing may be written');
  });

  it('rejects an impossible calendar date', async () => {
    signIn('client1');
    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: { title: 'Impossible date', dueDate: '2026-02-30' },
    });

    assert.equal(res.status, 400);
    assert.match(res.body.errors.join(' '), /dueDate/);
    assert.equal(docs('cases').length, 0);
  });

  it('rejects a full timestamp filled into the date field', async () => {
    signIn('client1');
    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: { title: 'Timestamp', dueDate: '2026-11-30T10:00:00Z' },
    });

    assert.equal(res.status, 400);
    assert.match(res.body.errors.join(' '), /dueDate/);
  });

  it('rejects a non-ISO order', async () => {
    signIn('client1');
    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: { title: 'Local format', dueDate: '30/11/2026' },
    });

    assert.equal(res.status, 400);
  });

  it('rejects a NEW invalid date on update', async () => {
    reset({ collections: seed({ cases: [stored()] }) });
    signIn('client1');

    const res = await put(`${BASE}/case-1`, {
      token: tokenFor('client1'),
      body: { dueDate: 'whenever' },
    });

    assert.equal(res.status, 400);
    assert.equal(caseOf('case-1').dueDate, '2026-11-30', 'stored value is untouched');
  });

  it('accepts a NEW valid date on update', async () => {
    reset({ collections: seed({ cases: [stored()] }) });
    signIn('client1');

    const res = await put(`${BASE}/case-1`, {
      token: tokenFor('client1'),
      body: { dueDate: '2027-01-15' },
    });

    assert.equal(res.status, 200);
    assert.equal(caseOf('case-1').dueDate, '2027-01-15');
  });

  it('tolerates an UNCHANGED legacy value so unrelated edits still work', async () => {
    // A record written before dueDate was validated.
    reset({
      collections: seed({
        cases: [stored({ dueDate: 'end of next month' })],
      }),
    });
    signIn('client1');

    const res = await put(`${BASE}/case-1`, {
      token: tokenFor('client1'),
      body: { title: 'Renamed only', dueDate: 'end of next month' },
    });

    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(res.body.data.title, 'Renamed only');
    assert.equal(caseOf('case-1').dueDate, 'end of next month', 'not rewritten');
    assert.equal(caseOf('case-1').status, 'In Progress');
  });
});

describe('cases 1.2: status and priority stay controlled vocabulary', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('rejects an unknown status on create', async () => {
    signIn('client1');
    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: { title: 'Bad status', status: 'Dismissed' },
    });

    assert.equal(res.status, 400);
    assert.match(res.body.errors.join(' '), /status/);
  });

  it('rejects an unknown priority on create', async () => {
    signIn('client1');
    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: { title: 'Bad priority', priority: 'Urgent' },
    });

    assert.equal(res.status, 400);
    assert.match(res.body.errors.join(' '), /priority/);
  });

  it('rejects an unknown status on update', async () => {
    reset({ collections: seed({ cases: [stored()] }) });
    signIn('client1');

    const res = await put(`${BASE}/case-1`, {
      token: tokenFor('client1'),
      body: { status: 'Dismissed' },
    });

    assert.equal(res.status, 400);
    assert.equal(caseOf('case-1').status, 'In Progress');
  });

  it('still rejects an empty title', async () => {
    signIn('client1');
    const res = await post(BASE, { token: tokenFor('client1'), body: { title: 'x' } });

    assert.equal(res.status, 400);
    assert.match(res.body.errors.join(' '), /title/);
  });
});

// ---------------------------------------------------------------------------
// 3. Client ownership
// ---------------------------------------------------------------------------

describe('cases 1.3: the owner is validated when an administrator picks one', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('rejects an administrator-supplied userId that does not exist', async () => {
    signIn('admin1');

    const res = await post(BASE, {
      token: tokenFor('admin1'),
      body: { title: 'Ghost case', userId: 'ghost-uid' },
    });

    assert.equal(res.status, 400);
    assert.equal(res.body.success, false);
    assert.match(res.body.message, /does not match an existing user/);
    assert.equal(docs('cases').length, 0, 'an orphan record must not be written');
  });

  it('rejects a userId that resolves to an administrator', async () => {
    signIn('admin1');

    const res = await post(BASE, {
      token: tokenFor('admin1'),
      body: { title: 'Admin owned', userId: 'admin-1' },
    });

    assert.equal(res.status, 400);
    assert.match(res.body.message, /not an eligible case owner/);
    assert.equal(docs('cases').length, 0);
  });

  it('accepts a real client and stores that client as the owner', async () => {
    signIn('admin1');

    const res = await post(BASE, {
      token: tokenFor('admin1'),
      body: { title: 'For a client', userId: 'client-2' },
    });

    assert.equal(res.status, 201);
    assert.equal(res.body.data.userId, 'client-2');
    assert.equal(caseOf(res.body.data.id).userId, 'client-2');
    assert.equal(res.body.warnings, undefined, 'a real client needs no warning');
  });

  it('rejects a lawyer as the case owner because cases are client-owned', async () => {
    signIn('admin1');

    const res = await post(BASE, {
      token: tokenFor('admin1'),
      body: { title: 'Lawyer-owned case', userId: 'lawyer-1' },
    });

    assert.equal(res.status, 400);
    assert.match(res.body.message, /not an eligible case owner/);
    assert.equal(docs('cases').length, 0);
  });

  it('requires an administrator to choose a client instead of creating an ownerless case', async () => {
    signIn('admin1');

    const res = await post(BASE, {
      token: tokenFor('admin1'),
      body: { title: 'Case without a client' },
    });

    assert.equal(res.status, 400);
    assert.match(res.body.message, /userId is required/);
    assert.equal(docs('cases').length, 0);
  });

  it('rejects an admin reassignment to an unknown user and changes nothing', async () => {
    reset({ collections: seed({ cases: [stored()] }) });
    signIn('admin1');

    const res = await put(`${BASE}/case-1`, {
      token: tokenFor('admin1'),
      body: { userId: 'ghost-uid' },
    });

    assert.equal(res.status, 400);
    assert.equal(caseOf('case-1').userId, 'client-1');
  });

  it('lets an admin reassign a case to a real client', async () => {
    reset({ collections: seed({ cases: [stored()] }) });
    signIn('admin1');

    const res = await put(`${BASE}/case-1`, {
      token: tokenFor('admin1'),
      body: { userId: 'client-2' },
    });

    assert.equal(res.status, 200);
    assert.equal(res.body.data.userId, 'client-2');
    assert.equal(caseOf('case-1').userId, 'client-2');
    assert.equal(caseOf('case-1').status, 'In Progress', 'other fields survive');
  });

  it('does not blank ownership when an admin sends an empty userId', async () => {
    reset({ collections: seed({ cases: [stored()] }) });
    signIn('admin1');

    const res = await put(`${BASE}/case-1`, {
      token: tokenFor('admin1'),
      body: { userId: '', title: 'Still owned' },
    });

    assert.equal(res.status, 200);
    assert.equal(caseOf('case-1').userId, 'client-1');
    assert.equal(caseOf('case-1').title, 'Still owned');
  });
});

describe('cases 1.3: existing owner rules are preserved', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('ignores a forged userId from a client (201, owned by the caller)', async () => {
    // Deliberately unchanged: `ownership.test.js` asserts this contract, and
    // turning it into a 403 would break clients that already send the field.
    signIn('client1');

    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: { title: 'Forged owner', userId: 'client-2' },
    });

    assert.equal(res.status, 201);
    assert.equal(res.body.data.userId, 'client-1');
    assert.equal(caseOf(res.body.data.id).userId, 'client-1');
    assert.equal(res.body.warnings, undefined);
  });

  it('does not let a client move their case to another account', async () => {
    reset({ collections: seed({ cases: [stored()] }) });
    signIn('client1');

    const res = await put(`${BASE}/case-1`, {
      token: tokenFor('client1'),
      body: { userId: 'client-2' },
    });

    assert.equal(res.status, 200);
    assert.equal(caseOf('case-1').userId, 'client-1');
  });

  it('denies a non-owner before validating the payload', async () => {
    reset({ collections: seed({ cases: [stored()] }) });
    signIn('client2');

    const res = await put(`${BASE}/case-1`, {
      token: tokenFor('client2'),
      body: { dueDate: 'not-a-date' },
    });

    assert.equal(res.status, 403);
    assert.equal(caseOf('case-1').dueDate, '2026-11-30');
  });

  it('scopes the list to the caller', async () => {
    reset({
      collections: seed({
        cases: [
          stored({ id: 'case-1' }),
          stored({ id: 'case-2', userId: 'client-2', title: 'Other client' }),
        ],
      }),
    });
    signIn('client1');

    const res = await get(`${BASE}?userId=client-2`, { token: tokenFor('client1') });

    assert.equal(res.status, 200);
    assert.equal(res.body.data.items.length, 1);
    assert.equal(res.body.data.items[0].id, 'case-1');
  });

  it('requires authentication for create and update', async () => {
    reset({ collections: seed({ cases: [stored()] }) });

    const created = await post(BASE, { body: { title: 'Anonymous' } });
    assert.equal(created.status, 401);

    const updated = await put(`${BASE}/case-1`, { body: { title: 'Anonymous' } });
    assert.equal(updated.status, 401);

    assert.equal(caseOf('case-1').title, 'Original title');
  });

  it('answers 404 for a missing record', async () => {
    signIn('client1');
    const res = await put(`${BASE}/nope`, {
      token: tokenFor('client1'),
      body: { title: 'Missing' },
    });
    assert.equal(res.status, 404);
  });
});

// ---------------------------------------------------------------------------
// 4. Documented follow-ups (asserted so a future fix has a red test first)
// ---------------------------------------------------------------------------

describe('cases 1.4: known limitations', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('still has no idempotency: two identical creates produce two cases', async () => {
    // Documented, not fixed: there is no idempotency store for cases and adding
    // a required client key would not be backward compatible. See Phase 1
    // report, "Remaining risks", for the proposed follow-up.
    signIn('client1');
    const body = { title: 'Double submit' };

    const first = await post(BASE, { token: tokenFor('client1'), body });
    const second = await post(BASE, { token: tokenFor('client1'), body });

    assert.equal(first.status, 201);
    assert.equal(second.status, 201);
    assert.notEqual(first.body.data.id, second.body.data.id);
    assert.equal(docs('cases').length, 2);
  });

  it('keeps the phase-1 response envelope for a normal create', async () => {
    signIn('client1');
    const res = await post(BASE, {
      token: tokenFor('client1'),
      body: { title: 'Envelope check' },
    });

    assert.deepEqual(Object.keys(res.body).sort(), ['data', 'message', 'success']);
    assert.equal(res.body.success, true);
    assert.equal(res.body.message, 'Case created');
  });

  it('still deletes an owned case', async () => {
    reset({ collections: seed({ cases: [stored()] }) });
    signIn('client1');

    const res = await del(`${BASE}/case-1`, { token: tokenFor('client1') });

    assert.equal(res.status, 200);
    assert.equal(caseOf('case-1'), undefined);
  });
});
