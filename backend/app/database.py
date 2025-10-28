import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base

# 디폴트는 SQLite. (원하면 MySQL/PostgreSQL로 교체 가능)
DB_URL = os.getenv("DATABASE_URL", "sqlite:///./dev.db")

# SQLite일 때는 check_same_thread 옵션이 필요
connect_args = {"check_same_thread": False} if DB_URL.startswith("sqlite") else {}

engine = create_engine(DB_URL, pool_pre_ping=True, connect_args=connect_args)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# ✅ 여기 추가: 모든 모델을 import 해서 테이블 생성
from . import models  # Product, Rental, User, Photo 등
Base.metadata.create_all(bind=engine)
