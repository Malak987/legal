import { admin } from '../config/firebase.js';

/**
 * Generic Firestore helpers used by all routes.
 *
 * NOTE: For small/medium datasets we read the collection and filter/paginate
 * in memory, which keeps the API simple and dependency-free. For large
 * datasets you can swap these for native Firestore queries (where/orderBy/startAfter).
 */

const serverTimestamp = () => admin.firestore.FieldValue.serverTimestamp();

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
