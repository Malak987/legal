/**
 * Seed credentials.
 *
 * The seed script creates real, sign-in-capable accounts. Their passwords used
 * to be literals in `seed.js` (and printed in the README), which meant anybody
 * with repository access knew a working administrator login for every project
 * that had been seeded with defaults. Nothing here has a default: an operator
 * must supply a value per account, and the script refuses to run otherwise.
 *
 * This module is deliberately free of Firebase imports so it can be unit
 * tested, and so a misconfigured environment fails before any write happens.
 */

/** Environment variable that carries each seeded account's password. */
export const SEED_PASSWORD_ENV = Object.freeze({
  admin: 'SEED_ADMIN_PASSWORD',
  client: 'SEED_CLIENT_PASSWORD',
  lawyer: 'SEED_LAWYER_PASSWORD',
});

/**
 * Shortest accepted seed password.
 *
 * Seed accounts are ordinary accounts with real privileges (the admin one can
 * manage every record), so the floor is higher than a placeholder token.
 */
export const MIN_SEED_PASSWORD_LENGTH = 12;

/** Raised when the seed cannot run because its configuration is incomplete. */
export class SeedConfigError extends Error {
  /**
   * @param {string} message   safe to show: variable names only, never values
   * @param {string[]} variables  the environment variables at fault
   */
  constructor(message, variables = []) {
    super(message);
    this.name = 'SeedConfigError';
    this.variables = variables;
  }
}

/**
 * Reads and validates the seeded account passwords.
 *
 * Never returns, throws or logs a partial result: either every account has a
 * usable password or the seed does not start. Error messages name the
 * environment variable, never the value that was supplied.
 *
 * @param {Record<string, string|undefined>} [env] source of the variables
 * @returns {{admin: string, client: string, lawyer: string}}
 */
export function resolveSeedPasswords(env = process.env) {
  const missing = [];
  const tooShort = [];
  const resolved = {};

  for (const [account, variable] of Object.entries(SEED_PASSWORD_ENV)) {
    const raw = env?.[variable];
    const value = typeof raw === 'string' ? raw.trim() : '';

    if (!value) {
      missing.push(variable);
      continue;
    }
    if (value.length < MIN_SEED_PASSWORD_LENGTH) {
      tooShort.push(variable);
      continue;
    }
    resolved[account] = value;
  }

  if (missing.length || tooShort.length) {
    const problems = [];
    if (missing.length) {
      problems.push(`missing ${missing.join(', ')}`);
    }
    if (tooShort.length) {
      problems.push(
        `${tooShort.join(', ')} must be at least ${MIN_SEED_PASSWORD_LENGTH} characters`,
      );
    }

    throw new SeedConfigError(
      'Seeding requires explicit credentials for every seeded account: ' +
        `${problems.join('; ')}. ` +
        'Set these variables in the environment (or .env) before running the ' +
        'seed. No account is created and no data is written until they are set.',
      [...missing, ...tooShort],
    );
  }

  return resolved;
}
