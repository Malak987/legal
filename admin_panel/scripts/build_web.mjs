// Release web build with the Supabase public configuration compiled in.
//
//   SUPABASE_ANON_KEY=<public key> node scripts/build_web.mjs [extra flutter args]
//
// Values come from the environment or the git-ignored supabase.local.json (see
// scripts/supabase_env.mjs). The anon/publishable key is public client
// configuration; a service-role/secret key is always refused.
//
// --allow-unconfigured-compile-check (CI only): when SUPABASE_ANON_KEY is not
// configured, compile into build/web-compile-check WITHOUT any key so the job
// still verifies the code compiles. That bundle shows the configuration screen
// and is never written to build/web, the Firebase Hosting public directory.
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import {
  ADMIN_PANEL_DIR,
  dartDefineArgs,
  describeConfig,
  flutterEnv,
  loadSupabaseDefines,
  printableCommand,
  rejectUnsafeFlutterConfigArgs,
  reportIssues,
  validateSupabaseDefines,
} from './supabase_env.mjs';

const COMPILE_CHECK_FLAG = '--allow-unconfigured-compile-check';
const cliArgs = process.argv.slice(2);
const allowCompileCheck = cliArgs.includes(COMPILE_CHECK_FLAG);
const extraArgs = cliArgs.filter((arg) => arg !== COMPILE_CHECK_FLAG);
try {
  rejectUnsafeFlutterConfigArgs(extraArgs);
} catch (error) {
  console.error(error.message);
  process.exit(1);
}

let config;
try {
  config = loadSupabaseDefines();
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
const { defines } = config;
const issues = validateSupabaseDefines(defines);
const compileCheck =
  allowCompileCheck && issues.length === 1 && issues[0].code === 'missingKey';

if (issues.length && !compileCheck) {
  reportIssues(issues);
  process.exit(1);
}

let outputDir = 'build/web';
let buildDefines = defines;
if (compileCheck) {
  outputDir = 'build/web-compile-check';
  buildDefines = { ...defines };
  delete buildDefines.SUPABASE_ANON_KEY;
  const warning =
    'SUPABASE_ANON_KEY is not configured: building a NON-DEPLOYABLE compile check in ' +
    `${outputDir} (the app will show its configuration screen). Set the repository ` +
    'variable SUPABASE_ANON_KEY to build a deployable bundle.';
  console.log(process.env.GITHUB_ACTIONS ? `::warning title=Admin web build::${warning}` : `WARNING: ${warning}`);
}

console.log(`Supabase configuration for the web build:\n${describeConfig(config)}`);
const args = ['build', 'web', '--release', ...dartDefineArgs(buildDefines), '--output', outputDir, ...extraArgs];
console.log(`> ${printableCommand(args, defines)}`);

const result = spawnSync('flutter', args, {
  cwd: ADMIN_PANEL_DIR,
  stdio: 'inherit',
  env: flutterEnv(),
});
if (result.error) {
  console.error(`Could not start Flutter web build: ${result.error.message}`);
  process.exit(1);
}
if (result.status !== 0) process.exit(result.status ?? 1);

// Confirm the compiled bundle really carries the public key, without printing it.
const bundle = join(ADMIN_PANEL_DIR, outputDir, 'main.dart.js');
if (!existsSync(bundle)) {
  console.error(`Build finished but ${outputDir}/main.dart.js was not found; cannot verify configuration.`);
  process.exit(1);
}
const compiled = readFileSync(bundle, 'utf8');
if (compileCheck) {
  console.log(`Compile check OK (${outputDir}); no Supabase key embedded. Do not deploy this bundle.`);
} else if (!compiled.includes(defines.SUPABASE_ANON_KEY) || !compiled.includes(defines.SUPABASE_URL)) {
  console.error(
    'Build finished but the compiled bundle does not contain the configured Supabase URL/key. ' +
      'Check that no other --dart-define overrides them.',
  );
  process.exit(1);
} else {
  console.log(`Verified: ${outputDir}/main.dart.js contains the configured SUPABASE_URL and SUPABASE_ANON_KEY (value not printed).`);
}
