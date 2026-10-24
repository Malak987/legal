/**
 * Supabase profile lifecycle contract.
 *
 * `POST /api/users/me` is intentionally non-mutating: a trusted database trigger
 * creates profiles after Supabase Auth email confirmation. The Express route
 * must not create a profile, assign a role, copy client-provided identity, or
 * overwrite a profile. These tests exercise the real middleware and route with
 * the isolated request/Auth fixtures in `helpers/harness.js`.
 */

import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  docs,
  get,
  post,
  reset,
  setUser,
  signIn,
  startApp,
  stopApp,
  tokenFor,
  users,
} from './helpers/harness.js';

const ME = '/api/users/me';

before(startApp);
after(stopApp);
beforeEach(() => reset({ collections: { users: [], cases: [] } }));

function signInWithoutProfile(uid = 'new-user-1', email = 'new-user-1@example.com') {
  setUser({ uid, email, role: 'client', name: 'New User', token: `token-${uid}` });
  return `token-${uid}`;
}

const profileOf = (uid) => docs('users').find((user) => user.id === uid);

describe('POST /api/users/me: profile creation belongs to Supabase Auth lifecycle', () => {
  it('returns a non-mutating conflict for a verified caller with no profile', async () => {
    const token = signInWithoutProfile();
    const response = await post(ME, {
      token,
      body: { name: 'Amina Saleh', phone: '+20 100 000 0000' },
    });

    assert.equal(response.status, 409);
    assert.equal(response.body.success, false);
    assert.equal(
      response.body.message,
      'Profile creation is managed by the Supabase Auth lifecycle.',
    );
    assert.equal(profileOf('new-user-1'), undefined);
    assert.equal(docs('users').length, 0);
  });

  it('does not accept body identity or role fields as a profile-provisioning path', async () => {
    const token = signInWithoutProfile('new-user-2', 'real@example.com');
    const response = await post(ME, {
      token,
      body: {
        name: 'Spoofed',
        email: 'victim@example.com',
        uid: 'admin-1',
        id: 'admin-1',
        userId: 'admin-1',
        role: 'admin',
      },
    });

    assert.equal(response.status, 409);
    assert.equal(profileOf('new-user-2'), undefined);
    assert.equal(profileOf('admin-1'), undefined);
    assert.equal(docs('users').length, 0);
  });

  it('never overwrites an existing profile, even when the request repeats', async () => {
    reset({ collections: { users: users('client1') } });
    signIn('client1');

    const before = profileOf('client-1');
    const first = await post(ME, {
      token: tokenFor('client1'),
      body: { name: 'Changed Name', role: 'admin' },
    });
    const second = await post(ME, {
      token: tokenFor('client1'),
      body: { name: 'Another Name', role: 'admin' },
    });

    assert.equal(first.status, 409);
    assert.equal(second.status, 409);
    assert.deepEqual(profileOf('client-1'), before);
  });
});

describe('GET /api/users/me: only the linked profile is returned', () => {
  it('answers 404 while the Auth lifecycle has not created a profile', async () => {
    const token = signInWithoutProfile();
    const response = await get(ME, { token });

    assert.equal(response.status, 404);
    assert.equal(response.body.success, false);
    assert.equal(docs('users').length, 0);
  });

  it('returns an existing profile without creating or rewriting it', async () => {
    reset({ collections: { users: users('client1') } });
    signIn('client1');
    const before = profileOf('client-1');

    const response = await get(ME, { token: tokenFor('client1') });

    assert.equal(response.status, 200);
    assert.equal(response.body.data.id, 'client-1');
    assert.deepEqual(profileOf('client-1'), before);
  });
});

describe('users/me: authentication is required before profile lifecycle checks', () => {
  it('rejects a missing bearer token and writes nothing', async () => {
    signInWithoutProfile();
    const response = await post(ME, { body: { name: 'Anonymous' } });

    assert.equal(response.status, 401);
    assert.equal(docs('users').length, 0);
  });

  it('rejects an invalid token and writes nothing', async () => {
    signInWithoutProfile();
    const response = await post(ME, {
      token: 'not-a-valid-token',
      body: { name: 'Forged' },
    });

    assert.equal(response.status, 401);
    assert.equal(docs('users').length, 0);
  });
});
