# app/routers/reviews.py
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List

from ..database import get_db
from ..deps import get_current_user
from .. import models, schemas

router = APIRouter(prefix="/reviews", tags=["reviews"])

@router.post("", response_model=schemas.ReviewOut, status_code=201)
def create_review(
    payload: schemas.ReviewCreate,  # 🔁 ReviewIn → ReviewCreate
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    # 1) 렌탈 소유자/상태 체크
    r = db.get(models.Rental, payload.rental_id)
    if not r:
        raise HTTPException(status_code=404, detail="Rental not found")
    if r.user_id != user.id:
        raise HTTPException(status_code=403, detail="Forbidden")

    # CLOSED 이후만 리뷰 허용 (모델에서 EXPIRED를 쓰지 않는 설계라면 CLOSED만 체크)
    if r.status not in (models.RentalStatus.CLOSED,):
        raise HTTPException(status_code=400, detail="You can review only after close")

    # 2) 한 렌탈당 리뷰 1회 제한
    exists = (
        db.query(models.Review)
        .filter(models.Review.rental_id == r.id, models.Review.user_id == user.id)
        .first()
    )
    if exists:
        raise HTTPException(status_code=400, detail="Review already exists for this rental")

    # 3) rating 범위 확인 (1~5)
    if not (1 <= payload.rating <= 5):
        raise HTTPException(status_code=422, detail="rating must be between 1 and 5")

    rev = models.Review(
        rental_id=r.id,
        product_id=r.product_id,
        user_id=user.id,
        rating=payload.rating,
        comment=payload.comment,
    )
    db.add(rev)
    db.commit()
    db.refresh(rev)
    return rev


@router.get("/by-product/{product_id}", response_model=List[schemas.ReviewOut])
def by_product(
    product_id: int,
    db: Session = Depends(get_db),
):
    rows = (
        db.query(models.Review)
        .filter(models.Review.product_id == product_id)
        .order_by(models.Review.id.desc())
        .all()
    )
    return rows
