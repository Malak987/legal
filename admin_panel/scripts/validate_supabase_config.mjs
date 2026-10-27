#!/usr/bin/env node
// Preflight for IDE launch configurations and local builds. By default this
// resolves environment first, then admin_panel/supabase.local.json. With
// --file-only it validates exactly the file passed by VS Code's
// --dart-define-from-file launch argument.
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

import {
  ADMIN_PANEL_DIR,
  describeConfig,
  loadSupabaseDefines,
  reportIssues,
  validateSupabaseDefines,
} from './supabase_env.mjs';

export function inspectSupabaseConfig({
  adminDir = ADMIN_PANEL_DIR,
  env = process.env,
  fileOnly = false,
} = {}) {
  const config = loadSupabaseDefines({
    env: fileOnly ? {} : env,
    adminDir,
  });
  return { config, issues: validateSupabaseDefines(config.defines) };
}

function main(args) {
  const allowed = new Set(['--file-only']);
  const unsupported = args.filter((arg) => !allowed.has(arg));
  if (unsupported.length || args.filter((arg) => arg === '--file-only').length > 1) {
    console.error('Usage: node scripts/validate_supabase_config.mjs [--file-only]');
    return 64;
  }

  let result;
  try {
    result = inspectSupabaseConfig({ fileOnly: args.includes('--file-only') });
  } catch {
    console.error('Supabase configuration file is invalid JSON or unreadable. Repair the local file; details hidden.');
    return 1;
  }
  if (result.issues.length) {
    reportIssues(result.issues);
    return 1;
  }
  console.log(`Supabase configuration valid:\n${describeConfig(result.config)}`);
  return 0;
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  process.exitCode = main(process.argv.slice(2));
}
