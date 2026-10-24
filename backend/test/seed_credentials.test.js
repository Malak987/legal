/**
 * Security tests for the current synthetic Supabase seed.
 *
 * The seed is a local integration-test fixture, not an account bootstrapper:
 * it creates no Auth users or passwords, is disabled in production, and only
 * accepts a loopback Supabase URL after an explicit opt-in.
 */

import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { resolveTestSeedConfig } from '../src/seed.js';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SEED_PATH = path.join(HERE, '..', 'src', 'seed.js');
const README_PATH = path.join(HERE, '..', '..', 'README.md');
const SAFE_TEST_KEY = 'synthetic-test-key-not-a-credential';

const validEnv = (overrides = {}) => ({
  NODE_ENV: 'test',
  LEGAL_ALLOW_TEST_SEED: 'true',
  SUPABASE_TEST_URL: 'http://127.0.0.1:54321',
  SUPABASE_TEST_SERVICE_ROLE_KEY: SAFE_TEST_KEY,
  ...overrides,
});

describe('synthetic seed: explicit local-only configuration', () => {
  it('requires an explicit opt-in', () => {
    assert.throws(
      () => resolveTestSeedConfig(validEnv({ LEGAL_ALLOW_TEST_SEED: undefined })),
      /LEGAL_ALLOW_TEST_SEED=true/,
    );
  });

  it('refuses production even when all local seed options are present', () => {
    assert.throws(
      () => resolveTestSeedConfig(validEnv({ NODE_ENV: 'production' })),
      /disabled in production/,
    );
  });

  it('requires the dedicated test URL and key without echoing supplied values', () => {
    assert.throws(
      () => resolveTestSeedConfig(validEnv({
        SUPABASE_TEST_URL: undefined,
        SUPABASE_TEST_SERVICE_ROLE_KEY: undefined,
      })),
      (error) => {
        assert.match(error.message, /SUPABASE_TEST_URL/);
        assert.match(error.message, /SUPABASE_TEST_SERVICE_ROLE_KEY/);
        assert.equal(error.message.includes(SAFE_TEST_KEY), false);
        return true;
      },
    );
  });

  it('accepts IPv4, IPv6, and localhost loopback hosts', () => {
    for (const host of ['127.0.0.1', '[::1]', 'localhost']) {
      const config = resolveTestSeedConfig(validEnv({
        SUPABASE_TEST_URL: `http://${host}:54321/`,
      }));
      assert.equal(config.url, `http://${host}:54321`);
      assert.equal(config.serviceRoleKey, SAFE_TEST_KEY);
    }
  });

  it('rejects remote hosts, URL credentials, query parameters, and fragments', () => {
    const unsafeUrls = [
      'https://project.supabase.co',
      'http://user:pass@127.0.0.1:54321',
      'http://127.0.0.1:54321/?apikey=not-a-secret',
      'http://127.0.0.1:54321/#fragment',
      'file:///tmp/supabase',
    ];

    for (const url of unsafeUrls) {
      assert.throws(
        () => resolveTestSeedConfig(validEnv({ SUPABASE_TEST_URL: url })),
        /loopback|credentials or URL parameters|valid local Supabase URL/,
        `unsafe test seed URL should be rejected: ${url}`,
      );
    }
  });
});

describe('synthetic seed: it does not revive credentialed Firebase seeding', () => {
  const seedSource = readFileSync(SEED_PATH, 'utf8');

  it('contains no Firebase initialization or password-based account creation', () => {
    assert.doesNotMatch(seedSource, /initializeFirebase|SEED_(?:ADMIN|CLIENT|LAWYER)_PASSWORD/);
    assert.doesNotMatch(seedSource, /createUser\s*\(/);
    assert.match(seedSource, /example\.invalid/);
    assert.match(seedSource, /ignoreDuplicates:\s*true/);
  });

  it('documents the loopback-only Supabase safeguards, not obsolete Firebase passwords', () => {
    const readme = readFileSync(README_PATH, 'utf8');
    assert.match(readme, /LEGAL_ALLOW_TEST_SEED=true/);
    assert.match(readme, /SUPABASE_TEST_URL/);
    assert.match(readme, /SUPABASE_TEST_SERVICE_ROLE_KEY/);
    assert.doesNotMatch(readme, /SEED_(?:ADMIN|CLIENT|LAWYER)_PASSWORD/);
  });
});
