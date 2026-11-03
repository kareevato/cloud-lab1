import json
import os
import redis

NOTES_LIST_KEY = "notes:list"
_client = None

def redis_client():
    global _client
    url = os.getenv("REDIS_URL")
    on = os.getenv("CACHE_ENABLED", "true").lower() in ("1", "true", "yes")
    if not on or not url:
        return None
    if _client is None:
        _client = redis.Redis.from_url(url, socket_timeout=1, decode_responses=True)
    return _client

def remember(key, loader):
    client = redis_client()
    ttl = int(os.getenv("CACHE_TTL_SECONDS", "45"))
    if client is None:
        return loader(), "BYPASS"
    try:
        raw = client.get(key)
        if raw is not None:
            return json.loads(raw), "HIT"
        data = loader()
        if data is not None:
            client.setex(key, ttl, json.dumps(data))
        return data, "MISS"
    except redis.RedisError:
        return loader(), "BYPASS"

def invalidate(*keys):
    client = redis_client()
    if client and keys:
        try:
            client.delete(*keys)
        except redis.RedisError:
            return

def cache_stats():
    return {"enabled": redis_client() is not None, "ttl_seconds": int(os.getenv("CACHE_TTL_SECONDS", "45"))}
