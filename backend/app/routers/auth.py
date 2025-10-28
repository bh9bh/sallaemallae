# app/routers/auth.py
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status
from jose import JWTError, jwt
from passlib.context import CryptContext
from pydantic import BaseModel
from sqlalchemy.orm import Session

from .. import models, schemas
from ..database import get_db

router = APIRouter(prefix="/auth", tags=["auth"])

# ----- crypto / jwt -----
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
SECRET_KEY = "dev_secret_change_me"     # 실제 운영에서는 환경변수에서 로드
ALGORITHM = "HS256"

def hash_pw(pw: str) -> str:
    return pwd_context.hash(pw)

def verify_pw(pw: str, hashed: Optional[str]) -> bool:
    if not hashed:
        return False
    return pwd_context.verify(pw, hashed)

def make_token(user_id: int) -> str:
    payload = {"sub": str(user_id), "exp": datetime.utcnow() + timedelta(days=1)}
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)

# ----- current user -----
from fastapi.security import OAuth2PasswordBearer
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")

def get_current_user(
    db: Session = Depends(get_db),
    token: str = Depends(oauth2_scheme),
) -> models.User:
    cred_exc = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        sub = payload.get("sub")
        if sub is None:
            raise cred_exc
        user_id = int(sub)
    except (JWTError, ValueError):
        raise cred_exc

    user = db.get(models.User, user_id)
    if user is None:
        raise cred_exc
    return user

# ----- pydantic for json login (프런트 JSON용) -----
class LoginJSON(BaseModel):
    username: str
    password: str

# ----- routes -----
@router.post("/register", response_model=schemas.UserOut)
def register(user: schemas.UserCreate, db: Session = Depends(get_db)):
    exist = db.query(models.User).filter(models.User.email == user.email).first()
    if exist:
        raise HTTPException(status_code=400, detail="Email already registered")

    u = models.User(
        email=user.email,
        hashed_password=hash_pw(user.password),
        name=user.name,
    )
    db.add(u)
    db.commit()
    db.refresh(u)
    return u

@router.post("/login", response_model=schemas.Token)
async def login(request: Request, db: Session = Depends(get_db)):
    """
    ✅ JSON(application/json) 또는 x-www-form-urlencoded / multipart 모두 처리
    - JSON: { "username": "...", "password": "..." }
    - FORM: username=...&password=...
    """
    username: Optional[str] = None
    password: Optional[str] = None

    ct = (request.headers.get("content-type") or "").lower()

    # 1) JSON 시도
    if "application/json" in ct:
        try:
            data = await request.json()
            if isinstance(data, dict):
                username = str(data.get("username") or "")
                password = str(data.get("password") or "")
        except Exception:
            # json 파싱 실패 → 폼으로 폴백
            pass

    # 2) 폼 시도
    if not username or not password:
        try:
            form = await request.form()
            if form:
                username = str(form.get("username") or username or "")
                password = str(form.get("password") or password or "")
        except Exception:
            pass

    # 3) 최종 검증
    if not username or not password:
        raise HTTPException(status_code=400, detail="username and password are required")

    user = db.query(models.User).filter(models.User.email == username).first()
    if not user or not verify_pw(password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
        )

    return {"access_token": make_token(user.id), "token_type": "bearer"}

@router.get("/me", response_model=schemas.UserOut)
def me(current_user: models.User = Depends(get_current_user)):
    return current_user
