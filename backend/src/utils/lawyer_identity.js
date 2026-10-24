import { requestDatabase } from './supabase_rpc.js';

/**
 * Resolves the caller's single lawyer catalogue row through the verified
 * application profile ID. `lawyers.id` is not assumed to equal the Supabase
 * Auth UUID or the application-user ID.
 *
 * Ambiguous/missing relationships fail closed and are never inferred from an
 * email, caller payload, or display name.
 */
export async function resolveOwnLawyerId(req) {
  if (Object.hasOwn(req, '_resolvedOwnLawyerId')) return req._resolvedOwnLawyerId;
  const profileId = req.user?.uid;
  if (!profileId) {
    req._resolvedOwnLawyerId = null;
    return null;
  }

  const matches = await requestDatabase(req)
    .collection('lawyers')
    .where('userId', '==', profileId)
    .limit(2)
    .get();
  req._resolvedOwnLawyerId = matches.docs.length === 1 ? matches.docs[0].id : null;
  return req._resolvedOwnLawyerId;
}

export async function isAssignedLawyer(req, lawyerId) {
  if (req.user?.role !== 'lawyer' || !lawyerId) return false;
  const ownLawyerId = await resolveOwnLawyerId(req);
  return ownLawyerId !== null && ownLawyerId === lawyerId;
}
