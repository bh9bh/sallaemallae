from fastapi import APIRouter, Depends, HTTPException, File, UploadFile, Form
from sqlalchemy.orm import Session
from typing import List, Optional
from pathlib import Path
import shutil
from datetime import datetime

from .. import models, schemas
from ..database import get_db

# ✅ 로드 경로 로그
print("[ROUTER] products loaded from:", Path(__file__).resolve())

router = APIRouter(prefix="/products", tags=["products"])

# ---------- (중요) 업로드 라우트: 동적 경로보다 '위'에 둔다 ----------
UPLOAD_DIR = Path("uploads/products")
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

@router.post(
    "/with-image",
    response_model=schemas.ProductOut,
    include_in_schema=True,   # 문서에 반드시 노출
)
@router.post(
    "/with-image/",
    response_model=schemas.ProductOut,
    include_in_schema=True,
)
async def create_product_with_image(
    title: str = Form(...),
    description: Optional[str] = Form(None),
    category: Optional[str] = Form(None),
    region: Optional[str] = Form(None),
    daily_price: float = Form(...),
    deposit: float = Form(...),
    is_rentable: bool = Form(True),
    is_purchasable: bool = Form(True),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
):
    suffix = Path(file.filename).suffix.lower()
    if suffix not in [".jpg", ".jpeg", ".png", ".webp"]:
        raise HTTPException(status_code=400, detail="Unsupported file type")

    ts = datetime.utcnow().strftime("%Y%m%d%H%M%S%f")
    fname = f"product_{ts}{suffix}"
    dst = UPLOAD_DIR / fname
    with dst.open("wb") as f:
        shutil.copyfileobj(file.file, f)

    image_url = f"/static/products/{fname}"  # /static은 main.py에서 mount

    new = models.Product(
        title=title,
        description=description,
        image_url=image_url,
        category=category,
        region=region,
        daily_price=daily_price,
        deposit=deposit,
        is_rentable=is_rentable,
        is_purchasable=is_purchasable,
    )
    db.add(new)
    db.commit()
    db.refresh(new)
    return new

# ---------- 목록 ----------
@router.get("", response_model=List[schemas.ProductOut])
def list_products(
    db: Session = Depends(get_db),
    q: Optional[str] = None,
    category: Optional[str] = None,
    region: Optional[str] = None,
    skip: int = 0,
    limit: int = 50,
):
    query = db.query(models.Product)
    if q:
        like = f"%{q}%"
        query = query.filter(models.Product.title.like(like))
    if category:
        query = query.filter(models.Product.category == category)
    if region:
        query = query.filter(models.Product.region == region)
    return query.offset(skip).limit(limit).all()

# ---------- 단건 ----------
# ✅ 정수 컨버터로 문자열 경로와 충돌 방지
@router.get("/{product_id:int}", response_model=schemas.ProductOut)
def get_product(product_id: int, db: Session = Depends(get_db)):
    p = db.get(models.Product, product_id)
    if not p:
        raise HTTPException(status_code=404, detail="Product not found")
    return p

# ---------- 생성 (이미지 URL로) ----------
@router.post("", response_model=schemas.ProductOut)
def create_product(product: schemas.ProductCreate, db: Session = Depends(get_db)):
    new = models.Product(**product.model_dump())
    db.add(new)
    db.commit()
    db.refresh(new)
    return new

# ---------- 삭제 ----------
# ✅ 정수 컨버터로 문자열 경로와 충돌 방지
@router.delete("/{product_id:int}", status_code=204)
def delete_product(product_id: int, db: Session = Depends(get_db)):
    p = db.get(models.Product, product_id)
    if not p:
        raise HTTPException(status_code=404, detail="Product not found")
    db.delete(p)
    db.commit()
    return
