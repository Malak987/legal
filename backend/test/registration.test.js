/**
 * Profile provisioning: `POST /api/users/me`.
 *
 * Registration is split in two. The client SDK creates the Firebase
 * Authentication account (so the password never reaches this server), then the
 * authenticated client calls this route to create the matching Firestore
 * document at `users/{uid}`.
 *
 * The tests below pin the security properties of that split:
 *   - the uid comes from the verified token, never from the body;
 *   - the role is always `client`, whatever the body asks for;
 *   - an existing profile is a 409, never an overwrite (so nobody can reset an
 *     administrator's document, or their own, through this route).
 *
 * Duplicate-email rejection itself belongs to Firebase Authentication
 * (`auth/email-already-in-use`, surfaced by the Flutter client); Firebase does
 * not allow two accounts to share an address, so this route cannot observe it.
 */

import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  failWritesTo,
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

/// A verified caller whose profile does not exist yet — a fresh registrant.
function signInFreshAccount(uid = 'new-user-1', email = 'new-user-1@example.com') {
  setUser({ uid, role: 'client', name: 'New User', email, token: `token-${uid}` });
}

const profileOf = (uid) => docs('users').find((u) => u.id === uid);

beforeEach(() => reset({ collections: { users: [], cases: [] } }));

describe('POST /users/me: provisions the caller\'s own profile', () => {
  it('creates users/{uid} with the default client role', async () => {
    signInFreshAccount();

    const res = await post(ME, {
      token: 'token-new-user-1',
      body: { name: 'Amina Saleh', phone: '+20 100 000 0000' },
    });

    assert.equal(res.status, 201, JSON.stringify(res.body));
    assert.equal(res.body.success, true);
    assert.equal(res.body.message, 'Profile created');

    // Stored document: keyed by the uid, with the client role.
    const stored = profileOf('new-user-1');
    assert.ok(stored, 'a users/new-user-1 document must exist');
    assert.equal(stored.role, 'client');
    assert.equal(stored.name, 'Amina Saleh');
    assert.equal(stored.phone, '+20 100 000 0000');
    assert.equal(stored.email, 'new-user-1@example.com');
    assert.equal(stored.uid, 'new-user-1');

    // Response mirrors the stored document.
    assert.equal(res.body.data.id, 'new-user-1');
    assert.equal(res.body.data.role, 'client');
  });

  it('stamps the document with timestamps', async () => {
    signInFreshAccount();

    await post(ME, { token: 'token-new-user-1', body: { name: 'Amina Saleh' } });

    const stored = profileOf('new-user-1');
    assert.ok(stored.createdAt, 'createdAt must be written');
    assert.ok(stored.updatedAt, 'updatedAt must be written');
  });

  it('accepts an empty phone/avatar/address', async () => {
    signInFreshAccount();

    const res = await post(ME, {
      token: 'token-new-user-1',
      body: { name: 'Amina Saleh', phone: '', avatar: '', address: '' },
    });

    assert.equal(res.status, 201, JSON.stringify(res.body));
    assert.equal(profileOf('new-user-1').role, 'client');
  });
});

describe('POST /users/me: the identity comes from the token', () => {
  it('ignores uid/userId in the body and cannot provision somebody else', async () => {
    reset({ collections: { users: users('admin1') } });
    signInFreshAccount();

    const res = await post(ME, {
      token: 'token-new-user-1',
      body: { name: 'Impostor', uid: 'admin-1', userId: 'admin-1' },
    });

    assert.equal(res.status, 201, JSON.stringify(res.body));
    assert.equal(res.body.data.id, 'new-user-1', 'the uid is the verified one');

    // The administrator's document is untouched.
    const admin = profileOf('admin-1');
    assert.equal(admin.role, 'admin');
    assert.equal(admin.name, 'Admin One');
    assert.equal(admin.updatedAt, undefined, 'no write may touch another profile');
  });

  it('takes the email from the token, not from the body', async () => {
    signInFreshAccount('new-user-1', 'real@example.com');

    const res = await post(ME, {
      token: 'token-new-user-1',
      body: { name: 'Real Owner', email: 'victim@example.com' },
    });

    assert.equal(res.status, 201, JSON.stringify(res.body));
    assert.equal(profileOf('new-user-1').email, 'real@example.com');
  });
});

describe('POST /users/me: privilege cannot be self-assigned', () => {
  it('stores `client` when the body asks for `admin`', async () => {
    signInFreshAccount();

    const res = await post(ME, {
      token: 'token-new-user-1',
      body: { name: 'Climber', role: 'admin' },
    });

    assert.equal(res.status, 201, JSON.stringify(res.body));
    assert.equal(res.body.data.role, 'client');
    assert.equal(profileOf('new-user-1').role, 'client');
  });

  it('stores `client` when the body asks for `lawyer`', async () => {
    signInFreshAccount();

    const res = await post(ME, {
      token: 'token-new-user-1',
      body: { name: 'Wannabe Lawyer', role: 'lawyer' },
    });

    assert.equal(res.status, 201, JSON.stringify(res.body));
    assert.equal(profileOf('new-user-1').role, 'client');
  });

  it('cannot be used to re-write an existing admin as anything else', async () => {
    reset({ collections: { users: users('admin1') } });
    signIn('admin1');

    const res = await post(ME, {
      token: tokenFor('admin1'),
      body: { name: 'Renamed Admin', role: 'client' },
    });

    assert.equal(res.status, 409, JSON.stringify(res.body));
    assert.equal(profileOf('admin-1').role, 'admin');
    assert.equal(profileOf('admin-1').name, 'Admin One', 'nothing is overwritten');
  });
});

describe('POST /users/me: an existing profile is a conflict', () => {
  it('answers 409 and leaves the stored profile alone', async () => {
    reset({ collections: { users: users('client1') } });
    signIn('client1');

    const res = await post(ME, {
      token: tokenFor('client1'),
      body: { name: 'Changed Name' },
    });

    assert.equal(res.status, 409, JSON.stringify(res.body));
    assert.equal(res.body.success, false);
    assert.match(res.body.message, /already exists/i);
    // The stored document is not echoed on conflict.
    assert.equal(res.body.data, undefined);
    // And it is not modified.
    assert.equal(profileOf('client-1').name, 'Client One');
  });

  it('is idempotent-safe: a retried request still cannot create a second one', async () => {
    signInFreshAccount();

    const first = await post(ME, {
      token: 'token-new-user-1',
      body: { name: 'Amina Saleh' },
    });
    const second = await post(ME, {
      token: 'token-new-user-1',
      body: { name: 'Amina Saleh' },
    });

    assert.equal(first.status, 201);
    assert.equal(second.status, 409);
    assert.equal(docs('users').filter((u) => u.id === 'new-user-1').length, 1);
  });
});

describe('POST /users/me: authentication is required', () => {
  it('rejects a request with no token', async () => {
    signInFreshAccount();

    const res = await post(ME, { body: { name: 'Anonymous' } });

    assert.equal(res.status, 401);
    assert.equal(res.body.success, false);
    assert.equal(docs('users').length, 0, 'nothing may be written');
  });

  it('rejects a token that does not verify', async () => {
    signInFreshAccount();

    const res = await post(ME, {
      token: 'not-a-valid-token',
      body: { name: 'Forged' },
    });

    assert.equal(res.status, 401);
    assert.equal(docs('users').length, 0, 'nothing may be written');
  });

  it('rejects an empty bearer token', async () => {
    const res = await post(ME, { token: '', body: { name: 'Nobody' } });

    assert.equal(res.status, 401);
    assert.equal(docs('users').length, 0);
  });
});

describe('POST /users/me: body validation', () => {
  it('rejects a missing name', async () => {
    signInFreshAccount();

    const res = await post(ME, { token: 'token-new-user-1', body: {} });

    assert.equal(res.status, 400);
    assert.equal(res.body.message, 'Validation failed.');
    assert.match(res.body.errors.join(' '), /name/);
    assert.equal(docs('users').length, 0);
  });

  it('rejects a name that is too short', async () => {
    signInFreshAccount();

    const res = await post(ME, {
      token: 'token-new-user-1',
      body: { name: 'A' },
    });

    assert.equal(res.status, 400);
    assert.equal(docs('users').length, 0);
  });

  it('rejects a non-string name', async () => {
    signInFreshAccount();

    const res = await post(ME, {
      token: 'token-new-user-1',
      body: { name: { first: 'Amina' } },
    });

    assert.equal(res.status, 400);
    assert.equal(docs('users').length, 0);
  });
});

describe('POST /users/me: a failed write leaves nothing behind', () => {
  it('answers 5xx and creates no document when Firestore rejects the write', async () => {
    signInFreshAccount();
    failWritesTo('users');

    const res = await post(ME, {
      token: 'token-new-user-1',
      body: { name: 'Unlucky' },
    });

    assert.ok(res.status >= 500, `expected a 5xx, got ${res.status}`);
    assert.equal(res.body.success, false);
    assert.equal(docs('users').length, 0, 'no partial profile may be written');
  });
});

describe('POST /users/me: the caller cannot target another account', () => {
  it('has no route for provisioning somebody else by path', async () => {
    reset({ collections: { users: users('admin1') } });
    signInFreshAccount();

    const res = await post('/api/users/admin-1', {
      token: 'token-new-user-1',
      body: { name: 'Impostor' },
    });

    assert.equal(res.status, 404, 'only /users/me exists');
    assert.equal(docs('users').filter((u) => u.id === 'admin-1').length, 1);
    assert.equal(docs('users').length, 1, 'no document was created');
  });
});

describe('POST /users/me: the profile reaches the admin dashboard', () => {
  it('appears in GET /api/users for an administrator', async () => {
    // The original defect: an account created only in Firebase Authentication
    // never appeared in the panel, which lists Firestore. Provisioning closes
    // that gap, so the new user must show up in the admin list.
    reset({ collections: { users: users('admin1') } });
    signInFreshAccount();

    const created = await post(ME, {
      token: 'token-new-user-1',
      body: { name: 'Amina Saleh', phone: '+20 100 000 0000' },
    });
    assert.equal(created.status, 201);

    signIn('admin1');
    const list = await get('/api/users', { token: tokenFor('admin1') });

    assert.equal(list.status, 200);
    const names = list.body.data.items.map((u) => u.name);
    assert.ok(names.includes('Amina Saleh'), 'the new client must be listed');
    assert.ok(names.includes('Admin One'), 'existing profiles are untouched');
  });
});
