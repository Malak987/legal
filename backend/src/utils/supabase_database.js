
/**
 * Generic Supabase/PostgreSQL helpers used by all routes.
 *
 * The compatibility-shaped collection/query API is implemented by the
 * Supabase adapter and issues PostgREST/PostgreSQL operations only.
 */

const serverTimestamp = () => ({ __serverTimestamp: true });

/**
 * Normalises a PostgreSQL timestamp, `Date`, ISO string, epoch-millis value,
 * or serialized legacy Firestore Timestamp to milliseconds so records can be
 * ordered in memory.
 *
 * A stable timestamp normalization keeps route sorting deterministic when
 * nullable PostgreSQL timestamp values are returned, while preserving the
 * legacy Firebase fallback's serialized timestamp shape.
 *
 * Missing or unparseable values become `0` rather than `NaN`, so documents are
 * kept in the result set instead of being dropped or poisoning the sort.
 */
export function toMillis(value) {
  if (value === null || value === undefined) return 0;
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'number') return Number.isFinite(value) ? value : 0;
  if (typeof value === 'object' && typeof value._seconds === 'number') {
    const seconds = value._seconds * 1000;
    const nanos = Number(value._nanoseconds ?? value.nanoseconds ?? 0);
    return Number.isFinite(seconds) && Number.isFinite(nanos)
      ? seconds + Math.floor(nanos / 1e6)
      : 0;
  }
  const parsed = Date.parse(value);
  return Number.isNaN(parsed) ? 0 : parsed;
}

/**
 * Sorts documents in place, newest first, by the given timestamp field.
 * Documents without a usable timestamp sort last.
 */
export function sortByDesc(docs, field = 'createdAt') {
  return docs.sort((a, b) => toMillis(b?.[field]) - toMillis(a?.[field]));
}

export async function listDocs(db, collection, options = {}) {
  const {
    search = '',
    searchFields = [],
    filters = {},
    sort = 'createdAt',
    order = 'desc',
    page = 1,
    limit = 20,
  } = options;

  const snap = await db.collection(collection).get();
  let docs = snap.docs.map((d) => ({ id: d.id, ...d.data() }));

  // Apply exact-match filters
  for (const [key, value] of Object.entries(filters)) {
    if (value !== undefined && value !== null && value !== '') {
      docs = docs.filter((d) => d[key] === value);
    }
  }

  // Apply free-text search across the given fields
  if (search && searchFields.length) {
    docs = docs.filter((d) =>
      searchFields.some((f) =>
        String(d[f] ?? '')
          .toLowerCase()
          .includes(search),
      ),
    );
  }

  // Sort
  docs.sort((a, b) => {
    const av = a[sort];
    const bv = b[sort];
    if (av === bv) return 0;
    if (av === undefined || av === null) return 1;
    if (bv === undefined || bv === null) return -1;
    return order === 'asc' ? (av > bv ? 1 : -1) : av < bv ? 1 : -1;
  });

  const total = docs.length;
  const start = (page - 1) * limit;
  const items = docs.slice(start, start + limit);

  return { items, total, page, limit, totalPages: Math.ceil(total / limit) || 1 };
}

export async function getDocById(db, collection, id) {
  const snap = await db.collection(collection).doc(id).get();
  if (!snap.exists) return null;
  return { id: snap.id, ...snap.data() };
}

export async function createDoc(db, collection, data) {
  const ref = await db.collection(collection).add({
    ...data,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });
  const snap = await ref.get();
  return { id: snap.id, ...snap.data() };
}

/**
 * True when PostgreSQL rejects a create because the primary/unique key exists.
 */
function isAlreadyExists(error) {
  const code = error?.code;
  return code === 6 || code === 'already-exists' || code === 'ALREADY_EXISTS';
}

/**
 * Creates a row with a caller-chosen ID, refusing to overwrite.
 *
 * `create()` uses a PostgreSQL INSERT and rejects duplicate keys atomically.
 *
 * Returns the stored document, or `null` when it already existed (callers map
 * that to a 409 rather than treating it as an error).
 */
export async function createDocWithId(db, collection, id, data) {
  const ref = db.collection(collection).doc(id);
  try {
    await ref.create({
      ...data,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
  } catch (error) {
    if (isAlreadyExists(error)) return null;
    throw error;
  }
  const snap = await ref.get();
  return { id: snap.id, ...snap.data() };
}

export async function updateDoc(db, collection, id, data) {
  const ref = db.collection(collection).doc(id);
  const snap = await ref.get();
  if (!snap.exists) return null;
  await ref.update({ ...data, updatedAt: serverTimestamp() });
  const updated = await ref.get();
  return { id: updated.id, ...updated.data() };
}

export async function deleteDoc(db, collection, id) {
  const ref = db.collection(collection).doc(id);
  const snap = await ref.get();
  if (!snap.exists) return false;
  await ref.delete();
  return true;
}

export { serverTimestamp };
