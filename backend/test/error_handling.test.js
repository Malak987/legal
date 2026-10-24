/**
 * Wave 1.3 — error responses must not hand internals to the caller.
 *
 * Two things are pinned here:
 *   - a 5xx in production answers with a fixed message and no stack;
 *   - a failed token verification no longer reports why it failed.
 *
 * Development keeps the detailed message on purpose: that is what makes a
 * failing test readable. The existing test suite runs without NODE_ENV set,
 * so nothing else changes for it.
 */

import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  failWritesTo,
  get,
  post,
  reset,
  signIn,
  startApp,
  stopApp,
  tokenFor,
  users,
} from './helpers/harness.js';

before(startApp);
after(stopApp);

const ORIGINAL_ENV = process.env.NODE_ENV;

after(() => {
  if (ORIGINAL_ENV === undefined) delete process.env.NODE_ENV;
  else process.env.NODE_ENV = ORIGINAL_ENV;
});

function seed() {
  return {
    users: users('admin1', 'client1'),
    wallets: [{ id: 'client-1', userId: 'client-1', balance: 10, currency: 'USD' }],
    wallet_transactions: [],
  };
}

describe('errors 1.3: internal details stay in the logs', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('returns a generic message for 5xx in production', async () => {
    process.env.NODE_ENV = 'production';
    signIn('admin1');
    failWritesTo('wallets');

    const res = await post('/api/wallet/transactions', {
      token: tokenFor('admin1'),
      body: { userId: 'client-1', type: 'credit', amount: 5 },
    });

    assert.equal(res.status, 500);
    assert.equal(res.body.message, 'Internal server error.');
    assert.equal(res.body.stack, undefined, 'no stack in production');
    assert.doesNotMatch(JSON.stringify(res.body), /simulated write failure/);
  });

  it('keeps the detailed message outside production (for tests and dev)', async () => {
    process.env.NODE_ENV = 'development';
    signIn('admin1');
    failWritesTo('wallet_transactions');

    const res = await post('/api/wallet/transactions', {
      token: tokenFor('admin1'),
      body: { userId: 'client-1', type: 'credit', amount: 5 },
    });

    assert.equal(res.status, 500);
    assert.match(res.body.message, /simulated write failure/);
  });

  it('still returns 4xx messages verbatim in production', async () => {
    process.env.NODE_ENV = 'production';
    signIn('admin1');

    const res = await post('/api/wallet/transactions', {
      token: tokenFor('admin1'),
      body: { userId: 'client-1', type: 'credit', amount: -5 },
    });

    assert.equal(res.status, 400);
    assert.match(res.body.message, /amount must be a positive number/);
  });
});

describe('errors 1.3: auth failures do not explain themselves', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('does not echo the token-verification error', async () => {
    signIn('client1');

    const res = await get('/api/wallet/client-1', { token: 'not-a-real-token' });

    assert.equal(res.status, 401);
    assert.equal(res.body.message, 'Invalid or expired Supabase access token.');
    assert.equal(res.body.error, undefined);
    assert.doesNotMatch(JSON.stringify(res.body), /Decoding Firebase ID token failed/);
  });
});

describe('errors 1.3: identity comes from the token, not the profile document', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('ignores a uid stored on the profile document', async () => {
    reset({
      collections: {
        ...seed(),
        users: [
          // A bad migration or a manual edit left somebody else's uid here.
          { id: 'client-1', uid: 'admin-1', name: 'Sneaky', role: 'client', email: 'client1@example.com' },
        ],
      },
    });
    signIn('client1');

    const res = await get('/api/wallet/client-1', { token: tokenFor('client1') });

    assert.equal(res.status, 200, 'the caller is client-1, and client-1 owns this wallet');

    const forbidden = await get('/api/wallet/admin-1', { token: tokenFor('client1') });
    assert.equal(forbidden.status, 403, 'the planted uid must not grant admin scope');
  });
});
