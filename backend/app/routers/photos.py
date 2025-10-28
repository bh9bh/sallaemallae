from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from sqlalchemy.orm import Session
from datetime import datetime
from pathlib import Path
import shutil
from typing import List

from .. import models
from ..database import get_db
from .auth import get_current_user

router = APIRouter(prefix="/photos", tags=["photos"])

# 업로드 폴더 보장
BASE_UPLOAD = Path("uploads")
PHOTO_DIR = BASE_UPLOAD / "photos"
PHOTO_DIR.mkdir(parents=True, exist_ok=True)

STATIC_PREFIX = "/static/photos"  # main.py에서 /static -> uploads mount 필요

ALLOWED = {".jpg", ".jpeg", ".png", ".webp"}

@router.post("/upload")
async def upload_photo(
    rental_id: int = Form(...),
    phase: str = Form(...),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),  # ✅ 로그인 사용자
):
    try:
        # 1) rental 존재 여부 검사
        rental = db.get(models.Rental, rental_id)
        if not rental:
            raise HTTPException(status_code=404, detail="Rental not found")

        # 2) phase 정규화
        phase_up = phase.upper()
        if phase_up not in ("BEFORE", "AFTER"):
            raise HTTPException(status_code=400, detail="phase must be BEFORE or AFTER")

        # 3) 확장자 검사
        sfx = Path(file.filename).suffix.lower()
        if sfx not in ALLOWED:
            raise HTTPException(status_code=400, detail="Unsupported file type")

        # 4) 저장 파일명/경로
        ts = datetime.utcnow().strftime("%Y%m%d%H%M%S%f")
        fname = f"rental{rental_id}_{phase_up}_{ts}{sfx}"
        dst = PHOTO_DIR / fname

        # 5) 실제 저장
        with dst.open("wb") as f:
            shutil.copyfileobj(file.file, f)

        file_url = f"{STATIC_PREFIX}/{fname}"  # 예: /static/photos/rental3_BEFORE_2025...

        # 6) DB 저장
        photo = models.Photo(
            rental_id=rental_id,
            phase=phase_up,
            file_url=file_url,
        )
        db.add(photo)
        db.commit()
        db.refresh(photo)

        return {
            "id": photo.id,
            "rental_id": photo.rental_id,
            "phase": photo.phase,
            "file_url": photo.file_url,
        }

    except HTTPException:
        raise
    except Exception as e:
        print("[/photos/upload] ERROR:", repr(e))
        raise HTTPException(status_code=500, detail="Upload failed")


@router.get("/by-rental/{rental_id}")
def list_photos_by_rental(rental_id: int, db: Session = Depends(get_db)):
    rows = (
        db.query(models.Photo)
        .filter(models.Photo.rental_id == rental_id)
        .order_by(models.Photo.id.desc())
        .all()
    )
    return [
        {
            "id": p.id,
            "rental_id": p.rental_id,
            "phase": p.phase,
            "file_url": p.file_url,
        }
        for p in rows
    ]


# ✅ 사진 단건 삭제 (본인 소유 대여건만)
@router.delete("/{photo_id}", status_code=204)
def delete_photo(
    photo_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    p = db.get(models.Photo, photo_id)
    if not p:
        raise HTTPException(status_code=404, detail="Photo not found")

    # 소유권 체크: 해당 사진의 rental이 현재 유저의 것인지 확인
    rental = db.get(models.Rental, p.rental_id)
    if not rental or rental.user_id != user.id:
        raise HTTPException(status_code=403, detail="Not allowed")

    # 실제 파일 삭제 (있으면)
    if p.file_url and p.file_url.startswith(f"{STATIC_PREFIX}/"):
        fname = p.file_url.split(f"{STATIC_PREFIX}/", 2)[1]
        path = PHOTO_DIR / fname
        try:
            if path.exists():
                path.unlink()
        except Exception as e:
            # 파일 삭제 실패는 DB 삭제를 막진 않음
            print(f"[/photos/{photo_id} DELETE] file unlink failed:", repr(e))

    db.delete(p)
    db.commit()
    return
