import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  get,
  reset,
  signIn,
  startApp,
  stopApp,
  tokenFor,
} from './helpers/harness.js';

before(startApp);
after(stopApp);
beforeEach(() => reset());

describe('trusted owner role compatibility', () => {
  it('treats a server-verified owner as an admin for admin-only routes', async () => {
    signIn('owner1');
    const response = await get('/api/dashboard/stats', { token: tokenFor('owner1') });
    assert.equal(response.status, 200, JSON.stringify(response.body));
    assert.equal(response.body.success, true);
  });

  it('does not grant admin routes to a lawyer', async () => {
    signIn('lawyer1');
    const response = await get('/api/dashboard/stats', { token: tokenFor('lawyer1') });
    assert.equal(response.status, 403);
  });
});
