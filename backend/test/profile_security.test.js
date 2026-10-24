/**
 * Profile lifecycle and role-integrity regressions.
 *
 * Complements `registration.test.js` (which covers provisioning itself) by
 * pinning the properties the rest of the system relies on once a profile
 * exists:
 *
 *   - a profile's `role` is server-owned and cannot be raised by the account
 *     that owns it;
 *   - a malformed or legacy profile document never becomes an administrator;
 *   - an account with no profile is treated as an ordinary client;
 *   - the admin list keeps working when documents carry missing/legacy fields.
 *
 * Only the in-memory harness is used: no production Firebase is touched.
 */

import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  docs,
  get,
  post,
  put,
  reset,
  setUser,
  signIn,
  startApp,
  stopApp,
  tokenFor,
  users,
} from './helpers/harness.js';

const USERS = '/api/users';
const ME = '/api/users/me';

before(startApp);
after(stopApp);

beforeEach(() => reset({ collections: { users: [], cases: [] } }));

const profileOf = (uid) => docs('users').find((u) => u.id === uid);

describe('profiles: the owner cannot raise their own role', () => {
  it('keeps `client` when the owner PUTs role: admin', async () => {
    reset({ collections: { users: users('client1') } });
    signIn('client1');

    const res = await put(`${USERS}/client-1`, {
      token: tokenFor('client1'),
      // `name` and `email` are required by `userSchema` even on update.
      body: { name: 'Client One', email: 'client1@example.com', role: 'admin' },
    });

    // `userSchema` has no `role`, so the field is stripped rather than rejected.
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(profileOf('client-1').role, 'client');
  });

  it('keeps `client` when the owner PUTs role: lawyer', async () => {
    reset({ collections: { users: users('client1') } });
    signIn('client1');

    await put(`${USERS}/client-1`, {
      token: tokenFor('client1'),
      body: { name: 'Client One', email: 'client1@example.com', role: 'lawyer' },
    });

    assert.equal(profileOf('client-1').role, 'client');
  });

  it('provisioning cannot be used to downgrade or upgrade an existing role', async () => {
    // An administrator has already promoted this account.
    reset({
      collections: {
        users: [{ id: 'client-1', uid: 'client-1', name: 'Promoted', role: 'lawyer', email: 'c@example.com' }],
      },
    });
    setUser({ uid: 'client-1', role: 'lawyer', name: 'Promoted', email: 'c@example.com', token: 'token-client-1' });

    const res = await post(ME, {
      token: 'token-client-1',
      body: { name: 'Renamed', role: 'client' },
    });

    assert.equal(res.status, 409, JSON.stringify(res.body));
    const stored = profileOf('client-1');
    assert.equal(stored.role, 'lawyer', 'the trusted role is preserved');
    assert.equal(stored.name, 'Promoted', 'the stored profile is not rewritten');
  });
});

describe('profiles: malformed or legacy documents never grant admin', () => {
  const malformed = [
    { label: 'a capitalised role', role: 'Admin' },
    { label: 'an unknown role', role: 'superuser' },
    { label: 'a non-string role', role: 1 },
    { label: 'an empty role', role: '' },
  ];

  for (const { label, role } of malformed) {
    it(`denies admin routes for ${label}`, async () => {
      reset({
        collections: {
          users: [{ id: 'u-1', uid: 'u-1', name: 'Odd', email: 'odd@example.com', role }],
        },
      });
      setUser({ uid: 'u-1', role: 'client', token: 'token-u-1' });

      const res = await get(USERS, { token: 'token-u-1' });

      assert.equal(res.status, 403, `${label} must not be administrator`);
    });
  }

  it('treats an account with NO profile document as a client', async () => {
    // Authenticated, but nothing at users/{uid}.
    setUser({ uid: 'ghost-1', role: 'client', token: 'token-ghost-1' });

    const adminRoute = await get(USERS, { token: 'token-ghost-1' });
    assert.equal(adminRoute.status, 403);

    // ...and its own profile genuinely does not exist.
    const own = await get(`${USERS}/ghost-1`, { token: 'token-ghost-1' });
    assert.equal(own.status, 404);
  });

  it('reads a profile that is missing optional fields without crashing', async () => {
    reset({
      collections: {
        // No phone/avatar/address, and no `uid` field (a legacy document).
        users: [{ id: 'client-1', name: 'Minimal', email: 'min@example.com', role: 'client' }],
      },
    });
    signIn('client1');

    const res = await get(`${USERS}/client-1`, { token: tokenFor('client1') });

    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(res.body.data.role, 'client');
    assert.equal(res.body.data.name, 'Minimal');
  });
});

describe('profiles: provisioning is delegated to the confirmed Supabase Auth lifecycle', () => {
  it('does not create a profile for an unconfirmed Auth caller', async () => {
    const uid = 'new-client';
    setUser({
      uid,
      email: 'new-client@example.com',
      email_verified: false,
      token: `token-${uid}`,
    });

    const res = await post(ME, {
      token: `token-${uid}`,
      body: { name: 'New Client' },
    });

    assert.equal(res.status, 409, JSON.stringify(res.body));
    assert.equal(profileOf(uid), undefined);
    assert.equal(docs('users').length, 0);
  });

  it('does not let body identity or role claims provision any account', async () => {
    const uid = 'spoof-client';
    setUser({ uid, email: 'real@example.com', token: `token-${uid}` });

    const res = await post(ME, {
      token: `token-${uid}`,
      body: {
        name: 'Spoof Client',
        email: 'victim@example.com',
        uid: 'client-1',
        id: 'client-1',
        role: 'admin',
      },
    });

    assert.equal(res.status, 409, JSON.stringify(res.body));
    assert.equal(profileOf(uid), undefined);
    assert.equal(profileOf('client-1'), undefined);
    assert.equal(docs('users').length, 0);
  });
});

describe('profiles: the admin list stays compatible', () => {
  it('lists provisioned clients alongside legacy documents', async () => {
    reset({
      collections: {
        users: [
          { id: 'admin-1', uid: 'admin-1', name: 'Admin One', email: 'a@example.com', role: 'admin' },
          // Legacy: no uid, no email, no role.
          { id: 'legacy-1', name: 'Legacy Account' },
        ],
      },
    });
    signIn('admin1');

    const res = await get(USERS, { token: tokenFor('admin1') });

    assert.equal(res.status, 200, JSON.stringify(res.body));
    const items = res.body.data.items;
    assert.equal(items.length, 2);
    const legacy = items.find((u) => u.id === 'legacy-1');
    assert.ok(legacy, 'a document without optional fields is still listed');
    assert.equal(legacy.name, 'Legacy Account');
    // The API returns what is stored; nothing is invented for missing fields.
    assert.equal(legacy.role, undefined);
  });

  it('keeps the list admin-only', async () => {
    reset({ collections: { users: users('client1') } });
    signIn('client1');

    const res = await get(USERS, { token: tokenFor('client1') });
    assert.equal(res.status, 403);
  });

  it('keeps role management admin-only', async () => {
    reset({ collections: { users: users('client1', 'admin1') } });

    signIn('client1');
    const denied = await fetchRoleChange('/api/users/client-1/role', tokenFor('client1'));
    assert.equal(denied.status, 403);
    assert.equal(profileOf('client-1').role, 'client');

    signIn('admin1');
    const allowed = await fetchRoleChange('/api/users/client-1/role', tokenFor('admin1'));
    assert.equal(allowed.status, 200, JSON.stringify(allowed.body));
    assert.equal(profileOf('client-1').role, 'lawyer');
  });
});

/// Small helper: PATCH is not exported by the harness's convenience wrappers
/// in a form that takes a body here, so go through `request` semantics.
async function fetchRoleChange(path, token) {
  const { request } = await import('./helpers/harness.js');
  return request('PATCH', path, { token, body: { role: 'lawyer' } });
}
