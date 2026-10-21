/**
 * Authorization regression tests for the users routes.
 *
 * Covers the self-promotion defect: `PUT /api/users/:id` used to accept any
 * field from `userSchema`, which included `role`. Because that route lets a
 * caller edit their own document, any signed-in account could send
 * `{ role: 'admin' }` and grant itself administrator rights.
 */

import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { userSchema, userRoleSchema, validate } from '../src/utils/validators.js';
import {
  PEOPLE,
  del,
  docs,
  get,
  patch,
  put,
  reset,
  signIn,
  startApp,
  stopApp,
  tokenFor,
  users,
  authUpdates,
  failAuthUpdates,
} from './helpers/harness.js';

const BASE = '/api/users';

before(startApp);
after(stopApp);

function seed() {
  return users('client1', 'client2', 'lawyer1', 'admin1');
}

const roleOf = (uid) => docs('users').find((u) => u.id === uid)?.role;

describe('users: the profile schema cannot carry a role', () => {
  it('strips `role` from a profile payload', () => {
    const data = validate(
      userSchema,
      { name: 'Client One', email: 'client1@example.com', role: 'admin' },
      { presence: 'optional' },
    );

    assert.equal('role' in data, false, 'userSchema must not accept role');
  });

  it('still accepts a legitimate profile payload', () => {
    const data = validate(
      userSchema,
      { name: 'Client One', email: 'client1@example.com', phone: '0100' },
      { presence: 'optional' },
    );

    assert.equal(data.name, 'Client One');
    assert.equal(data.phone, '0100');
  });

  it('keeps role changes restricted to real roles', () => {
    assert.equal(validate(userRoleSchema, { role: 'lawyer' }).role, 'lawyer');
    assert.throws(() => validate(userRoleSchema, { role: 'root' }));
  });
});

describe('users: role escalation', () => {
  beforeEach(() => reset({ collections: { users: seed() } }));

  it('strips `role` from a self profile update and grants nothing', async () => {
    signIn('client1');

    const res = await put(`${BASE}/client-1`, {
      token: tokenFor('client1'),
      body: { name: 'Renamed Client', email: 'client1@example.com', role: 'admin' },
    });

    assert.equal(res.status, 200);
    assert.equal(res.body.success, true);
    assert.equal(res.body.data.name, 'Renamed Client');
    // The name change is legitimate; the privilege change is not.
    assert.equal(roleOf('client-1'), 'client');
    assert.equal(res.body.data.role, 'client');
  });

  it('ignores a body containing only `role` and writes nothing', async () => {
    signIn('client1');

    const res = await put(`${BASE}/client-1`, {
      token: tokenFor('client1'),
      body: { role: 'lawyer' },
    });

    // `name` and `email` are required on this route (pre-existing contract),
    // so the request is rejected before it can reach Firestore. The privilege
    // change must not happen either way.
    assert.equal(res.status, 400);
    assert.equal(res.body.success, false);
    assert.equal(roleOf('client-1'), 'client');
  });

  it('does not let a client write `uid` or `userId` on their own record', async () => {
    signIn('client1');

    const res = await put(`${BASE}/client-1`, {
      token: tokenFor('client1'),
      body: {
        name: 'Client One',
        email: 'client1@example.com',
        uid: 'admin-1',
        userId: 'admin-1',
      },
    });

    assert.equal(res.status, 200);
    assert.equal(res.body.data.uid, 'client-1');
    assert.equal(res.body.data.userId, undefined);
  });

  it('denies a client editing another user\'s profile', async () => {
    signIn('client1');

    const res = await put(`${BASE}/client-2`, {
      token: tokenFor('client1'),
      body: { name: 'Hijacked', email: 'hijacked@example.com' },
    });

    assert.equal(res.status, 403);
    assert.equal(res.body.success, false);
    assert.equal(docs('users').find((u) => u.id === 'client-2').name, 'Client Two');
  });

  it('denies a client reading another user\'s profile', async () => {
    signIn('client1');

    const res = await get(`${BASE}/client-2`, { token: tokenFor('client1') });

    assert.equal(res.status, 403);
    assert.equal(res.body.success, false);
  });

  it('lets a user read their own profile', async () => {
    signIn('client1');

    const res = await get(`${BASE}/client-1`, { token: tokenFor('client1') });

    assert.equal(res.status, 200);
    assert.equal(res.body.data.id, 'client-1');
  });

  it('rejects an unauthenticated profile update', async () => {
    const res = await put(`${BASE}/client-1`, { body: { role: 'admin' } });

    assert.equal(res.status, 401);
    assert.equal(roleOf('client-1'), 'client');
  });
});

describe('users: role administration', () => {
  beforeEach(() => reset({ collections: { users: seed() } }));

  it('denies a non-admin calling the role endpoint', async () => {
    signIn('client1');

    const res = await patch(`${BASE}/client-2/role`, {
      token: tokenFor('client1'),
      body: { role: 'admin' },
    });

    assert.equal(res.status, 403);
    assert.equal(roleOf('client-2'), 'client');
  });

  it('denies a client promoting themselves through the role endpoint', async () => {
    signIn('client1');

    const res = await patch(`${BASE}/client-1/role`, {
      token: tokenFor('client1'),
      body: { role: 'admin' },
    });

    assert.equal(res.status, 403);
    assert.equal(roleOf('client-1'), 'client');
  });

  it('lets an admin promote a user', async () => {
    signIn('admin1');

    const res = await patch(`${BASE}/client-2/role`, {
      token: tokenFor('admin1'),
      body: { role: 'lawyer' },
    });

    assert.equal(res.status, 200);
    assert.equal(res.body.data.role, 'lawyer');
    assert.equal(roleOf('client-2'), 'lawyer');
  });

  it('rejects an unknown role value', async () => {
    signIn('admin1');

    const res = await patch(`${BASE}/client-2/role`, {
      token: tokenFor('admin1'),
      body: { role: 'superuser' },
    });

    assert.equal(res.status, 400);
    assert.equal(roleOf('client-2'), 'client');
  });

  it('answers 404 for a role change on a missing user', async () => {
    signIn('admin1');

    const res = await patch(`${BASE}/ghost/role`, {
      token: tokenFor('admin1'),
      body: { role: 'lawyer' },
    });

    assert.equal(res.status, 404);
    assert.equal(res.body.success, false);
  });
});

describe('users: deletion', () => {
  beforeEach(() => reset({ collections: { users: seed() } }));

  it('denies a non-admin deleting a user', async () => {
    signIn('client1');

    const res = await del(`${BASE}/client-2`, { token: tokenFor('client1') });

    assert.equal(res.status, 403);
    assert.ok(docs('users').some((u) => u.id === 'client-2'));
  });

  it('denies an admin deleting their own account', async () => {
    signIn('admin1');

    const res = await del(`${BASE}/admin-1`, { token: tokenFor('admin1') });

    assert.equal(res.status, 403);
    assert.ok(docs('users').some((u) => u.id === 'admin-1'));
  });

  it('keeps the legitimate admin delete working', async () => {
    signIn('admin1');

    const res = await del(`${BASE}/client-2`, { token: tokenFor('admin1') });

    assert.equal(res.status, 200);
    assert.equal(res.body.data.id, 'client-2');
    assert.equal(docs('users').some((u) => u.id === 'client-2'), false);
  });
});

describe('users: admin list is unchanged', () => {
  beforeEach(() => reset({ collections: { users: seed() } }));

  it('allows an admin to list users', async () => {
    signIn('admin1');

    const res = await get(BASE, { token: tokenFor('admin1') });

    assert.equal(res.status, 200);
    assert.ok(Array.isArray(res.body.data.items));
    assert.equal(res.body.data.items.length, seed().length);
  });

  it('denies a non-admin listing users', async () => {
    signIn('client1');

    const res = await get(BASE, { token: tokenFor('client1') });

    assert.equal(res.status, 403);
  });
});

describe('users: the fixture admin is really an admin', () => {
  beforeEach(() => reset({ collections: { users: seed() } }));

  it('resolves the admin role from the Firestore profile', async () => {
    signIn('admin1');

    const res = await get(`${BASE}/${PEOPLE.client1.uid}`, {
      token: tokenFor('admin1'),
    });

    assert.equal(res.status, 200);
    assert.equal(res.body.data.id, 'client-1');
  });
});

/* =====================================================================
 * WAVE 1.3 — Firebase Auth and the profile must not drift
 * ===================================================================*/

describe('users 1.3: email synchronisation', () => {
  beforeEach(() => reset({ collections: { users: seed() } }));

  it('updates the sign-in email in Firebase Auth when an admin changes it', async () => {
    signIn('admin1');

    const res = await put(`${BASE}/client-1`, {
      token: tokenFor('admin1'),
      body: { name: 'Client One', email: 'new-address@example.com' },
    });

    assert.equal(res.status, 200);
    assert.equal(docs('users').find((u) => u.id === 'client-1').email, 'new-address@example.com');
    assert.deepEqual(authUpdates(), [
      { uid: 'client-1', email: 'new-address@example.com' },
    ]);
  });

  it('does not touch Firebase Auth when the email is unchanged', async () => {
    signIn('admin1');

    const res = await put(`${BASE}/client-1`, {
      token: tokenFor('admin1'),
      body: { name: 'Renamed', email: 'client1@example.com' },
    });

    assert.equal(res.status, 200);
    assert.equal(authUpdates().length, 0);
  });

  it('denies an ordinary user changing their own sign-in email', async () => {
    signIn('client1');

    const res = await put(`${BASE}/client-1`, {
      token: tokenFor('client1'),
      body: { name: 'Client One', email: 'attacker@example.com' },
    });

    assert.equal(res.status, 403);
    assert.equal(docs('users').find((u) => u.id === 'client-1').email, 'client1@example.com');
    assert.equal(authUpdates().length, 0);
  });

  it('allows an ordinary user to re-send their current email', async () => {
    signIn('client1');

    const res = await put(`${BASE}/client-1`, {
      token: tokenFor('client1'),
      body: { name: 'Client One', email: 'client1@example.com' },
    });

    assert.equal(res.status, 200);
    assert.equal(authUpdates().length, 0);
  });

  it('reports a client error and writes nothing when Auth rejects the address', async () => {
    signIn('admin1');
    failAuthUpdates('auth/email-already-exists');

    const res = await put(`${BASE}/client-1`, {
      token: tokenFor('admin1'),
      body: { name: 'Client One', email: 'taken@example.com' },
    });

    assert.equal(res.status, 400);
    assert.equal(
      docs('users').find((u) => u.id === 'client-1').email,
      'client1@example.com',
      'the profile must not drift from the sign-in address',
    );
    assert.equal(authUpdates().length, 0);
  });
});
