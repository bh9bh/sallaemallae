from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy.orm import Session
from typing import List, Optional

from ..database import get_db
from ..deps import get_current_user
from .. import models, schemas

router = APIRouter(prefix="/admin", tags=["admin"])

def _assert_admin(u: models.User):
    if not getattr(u, "is_admin", False):
        raise HTTPException(status_code=403, detail="Admin only")

@router.get("/rentals/pending", response_model=List[schemas.RentalOut])
def list_pending(
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    _assert_admin(user)
    rows = (
        db.query(models.Rental)
        .filter(models.Rental.status == models.RentalStatus.PENDING)
        .order_by(models.Rental.id.desc())
        .all()
    )
    # pydantic v2: model_validate / model_dump 경로로 안전 직렬화
    return [schemas.RentalOut.model_validate(r) for r in rows]

@router.patch("/rentals/{rental_id}/approve", response_model=schemas.RentalOut)
def approve(
    rental_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    _assert_admin(user)
    r = db.get(models.Rental, rental_id)
    if not r:
        raise HTTPException(status_code=404, detail="Rental not found")
    if r.status != models.RentalStatus.PENDING:
        raise HTTPException(status_code=400, detail="Only PENDING can be approved")

    r.status = models.RentalStatus.ACTIVE
    db.add(r); db.commit(); db.refresh(r)
    return schemas.RentalOut.model_validate(r)

@router.patch("/rentals/{rental_id}/reject", response_model=schemas.RentalOut)
def reject(
    rental_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    _assert_admin(user)
    r = db.get(models.Rental, rental_id)
    if not r:
        raise HTTPException(status_code=404, detail="Rental not found")
    if r.status != models.RentalStatus.PENDING:
        raise HTTPException(status_code=400, detail="Only PENDING can be rejected")

    r.status = models.RentalStatus.REJECTED
    db.add(r); db.commit(); db.refresh(r)
    return schemas.RentalOut.model_validate(r)

# -------------------------------------------------------------------------
# ✅ 관리자: 리뷰 관리
# 1) 목록 조회: GET /admin/reviews?product_id=&rating=
# 2) 삭제:     DELETE /admin/reviews/{review_id}
# -------------------------------------------------------------------------

@router.get("/reviews", response_model=List[schemas.ReviewOut])
def admin_list_reviews(
    product_id: Optional[int] = None,
    rating: Optional[int] = None,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    """
    관리자 리뷰 목록.
    - product_id 지정 시 해당 상품 리뷰만
    - rating 지정 시 해당 평점만
    - 둘 다 없으면 전체 리뷰
    """
    _assert_admin(user)

    q = db.query(models.Review)
    if product_id is not None:
        q = q.filter(models.Review.product_id == product_id)
    if rating is not None:
        q = q.filter(models.Review.rating == rating)

    rows = q.order_by(models.Review.id.desc()).all()
    return [schemas.ReviewOut.model_validate(r) for r in rows]

@router.delete("/reviews/{review_id}", status_code=status.HTTP_204_NO_CONTENT)
def admin_delete_review(
    review_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    """
    관리자 리뷰 삭제 (하드 삭제).
    필요 시 soft-delete로 변경 가능: 컬럼 is_deleted 추가 후 True로 세팅.
    """
    _assert_admin(user)

    review = db.get(models.Review, review_id)
    if review is None:
        raise HTTPException(status_code=404, detail="Review not found")

    db.delete(review)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
