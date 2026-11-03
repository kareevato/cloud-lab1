async function remember(client, key, loader, ttl = 45) {
  if (!client) return [loader(), "BYPASS"];
  try {
    const raw = await client.get(key);
    if (raw != null) return [JSON.parse(raw), "HIT"];
    const data = loader();
    if (data != null) await client.setEx(key, ttl, JSON.stringify(data));
    return [data, "MISS"];
  } catch {
    return [loader(), "BYPASS"];
  }
}

async function invalidate(client, keys) {
  if (!client || !keys.length) return;
  try {
    await client.del(keys);
  } catch {
    return;
  }
}

module.exports = { remember, invalidate };
