import json
import os
import time

import redis

NOTES_LIST_KEY = "notes:list"
HITS_KEY = "cache:hits"
MISSES_KEY = "cache:misses"
_redis = None


def _cache_enabled() -> bool:
    flag = os.getenv("CACHE_ENABLED", "true").lower()
    return flag in ("1", "true", "yes") and bool(os.getenv("REDIS_URL"))


def ttl_seconds() -> int:
    return int(os.getenv("CACHE_TTL_SECONDS", "45"))


def redis_client():
    global _redis
    if not _cache_enabled():
        return None
    if _redis is None:
        _redis = redis.Redis.from_url(
            os.environ["REDIS_URL"],
            socket_timeout=1,
            socket_connect_timeout=1,
            decode_responses=True,
        )
    return _redis


def _incr(key: str) -> None:
    client = redis_client()
    if client is None:
        return
    try:
        client.incr(key)
    except redis.RedisError:
        return


def _read(key: str):
    client = redis_client()
    if client is None:
        return None, "BYPASS"
    try:
        raw = client.get(key)
    except redis.RedisError:
        return None, "BYPASS"
    if raw is None:
        return None, "MISS"
    return json.loads(raw), "HIT"


def set_json(key: str, value, ttl: int | None = None) -> None:
    client = redis_client()
    if client is None:
        return
    try:
        client.setex(key, ttl if ttl is not None else ttl_seconds(), json.dumps(value))
    except redis.RedisError:
        return


def invalidate(*keys: str) -> None:
    client = redis_client()
    if client is None or not keys:
        return
    try:
        client.delete(*keys)
    except redis.RedisError:
        return


def remember(key: str, loader, ttl: int | None = None):
    """Cache-aside. A short lock keeps a stampede from hitting the database together."""
    cached, status = _read(key)
    if status == "HIT":
        _incr(HITS_KEY)
        return cached, "HIT"
    if status == "BYPASS":
        return loader(), "BYPASS"

    client = redis_client()
    got_lock = False
    try:
        got_lock = bool(client.set(f"{key}:lock", "1", nx=True, ex=5))
    except redis.RedisError:
        return loader(), "BYPASS"

    if not got_lock:
        time.sleep(0.1)
        cached, status = _read(key)
        if status == "HIT":
            _incr(HITS_KEY)
            return cached, "HIT"

    _incr(MISSES_KEY)
    data = loader()
    if data is not None:
        set_json(key, data, ttl)
    if got_lock and client is not None:
        try:
            client.delete(f"{key}:lock")
        except redis.RedisError:
            pass
    return data, "MISS"


def cache_stats() -> dict:
    client = redis_client()
    if client is None:
        return {"enabled": False, "ttl_seconds": ttl_seconds()}
    try:
        hits = int(client.get(HITS_KEY) or 0)
        misses = int(client.get(MISSES_KEY) or 0)
    except redis.RedisError:
        return {"enabled": True, "error": "redis_unavailable", "ttl_seconds": ttl_seconds()}
    total = hits + misses
    return {
        "enabled": True,
        "hits": hits,
        "misses": misses,
        "hit_ratio": round(hits / total, 4) if total else 0,
        "ttl_seconds": ttl_seconds(),
    }
