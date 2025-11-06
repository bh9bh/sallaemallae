# FILE: app/routers/reviews_summary.py
from typing import Optional
from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session
from sqlalchemy import func, select

from app.database import get_db
from app import models

router = APIRouter(prefix="/reviews", tags=["reviews"])

class ReviewSummaryOut(BaseModel):
    product_id: int
    rating_avg: Optional[float] = None
    rating_count: int = 0

    model_config = {"from_attributes": True}

@router.get("/summary/{product_id}", response_model=ReviewSummaryOut, summary="상품별 리뷰 요약")
def get_review_summary(product_id: int, db: Session = Depends(get_db)):
    stmt = (
        select(
            func.avg(models.Review.rating),
            func.count(models.Review.id)
        )
        .where(models.Review.product_id == product_id)
    )
    avg_, cnt_ = db.execute(stmt).one()
    return ReviewSummaryOut(
        product_id=product_id,
        rating_avg=(float(avg_) if avg_ is not None else None),
        rating_count=int(cnt_ or 0),
    )
