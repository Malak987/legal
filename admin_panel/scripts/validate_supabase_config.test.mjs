import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';

import { describeConfig } from './supabase_env.mjs';
import { inspectSupabaseConfig } from './validate_supabase_config.mjs';

const URL = 'https://qqfzbecwhewswkyxgebu.supabase.co';
const KEY = 'sb_publishable_TESTONLY_admin_preflight_0000';
const jwt = (claims) =>
  [{ alg: 'HS256', typ: 'JWT' }, claims]
    .map((value) => Buffer.from(JSON.stringify(value)).toString('base64url'))
    .join('.') + '.test-signature';

function sandbox(values) {
  const dir = mkdtempSync(join(tmpdir(), 'admin-supabase-preflight-'));
  if (values !== null) {
    writeFileSync(join(dir, 'supabase.local.json'), JSON.stringify(values));
  }
  return dir;
}

test('preflight rejects a missing public key and does not print key material', () => {
  const dir = sandbox({ SUPABASE_URL: URL });
  try {
    const result = inspectSupabaseConfig({ adminDir: dir, env: {}, fileOnly: true });
    assert.deepEqual(result.issues.map((issue) => issue.code), ['missingKey']);
    const output = describeConfig(result.config) + result.issues.map((i) => i.message).join(' ');
    assert.ok(!output.includes(KEY));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('preflight accepts a valid public key and rejects placeholders and secret keys', () => {
  const validDir = sandbox({ SUPABASE_URL: URL, SUPABASE_ANON_KEY: KEY });
  const placeholderDir = sandbox({ SUPABASE_URL: URL, SUPABASE_ANON_KEY: '<public anon key>' });
  const secretDir = sandbox({ SUPABASE_URL: URL, SUPABASE_ANON_KEY: 'sb_secret_TESTONLY_0000000000' });
  try {
    assert.deepEqual(inspectSupabaseConfig({ adminDir: validDir, env: {}, fileOnly: true }).issues, []);
    assert.deepEqual(inspectSupabaseConfig({ adminDir: placeholderDir, env: {}, fileOnly: true }).issues.map((i) => i.code), ['malformedKey']);
    assert.deepEqual(inspectSupabaseConfig({ adminDir: secretDir, env: {}, fileOnly: true }).issues.map((i) => i.code), ['secretKey']);
  } finally {
    for (const dir of [validDir, placeholderDir, secretDir]) rmSync(dir, { recursive: true, force: true });
  }
});

test('preflight catches URL defects and legacy anon project mismatch', () => {
  const badUrl = sandbox({ SUPABASE_URL: `${URL}/rest/v1`, SUPABASE_ANON_KEY: KEY });
  const mismatchedKey = jwt({ role: 'anon', ref: 'different-project' });
  const mismatch = sandbox({ SUPABASE_URL: URL, SUPABASE_ANON_KEY: mismatchedKey });
  try {
    assert.deepEqual(inspectSupabaseConfig({ adminDir: badUrl, env: {}, fileOnly: true }).issues.map((i) => i.code), ['malformedUrl']);
    assert.deepEqual(inspectSupabaseConfig({ adminDir: mismatch, env: {}, fileOnly: true }).issues.map((i) => i.code), ['projectMismatch']);
  } finally {
    rmSync(badUrl, { recursive: true, force: true });
    rmSync(mismatch, { recursive: true, force: true });
  }
});

test('environment wins for normal builds, while IDE file-only preflight matches dart-define-from-file', () => {
  const dir = sandbox({ SUPABASE_URL: URL, SUPABASE_ANON_KEY: KEY });
  try {
    const envKey = `${KEY}_env`;
    const normal = inspectSupabaseConfig({ adminDir: dir, env: { SUPABASE_ANON_KEY: envKey } });
    assert.equal(normal.config.defines.SUPABASE_ANON_KEY, envKey);
    assert.equal(normal.config.sources.SUPABASE_ANON_KEY, 'environment');

    const ide = inspectSupabaseConfig({ adminDir: dir, env: { SUPABASE_ANON_KEY: envKey }, fileOnly: true });
    assert.equal(ide.config.defines.SUPABASE_ANON_KEY, KEY);
    assert.equal(ide.config.sources.SUPABASE_ANON_KEY, 'supabase.local.json');
    assert.deepEqual(ide.issues, []);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('preflight messages and config summaries redact the full public key', () => {
  const dir = sandbox({ SUPABASE_URL: URL, SUPABASE_ANON_KEY: KEY });
  try {
    const result = inspectSupabaseConfig({ adminDir: dir, env: {}, fileOnly: true });
    const output = describeConfig(result.config) + result.issues.map((i) => i.message).join(' ');
    assert.ok(output.includes('sb_publishable_…'));
    assert.ok(!output.includes(KEY));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
