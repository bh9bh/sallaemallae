from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List

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
