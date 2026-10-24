import { fromDbRow } from '../config/supabase.js';

/** True only for a verified request-scoped Supabase JWT client. */
export function hasSupabaseRequest(req) {
  return req?.supabaseDb?._isAuthenticatedRequest === true;
}

/** Fails closed: caller data access must never fall back to service_role. */
export function requestDatabase(req) {
  if (!hasSupabaseRequest(req)) {
    const error = new Error('A verified Supabase caller session is required.');
    error.status = 401;
    throw error;
  }
  return req.supabaseDb;
}

/** Call a business RPC using the verified caller JWT, never service_role. */
export async function callUserRpc(req, functionName, parameters = {}) {
  if (!hasSupabaseRequest(req)) {
    const error = new Error('Authenticated Supabase access is not configured.');
    error.status = 401;
    throw error;
  }
  return req.supabaseDb.rpcAsUser(functionName, parameters);
}

/** Convert a JSON row returned by PostgreSQL to the API's camelCase shape. */
export function rpcRow(collectionName, row) {
  if (!row || typeof row !== 'object' || Array.isArray(row)) return null;
  const id = row.id === undefined || row.id === null ? undefined : String(row.id);
  return { ...(id === undefined ? {} : { id }), ...fromDbRow(collectionName, row) };
}

/** Extract a stable SQL/business error token from a PostgREST RPC exception. */
export function rpcErrorToken(error) {
  const detail = String(error?.details || '').trim();
  const message = String(error?.message || '').trim();
  const tail = (detail || message).split(':').at(-1)?.trim() || '';
  return /^[A-Z][A-Z0-9_]*$/.test(tail) ? tail : '';
}
