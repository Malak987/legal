/**
 * Authorization regression tests for the wallet routes.
 *
 * Covers two defects:
 *   1. `GET /api/wallet/:userId` issued `where('userId','==').orderBy('createdAt')`,
 *      which needs a COMPOSITE index that is not deployed — Firestore answered
 *      `9 FAILED_PRECONDITION` and the route returned 500.
 *   2. `POST /api/wallet/transactions` trusted a `userId` from the body.
 */

import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  docs,
  failWritesTo,
  get,
  post,
  queries,
  reset,
  signIn,
  startApp,
  stopApp,
  tokenFor,
  users,
} from './helpers/harness.js';

const BASE = '/api/wallet';

before(startApp);
after(stopApp);

const at = (iso) => ({ toMillis: () => Date.parse(iso) });

/**
 * 25 transactions for client-1 in scrambled order, mixing every timestamp
 * representation Firestore (or a serialised document) can hand back, plus one
 * document with no usable timestamp at all.
 */
function transactions() {
  const list = [];
  for (let i = 1; i <= 25; i += 1) {
    const day = String(i).padStart(2, '0');
    let createdAt;
    if (i % 4 === 0) createdAt = at(`2026-01-${day}T10:00:00Z`);
    else if (i % 4 === 1) createdAt = `2026-01-${day}T10:00:00Z`;
    else if (i % 4 === 2) createdAt = Date.parse(`2026-01-${day}T10:00:00Z`);
    else createdAt = { _seconds: Date.parse(`2026-01-${day}T10:00:00Z`) / 1000 };

    list.push({ id: `tx-${i}`, userId: 'client-1', type: 'credit', amount: 1, createdAt });
  }
  list.push({ id: 'tx-ownerless-date', userId: 'client-1', type: 'debit', amount: 1 });
  list.push({ id: 'tx-garbage-date', userId: 'client-1', type: 'debit', amount: 1, createdAt: 'not-a-date' });
  return list;
}

function seed() {
  return {
    users: users('client1', 'client2', 'admin1'),
    wallets: [{ id: 'client-1', userId: 'client-1', balance: 500, currency: 'USD' }],
    wallet_transactions: [
      ...transactions(),
      { id: 'tx-other', userId: 'client-2', type: 'credit', amount: 999, createdAt: at('2026-02-01T00:00:00Z') },
    ],
  };
}

describe('wallet: transaction history', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('answers 200 instead of 500 and returns newest first', async () => {
    signIn('client1');

    const res = await get(`${BASE}/client-1`, { token: tokenFor('client1') });

    assert.equal(res.status, 200);
    assert.equal(res.body.success, true);
    assert.equal(res.body.data.balance, 500);

    const dates = res.body.data.transactions.map((t) => t.createdAt);
    assert.equal(dates.length, 20, 'default page of 20 transactions');
    assert.equal(res.body.data.transactions[0].id, 'tx-25');
    assert.equal(res.body.data.transactions[19].id, 'tx-6');
  });

  it('never combines where() with orderBy() on wallet_transactions', async () => {
    signIn('client1');

    await get(`${BASE}/client-1`, { token: tokenFor('client1') });

    const history = queries().filter((q) => q.collection === 'wallet_transactions');
    assert.ok(history.length > 0, 'the route queried wallet_transactions');
    for (const query of history) {
      assert.deepEqual(query.orderBy, [], 'no orderBy — a composite index would be required');
    }
    // The ownership filter must stay on the server: never read the whole
    // collection and filter afterwards.
    assert.ok(history.some((q) => q.where.some((w) => w.field === 'userId' && w.value === 'client-1')));
  });

  it('only returns the caller\'s own transactions', async () => {
    signIn('client1');

    const res = await get(`${BASE}/client-1`, { token: tokenFor('client1') });

    assert.equal(res.status, 200);
    for (const tx of res.body.data.transactions) {
      assert.equal(tx.userId, 'client-1');
    }
    assert.equal(res.body.data.transactions.some((t) => t.id === 'tx-other'), false);
  });

  it('keeps unusable timestamps in the result set, sorted last', async () => {
    reset({
      collections: {
        users: users('client1'),
        wallet_transactions: [
          { id: 'tx-missing', userId: 'client-1', amount: 1 },
          { id: 'tx-garbage', userId: 'client-1', amount: 1, createdAt: 'not-a-date' },
          { id: 'tx-new', userId: 'client-1', amount: 1, createdAt: at('2026-03-01T00:00:00Z') },
          { id: 'tx-old', userId: 'client-1', amount: 1, createdAt: at('2026-01-01T00:00:00Z') },
        ],
      },
    });
    signIn('client1');

    const res = await get(`${BASE}/client-1`, { token: tokenFor('client1') });

    assert.equal(res.status, 200);
    const ids = res.body.data.transactions.map((t) => t.id);
    // Undated documents must not be dropped, and must not poison the sort.
    assert.equal(ids.length, 4);
    assert.deepEqual(ids.slice(0, 2), ['tx-new', 'tx-old']);
    assert.deepEqual(ids.slice(2).sort(), ['tx-garbage', 'tx-missing']);
  });

  it('denies reading another user\'s wallet', async () => {
    signIn('client1');

    const res = await get(`${BASE}/client-2`, { token: tokenFor('client1') });

    assert.equal(res.status, 403);
    assert.equal(res.body.success, false);
  });

  it('lets an admin read any wallet', async () => {
    signIn('admin1');

    const res = await get(`${BASE}/client-2`, { token: tokenFor('admin1') });

    assert.equal(res.status, 200);
    assert.equal(res.body.data.balance, 0);
  });
});

describe('wallet: transactions', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('rejects a forged userId and writes nothing', async () => {
    signIn('client1');

    const res = await post(`${BASE}/transactions`, {
      token: tokenFor('client1'),
      body: { userId: 'client-2', type: 'credit', amount: 1000 },
    });

    assert.equal(res.status, 403);
    assert.equal(res.body.success, false);
    assert.equal(docs('wallet_transactions').some((t) => t.userId === 'client-2' && t.amount === 1000), false);
    assert.equal(docs('wallets').find((w) => w.id === 'client-2'), undefined);
  });

  // WAVE 1.1 — this used to assert that a client could top up its own wallet.
  // Owning the wallet is not evidence that money was received, so crediting is
  // now an administrator-only operation and the test asserts the denial.
  it('denies a user crediting their own wallet and changes nothing', async () => {
    signIn('client1');
    const before = docs('wallets').find((w) => w.id === 'client-1').balance;

    const res = await post(`${BASE}/transactions`, {
      token: tokenFor('client1'),
      body: { userId: 'client-1', type: 'credit', amount: 250 },
    });

    assert.equal(res.status, 403);
    assert.equal(res.body.success, false);
    assert.equal(docs('wallets').find((w) => w.id === 'client-1').balance, before);
    assert.equal(docs('wallet_transactions').some((t) => t.amount === 250), false);
  });

  it('lets an admin credit another user\'s wallet', async () => {
    signIn('admin1');

    const res = await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body: { userId: 'client-2', type: 'credit', amount: 40 },
    });

    assert.equal(res.status, 201);
    assert.equal(res.body.data.balance, 40);
    assert.equal(docs('wallets').find((w) => w.id === 'client-2').balance, 40);
  });

  it('rejects an unauthenticated transaction', async () => {
    const res = await post(`${BASE}/transactions`, {
      body: { userId: 'client-1', type: 'credit', amount: 10 },
    });

    assert.equal(res.status, 401);
    assert.equal(docs('wallet_transactions').some((t) => t.amount === 10), false);
  });
});

/* =====================================================================
 * WAVE 1.1 — money integrity
 *
 * The independent review proved any signed-in user could create a `credit`
 * transaction of any size on their own wallet, and that `debit` with a
 * negative amount *increased* the balance. These tests pin the fix.
 * ===================================================================*/

// 25 generated rows + 2 rows with unusable timestamps (see transactions()).
const LEDGER_ROWS = 27;

const walletOf = (uid) => docs('wallets').find((w) => w.id === uid)?.balance;
const txOf = (uid) => docs('wallet_transactions').filter((t) => t.userId === uid);

describe('wallet 1.1: a normal user cannot create money', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('denies self-credit and leaves the balance untouched', async () => {
    signIn('client1');

    const res = await post(`${BASE}/transactions`, {
      token: tokenFor('client1'),
      body: { userId: 'client-1', type: 'credit', amount: 1_000_000 },
    });

    assert.equal(res.status, 403);
    assert.equal(res.body.success, false);
    assert.equal(walletOf('client-1'), 500, 'balance must not move');
    assert.equal(txOf('client-1').length, LEDGER_ROWS, 'no ledger row may be added');
  });

  it('denies self-credit even for a tiny amount', async () => {
    signIn('client1');

    const res = await post(`${BASE}/transactions`, {
      token: tokenFor('client1'),
      body: { userId: 'client-1', type: 'credit', amount: 0.01 },
    });

    assert.equal(res.status, 403);
    assert.equal(walletOf('client-1'), 500);
  });

  it('denies a lawyer crediting their own wallet', async () => {
    reset({
      collections: {
        users: users('lawyer1'),
        wallets: [{ id: 'lawyer-1', userId: 'lawyer-1', balance: 0, currency: 'USD' }],
        wallet_transactions: [],
      },
    });
    signIn('lawyer1');

    const res = await post(`${BASE}/transactions`, {
      token: tokenFor('lawyer1'),
      body: { userId: 'lawyer-1', type: 'credit', amount: 999 },
    });

    assert.equal(res.status, 403);
    assert.equal(walletOf('lawyer-1'), 0);
    assert.equal(txOf('lawyer-1').length, 0);
  });
});

describe('wallet 1.1: amount validation', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('rejects a debit with a negative amount and does not credit the wallet', async () => {
    signIn('client1');

    const res = await post(`${BASE}/transactions`, {
      token: tokenFor('client1'),
      body: { userId: 'client-1', type: 'debit', amount: -500 },
    });

    assert.equal(res.status, 400);
    assert.equal(res.body.success, false);
    // The old code did `current - amount` in dollars: -500 became +500.
    assert.equal(walletOf('client-1'), 500);
    assert.equal(txOf('client-1').length, LEDGER_ROWS);
  });

  for (const amount of [0, -0.01, -1, '100', null, undefined, true, {}, []]) {
    it(`rejects amount ${JSON.stringify(amount)} for a debit`, async () => {
      signIn('client1');

      const res = await post(`${BASE}/transactions`, {
        token: tokenFor('client1'),
        body: { userId: 'client-1', type: 'debit', amount },
      });

      assert.equal(res.status, 400);
      assert.equal(walletOf('client-1'), 500);
    });
  }

  for (const amount of [0, -10, '50']) {
    it(`rejects amount ${JSON.stringify(amount)} for an admin credit`, async () => {
      signIn('admin1');

      const res = await post(`${BASE}/transactions`, {
        token: tokenFor('admin1'),
        body: { userId: 'client-1', type: 'credit', amount },
      });

      assert.equal(res.status, 400);
      assert.equal(walletOf('client-1'), 500);
    });
  }

  it('rejects an amount above the financial cap', async () => {
    signIn('admin1');

    const res = await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body: { userId: 'client-1', type: 'credit', amount: 1_000_001 },
    });

    assert.equal(res.status, 400);
    assert.equal(walletOf('client-1'), 500);
  });

  it('rejects an amount with more precision than the currency allows', async () => {
    signIn('admin1');

    const res = await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body: { userId: 'client-1', type: 'credit', amount: 10.005 },
    });

    assert.equal(res.status, 400);
    assert.equal(walletOf('client-1'), 500);
  });

  it('keeps two-decimal amounts exact (no float drift)', async () => {
    reset({
      collections: {
        users: users('admin1', 'client1'),
        wallets: [{ id: 'client-1', userId: 'client-1', balance: 0, currency: 'USD' }],
        wallet_transactions: [],
      },
    });
    signIn('admin1');

    for (const amount of [0.1, 0.2]) {
      const res = await post(`${BASE}/transactions`, {
        token: tokenFor('admin1'),
        body: { userId: 'client-1', type: 'credit', amount },
      });
      assert.equal(res.status, 201);
    }

    // 0.1 + 0.2 must be 0.3, not 0.30000000000000004.
    assert.equal(walletOf('client-1'), 0.3);
  });
});

describe('wallet 1.1: authorized credit still works', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('lets an administrator credit a wallet inside the cap', async () => {
    signIn('admin1');

    const res = await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body: { userId: 'client-1', type: 'credit', amount: 250.75 },
    });

    assert.equal(res.status, 201);
    assert.equal(res.body.data.balance, 750.75);
    assert.equal(walletOf('client-1'), 750.75);
    assert.equal(txOf('client-1').at(-1).type, 'credit');
  });

  it('lets a user debit their own wallet (spending cannot create money)', async () => {
    signIn('client1');

    const res = await post(`${BASE}/transactions`, {
      token: tokenFor('client1'),
      body: { userId: 'client-1', type: 'debit', amount: 125.5 },
    });

    assert.equal(res.status, 201);
    assert.equal(res.body.data.balance, 374.5);
    assert.equal(walletOf('client-1'), 374.5);
  });

  it('denies a user debiting another user\'s wallet', async () => {
    signIn('client1');

    const res = await post(`${BASE}/transactions`, {
      token: tokenFor('client1'),
      body: { userId: 'client-2', type: 'debit', amount: 1 },
    });

    assert.equal(res.status, 403);
    assert.equal(walletOf('client-2'), undefined);
  });

  it('rejects a debit larger than the balance and moves nothing', async () => {
    signIn('client1');

    const res = await post(`${BASE}/transactions`, {
      token: tokenFor('client1'),
      body: { userId: 'client-1', type: 'debit', amount: 500.01 },
    });

    assert.equal(res.status, 400);
    assert.equal(res.body.message, 'Insufficient balance');
    assert.equal(walletOf('client-1'), 500);
  });
});

describe('wallet 1.1: atomicity', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('leaves the balance untouched when the ledger write fails', async () => {
    signIn('admin1');
    const before = walletOf('client-1');

    failWritesTo('wallet_transactions');

    const res = await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body: { userId: 'client-1', type: 'credit', amount: 100 },
    });

    assert.equal(res.status, 500, 'the failure must surface, not be masked');
    assert.equal(walletOf('client-1'), before, 'balance must not be written alone');
    assert.equal(txOf('client-1').length, LEDGER_ROWS, 'no partial ledger row');
  });

  it('does not lose an update when two credits run concurrently', async () => {
    reset({
      collections: {
        users: users('admin1', 'client1'),
        wallets: [{ id: 'client-1', userId: 'client-1', balance: 0, currency: 'USD' }],
        wallet_transactions: [],
      },
    });
    signIn('admin1');

    const [a, b] = await Promise.all([
      post(`${BASE}/transactions`, {
        token: tokenFor('admin1'),
        body: { userId: 'client-1', type: 'credit', amount: 100 },
      }),
      post(`${BASE}/transactions`, {
        token: tokenFor('admin1'),
        body: { userId: 'client-1', type: 'credit', amount: 50 },
      }),
    ]);

    assert.equal(a.status, 201);
    assert.equal(b.status, 201);
    // A lost update would leave 100 (or 50) instead of 150.
    assert.equal(walletOf('client-1'), 150);
    assert.equal(txOf('client-1').length, 2);
  });

  it('does not let two concurrent debits overdraw the wallet', async () => {
    reset({
      collections: {
        users: users('client1'),
        wallets: [{ id: 'client-1', userId: 'client-1', balance: 100, currency: 'USD' }],
        wallet_transactions: [],
      },
    });
    signIn('client1');

    const results = await Promise.all([
      post(`${BASE}/transactions`, {
        token: tokenFor('client1'),
        body: { userId: 'client-1', type: 'debit', amount: 80 },
      }),
      post(`${BASE}/transactions`, {
        token: tokenFor('client1'),
        body: { userId: 'client-1', type: 'debit', amount: 80 },
      }),
    ]);

    const statuses = results.map((r) => r.status).sort();
    assert.deepEqual(statuses, [201, 400], 'exactly one debit may succeed');
    assert.equal(walletOf('client-1'), 20);
    assert.equal(txOf('client-1').length, 1);
  });
});

describe('wallet 1.1: idempotency', () => {
  beforeEach(() => reset({ collections: seed() }));

  it('applies a retried request with the same key only once', async () => {
    signIn('admin1');

    const first = await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body: { userId: 'client-1', type: 'credit', amount: 100, idempotencyKey: 'topup-42' },
    });
    const second = await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body: { userId: 'client-1', type: 'credit', amount: 100, idempotencyKey: 'topup-42' },
    });

    assert.equal(first.status, 201);
    assert.equal(second.status, 200);
    assert.equal(second.body.message, 'Duplicate request ignored');
    assert.equal(walletOf('client-1'), 600, 'credited once, not twice');
    // WAVE 1.2: the raw key is no longer stored; the ledger row references the
    // hashed idempotency record, and exactly one such record exists.
    assert.equal(txOf('client-1').filter((t) => t.idempotencyKeyHash).length, 1);
    assert.equal(docs('wallet_idempotency').length, 1);
    assert.equal(second.body.data.transaction.id, first.body.data.transaction.id);
  });

  it('accepts the standard Idempotency-Key header', async () => {
    signIn('admin1');

    const body = { userId: 'client-1', type: 'credit', amount: 10 };
    const first = await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body,
      headers: { 'Idempotency-Key': 'hdr-1' },
    });
    const second = await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body,
      headers: { 'Idempotency-Key': 'hdr-1' },
    });

    assert.equal(first.status, 201);
    assert.equal(second.status, 200);
    assert.equal(walletOf('client-1'), 510);
  });

  it('keeps different keys as separate transactions', async () => {
    signIn('admin1');

    for (const key of ['a', 'b']) {
      const res = await post(`${BASE}/transactions`, {
        token: tokenFor('admin1'),
        body: { userId: 'client-1', type: 'credit', amount: 5, idempotencyKey: key },
      });
      assert.equal(res.status, 201);
    }

    assert.equal(walletOf('client-1'), 510);
  });

  it('does not let one user\'s key collide with another user\'s', async () => {
    signIn('admin1');

    await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body: { userId: 'client-1', type: 'credit', amount: 5, idempotencyKey: 'same' },
    });
    const other = await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body: { userId: 'client-2', type: 'credit', amount: 5, idempotencyKey: 'same' },
    });

    assert.equal(other.status, 201, 'keys are namespaced per wallet owner');
    assert.equal(walletOf('client-2'), 5);
  });
});

/* =====================================================================
 * WAVE 1.2 — deterministic idempotency, currency integrity, key limits
 *
 * The review (F-04/F-05/F-07/F-15) showed that idempotency relied on a
 * `where()` lookup inside a transaction — which Firestore gives no phantom
 * protection for — that a repeated key with a different amount silently
 * replayed the old result, that a wallet denominated in another currency was
 * silently relabelled "USD", and that long keys were truncated and merged.
 * ===================================================================*/

const idemDocs = () => docs('wallet_idempotency');
const balanceOf = (uid) => docs('wallets').find((w) => w.id === uid)?.balance;

function moneySeed(overrides = {}) {
  return {
    users: users('admin1', 'client1'),
    wallets: [{ id: 'client-1', userId: 'client-1', balance: 1000, currency: 'USD' }],
    wallet_transactions: [],
    ...overrides,
  };
}

describe('wallet 1.2: idempotency key document', () => {
  beforeEach(() => reset({ collections: moneySeed() }));

  it('stores one deterministic idempotency record per (owner, key)', async () => {
    signIn('admin1');

    await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body: { userId: 'client-1', type: 'credit', amount: 25, idempotencyKey: 'order-1' },
    });

    const records = idemDocs();
    assert.equal(records.length, 1);
    // SHA-256 hex — derived, never the raw key.
    assert.match(records[0].id, /^[0-9a-f]{64}$/);
    assert.equal(records[0].userId, 'client-1');
    assert.equal(records[0].amount, 25);
    assert.equal(records[0].currency, 'USD');

    const ledger = docs('wallet_transactions');
    assert.equal(ledger.length, 1);
    assert.equal(ledger[0].idempotencyKeyHash, records[0].id);
    assert.equal(ledger[0].idempotencyKey, undefined, 'raw key is not persisted');
  });

  it('gives the same key a different document per user', async () => {
    reset({
      collections: moneySeed({
        // WAVE 1.3: a transaction now requires the target account to exist.
        users: users('admin1', 'client1', 'client2'),
        wallets: [
          { id: 'client-1', userId: 'client-1', balance: 100, currency: 'USD' },
          { id: 'client-2', userId: 'client-2', balance: 100, currency: 'USD' },
        ],
      }),
    });
    signIn('admin1');

    await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body: { userId: 'client-1', type: 'credit', amount: 10, idempotencyKey: 'shared' },
    });
    await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body: { userId: 'client-2', type: 'credit', amount: 10, idempotencyKey: 'shared' },
    });

    assert.equal(idemDocs().length, 2, 'document ids are namespaced by owner');
    assert.equal(balanceOf('client-1'), 110);
    assert.equal(balanceOf('client-2'), 110);
  });
});

describe('wallet 1.2: repeated key with a different payload is a conflict', () => {
  beforeEach(() => reset({ collections: moneySeed() }));

  const first = () =>
    post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body: { userId: 'client-1', type: 'credit', amount: 100, idempotencyKey: 'K' },
    });

  it('returns 409 when the same key is retried with a different amount', async () => {
    signIn('admin1');
    await first();

    const res = await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body: { userId: 'client-1', type: 'credit', amount: 500, idempotencyKey: 'K' },
    });

    assert.equal(res.status, 409);
    assert.equal(res.body.success, false);
    assert.equal(balanceOf('client-1'), 1100, 'no money moved');
    assert.equal(docs('wallet_transactions').length, 1, 'no second ledger row');
    assert.equal(res.body.message, 'idempotencyKey was already used for a different transaction.');
    assert.equal(res.body.details, undefined, 'the API does not expose prior transaction details');
  });

  it('returns 409 when the same key is retried with a different type', async () => {
    signIn('admin1');
    await first();

    const res = await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body: { userId: 'client-1', type: 'debit', amount: 100, idempotencyKey: 'K' },
    });

    assert.equal(res.status, 409);
    assert.equal(balanceOf('client-1'), 1100);
    assert.equal(docs('wallet_transactions').length, 1);
  });

  it('still replays the original result for an identical retry', async () => {
    signIn('admin1');
    const a = await first();
    const b = await first();

    assert.equal(a.status, 201);
    assert.equal(b.status, 200);
    assert.equal(b.body.data.transaction.id, a.body.data.transaction.id);
    assert.equal(balanceOf('client-1'), 1100);
    assert.equal(docs('wallet_transactions').length, 1);
  });
});

describe('wallet 1.2: idempotency key limits', () => {
  beforeEach(() => reset({ collections: moneySeed() }));

  const postWithKey = (key) =>
    post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body: { userId: 'client-1', type: 'credit', amount: 10, idempotencyKey: key },
    });

  it('accepts a key of exactly the maximum length', async () => {
    signIn('admin1');

    const res = await postWithKey('k'.repeat(128));

    assert.equal(res.status, 201);
    assert.equal(idemDocs().length, 1);
  });

  it('rejects a longer key instead of truncating it', async () => {
    signIn('admin1');

    const res = await postWithKey('k'.repeat(129));

    assert.equal(res.status, 400);
    assert.equal(res.body.message, 'idempotencyKey must be at most 128 characters');
    assert.equal(docs('wallet_transactions').length, 0);
    assert.equal(idemDocs().length, 0);
    assert.equal(balanceOf('client-1'), 1000);
  });

  it('does not merge two keys that differ only after the old truncation point', async () => {
    signIn('admin1');
    const prefix = 'x'.repeat(200);

    const a = await postWithKey(`${prefix}-A`);
    const b = await postWithKey(`${prefix}-B`);

    // Both are rejected for length now — the point is that they can never be
    // conflated into one operation, which silent truncation would have done.
    assert.equal(a.status, 400);
    assert.equal(b.status, 400);
    assert.equal(docs('wallet_transactions').length, 0);
  });

  it('rejects a non-string key', async () => {
    signIn('admin1');

    const res = await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body: { userId: 'client-1', type: 'credit', amount: 10, idempotencyKey: { a: 1 } },
    });

    assert.equal(res.status, 400);
    assert.equal(balanceOf('client-1'), 1000);
  });
});

describe('wallet 1.2: wallet currency is never reinterpreted', () => {
  beforeEach(() =>
    reset({
      collections: moneySeed({
        wallets: [{ id: 'client-1', userId: 'client-1', balance: 5000, currency: 'EGP' }],
      }),
    }),
  );

  it('refuses a transaction on a non-USD wallet without changing it', async () => {
    signIn('admin1');

    const res = await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body: { userId: 'client-1', type: 'credit', amount: 10 },
    });

    assert.equal(res.status, 409);
    assert.match(res.body.message, /EGP/);

    const wallet = docs('wallets').find((w) => w.id === 'client-1');
    assert.equal(wallet.currency, 'EGP', 'currency must not be relabelled');
    assert.equal(wallet.balance, 5000);
    assert.equal(docs('wallet_transactions').length, 0);
  });

  it('refuses a debit on a non-USD wallet too', async () => {
    signIn('client1');

    const res = await post(`${BASE}/transactions`, {
      token: tokenFor('client1'),
      body: { userId: 'client-1', type: 'debit', amount: 10 },
    });

    assert.equal(res.status, 409);
    assert.equal(balanceOf('client-1'), 5000);
  });

  it('creates the wallet in USD when none exists yet', async () => {
    reset({
      collections: {
        // WAVE 1.3: the account must exist; the point of this test is that the
        // WALLET is created lazily, in USD, not that unknown ids are accepted.
        users: [
          ...users('admin1'),
          { id: 'new-user', uid: 'new-user', name: 'New User', role: 'client' },
        ],
        wallets: [],
        wallet_transactions: [],
      },
    });
    signIn('admin1');

    const res = await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body: { userId: 'new-user', type: 'credit', amount: 42.5 },
    });

    assert.equal(res.status, 201);
    const wallet = docs('wallets').find((w) => w.id === 'new-user');
    assert.equal(wallet.currency, 'USD');
    assert.equal(wallet.balance, 42.5);
  });
});

describe('wallet 1.2: concurrency and failure still hold', () => {
  beforeEach(() => reset({ collections: moneySeed() }));

  it('applies a concurrently retried key exactly once', async () => {
    signIn('admin1');
    const body = { userId: 'client-1', type: 'credit', amount: 100, idempotencyKey: 'race' };

    const results = await Promise.all([
      post(`${BASE}/transactions`, { token: tokenFor('admin1'), body }),
      post(`${BASE}/transactions`, { token: tokenFor('admin1'), body }),
      post(`${BASE}/transactions`, { token: tokenFor('admin1'), body }),
    ]);

    assert.equal(balanceOf('client-1'), 1100, 'exactly one credit applied');
    assert.equal(docs('wallet_transactions').length, 1);
    assert.equal(idemDocs().length, 1);
    assert.deepEqual(
      results.map((r) => r.status).sort(),
      [200, 200, 201],
      'one create and two replays',
    );
    // Guards the guard: if the harness ever went back to serialising
    // transactions, this race would pass for the wrong reason.
    assert.ok(
      globalThis.__fx.txAttempts > 3,
      'the three requests must have genuinely contended and retried',
    );
  });

  it('does not lose an update when many credits race', async () => {
    signIn('admin1');

    await Promise.all(
      Array.from({ length: 5 }, (_, i) =>
        post(`${BASE}/transactions`, {
          token: tokenFor('admin1'),
          body: { userId: 'client-1', type: 'credit', amount: 10, idempotencyKey: `c-${i}` },
        }),
      ),
    );

    assert.equal(balanceOf('client-1'), 1050);
    assert.equal(docs('wallet_transactions').length, 5);
    assert.equal(idemDocs().length, 5);
  });

  it('rolls back balance, ledger and idempotency record together on failure', async () => {
    signIn('admin1');
    failWritesTo('wallet_idempotency');

    const res = await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body: { userId: 'client-1', type: 'credit', amount: 100, idempotencyKey: 'will-fail' },
    });

    assert.equal(res.status, 500);
    assert.equal(balanceOf('client-1'), 1000, 'balance untouched');
    assert.equal(docs('wallet_transactions').length, 0, 'ledger untouched');
    assert.equal(idemDocs().length, 0, 'idempotency record untouched');
  });

  it('allows a retry with the same key after a rolled-back attempt', async () => {
    signIn('admin1');
    failWritesTo('wallet_idempotency');
    await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body: { userId: 'client-1', type: 'credit', amount: 100, idempotencyKey: 'retry-me' },
    });

    reset({ collections: moneySeed() });
    signIn('admin1');

    const res = await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body: { userId: 'client-1', type: 'credit', amount: 100, idempotencyKey: 'retry-me' },
    });

    assert.equal(res.status, 201);
    assert.equal(balanceOf('client-1'), 1100);
  });
});

/* =====================================================================
 * WAVE 1.3 — key precedence and the target-account check
 * ===================================================================*/

describe('wallet 1.3: idempotency key precedence', () => {
  beforeEach(() => reset({ collections: moneySeed() }));

  it('falls back to the header when the body value is empty', async () => {
    signIn('admin1');
    const body = { userId: 'client-1', type: 'credit', amount: 25, idempotencyKey: '' };

    const first = await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body,
      headers: { 'Idempotency-Key': 'header-key' },
    });
    const second = await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body,
      headers: { 'Idempotency-Key': 'header-key' },
    });

    assert.equal(first.status, 201);
    assert.equal(second.status, 200, 'the header key must still be honoured');
    assert.equal(balanceOf('client-1'), 1025, 'only one credit applied');
    assert.equal(docs('wallet_transactions').length, 1);
    assert.equal(idemDocs().length, 1);
  });

  it('falls back to the header when the body value is only whitespace', async () => {
    signIn('admin1');

    const first = await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body: { userId: 'client-1', type: 'credit', amount: 25, idempotencyKey: '   ' },
      headers: { 'Idempotency-Key': 'header-key-2' },
    });
    const second = await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body: { userId: 'client-1', type: 'credit', amount: 25, idempotencyKey: '   ' },
      headers: { 'Idempotency-Key': 'header-key-2' },
    });

    assert.equal(first.status, 201);
    assert.equal(second.status, 200);
    assert.equal(balanceOf('client-1'), 1025);
  });

  it('still prefers a non-empty body key over the header', async () => {
    signIn('admin1');

    const first = await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body: { userId: 'client-1', type: 'credit', amount: 25, idempotencyKey: 'from-body' },
      headers: { 'Idempotency-Key': 'from-header' },
    });
    const replay = await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body: { userId: 'client-1', type: 'credit', amount: 25, idempotencyKey: 'from-body' },
      headers: { 'Idempotency-Key': 'different-header' },
    });

    assert.equal(first.status, 201);
    assert.equal(replay.status, 200, 'the body key is the one that was stored');
    assert.equal(balanceOf('client-1'), 1025);
  });
});

describe('wallet 1.3: a wallet must belong to an existing account', () => {
  beforeEach(() => reset({ collections: moneySeed() }));

  it('refuses a credit to an unknown user and writes nothing', async () => {
    signIn('admin1');

    const res = await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body: { userId: 'ghost-user', type: 'credit', amount: 50 },
    });

    assert.equal(res.status, 404);
    assert.equal(docs('wallets').length, 1, 'no orphan wallet was created');
    assert.equal(docs('wallet_transactions').length, 0);
    assert.equal(docs('wallet_idempotency').length, 0);
  });

  it('refuses even when an orphan wallet already exists', async () => {
    reset({
      collections: moneySeed({
        wallets: [
          { id: 'client-1', userId: 'client-1', balance: 1000, currency: 'USD' },
          { id: 'ghost-user', userId: 'ghost-user', balance: 10, currency: 'USD' },
        ],
      }),
    });
    signIn('admin1');

    const res = await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body: { userId: 'ghost-user', type: 'credit', amount: 50 },
    });

    assert.equal(res.status, 404);
    assert.equal(balanceOf('ghost-user'), 10, 'orphan balance untouched');
    assert.equal(docs('wallet_transactions').length, 0);
  });

  it('still credits an existing account with no wallet yet', async () => {
    reset({
      collections: moneySeed({
        wallets: [],
        users: [
          ...users('admin1', 'client1'),
          { id: 'fresh-user', uid: 'fresh-user', name: 'Fresh', role: 'client' },
        ],
      }),
    });
    signIn('admin1');

    const res = await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body: { userId: 'fresh-user', type: 'credit', amount: 10 },
    });

    assert.equal(res.status, 201);
    assert.equal(balanceOf('fresh-user'), 10);
  });
});

/* =====================================================================
 * WAVE 1.3 — negative balances
 * ===================================================================*/

describe('wallet 1.3: a corrupt negative balance cannot be spent', () => {
  beforeEach(() =>
    reset({
      collections: {
        users: users('admin1', 'client1'),
        wallets: [{ id: 'client-1', userId: 'client-1', balance: -50, currency: 'USD' }],
        wallet_transactions: [],
      },
    }),
  );

  it('refuses a debit against a negative balance without changing it', async () => {
    signIn('client1');

    const res = await post(`${BASE}/transactions`, {
      token: tokenFor('client1'),
      body: { userId: 'client-1', type: 'debit', amount: 1 },
    });

    assert.equal(res.status, 400);
    assert.equal(balanceOf('client-1'), -50, 'the stored value is left for an admin to fix');
    assert.equal(docs('wallet_transactions').length, 0);
  });

  it('still allows an administrator to credit the account back to positive', async () => {
    signIn('admin1');

    const res = await post(`${BASE}/transactions`, {
      token: tokenFor('admin1'),
      body: { userId: 'client-1', type: 'credit', amount: 60 },
    });

    assert.equal(res.status, 201);
    assert.equal(balanceOf('client-1'), 10);
  });

  it('never lets the arithmetic wrap below zero through a large debit', async () => {
    reset({
      collections: {
        users: users('admin1', 'client1'),
        wallets: [{ id: 'client-1', userId: 'client-1', balance: 0.01, currency: 'USD' }],
        wallet_transactions: [],
      },
    });
    signIn('client1');

    const res = await post(`${BASE}/transactions`, {
      token: tokenFor('client1'),
      body: { userId: 'client-1', type: 'debit', amount: 0.02 },
    });

    assert.equal(res.status, 400);
    assert.equal(balanceOf('client-1'), 0.01);
  });
});
