/**
 * Regression tests for the Firebase service-account path resolution in
 * `src/config/env.js`.
 *
 * The previous code resolved `SERVICE_ACCOUNT_PATH` from
 * `path.dirname(__dirname)`, i.e. `<backend>/src/`, while both the error
 * message and `backend/.env.example` document `<backend>/serviceAccount.json`.
 * Working installations therefore exist with the file in EITHER directory, so
 * the resolver must accept both instead of silently breaking one of them.
 *
 * These tests copy only `src/config/env.js` into a temporary tree, create an
 * empty placeholder file (never a real key) in one or both directories, and
 * import the module fresh for every case. Nothing is read, logged or exported
 * from the file — only its path.
 *
 * Run with:  node --test test/
 */

import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { after, before, beforeEach, describe, it } from 'node:test';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const BACKEND_ROOT = path.resolve(HERE, '..');
const ENV_MODULE = path.join(BACKEND_ROOT, 'src', 'config', 'env.js');

let tmpDir;
let importCounter = 0;
const savedServiceAccountPath = process.env.SERVICE_ACCOUNT_PATH;

/** Documented location: <backend>/serviceAccount.json */
const documented = () => path.join(tmpDir, 'serviceAccount.json');
/** Legacy location: <backend>/src/serviceAccount.json */
const legacy = () => path.join(tmpDir, 'src', 'serviceAccount.json');

/**
 * Imports a fresh copy of `env.js` rooted at the temporary directory.
 * The query string busts the ESM module cache so each case is independent.
 */
async function loadEnv() {
  const url = pathToFileURL(path.join(tmpDir, 'src', 'config', 'env.js'));
  url.searchParams.set('case', String(importCounter++));
  return (await import(url.href)).default;
}

before(() => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'legal-env-test-'));
  fs.mkdirSync(path.join(tmpDir, 'src', 'config'), { recursive: true });
  fs.cpSync(ENV_MODULE, path.join(tmpDir, 'src', 'config', 'env.js'));
  fs.symlinkSync(
    path.join(BACKEND_ROOT, 'node_modules'),
    path.join(tmpDir, 'node_modules'),
    'dir',
  );
  fs.writeFileSync(path.join(tmpDir, 'src', 'config', 'package.json'), '{"type":"module"}');
});

after(() => {
  if (savedServiceAccountPath === undefined) delete process.env.SERVICE_ACCOUNT_PATH;
  else process.env.SERVICE_ACCOUNT_PATH = savedServiceAccountPath;
  if (tmpDir) fs.rmSync(tmpDir, { recursive: true, force: true });
});

beforeEach(() => {
  // An empty placeholder is enough — the resolver only ever stats the file.
  for (const file of [documented(), legacy()]) {
    fs.rmSync(file, { force: true });
  }
  delete process.env.SERVICE_ACCOUNT_PATH;
});

describe('serviceAccountPath resolution', () => {
  it('uses the documented location <backend>/serviceAccount.json', async () => {
    fs.writeFileSync(documented(), '{}');

    const env = await loadEnv();
    assert.equal(env.serviceAccountPath, documented());
  });

  it('still finds the legacy location <backend>/src/serviceAccount.json', async () => {
    fs.writeFileSync(legacy(), '{}');

    const env = await loadEnv();
    assert.equal(
      env.serviceAccountPath,
      legacy(),
      'an existing backend must not break on upgrade',
    );
  });

  it('prefers the documented location when both exist', async () => {
    fs.writeFileSync(documented(), '{}');
    fs.writeFileSync(legacy(), '{}');

    const env = await loadEnv();
    assert.equal(env.serviceAccountPath, documented());
  });

  it('falls back to the documented location when the file is missing', async () => {
    const env = await loadEnv();
    assert.equal(
      env.serviceAccountPath,
      documented(),
      'so the "not found" error points at the documented path',
    );
  });

  it('honours an absolute SERVICE_ACCOUNT_PATH', async () => {
    const absolute = path.join(tmpDir, 'custom', 'key.json');
    fs.mkdirSync(path.dirname(absolute), { recursive: true });
    fs.writeFileSync(absolute, '{}');
    process.env.SERVICE_ACCOUNT_PATH = absolute;

    const env = await loadEnv();
    assert.equal(env.serviceAccountPath, absolute);
  });

  it('resolves a relative SERVICE_ACCOUNT_PATH from the backend root', async () => {
    const target = path.join(tmpDir, 'config', 'key.json');
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, '{}');
    process.env.SERVICE_ACCOUNT_PATH = './config/key.json';

    const env = await loadEnv();
    assert.equal(env.serviceAccountPath, target);
  });

  it('exposes only the path — never the contents of the service account', async () => {
    const sentinel = 'SENTINEL_PRIVATE_KEY_MATERIAL';
    fs.writeFileSync(documented(), `{"private_key":"${sentinel}"}`);

    const env = await loadEnv();
    const serialised = JSON.stringify(env);

    assert.equal(typeof env.serviceAccountPath, 'string');
    assert.ok(env.serviceAccountPath.endsWith('.json'));
    assert.ok(
      !serialised.includes(sentinel),
      'the service-account file must never be read into the env object',
    );
    assert.ok(
      !serialised.includes('private_key'),
      'no private key material may appear on the env object',
    );
  });
});
