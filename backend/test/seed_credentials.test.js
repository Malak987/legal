/**
 * Wave 1.3 follow-up — the seed must not ship usable credentials.
 *
 * Historically `seed.js` contained three literal passwords (one of them for an
 * administrator) and the README published the admin login. Anyone with
 * repository access therefore knew a working administrator account for every
 * project seeded with defaults.
 *
 * These tests pin the replacement contract:
 *   - no seeded account has a default password;
 *   - a missing or unusable value aborts the seed and names the variable;
 *   - error messages never echo the value that was supplied;
 *   - a complete configuration is accepted and mapped to the right account.
 *
 * The values used here are obvious fakes generated for the test, not
 * credentials for anything.
 */

import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  MIN_SEED_PASSWORD_LENGTH,
  SEED_PASSWORD_ENV,
  SeedConfigError,
  resolveSeedPasswords,
} from '../src/config/seedCredentials.js';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SEED_PATH = path.join(HERE, '..', 'src', 'seed.js');
const README_PATH = path.join(HERE, '..', '..', 'README.md');

/** A syntactically valid, obviously fake password for tests only. */
const fake = (label) => `test-only-${label}-${'x'.repeat(12)}`;

const complete = () => ({
  [SEED_PASSWORD_ENV.admin]: fake('admin'),
  [SEED_PASSWORD_ENV.client]: fake('client'),
  [SEED_PASSWORD_ENV.lawyer]: fake('lawyer'),
});

describe('seed credentials: configuration is mandatory', () => {
  it('has no built-in default, so an empty environment is refused', () => {
    assert.throws(
      () => resolveSeedPasswords({}),
      (error) => {
        assert.ok(error instanceof SeedConfigError);
        assert.equal(error.name, 'SeedConfigError');
        // The message must tell the operator exactly what to set.
        for (const variable of Object.values(SEED_PASSWORD_ENV)) {
          assert.match(error.message, new RegExp(variable));
        }
        return true;
      },
    );
  });

  it('names only the missing variable when one account is unconfigured', () => {
    const env = complete();
    delete env[SEED_PASSWORD_ENV.lawyer];

    assert.throws(
      () => resolveSeedPasswords(env),
      (error) => {
        assert.ok(error.variables.includes(SEED_PASSWORD_ENV.lawyer));
        assert.equal(error.variables.length, 1, 'only the missing one is reported');
        assert.doesNotMatch(error.message, new RegExp(SEED_PASSWORD_ENV.admin));
        return true;
      },
    );
  });

  it('treats a blank or whitespace-only value as missing', () => {
    for (const blank of ['', '   ', '\t\n']) {
      const env = complete();
      env[SEED_PASSWORD_ENV.admin] = blank;

      assert.throws(
        () => resolveSeedPasswords(env),
        (error) => {
          assert.ok(error instanceof SeedConfigError);
          assert.ok(error.variables.includes(SEED_PASSWORD_ENV.admin));
          return true;
        },
        `blank value ${JSON.stringify(blank)} must be rejected`,
      );
    }
  });

  it('rejects a value shorter than the documented minimum', () => {
    const env = complete();
    env[SEED_PASSWORD_ENV.admin] = 'short';

    assert.throws(
      () => resolveSeedPasswords(env),
      (error) => {
        assert.ok(error instanceof SeedConfigError);
        assert.match(error.message, new RegExp(String(MIN_SEED_PASSWORD_LENGTH)));
        assert.ok(error.variables.includes(SEED_PASSWORD_ENV.admin));
        return true;
      },
    );
  });

  it('never puts a supplied value into the error message', () => {
    const secretish = 'leak-me-if-you-can-123456';
    const env = complete();
    env[SEED_PASSWORD_ENV.client] = secretish;
    // Make a *different* account fail so an error is raised while this value
    // is present in the input.
    delete env[SEED_PASSWORD_ENV.admin];

    try {
      resolveSeedPasswords(env);
      assert.fail('expected the resolver to throw');
    } catch (error) {
      assert.ok(error instanceof SeedConfigError);
      assert.equal(
        error.message.includes(secretish),
        false,
        'the supplied password must not appear in the error message',
      );
      assert.equal(
        String(error.stack).includes(secretish),
        false,
        'nor in the stack trace',
      );
    }
  });
});

describe('seed credentials: a complete configuration is accepted', () => {
  it('maps each account to its own variable', () => {
    const env = complete();
    const resolved = resolveSeedPasswords(env);

    assert.deepEqual(resolved, {
      admin: env[SEED_PASSWORD_ENV.admin],
      client: env[SEED_PASSWORD_ENV.client],
      lawyer: env[SEED_PASSWORD_ENV.lawyer],
    });
  });

  it('trims surrounding whitespace instead of failing on it', () => {
    const env = complete();
    env[SEED_PASSWORD_ENV.admin] = `  ${fake('padded')}  `;

    assert.equal(resolveSeedPasswords(env).admin, fake('padded'));
  });

  it('accepts a value exactly at the minimum length', () => {
    const env = complete();
    env[SEED_PASSWORD_ENV.lawyer] = 'a'.repeat(MIN_SEED_PASSWORD_LENGTH);

    assert.equal(
      resolveSeedPasswords(env).lawyer.length,
      MIN_SEED_PASSWORD_LENGTH,
    );
  });
});

describe('seed credentials: the source stays clean', () => {
  const seedSource = readFileSync(SEED_PATH, 'utf8');

  it('seed.js contains no literal password assignment', () => {
    const literal = /password\s*:\s*['"][^'"]+['"]/;
    assert.equal(
      literal.test(seedSource),
      false,
      'seed.js must not hardcode a password',
    );
  });

  it('seed.js resolves credentials before it touches Firebase', () => {
    const body = seedSource.slice(seedSource.indexOf('export async function runSeed'));
    const resolveAt = body.indexOf('resolveSeedPasswords()');
    const initAt = body.indexOf('initializeFirebase()');
    const usersAt = body.indexOf('await seedUsers(');

    assert.ok(resolveAt !== -1, 'runSeed must call resolveSeedPasswords()');
    assert.ok(initAt !== -1, 'runSeed must initialise Firebase');
    assert.ok(usersAt !== -1, 'runSeed must seed users');
    assert.ok(
      resolveAt < initAt && resolveAt < usersAt,
      'credentials must be validated before any Firebase work, so a missing ' +
        'value cannot leave a half-seeded project behind',
    );
  });

  it('the README does not publish a seeded password', () => {
    const readme = readFileSync(README_PATH, 'utf8');
    assert.equal(
      /Seed admin|admin password:\s*\S|admin@legalapp\.com\W+\|/i.test(readme) &&
        /\|\s*Email\s*\|\s*Password\s*\|/i.test(readme),
      false,
      'README must not contain a credentials table',
    );
    assert.match(readme, /SEED_ADMIN_PASSWORD/);
  });
});
