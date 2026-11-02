import cache
import fakeredis
import pytest
from fastapi.testclient import TestClient

cache._client = fakeredis.FakeRedis(decode_responses=True)

import main
from database import SessionLocal
from models import NoteModel


@pytest.fixture
def client():
    cache._client.flushall()
    with TestClient(main.app) as test_client:
        db = SessionLocal()
        db.query(NoteModel).delete()
        db.commit()
        db.close()
        yield test_client


def auth_headers(client):
    response = client.post("/auth/login", json={"username": "admin", "password": "test-pass"})
    assert response.status_code == 200
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def test_login_rejects_bad_password(client):
    response = client.post("/auth/login", json={"username": "admin", "password": "nope"})
    assert response.status_code == 401


def test_list_is_cache_aside_and_write_invalidates_it(client):
    headers = auth_headers(client)
    first = client.get("/notes")
    assert first.status_code == 200
    assert first.headers["X-Cache"] == "MISS"
    assert first.json() == []

    second = client.get("/notes")
    assert second.headers["X-Cache"] == "HIT"

    created = client.post("/notes", json={"text": "hello"}, headers=headers)
    assert created.status_code == 200
    body = created.json()
    assert body["text"] == "hello"
    assert body["author"] == "admin"

    refreshed = client.get("/notes")
    assert refreshed.headers["X-Cache"] == "MISS"
    assert refreshed.json()[0]["text"] == "hello"

    again = client.get("/notes")
    assert again.headers["X-Cache"] == "HIT"


def test_note_and_author_reads_are_cached(client):
    headers = auth_headers(client)
    created = client.post("/notes", json={"text": "one"}, headers=headers)
    note_id = created.json()["id"]

    by_id = client.get(f"/notes/{note_id}")
    assert by_id.headers["X-Cache"] == "MISS"
    assert client.get(f"/notes/{note_id}").headers["X-Cache"] == "HIT"

    author = client.get("/authors/admin")
    assert author.status_code == 200
    assert author.headers["X-Cache"] == "MISS"
    assert author.json()["notes_count"] == 1
    assert client.get("/authors/admin").headers["X-Cache"] == "HIT"

    assert client.get("/notes/999999").status_code == 404


def test_notes_require_jwt(client):
    assert client.post("/notes", json={"text": "nope"}).status_code == 401


def test_cache_stats(client):
    client.get("/notes")
    client.get("/notes")
    stats = client.get("/cache/stats")
    assert stats.status_code == 200
    payload = stats.json()
    assert payload["enabled"] is True
    assert payload["hits"] == 1
    assert payload["misses"] == 1
    assert payload["ttl_seconds"] == 45
