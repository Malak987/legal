import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, '../..');
const launch = JSON.parse(readFileSync(resolve(repo, '.vscode/launch.json'), 'utf8'));
const tasks = JSON.parse(readFileSync(resolve(repo, '.vscode/tasks.json'), 'utf8'));

const configurations = new Map(launch.configurations.map((item) => [item.name, item]));
const taskLabels = new Set(tasks.tasks.map((item) => item.label));

test('VS Code Run configs inject the local file and preflight the same file', () => {
  for (const [name, program, cwd, task] of [
    [
      'Admin Web (local Supabase)',
      '${workspaceFolder}/admin_panel/lib/main.dart',
      '${workspaceFolder}/admin_panel',
      'Supabase: validate Admin local config',
    ],
    [
      'Legal App Android (local Supabase)',
      '${workspaceFolder}/legal_app/lib/main.dart',
      '${workspaceFolder}/legal_app',
      'Supabase: validate Mobile local config',
    ],
    [
      'Legal App iOS (local Supabase)',
      '${workspaceFolder}/legal_app/lib/main.dart',
      '${workspaceFolder}/legal_app',
      'Supabase: validate Mobile local config',
    ],
  ]) {
    const config = configurations.get(name);
    assert.ok(config, `missing launch configuration: ${name}`);
    assert.equal(config.program, program);
    assert.equal(config.cwd, cwd);
    assert.ok(config.toolArgs.includes('--dart-define-from-file=supabase.local.json'));
    assert.deepEqual(config.env, {
      SUPABASE_SERVICE_ROLE_KEY: '',
      SUPABASE_SECRET_KEY: '',
    });
    assert.equal(config.preLaunchTask, task);
    assert.ok(taskLabels.has(task));
  }
});

test('VS Code preflight tasks validate local files without echoing key values', () => {
  const admin = tasks.tasks.find((item) => item.label === 'Supabase: validate Admin local config');
  const mobile = tasks.tasks.find((item) => item.label === 'Supabase: validate Mobile local config');
  assert.deepEqual(admin.args, ['scripts/validate_supabase_config.mjs', '--file-only']);
  assert.deepEqual(mobile.args, ['run', 'tool/supabase_flutter.dart', 'validate', '--file-only']);
  const ignore = readFileSync(resolve(repo, '.gitignore'), 'utf8');
  assert.ok(ignore.includes('!.vscode/launch.json'));
  assert.ok(ignore.includes('!.vscode/tasks.json'));
  const ignoreLines = new Set(ignore.split(/\r?\n/).map((line) => line.trim()));
  assert.ok(ignoreLines.has('admin_panel/supabase.local.json'));
  assert.ok(ignoreLines.has('legal_app/supabase.local.json'));
});
