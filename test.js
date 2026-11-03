const test = require("node:test");
const assert = require("node:assert/strict");
const { remember, invalidate } = require("./cache");

function memory() {
  const store = new Map();
  return {
    get: (key) => Promise.resolve(store.has(key) ? store.get(key) : null),
    setEx: (key, _ttl, value) => (store.set(key, value), Promise.resolve()),
    del: (keys) => (keys.forEach((key) => store.delete(key)), Promise.resolve()),
  };
}

test("cache-aside hits after the first miss", async () => {
  const client = memory();
  let loads = 0;
  const loader = () => ({ id: ++loads });
  const [miss, missState] = await remember(client, "notes:list", loader, 45);
  const [hit, hitState] = await remember(client, "notes:list", loader, 45);
  assert.equal(missState, "MISS");
  assert.equal(hitState, "HIT");
  assert.deepEqual(hit, miss);
  assert.equal(loads, 1);
  await invalidate(client, ["notes:list"]);
  const [, again] = await remember(client, "notes:list", loader, 45);
  assert.equal(again, "MISS");
});
