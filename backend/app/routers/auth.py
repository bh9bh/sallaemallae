# FILE: app/routers/auth.py
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from jose import jwt
from passlib.context import CryptContext
from sqlalchemy.orm import Session

from .. import models, schemas
from ..database import get_db
from ..deps import get_current_user          # ✅ 검증은 deps의 단일 경로만 사용
from ..settings import SECRET_KEY, ALGORITHM, ACCESS_TOKEN_EXPIRE_MINUTES  # ✅ 한 곳에서만 키 관리

router = APIRouter(prefix="/auth", tags=["auth"])

# -----------------------------
# Password hashing
# -----------------------------
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)

def get_password_hash(password: str) -> str:
    return pwd_context.hash(password)

# -----------------------------
# JWT
# -----------------------------
def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    # 만료는 UTC 기준으로 설정
    expire = datetime.now(timezone.utc) + (
        expires_delta or timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    )
    to_encode = data.copy()
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

# -----------------------------
# Endpoints
# -----------------------------

@router.post("/register", response_model=schemas.UserOut, status_code=201)
def register(user: schemas.UserCreate, db: Session = Depends(get_db)):
    """
    회원가입
    Body: { email, password, full_name? }
    """
    exists = db.query(models.User).filter(models.User.email == user.email).first()
    if exists:
        raise HTTPException(status_code=400, detail="Email already registered.")

    db_user = models.User(
        email=user.email,
        hashed_password=get_password_hash(user.password),
        full_name=user.full_name,
        is_admin=False,  # 기본값
    )
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    return db_user

@router.post("/login", response_model=schemas.Token)
def login(payload: schemas.UserLogin, db: Session = Depends(get_db)):
    """
    JSON 로그인
    Body: { email, password }
    """
    user = db.query(models.User).filter(models.User.email == payload.email).first()
    if not user or not verify_password(payload.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid email or password.")

    token = create_access_token({
        "sub": str(user.id),
        "email": user.email,
        "is_admin": bool(getattr(user, "is_admin", False)),
    })
    return schemas.Token(access_token=token)

@router.post("/token", response_model=schemas.Token)
def login_token(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    """
    OAuth2 Password Flow (폼 로그인용: username = email)
    """
    user = db.query(models.User).filter(models.User.email == form_data.username).first()
    if not user or not verify_password(form_data.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Incorrect username or password.")

    token = create_access_token({
        "sub": str(user.id),
        "email": user.email,
        "is_admin": bool(getattr(user, "is_admin", False)),
    })
    return schemas.Token(access_token=token)

@router.get("/me", response_model=schemas.UserOut)
def me(current_user: models.User = Depends(get_current_user)):
    """
    현재 로그인 사용자 정보.
    반드시 deps.get_current_user를 통해 같은 검증 경로를 타게 한다.
    """
    return current_user
