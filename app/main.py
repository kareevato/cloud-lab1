import os
from datetime import datetime, timedelta
from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy import Column, Integer, String
from sqlalchemy.orm import Session
from pydantic import BaseModel
import jwt

from database import Base, engine, get_db

SECRET_KEY = os.getenv("JWT_SECRET_KEY", "super-secret-jwt-key-2026")
ALGORITHM = "HS256"

app = FastAPI(
    title="Cloud Lab API",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc"
)

security = HTTPBearer()

class NoteModel(Base):
    __tablename__ = "notes"
    id = Column(Integer, primary_key=True, index=True)
    text = Column(String, index=True)

Base.metadata.create_all(bind=engine)

class NoteCreate(BaseModel):
    text: str

class LoginRequest(BaseModel):
    username: str
    password: str

def verify_token(credentials: HTTPAuthorizationCredentials = Depends(security)):
    token = credentials.credentials
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        return payload.get("sub")
    except jwt.PyJWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired JWT token",
            headers={"WWW-Authenticate": "Bearer"},
        )

@app.get("/health")
def health_check():
    return {"status": "healthy"}

@app.get("/")
def read_root():
    return {"message": "REST API is running"}

@app.post("/auth/login")
def login(creds: LoginRequest):
    if creds.username == "admin" and creds.password == "admin123":
        expire = datetime.utcnow() + timedelta(hours=2)
        token = jwt.encode({"sub": creds.username, "exp": expire}, SECRET_KEY, algorithm=ALGORITHM)
        return {"access_token": token, "token_type": "bearer"}
    
    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Incorrect username or password"
    )

@app.get("/notes")
def get_notes(db: Session = Depends(get_db)):
    return db.query(NoteModel).all()

@app.post("/notes", dependencies=[Depends(verify_token)])
def create_note(note: NoteCreate, db: Session = Depends(get_db)):
    db_note = NoteModel(text=note.text)
    db.add(db_note)
    db.commit()
    db.refresh(db_note)
    return db_note
