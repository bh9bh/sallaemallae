from datetime import datetime
from pydantic import BaseModel, EmailStr
from typing import Optional, List

# =======================
# Auth
# =======================
class UserCreate(BaseModel):
    email: EmailStr
    password: str
    name: Optional[str] = None

class UserOut(BaseModel):
    id: int
    email: EmailStr
    name: Optional[str] = None
    is_admin: bool          # ✅ 관리자 여부 추가
    class Config:
        from_attributes = True


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"


# =======================
# Products
# =======================
class ProductBase(BaseModel):
    title: str
    description: Optional[str] = None
    image_url: Optional[str] = None
    category: Optional[str] = None
    region: Optional[str] = None
    daily_price: float
    deposit: float
    acquisition_price: Optional[float] = None
    is_rentable: bool = True
    is_purchasable: bool = True

class ProductCreate(ProductBase):
    pass

class ProductOut(ProductBase):
    id: int
    class Config:
        from_attributes = True


# =======================
# Rentals
# =======================
class RentalCreate(BaseModel):
    product_id: int
    start_date: datetime
    end_date: datetime

class RentalOut(BaseModel):
    id: int
    user_id: Optional[int] = None
    product_id: int
    start_date: datetime
    end_date: datetime
    total_price: float
    deposit: float
    status: str
    class Config:
        from_attributes = True

# 예약 불가 구간 응답 (/rentals/blocked-dates)
class BlockedRangeOut(BaseModel):
    start: datetime
    end: datetime

# 커서 페이지네이션 응답 (/rentals/me/page)
class RentalPageOut(BaseModel):
    items: List[RentalOut]
    next_cursor: Optional[str] = None


# =======================
# Photos
# =======================
class PhotoOut(BaseModel):
    id: int
    rental_id: int
    phase: str              # "BEFORE" | "AFTER"
    file_url: str           # /static/photos/...
    created_at: Optional[datetime] = None
    class Config:
        from_attributes = True


# =======================
# Reviews (거래 후기)
# =======================
class ReviewCreate(BaseModel):
    rental_id: int
    rating: int                 # 1~5
    comment: Optional[str] = None

    # ⬇️ 추가: 기존 라우터 호환용 별칭
class ReviewIn(ReviewCreate):
    pass

class ReviewOut(BaseModel):
    id: int
    rental_id: int
    user_id: int
    product_id: int
    rating: int
    comment: Optional[str] = None
    created_at: Optional[datetime] = None
    class Config:
        from_attributes = True


# =======================
# Payments (결제 시뮬레이터)
# =======================
class PaymentSimulateIn(BaseModel):
    rental_id: int
    amount: float               # 결제 시뮬레이션 금액

class PaymentSimulateOut(BaseModel):
    success: bool
    paid_amount: float
    message: str


# =======================
# Admin (관리자 승인/상태 변경)
# =======================
class AdminRentalStatusIn(BaseModel):
    status: str                 # "ACTIVE" | "RETURN_REQUESTED" | "CLOSED" | etc.

class AdminActionOut(BaseModel):
    ok: bool
    message: str
