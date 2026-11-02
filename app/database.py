import os

from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import declarative_base, sessionmaker

DATABASE_URL = os.environ["DATABASE_URL"]

connect_args = {"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}
engine = create_engine(DATABASE_URL, pool_pre_ping=True, connect_args=connect_args)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def ensure_schema() -> None:
    # Models must be imported before this runs so they are registered on Base.
    Base.metadata.create_all(bind=engine)
    inspector = inspect(engine)
    if not inspector.has_table("notes"):
        return
    columns = {column["name"] for column in inspector.get_columns("notes")}
    if "author" not in columns:
        with engine.begin() as connection:
            connection.execute(text("ALTER TABLE notes ADD COLUMN author VARCHAR"))
