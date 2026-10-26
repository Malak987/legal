// Local development run with the Supabase public configuration compiled in.
//
//   node scripts/run_web.mjs                 # flutter run -d chrome + defines
//   node scripts/run_web.mjs -d web-server   # any extra flutter run args
//
// Values come from the environment or the git-ignored supabase.local.json (see
// scripts/supabase_env.mjs). Dart defines are fixed when the app is compiled:
// after changing a value, quit (q) and run this script again — hot restart (R)
// does not pick up new defines.
import { spawnSync } from 'node:child_process';

import {
  ADMIN_PANEL_DIR,
  dartDefineArgs,
  describeConfig,
  flutterEnv,
  loadSupabaseDefines,
  printableCommand,
  reportIssues,
  validateSupabaseDefines,
} from './supabase_env.mjs';

const extraArgs = process.argv.slice(2);
let config;
try {
  config = loadSupabaseDefines();
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
const issues = validateSupabaseDefines(config.defines);
if (issues.length) {
  reportIssues(issues);
  process.exit(1);
}

const hasDevice = extraArgs.some((arg) => arg === '-d' || arg.startsWith('--device-id') || arg.startsWith('-d'));
const args = ['run', ...(hasDevice ? [] : ['-d', 'chrome']), ...dartDefineArgs(config.defines), ...extraArgs];
console.log(`Supabase configuration for flutter run:\n${describeConfig(config)}`);
console.log(`> ${printableCommand(args, config.defines)}`);

const result = spawnSync('flutter', args, {
  cwd: ADMIN_PANEL_DIR,
  stdio: 'inherit',
  env: flutterEnv(),
});
if (result.error) {
  console.error(`Could not start flutter run: ${result.error.message}`);
  process.exit(1);
}
process.exitCode = result.status ?? 1;
