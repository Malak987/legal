import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';

const packageJson = JSON.parse(
  await readFile(new URL('../package.json', import.meta.url), 'utf8'),
);
const firebaseJson = JSON.parse(
  await readFile(new URL('../../firebase.json', import.meta.url), 'utf8'),
);

test('Firebase deployment resolves the Functions wrapper while standalone Express remains available', async () => {
  assert.equal(packageJson.main, 'index.js');
  assert.equal(firebaseJson.functions[0].source, 'backend');
  assert.deepEqual(
    firebaseJson.hosting.rewrites.slice(0, 2),
    [
      { source: '/api', function: { functionId: 'api', region: 'us-central1' } },
      { source: '/api/**', function: { functionId: 'api', region: 'us-central1' } },
    ],
    'the optional API compatibility routes must reach the secured function before the SPA fallback',
  );
  assert.equal(firebaseJson.hosting.rewrites.at(-1)?.destination, '/index.html');
  assert.deepEqual(
    firebaseJson.hosting.predeploy,
    ['cd admin_panel && node scripts/build_web.mjs --no-wasm-dry-run'],
    'Hosting predeploy must use the bounded JavaScript-only build path',
  );
  assert.equal(packageJson.scripts.start, 'node src/index.js');
  assert.equal(packageJson.scripts.dev, 'node --watch src/index.js');
  assert.match(packageJson.scripts['deploy:functions'], /^cd \.\. && firebase deploy --only functions /);
  assert.match(packageJson.scripts['deploy:hosting'], /^cd \.\. && firebase deploy --only hosting /);
  assert.match(packageJson.scripts.emulator, /^cd \.\. && firebase emulators:start /);
  assert.equal(typeof packageJson.scripts['test:emulator'], 'string');

  const functionsEntrypoint = await import('../index.js');
  assert.equal(typeof functionsEntrypoint.api, 'function');
  assert.equal(typeof functionsEntrypoint.app, 'function');
  assert.deepEqual(
    functionsEntrypoint.api.__endpoint.secretEnvironmentVariables.map(({ key }) => key),
    ['SUPABASE_SERVICE_ROLE_KEY'],
  );
});
