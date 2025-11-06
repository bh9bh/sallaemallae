# FILE: app/routers/photos.py
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, Query
from sqlalchemy.orm import Session
from datetime import datetime, timezone
from pathlib import Path
import shutil
from typing import Optional, Dict, Any

from .. import models
from ..database import get_db
from .auth import get_current_user

router = APIRouter(prefix="/photos", tags=["photos"])

# -------- 저장/정적 경로 --------
BASE_UPLOAD = Path("uploads")
PHOTO_DIR = BASE_UPLOAD / "photos"
PHOTO_DIR.mkdir(parents=True, exist_ok=True)

# main.py에 app.mount("/static", StaticFiles(directory="uploads"), name="static") 필수
STATIC_PREFIX = "/static/photos"
ALLOWED = {".jpg", ".jpeg", ".png", ".webp"}


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _build_url(filename: str) -> str:
    return f"{STATIC_PREFIX}/{filename}"


def _photo_field_names() -> Dict[str, str]:
    """
    현재 models.Photo의 실제 컬럼명을 런타임 감지해서 반환.
    - phase(kind), file_url(url/path), created_at(옵션)
    """
    Photo = models.Photo
    # phase / kind
    phase_field = "phase" if hasattr(Photo, "phase") else ("kind" if hasattr(Photo, "kind") else None)
    # file_url / url / path
    if hasattr(Photo, "file_url"):
        file_field = "file_url"
    elif hasattr(Photo, "url"):
        file_field = "url"
    elif hasattr(Photo, "path"):
        file_field = "path"
    else:
        file_field = "file_url"  # DB에 없더라도 setattr로 넣어보되, 없는 경우 무시됨

    created_at_field = "created_at" if hasattr(Photo, "created_at") else None

    return {
        "phase": phase_field,      # None이면 컬럼이 없는 모델
        "file": file_field,
        "created_at": created_at_field,
    }


def _normalize_photo_dict(p: models.Photo) -> Dict[str, Any]:
    names = _photo_field_names()
    # file_url 통일
    file_url = getattr(p, names["file"], None) or ""
    # phase 통일
    phase_value = ""
    if names["phase"]:
        phase_value = getattr(p, names["phase"], "") or ""
    # created_at 통일
    created = _now_iso()
    if names["created_at"]:
        created = (getattr(p, names["created_at"], None) or created)
        if isinstance(created, datetime):
            created = created.astimezone(timezone.utc).isoformat()

    return {
        "id": p.id,
        "rental_id": p.rental_id,
        "phase": phase_value,   # BEFORE / AFTER (없으면 빈 문자열)
        "file_url": file_url,   # 서버 내부 표준
        "url": file_url,        # 클라이언트 호환
        "created_at": created,
    }


@router.post("/upload", status_code=201)
async def upload_photo(
    rental_id: Optional[int] = Form(None),
    rental_id_alias: Optional[int] = Form(None, alias="rentalId"),
    phase: Optional[str] = Form(None),
    kind: Optional[str] = Form(None),  # phase alias
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """
    업로드 폼 키 허용:
      - rental_id 또는 rentalId
      - phase 또는 kind (BEFORE/AFTER)
      - file
    """
    rid = rental_id if rental_id is not None else rental_id_alias
    if not rid:
        raise HTTPException(status_code=422, detail="rental_id is required")

    # 대여 존재/소유 확인(원하면 소유 확인 주석 해제)
    rental = db.get(models.Rental, rid)
    if not rental:
        raise HTTPException(status_code=404, detail="Rental not found")
    # if rental.user_id != current_user.id and not getattr(current_user, "is_admin", False):
    #     raise HTTPException(status_code=403, detail="Not allowed")

    # phase/확장자 체크
    phase_val = (phase or kind or "").strip().upper()
    if phase_val not in ("BEFORE", "AFTER"):
        raise HTTPException(status_code=400, detail="phase must be BEFORE or AFTER")

    ext = Path(file.filename or "").suffix.lower()
    if ext not in ALLOWED:
        raise HTTPException(status_code=400, detail="Unsupported file type")

    # 파일 저장
    ts = datetime.utcnow().strftime("%Y%m%d%H%M%S%f")
    fname = f"rental{rid}_{phase_val}_{ts}{ext}"
    dst = PHOTO_DIR / fname
    try:
        with dst.open("wb") as f:
            shutil.copyfileobj(file.file, f)
    except Exception as e:
        print("[/photos/upload] save ERROR:", repr(e))
        raise HTTPException(status_code=500, detail="Upload failed")

    url = _build_url(fname)

    # DB insert: 모델 컬럼명에 맞춰 동적 set
    names = _photo_field_names()
    photo = models.Photo()
    photo.rental_id = rid
    if names["phase"]:
        setattr(photo, names["phase"], phase_val)
    if names["file"]:
        setattr(photo, names["file"], url)
    # created_at은 DB default면 생략

    try:
        db.add(photo)
        db.commit()
        db.refresh(photo)
    except Exception as e:
        # 롤백 및 파일 삭제
        db.rollback()
        try:
            if dst.exists():
                dst.unlink()
        except Exception:
            pass
        print("[/photos/upload] DB ERROR:", repr(e))
        raise HTTPException(status_code=500, detail="Upload failed")

    return _normalize_photo_dict(photo)


# 조회(여러 alias 제공)
@router.get("/by-rental/{rental_id}")
def list_photos_by_rental(rental_id: int, db: Session = Depends(get_db)):
    rows = (
        db.query(models.Photo)
        .filter(models.Photo.rental_id == rental_id)
        .order_by(models.Photo.id.desc())
        .all()
    )
    return [_normalize_photo_dict(p) for p in rows]


@router.get("/by_rental/{rental_id}")
def list_photos_by_rental_snake(rental_id: int, db: Session = Depends(get_db)):
    return list_photos_by_rental(rental_id, db)


# /photos?rental_id=123 지원
@router.get("")
def list_photos_query(
    rental_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
):
    if not rental_id:
        return []
    return list_photos_by_rental(rental_id, db)


@router.delete("/{photo_id}", status_code=204)
def delete_photo(
    photo_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    p = db.get(models.Photo, photo_id)
    if not p:
        raise HTTPException(status_code=404, detail="Photo not found")

    rental = db.get(models.Rental, p.rental_id)
    if not rental or rental.user_id != user.id:
        raise HTTPException(status_code=403, detail="Not allowed")

    # 실제 파일 삭제
    names = _photo_field_names()
    file_url = getattr(p, names["file"], None) or ""
    if file_url.startswith(f"{STATIC_PREFIX}/"):
        try:
            fname = file_url[len(f"{STATIC_PREFIX}/") :]
            path = PHOTO_DIR / fname
            if path.exists():
                path.unlink()
        except Exception as e:
            print(f"[/photos/{photo_id} DELETE] file unlink failed:", repr(e))

    db.delete(p)
    db.commit()
    return
