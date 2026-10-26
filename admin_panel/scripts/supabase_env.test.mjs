// node --test scripts/*.test.mjs   (from admin_panel/)
//
// Uses only fake, test-only keys. The end-to-end cases run build_web.mjs and
// run_web.mjs against a stub `flutter` executable that records its arguments.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, cpSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';

import {
  ADMIN_PANEL_DIR,
  DEFAULT_SUPABASE_URL,
  LEGACY_CI_PLACEHOLDER_KEY,
  loadSupabaseDefines,
  redactKey,
  validateSupabaseDefines,
} from './supabase_env.mjs';

const URL = 'https://qqfzbecwhewswkyxgebu.supabase.co';
const KEY = 'sb_publishable_TESTONLY_script_check_0000';
const jwt = (claims) =>
  [{ alg: 'HS256', typ: 'JWT' }, claims].map((p) => Buffer.from(JSON.stringify(p)).toString('base64url')).join('.') +
  '.sig';
const codes = (url, key) => validateSupabaseDefines({ SUPABASE_URL: url, SUPABASE_ANON_KEY: key }).map((i) => i.code);

test('valid publishable and legacy anon keys pass', () => {
  assert.deepEqual(codes(URL, KEY), []);
  assert.deepEqual(codes(URL, jwt({ role: 'anon', ref: 'qqfzbecwhewswkyxgebu' })), []);
  assert.deepEqual(codes('http://127.0.0.1:54321', KEY), []);
});

test('missing, empty, malformed and unsafe values are rejected like the Dart validator', () => {
  assert.deepEqual(codes('', KEY), ['missingUrl']);
  assert.deepEqual(codes(URL, ''), ['missingKey']);
  assert.deepEqual(codes('  ', '  '), ['missingUrl', 'missingKey']);
  for (const url of ['qqfzbecwhewswkyxgebu.supabase.co', `${URL}/rest/v1`, `${URL}?a=1`, 'https://', 'not a url', 'ftp://x.supabase.co']) {
    assert.deepEqual(codes(url, KEY), ['malformedUrl'], url);
  }
  assert.deepEqual(codes('http://qqfzbecwhewswkyxgebu.supabase.co', KEY), ['insecureUrl']);
  for (const key of ['<public anon/publishable key>', LEGACY_CI_PLACEHOLDER_KEY, 'sb_publishable_', 'anon-key']) {
    assert.deepEqual(codes(URL, key), ['malformedKey'], redactKey(key));
  }
  assert.deepEqual(codes(URL, 'sb_secret_TESTONLY_000000'), ['secretKey']);
  assert.deepEqual(codes(URL, jwt({ role: 'service_role' })), ['secretKey']);
  assert.deepEqual(codes(URL, jwt({ role: 'anon', ref: 'otherproject' })), ['projectMismatch']);
});

test('messages never include the key value', () => {
  const marker = 'SENSITIVE0123456789';
  for (const key of [`sb_publishable_${marker}`, `sb_secret_${marker}`, `<${marker}>`]) {
    const text = validateSupabaseDefines({ SUPABASE_URL: URL, SUPABASE_ANON_KEY: key }).map((i) => i.message).join(' ');
    assert.ok(!text.includes(marker));
    assert.ok(!redactKey(key).includes(marker));
  }
});

test('environment wins over the local file; URL falls back to the project', () => {
  const dir = mkdtempSync(join(tmpdir(), 'admin-cfg-'));
  assert.equal(loadSupabaseDefines({ env: {}, adminDir: dir }).defines.SUPABASE_URL, DEFAULT_SUPABASE_URL);
  writeFileSync(join(dir, 'supabase.local.json'), JSON.stringify({ SUPABASE_ANON_KEY: KEY, SUPABASE_URL: `${URL}/` }));
  const fromFile = loadSupabaseDefines({ env: {}, adminDir: dir });
  assert.equal(fromFile.defines.SUPABASE_ANON_KEY, KEY);
  assert.equal(fromFile.defines.SUPABASE_URL, URL);
  assert.equal(fromFile.sources.SUPABASE_ANON_KEY, 'supabase.local.json');
  const fromEnv = loadSupabaseDefines({ env: { SUPABASE_ANON_KEY: `${KEY}_env` }, adminDir: dir });
  assert.equal(fromEnv.defines.SUPABASE_ANON_KEY, `${KEY}_env`);
  assert.equal(fromEnv.sources.SUPABASE_ANON_KEY, 'environment');
});

// ---------------------------------------------------------------------------
// End-to-end with a stub flutter binary.
// ---------------------------------------------------------------------------
function sandbox() {
  const root = mkdtempSync(join(tmpdir(), 'admin-e2e-'));
  const admin = join(root, 'admin_panel');
  mkdirSync(join(admin, 'scripts'), { recursive: true });
  for (const file of ['supabase_env.mjs', 'build_web.mjs', 'run_web.mjs']) {
    cpSync(join(ADMIN_PANEL_DIR, 'scripts', file), join(admin, 'scripts', file));
  }
  const bin = join(root, 'bin');
  mkdirSync(bin);
  // Records argv + whether a server-only variable leaked, then emulates the
  // dart2js output by writing the define values into main.dart.js.
  writeFileSync(
    join(bin, 'flutter'),
    `#!/usr/bin/env node
const fs = require('fs'); const path = require('path');
fs.writeFileSync(path.join(process.cwd(), 'flutter-args.json'), JSON.stringify({
  argv: process.argv.slice(2), serviceRoleLeaked: 'SUPABASE_SERVICE_ROLE_KEY' in process.env }));
const out = process.argv.indexOf('--output');
if (process.argv[2] === 'build' && out > 0) {
  const dir = path.join(process.cwd(), process.argv[out + 1]); fs.mkdirSync(dir, { recursive: true });
  const defs = process.argv.filter((a) => a.startsWith('--dart-define=')).map((a) => a.split('=').slice(2).join('='));
  fs.writeFileSync(path.join(dir, 'main.dart.js'), 'var a=' + JSON.stringify(defs) + ';');
}
`,
  );
  chmodSync(join(bin, 'flutter'), 0o755);
  return { admin, bin };
}

function runScript(box, script, { env = {}, args = [] } = {}) {
  const result = spawnSync(process.execPath, [join(box.admin, 'scripts', script), ...args], {
    cwd: box.admin,
    encoding: 'utf8',
    env: { PATH: `${box.bin}:${process.env.PATH}`, ...env },
  });
  const argsFile = join(box.admin, 'flutter-args.json');
  return { ...result, flutter: existsSync(argsFile) ? JSON.parse(readFileSync(argsFile, 'utf8')) : null };
}

test('build_web passes the defines, strips server-only env and never prints the key', () => {
  const box = sandbox();
  const r = runScript(box, 'build_web.mjs', {
    env: { SUPABASE_ANON_KEY: KEY, SUPABASE_SERVICE_ROLE_KEY: 'sb_secret_should_not_leak' },
  });
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(r.flutter.argv.slice(0, 3), ['build', 'web', '--release']);
  assert.ok(r.flutter.argv.includes(`--dart-define=SUPABASE_URL=${DEFAULT_SUPABASE_URL}`));
  assert.ok(r.flutter.argv.includes(`--dart-define=SUPABASE_ANON_KEY=${KEY}`));
  assert.equal(r.flutter.serviceRoleLeaked, false);
  assert.ok(!r.stdout.includes(KEY) && !r.stderr.includes(KEY), 'key value printed');
  assert.match(r.stdout, /Verified: build\/web\/main\.dart\.js contains/);
});

test('build_web fails before invoking flutter when the key is missing or a placeholder', () => {
  for (const env of [{}, { SUPABASE_ANON_KEY: LEGACY_CI_PLACEHOLDER_KEY }, { SUPABASE_ANON_KEY: 'sb_secret_x0000000000' }]) {
    const box = sandbox();
    const r = runScript(box, 'build_web.mjs', { env });
    assert.equal(r.status, 1);
    assert.equal(r.flutter, null, 'flutter must not run');
    assert.match(r.stderr, /Supabase configuration is invalid/);
  }
});

test('CI compile check builds a key-less bundle outside build/web', () => {
  const box = sandbox();
  const r = runScript(box, 'build_web.mjs', { args: ['--allow-unconfigured-compile-check'] });
  assert.equal(r.status, 0, r.stderr);
  assert.ok(r.flutter.argv.includes('build/web-compile-check'));
  assert.ok(!r.flutter.argv.some((a) => a.startsWith('--dart-define=SUPABASE_ANON_KEY')));
  assert.ok(!existsSync(join(box.admin, 'build', 'web')));
  assert.match(r.stdout, /NON-DEPLOYABLE/);
  // The flag never relaxes other errors.
  const bad = runScript(sandbox(), 'build_web.mjs', {
    args: ['--allow-unconfigured-compile-check'],
    env: { SUPABASE_ANON_KEY: 'sb_secret_x0000000000' },
  });
  assert.equal(bad.status, 1);
});

test('run_web uses chrome by default and reads the git-ignored local file', () => {
  const box = sandbox();
  writeFileSync(join(box.admin, 'supabase.local.json'), JSON.stringify({ SUPABASE_URL: URL, SUPABASE_ANON_KEY: KEY }));
  const r = runScript(box, 'run_web.mjs');
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(r.flutter.argv.slice(0, 3), ['run', '-d', 'chrome']);
  assert.ok(r.flutter.argv.includes(`--dart-define=SUPABASE_ANON_KEY=${KEY}`));
  assert.ok(!r.stdout.includes(KEY));
  const custom = runScript(box, 'run_web.mjs', { args: ['-d', 'web-server'] });
  assert.equal(custom.flutter.argv[0], 'run');
  assert.deepEqual(custom.flutter.argv.slice(-2), ['-d', 'web-server']);
  assert.ok(!custom.flutter.argv.includes('chrome'));
});
