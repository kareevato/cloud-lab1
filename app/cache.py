import json
import os
import time

import redis

NOTES_LIST_KEY = "notes:list"
HITS_KEY = "cache:hits"
MISSES_KEY = "cache:misses"

_client = None


def _enabled() -> bool:
    flag = os.getenv("CACHE_ENABLED", "true").lower()
    return flag in ("1", "true", "yes") and bool(os.getenv("REDIS_URL"))


def ttl_seconds() -> int:
    return int(os.getenv("CACHE_TTL_SECONDS", "45"))


def client():
    global _client
    if not _enabled():
        return None
    if _client is None:
        _client = redis.Redis.from_url(
            os.environ["REDIS_URL"],
            socket_timeout=1,
            socket_connect_timeout=1,
            decode_responses=True,
        )
    return _client


def _incr(key: str) -> None:
    redis_client = client()
    if redis_client is None:
        return
    try:
        redis_client.incr(key)
    except redis.RedisError:
        return


def _read(key: str):
    redis_client = client()
    if redis_client is None:
        return None, "BYPASS"
    try:
        raw = redis_client.get(key)
    except redis.RedisError:
        return None, "BYPASS"
    if raw is None:
        return None, "MISS"
    return json.loads(raw), "HIT"


def set_json(key: str, value, ttl: int | None = None) -> None:
    redis_client = client()
    if redis_client is None:
        return
    try:
        redis_client.setex(key, ttl if ttl is not None else ttl_seconds(), json.dumps(value))
    except redis.RedisError:
        return


def invalidate(*keys: str) -> None:
    redis_client = client()
    if redis_client is None or not keys:
        return
    try:
        redis_client.delete(*keys)
    except redis.RedisError:
        return


def remember(key: str, loader, ttl: int | None = None, cache_none: bool = False):
    """Cache-aside. A short lock keeps a stampede from hitting the database together."""
    cached, status = _read(key)
    if status == "HIT":
        _incr(HITS_KEY)
        return cached, "HIT"
    if status == "BYPASS":
        return loader(), "BYPASS"

    redis_client = client()
    got_lock = False
    try:
        got_lock = bool(redis_client.set(f"{key}:lock", "1", nx=True, ex=5))
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
    if data is not None or cache_none:
        set_json(key, data, ttl)
    if got_lock and redis_client is not None:
        try:
            redis_client.delete(f"{key}:lock")
        except redis.RedisError:
            pass
    return data, "MISS"


def stats() -> dict:
    redis_client = client()
    if redis_client is None:
        return {"enabled": False, "ttl_seconds": ttl_seconds()}
    try:
        hits = int(redis_client.get(HITS_KEY) or 0)
        misses = int(redis_client.get(MISSES_KEY) or 0)
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
