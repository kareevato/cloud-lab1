from sqlalchemy import Column, Integer, String

from database import Base


class NoteModel(Base):
    __tablename__ = "notes"
    id = Column(Integer, primary_key=True, index=True)
    text = Column(String, index=True)
    author = Column(String, nullable=True, index=True)
