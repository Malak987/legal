import { FieldValue } from 'firebase-admin/firestore';

/**
 * Generic Firestore helpers used by all routes.
 *
 * NOTE: For small/medium datasets we read the collection and filter/paginate
 * in memory, which keeps the API simple and dependency-free. For large
 * datasets you can swap these for native Firestore queries (where/orderBy/startAfter).
 */

const serverTimestamp = () => FieldValue.serverTimestamp();

/**
 * Normalises a Firestore Timestamp, `Date`, ISO string or epoch-millis value
 * to milliseconds so records can be ordered in memory.
 *
 * Firestore needs a COMPOSITE index to combine a filter with `orderBy` on a
 * different field, and those indexes are not deployed for this project.
 * Sorting in memory keeps single-field queries working — the convention this
 * module already documents above.
 *
 * Missing or unparseable values become `0` rather than `NaN`, so documents are
 * kept in the result set instead of being dropped or poisoning the sort.
 */
export function toMillis(value) {
  if (value === null || value === undefined) return 0;
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'number') return Number.isFinite(value) ? value : 0;
  // Serialised Firestore Timestamp ({ _seconds, _nanoseconds }).
  if (typeof value === 'object' && typeof value._seconds === 'number') {
    return value._seconds * 1000 + Math.floor((value._nanoseconds ?? 0) / 1e6);
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
 * True when a Firestore write was rejected because the document exists.
 *
 * firebase-admin surfaces `ALREADY_EXISTS` either as the gRPC code `6` or as
 * the string `'already-exists'`, depending on the transport in use.
 */
function isAlreadyExists(error) {
  const code = error?.code;
  return code === 6 || code === 'already-exists' || code === 'ALREADY_EXISTS';
}

/**
 * Creates a document with a CALLER-CHOSEN id, refusing to overwrite.
 *
 * `set()` replaces a document silently; `create()` is atomic and rejects with
 * `ALREADY_EXISTS` when it is already there. That is what makes "provision this
 * profile exactly once" safe against two concurrent requests, instead of a
 * read-then-write that two callers can interleave.
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

/**
 * Replaces the whole collection with the provided documents (used by seed).
 */
export async function replaceCollection(db, collection, docs) {
  const existing = await db.collection(collection).get();
  const batch = db.batch();
  existing.docs.forEach((d) => batch.delete(d.ref));
  await batch.commit();

  const batch2 = db.batch();
  for (const doc of docs) {
    batch2.set(db.collection(collection).doc(), { ...doc, createdAt: serverTimestamp(), updatedAt: serverTimestamp() });
  }
  await batch2.commit();
  return docs.length;
}

export { serverTimestamp };
