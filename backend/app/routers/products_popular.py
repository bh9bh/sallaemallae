# FILE: app/routers/products_popular.py
from typing import List, Optional
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from pydantic import BaseModel
from sqlalchemy import func, select, literal

from app.database import get_db
from app import models

router = APIRouter(prefix="/products", tags=["products"])


# ==== 응답 스키마: 항상 daily_price 사용 ====
class PopularProductOut(BaseModel):
    id: int
    name: str
    category: Optional[str] = None
    region: Optional[str] = None
    daily_price: float
    image_url: Optional[str] = None

    rating_avg: Optional[float] = None
    rating_count: int = 0
    rental_count: int = 0
    popularity: float

    model_config = {"from_attributes": True}


def _coalesce(expr, default):
    return func.coalesce(expr, default)


def _pcol(name: str, default=None):
    """Product 컬럼이 없으면 literal(default)로 대체"""
    col = getattr(models.Product, name, None)
    return col if col is not None else literal(default)


def _name_column():
    """
    이름 컬럼: name이 기본.
    (예전 스키마에 title만 있었다면 title 사용, 둘 다 없으면 '상품')
    """
    name = getattr(models.Product, "name", None)
    if name is not None:
        return name
    title = getattr(models.Product, "title", None)
    if title is not None:
        return title
    return literal("상품")


def _price_column():
    """daily_price → price_per_day → 0 순으로 선택"""
    col = getattr(models.Product, "daily_price", None)
    if col is not None:
        return col
    col = getattr(models.Product, "price_per_day", None)
    if col is not None:
        return col
    return literal(0)


def _image_column():
    """image_url → thumbnail_url → NULL"""
    img = getattr(models.Product, "image_url", None)
    thumb = getattr(models.Product, "thumbnail_url", None)
    if img is not None and thumb is not None:
        return _coalesce(img, thumb)
    if img is not None:
        return img
    if thumb is not None:
        return thumb
    return literal(None)


@router.get("/popular", response_model=List[PopularProductOut], summary="인기 상품 목록")
def get_popular_products(
    db: Session = Depends(get_db),
    limit: int = Query(20, ge=1, le=100),
    category: Optional[str] = Query(None, description="카테고리(ex: 가전, 캠핑, 의류 등)"),
    min_reviews: int = Query(0, ge=0, description="최소 리뷰 수 필터"),
):
    """
    인기 점수(popularity) 산식:
      - 평점 기여: (avg_rating / 5.0) * 0.7
      - 리뷰수 기여: ln(1 + review_count) * 0.2
      - 대여수 기여: ln(1 + rental_count) * 0.3
    """

    # 리뷰 집계
    reviews_subq = (
        select(
            models.Review.product_id.label("pid"),
            func.count(models.Review.id).label("review_count"),
            func.avg(models.Review.rating).label("avg_rating"),
        )
        .group_by(models.Review.product_id)
        .subquery()
    )

    # 대여 집계
    rentals_subq = (
        select(
            models.Rental.product_id.label("pid"),
            func.count(models.Rental.id).label("rental_count"),
        )
        .group_by(models.Rental.product_id)
        .subquery()
    )

    name_col = _name_column()
    price_col = _price_column()
    image_col = _image_column()
    category_col = _pcol("category")  # 없으면 NULL
    region_col = _pcol("region", "전국")

    stmt = (
        select(
            models.Product.id,
            name_col.label("name"),
            category_col.label("category"),
            _coalesce(region_col, literal("전국")).label("region"),
            price_col.label("daily_price"),
            image_col.label("image_url"),
            _coalesce(reviews_subq.c.avg_rating, literal(None)).label("avg_rating"),
            _coalesce(reviews_subq.c.review_count, literal(0)).label("review_count"),
            _coalesce(rentals_subq.c.rental_count, literal(0)).label("rental_count"),
        )
        .select_from(models.Product)
        .join(reviews_subq, reviews_subq.c.pid == models.Product.id, isouter=True)
        .join(rentals_subq, rentals_subq.c.pid == models.Product.id, isouter=True)
    )

    # 카테고리 필터 (category, category_key 어느 쪽이든 있으면 적용)
    if category:
        cat = getattr(models.Product, "category", None)
        cat_key = getattr(models.Product, "category_key", None)
        conds = []
        if cat is not None:
            conds.append(cat == category)
        if cat_key is not None:
            conds.append(cat_key == category)
        if conds:
            stmt = stmt.where(func.or_(*conds))

    if min_reviews > 0:
        stmt = stmt.where(_coalesce(reviews_subq.c.review_count, literal(0)) >= min_reviews)

    rows = db.execute(stmt).all()

    # popularity 계산
    import math

    def score(avg: Optional[float], rcnt: int, rencnt: int) -> float:
        s_avg = ((avg or 0.0) / 5.0) * 0.7
        s_rev = math.log1p(max(rcnt, 0)) * 0.2
        s_ren = math.log1p(max(rencnt, 0)) * 0.3
        return float(s_avg + s_rev + s_ren)

    items = [
        PopularProductOut(
            id=r.id,
            name=r.name,
            category=r.category,
            region=r.region,
            daily_price=float(r.daily_price or 0),
            image_url=r.image_url,
            rating_avg=(float(r.avg_rating) if r.avg_rating is not None else None),
            rating_count=int(r.review_count or 0),
            rental_count=int(r.rental_count or 0),
            popularity=score(r.avg_rating, int(r.review_count or 0), int(r.rental_count or 0)),
        )
        for r in rows
    ]

    items.sort(key=lambda x: x.popularity, reverse=True)
    return items[:limit]
