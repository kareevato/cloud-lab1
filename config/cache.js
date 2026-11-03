const ttlMs = Number(process.env.CACHE_TTL || 30) * 1000;
const maxEntries = 5000;

const store = new Map();

const get = async (key) => {
  const entry = store.get(key);
  if (!entry) {
    return null;
  }
  if (entry.expires < Date.now()) {
    store.delete(key);
    return null;
  }
  return entry.value;
};

const set = async (key, value) => {
  if (store.size >= maxEntries) {
    store.delete(store.keys().next().value);
  }
  store.set(key, { value, expires: Date.now() + ttlMs });
};

module.exports = { get, set };
