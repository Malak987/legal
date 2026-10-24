import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  lawyerSignupCalls,
  post,
  reset,
  setLawyerSignupHandler,
  startApp,
  stopApp,
} from './helpers/harness.js';

const ROUTE = '/api/auth/lawyer-signup';
const originalFlag = process.env.ENABLE_LAWYER_SIGNUP;
const originalSignupRedirect = process.env.LAWYER_SIGNUP_REDIRECT_URL;
const originalAuthRedirect = process.env.SUPABASE_AUTH_REDIRECT_URL;

function setSignupConfig({ enabled, redirect = '' }) {
  process.env.ENABLE_LAWYER_SIGNUP = enabled ? 'true' : 'false';
  process.env.LAWYER_SIGNUP_REDIRECT_URL = redirect;
  process.env.SUPABASE_AUTH_REDIRECT_URL = '';
}

function restoreSignupConfig() {
  if (originalFlag === undefined) delete process.env.ENABLE_LAWYER_SIGNUP;
  else process.env.ENABLE_LAWYER_SIGNUP = originalFlag;
  if (originalSignupRedirect === undefined) delete process.env.LAWYER_SIGNUP_REDIRECT_URL;
  else process.env.LAWYER_SIGNUP_REDIRECT_URL = originalSignupRedirect;
  if (originalAuthRedirect === undefined) delete process.env.SUPABASE_AUTH_REDIRECT_URL;
  else process.env.SUPABASE_AUTH_REDIRECT_URL = originalAuthRedirect;
}

before(startApp);
after(() => {
  restoreSignupConfig();
  return stopApp();
});
beforeEach(() => reset());

describe('public lawyer signup route', () => {
  it('is closed by default and does not reach the Auth boundary', async () => {
    setSignupConfig({ enabled: false, redirect: '' });
    setLawyerSignupHandler(async () => {
      assert.fail('disabled signup must not call Auth');
    });

    const response = await post(ROUTE, {
      body: { name: 'Lawyer Example', email: 'lawyer@example.test', password: 'a-long-test-password' },
    });

    assert.equal(response.status, 503);
    assert.equal(response.body.success, false);
    assert.deepEqual(lawyerSignupCalls(), []);
  });

  it('strips caller-supplied role and profile IDs before trusted signup', async () => {
    setSignupConfig({
      enabled: true,
      redirect: 'https://lawyers.example/auth/callback',
    });
    setLawyerSignupHandler(async (input) => {
      assert.deepEqual(Object.keys(input).sort(), ['email', 'name', 'password']);
      return { accepted: true };
    });

    const response = await post(ROUTE, {
      body: {
        name: '  Sam Example  ',
        email: 'SAM@EXAMPLE.COM',
        password: 'a-long-test-password',
        role: 'owner',
        userId: 'attacker-selected-profile',
        authUserId: '00000000-0000-4000-8000-000000000001',
      },
    });

    assert.equal(response.status, 202);
    assert.equal(response.body.success, true);
    assert.equal(response.body.data, undefined);
    assert.deepEqual(lawyerSignupCalls(), [{
      name: 'Sam Example',
      email: 'sam@example.com',
      password: 'a-long-test-password',
    }]);
  });

  it('requires the server-side feature flag and an explicit redirect', async () => {
    setSignupConfig({ enabled: true, redirect: '' });
    const response = await post(ROUTE, {
      body: { name: 'Sam Example', email: 'sam@example.test', password: 'a-long-test-password' },
    });
    assert.equal(response.status, 503);
    assert.deepEqual(lawyerSignupCalls(), []);
  });
});
