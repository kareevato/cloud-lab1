import json
import os
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone

from fastapi import Depends, FastAPI, HTTPException, Response, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel
from sqlalchemy import Column, Integer, String
from sqlalchemy.orm import Session
import jwt
import redis

from database import Base, engine, ensure_schema, get_db

SECRET_KEY = os.environ["JWT_SECRET_KEY"]
ADMIN_USERNAME = os.getenv("ADMIN_USERNAME", "admin")
ADMIN_PASSWORD = os.environ["ADMIN_PASSWORD"]
APP_VERSION = os.getenv("APP_VERSION", "local")
ALGORITHM = "HS256"
LIST_LIMIT = 50
NOTES_LIST_KEY = "notes:list"
_redis = None

security = HTTPBearer(auto_error=False)


def redis_client():
    global _redis
    url = os.getenv("REDIS_URL")
    on = os.getenv("CACHE_ENABLED", "true").lower() in ("1", "true", "yes")
    if not on or not url:
        return None
    if _redis is None:
        _redis = redis.Redis.from_url(url, socket_timeout=1, decode_responses=True)
    return _redis


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


class NoteModel(Base):
    __tablename__ = "notes"
    id = Column(Integer, primary_key=True, index=True)
    text = Column(String, index=True)
    author = Column(String, nullable=True, index=True)


@asynccontextmanager
async def lifespan(_app: FastAPI):
    ensure_schema()
    yield
    engine.dispose()
    client = redis_client()
    if client is not None:
        try:
            client.close()
        except Exception:
            pass


app = FastAPI(
    title="Cloud Lab API",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
    lifespan=lifespan,
)


class NoteCreate(BaseModel):
    text: str


class LoginRequest(BaseModel):
    username: str
    password: str


def unauthorized(detail: str) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=detail,
        headers={"WWW-Authenticate": "Bearer"},
    )


def verify_token(credentials: HTTPAuthorizationCredentials | None = Depends(security)) -> str:
    if credentials is None:
        raise unauthorized("Not authenticated")
    try:
        payload = jwt.decode(credentials.credentials, SECRET_KEY, algorithms=[ALGORITHM])
    except jwt.PyJWTError:
        raise unauthorized("Invalid or expired JWT token")
    subject = payload.get("sub")
    if not subject:
        raise unauthorized("Invalid or expired JWT token")
    return subject


def note_to_dict(note: NoteModel) -> dict:
    return {"id": note.id, "text": note.text, "author": note.author}


def mark_cache(response: Response, cache_status: str) -> None:
    response.headers["X-Cache"] = cache_status


@app.get("/health")
def health_check():
    return {"status": "healthy"}


@app.get("/")
def read_root():
    return {"message": "REST API is running", "version": APP_VERSION}


@app.get("/cache/stats")
def read_cache_stats():
    return cache_stats()


@app.post("/auth/login")
def login(creds: LoginRequest):
    if creds.username == ADMIN_USERNAME and creds.password == ADMIN_PASSWORD:
        expire = datetime.now(timezone.utc) + timedelta(hours=2)
        token = jwt.encode({"sub": creds.username, "exp": expire}, SECRET_KEY, algorithm=ALGORITHM)
        return {"access_token": token, "token_type": "bearer"}
    raise unauthorized("Incorrect username or password")


@app.get("/notes")
def get_notes(response: Response, db: Session = Depends(get_db)):
    def load():
        rows = db.query(NoteModel).order_by(NoteModel.id.desc()).limit(LIST_LIMIT).all()
        return [note_to_dict(row) for row in rows]

    payload, cache_status = remember(NOTES_LIST_KEY, load)
    mark_cache(response, cache_status)
    return payload


@app.get("/notes/{note_id}")
def get_note(note_id: int, response: Response, db: Session = Depends(get_db)):
    def load():
        note = db.query(NoteModel).filter(NoteModel.id == note_id).first()
        if note is None:
            return None
        return note_to_dict(note)

    payload, cache_status = remember(f"note:{note_id}", load)
    if payload is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Note not found")
    mark_cache(response, cache_status)
    return payload


@app.get("/authors/{author}")
def get_author(author: str, response: Response, db: Session = Depends(get_db)):
    def load():
        count = db.query(NoteModel).filter(NoteModel.author == author).count()
        return {"author": author, "notes_count": count}

    payload, cache_status = remember(f"author:{author}", load)
    mark_cache(response, cache_status)
    return payload


@app.post("/notes")
def create_note(
    note: NoteCreate,
    db: Session = Depends(get_db),
    author: str = Depends(verify_token),
):
    db_note = NoteModel(text=note.text, author=author)
    db.add(db_note)
    db.commit()
    db.refresh(db_note)
    invalidate(NOTES_LIST_KEY, f"author:{author}")
    return note_to_dict(db_note)
