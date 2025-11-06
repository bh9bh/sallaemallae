# FILE: app/routers/products.py
from fastapi import APIRouter, Depends, HTTPException, File, UploadFile, Form, Query
from sqlalchemy.orm import Session
from sqlalchemy import or_
from typing import List, Optional
from pathlib import Path
import shutil
from datetime import datetime

from .. import models, schemas
from ..database import get_db

# ✅ 로드 경로 로그(정말 이 파일이 로딩되는지 확인용)
print("[ROUTER] products loaded from:", Path(__file__).resolve())

router = APIRouter(prefix="/products", tags=["products"])

# -------------------- 업로드 --------------------
UPLOAD_DIR = Path("uploads/products")
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)


@router.post("/with-image", response_model=schemas.ProductOut, include_in_schema=True)
@router.post("/with-image/", response_model=schemas.ProductOut, include_in_schema=True)
async def create_product_with_image(
    # 이름은 name/title 둘 다 허용
    name: Optional[str] = Form(None),
    title: Optional[str] = Form(None),
    description: Optional[str] = Form(None),
    # 카테고리: 라벨/키 둘 다 허용
    category: Optional[str] = Form(None),
    category_key: Optional[str] = Form(None),
    region: Optional[str] = Form(None),
    # 가격: daily_price/price_per_day 둘 다 허용
    daily_price: Optional[float] = Form(None),
    price_per_day: Optional[int] = Form(None),
    # 보증금(옵션)
    deposit: Optional[float] = Form(None),
    # 파일
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
):
    # 파일 확장자 검증
    suffix = Path(file.filename).suffix.lower()
    if suffix not in [".jpg", ".jpeg", ".png", ".webp"]:
        raise HTTPException(status_code=400, detail="Unsupported file type")

    # 저장
    ts = datetime.utcnow().strftime("%Y%m%d%H%M%S%f")
    fname = f"product_{ts}{suffix}"
    dst = UPLOAD_DIR / fname
    with dst.open("wb") as f:
        shutil.copyfileobj(file.file, f)

    image_url = f"/static/products/{fname}"  # /static mount는 main.py에서 처리

    # 값 정리
    resolved_name = (name or title or "").strip()
    resolved_price = (
        price_per_day
        if price_per_day is not None
        else (int(daily_price) if daily_price is not None else None)
    )
    if not resolved_name or resolved_price is None:
        raise HTTPException(status_code=400, detail="name/title and price are required")

    new = models.Product(
        name=resolved_name,
        description=description,
        price_per_day=resolved_price,
        # 아래 필드는 모델에 있을 때만 의미가 있음 (없어도 문제 없음)
        deposit=int(deposit) if isinstance(deposit, (int, float)) else None,
        category=category,
        category_key=category_key,
        region=region,
        image_url=image_url,
    )
    db.add(new)
    db.commit()
    db.refresh(new)
    return _normalize_product_row(new)


# -------------------- 표준화 헬퍼 --------------------
def _normalize_product_row(p) -> dict:
    """
    응답 표준화:
    - 이름은 name 기준, 하위호환을 위해 title도 같이 넣어줌
    - 가격은 price_per_day/daily_price 양쪽 키로 노출(클라 호환)
    - 선택 컬럼(존재하지 않을 수 있음)은 getattr로 안전 접근
    """
    name = getattr(p, "name", None)
    price = getattr(p, "price_per_day", None)
    image_url = getattr(p, "image_url", None) or getattr(p, "thumbnail_url", None)

    return {
        "id": getattr(p, "id", None),
        "name": name,
        "title": name,  # ✅ 프론트 하위호환
        "description": getattr(p, "description", None),
        "image_url": image_url,
        "category": getattr(p, "category", None),
        "category_key": getattr(p, "category_key", None),
        "region": getattr(p, "region", None),
        "price_per_day": price,
        "daily_price": float(price) if price is not None else None,  # ✅ 클라 호환
        "deposit": getattr(p, "deposit", None),
        "created_at": getattr(p, "created_at", None),
        "updated_at": getattr(p, "updated_at", None),
    }


# -------------------- 목록 --------------------
@router.get("", response_model=List[schemas.ProductOut])
def list_products(
    db: Session = Depends(get_db),
    q: Optional[str] = Query(None, description="이름/설명 검색"),
    category: Optional[str] = Query(None, description="카테고리 라벨 또는 키"),
    region: Optional[str] = Query(None),
    # 페이지네이션: page/size 우선 적용 (프론트 로그와 호환)
    page: int = Query(1, ge=1),
    size: int = Query(50, ge=1, le=200),
    # (구버전 호환: skip/limit가 오면 무시)
    skip: Optional[int] = Query(None, ge=0),
    limit: Optional[int] = Query(None, ge=1, le=200),
    include_inactive: bool = Query(False, description="비활성 상품 포함 여부(필드가 있으면)"),
    sort: Optional[str] = Query(None, description="정렬 키(popular 등). 현재는 무시되고 별도 /products/popular 사용 권장"),
):
    query = db.query(models.Product)

    # 검색: name/description like
    if q:
        like = f"%{q}%"
        query = query.filter(
            or_(models.Product.name.like(like), models.Product.description.like(like))
        )

    # 카테고리: 라벨/키 둘 다 허용
    if category:
        if hasattr(models.Product, "category_key"):
            query = query.filter(
                or_(
                    models.Product.category == category,
                    models.Product.category_key == category,
                )
            )
        else:
            query = query.filter(models.Product.category == category)

    if region:
        query = query.filter(models.Product.region == region)

    # is_active 컬럼이 있는 경우에만 적용
    if not include_inactive and hasattr(models.Product, "is_active"):
        query = query.filter(
            (models.Product.is_active == True) | (models.Product.is_active.is_(None))  # noqa: E712
        )

    # 페이지네이션 계산(page/size 우선)
    if page is not None and size is not None:
        _skip = (page - 1) * size
        _limit = size
    else:
        _skip = skip or 0
        _limit = limit or 50

    rows = query.offset(_skip).limit(_limit).all()
    return [_normalize_product_row(r) for r in rows]


# -------------------- 단건 --------------------
@router.get("/{product_id:int}", response_model=schemas.ProductOut)
def get_product(product_id: int, db: Session = Depends(get_db)):
    p = db.get(models.Product, product_id)
    if not p:
        raise HTTPException(status_code=404, detail="Product not found")
    return _normalize_product_row(p)


# -------------------- 생성 (이미지 URL로) --------------------
@router.post("", response_model=schemas.ProductOut)
def create_product(product: schemas.ProductCreate, db: Session = Depends(get_db)):
    """
    schemas.ProductCreate가 name/title, price_per_day/daily_price, category/category_key 등을
    어느 조합으로 오든 모델 필드로 매핑해서 저장.
    """
    # 안전하게 getattr로 꺼냄(스키마에 없는 필드여도 안전)
    name = getattr(product, "name", None)
    title = getattr(product, "title", None)
    description = getattr(product, "description", None)
    image_url = getattr(product, "image_url", None)
    region = getattr(product, "region", None)
    category = getattr(product, "category", None)
    category_key = getattr(product, "category_key", None)
    owner_id = getattr(product, "owner_id", None)
    deposit = getattr(product, "deposit", None)

    price_per_day = getattr(product, "price_per_day", None)
    daily_price = getattr(product, "daily_price", None)

    resolved_name = (name or title or "").strip()
    resolved_price = (
        price_per_day
        if price_per_day is not None
        else (int(daily_price) if daily_price is not None else None)
    )
    if not resolved_name or resolved_price is None:
        raise HTTPException(status_code=400, detail="name/title and price are required")

    new = models.Product(
        name=resolved_name,
        description=description,
        price_per_day=resolved_price,
        deposit=int(deposit) if isinstance(deposit, (int, float)) else None,
        category=category,
        category_key=category_key,
        region=region,
        image_url=image_url,
        owner_id=owner_id,
    )
    db.add(new)
    db.commit()
    db.refresh(new)
    return _normalize_product_row(new)


# -------------------- 업데이트 --------------------
@router.patch("/{product_id:int}", response_model=schemas.ProductOut)
def update_product(
    product_id: int,
    patch: schemas.ProductUpdate,
    db: Session = Depends(get_db),
):
    p = db.get(models.Product, product_id)
    if not p:
        raise HTTPException(status_code=404, detail="Product not found")

    data = patch.model_dump(exclude_unset=True)

    # 매핑 규칙: title -> name, daily_price -> price_per_day
    if "title" in data and "name" not in data:
        data["name"] = data.pop("title")
    if "daily_price" in data and "price_per_day" not in data:
        dp = data.pop("daily_price")
        data["price_per_day"] = int(dp) if dp is not None else None

    # 모델에 존재하는 필드만 세팅
    for k, v in list(data.items()):
        if hasattr(models.Product, k):
            setattr(p, k, v)

    db.add(p)
    db.commit()
    db.refresh(p)
    return _normalize_product_row(p)


# -------------------- 삭제 --------------------
@router.delete("/{product_id:int}", status_code=204)
def delete_product(product_id: int, db: Session = Depends(get_db)):
    p = db.get(models.Product, product_id)
    if not p:
        raise HTTPException(status_code=404, detail="Product not found")
    db.delete(p)
    db.commit()
    return
