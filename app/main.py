import os
import time
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone

from fastapi import Depends, FastAPI, HTTPException, Request, Response, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel
from sqlalchemy import Column, Integer, String
from sqlalchemy.orm import Session
import jwt

from database import Base, engine, ensure_schema, get_db

SECRET_KEY = os.environ["JWT_SECRET_KEY"]
ADMIN_USERNAME = os.getenv("ADMIN_USERNAME", "admin")
ADMIN_PASSWORD = os.environ["ADMIN_PASSWORD"]
APP_VERSION = os.getenv("APP_VERSION", "local")
ALGORITHM = "HS256"
LIST_LIMIT = 50
TTL_MS = int(os.getenv("CACHE_TTL", "30")) * 1000
MAX_ENTRIES = 5000
_store = {}

security = HTTPBearer(auto_error=False)


def cache_get(key):
    entry = _store.get(key)
    if not entry:
        return None
    if entry["expires"] < time.time() * 1000:
        _store.pop(key, None)
        return None
    return entry["value"]


def cache_set(key, value):
    if len(_store) >= MAX_ENTRIES:
        _store.pop(next(iter(_store)))
    _store[key] = {"value": value, "expires": time.time() * 1000 + TTL_MS}


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


@app.get("/health")
def health_check():
    return {"status": "healthy"}


@app.get("/")
def read_root():
    return {"message": "REST API is running", "version": APP_VERSION}


@app.post("/auth/login")
def login(creds: LoginRequest):
    if creds.username == ADMIN_USERNAME and creds.password == ADMIN_PASSWORD:
        expire = datetime.now(timezone.utc) + timedelta(hours=2)
        token = jwt.encode({"sub": creds.username, "exp": expire}, SECRET_KEY, algorithm=ALGORITHM)
        return {"access_token": token, "token_type": "bearer"}
    raise unauthorized("Incorrect username or password")


@app.get("/notes")
def get_notes(db: Session = Depends(get_db)):
    rows = db.query(NoteModel).order_by(NoteModel.id.desc()).limit(LIST_LIMIT).all()
    return [note_to_dict(row) for row in rows]


@app.get("/notes/{note_id}")
def get_note(note_id: int, request: Request, response: Response, db: Session = Depends(get_db)):
    key = "note:" + str(note_id)
    bypass = request.headers.get("cache-control") == "no-cache"

    if not bypass:
        cached = cache_get(key)
        if cached is not None:
            response.headers["X-Cache"] = "HIT"
            return cached

    note = db.query(NoteModel).filter(NoteModel.id == note_id).first()
    if note is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Note not found")

    payload = note_to_dict(note)
    if not bypass:
        cache_set(key, payload)
    response.headers["X-Cache"] = "BYPASS" if bypass else "MISS"
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
    return note_to_dict(db_note)
