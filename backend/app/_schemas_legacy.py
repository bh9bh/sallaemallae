# FILE: app/schemas.py
from typing import Optional
from datetime import datetime, date
from pydantic import BaseModel, EmailStr, Field, model_validator

# ===================== Users =====================
class UserBase(BaseModel):
    email: EmailStr
    name: Optional[str] = None

class UserCreate(UserBase):
    password: str

class UserOut(UserBase):
    id: int
    is_admin: Optional[bool] = None

    model_config = {"from_attributes": True}


# ===================== Auth =====================
class Token(BaseModel):
    access_token: str
    token_type: str

TokenOut = Token


# ===================== Products =====================
class ProductBase(BaseModel):
    # 공통 필드
    title: Optional[str] = None
    description: Optional[str] = None
    image_url: Optional[str] = None
    category: Optional[str] = None
    region: Optional[str] = None

    # ✅ 표준: daily_price (응답은 이 필드만 노출)
    daily_price: Optional[float] = None
    deposit: Optional[float] = None

    is_active: Optional[bool] = None
    is_rentable: Optional[bool] = None
    is_purchasable: Optional[bool] = None
    thumbnail_url: Optional[str] = None
    owner_id: Optional[int] = None

    model_config = {
        "from_attributes": True,
        "populate_by_name": True,  # alias 입력 허용
    }

class ProductCreate(ProductBase):
    # ✅ 하위호환: 요청 바디에서 price_per_day 허용(자동 매핑)
    price_per_day: Optional[float] = Field(None, alias="price_per_day")

    @model_validator(mode="before")
    @classmethod
    def _unify_price_create(cls, values):
        if isinstance(values, dict):
            if values.get("daily_price") is None and values.get("price_per_day") is not None:
                values["daily_price"] = values.get("price_per_day")
        return values

class ProductUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    image_url: Optional[str] = None
    category: Optional[str] = None
    region: Optional[str] = None
    daily_price: Optional[float] = None
    deposit: Optional[float] = None
    is_active: Optional[bool] = None
    is_rentable: Optional[bool] = None
    is_purchasable: Optional[bool] = None
    thumbnail_url: Optional[str] = None

    # ✅ 하위호환: 업데이트에서도 price_per_day 입력 허용
    price_per_day: Optional[float] = Field(None, alias="price_per_day")

    model_config = {
        "from_attributes": True,
        "populate_by_name": True,
    }

    @model_validator(mode="before")
    @classmethod
    def _unify_price_update(cls, values):
        if isinstance(values, dict):
            if values.get("daily_price") is None and values.get("price_per_day") is not None:
                values["daily_price"] = values.get("price_per_day")
        return values

class ProductOut(BaseModel):
    # ✅ 응답은 daily_price만 노출 (하지만 레거시 dict 응답의 price_per_day도 alias로 흡수)
    id: int
    title: Optional[str] = None
    description: Optional[str] = None
    image_url: Optional[str] = None
    category: Optional[str] = None
    region: Optional[str] = None

    # 레거시(dict) 응답이 price_per_day를 보내도 읽힐 수 있게 alias 지정
    daily_price: Optional[float] = Field(default=None, alias="price_per_day")
    deposit: Optional[float] = None

    is_active: Optional[bool] = None
    is_rentable: Optional[bool] = None
    is_purchasable: Optional[bool] = None
    thumbnail_url: Optional[str] = None
    owner_id: Optional[int] = None

    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

    model_config = {
        "from_attributes": True,
        "populate_by_name": True,  # alias 입력 허용 (출력은 필드명=daily_price)
    }


# ===================== Rentals =====================
class RentalBase(BaseModel):
    product_id: Optional[int] = None
    renter_id: Optional[int] = None
    start_date: Optional[date] = None
    end_date: Optional[date] = None

class RentalCreate(RentalBase):
    pass

class RentalOut(BaseModel):
    id: int
    product_id: Optional[int] = None
    renter_id: Optional[int] = None
    start_date: Optional[date] = None
    end_date: Optional[date] = None
    status: Optional[str] = None
    total_price: Optional[float] = None
    deposit: Optional[float] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

    # forward refs
    product: Optional["ProductOut"] = None
    renter: Optional["UserOut"] = None

    model_config = {"from_attributes": True}


# ===================== Photos =====================
class PhotoBase(BaseModel):
    rental_id: Optional[int] = None
    user_id: Optional[int] = None
    kind: Optional[str] = None
    url: Optional[str] = None

class PhotoCreate(PhotoBase):
    pass

class PhotoOut(BaseModel):
    id: int
    rental_id: Optional[int] = None
    user_id: Optional[int] = None
    kind: Optional[str] = None
    url: Optional[str] = None
    created_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


# ===================== Reviews =====================
class ReviewBase(BaseModel):
    product_id: Optional[int] = None
    rental_id: Optional[int] = None
    user_id: Optional[int] = None
    rating: Optional[int] = None
    comment: Optional[str] = None

class ReviewCreate(ReviewBase):
    pass

class ReviewOut(BaseModel):
    id: int
    product_id: Optional[int] = None
    rental_id: Optional[int] = None
    user_id: Optional[int] = None
    rating: Optional[int] = None
    comment: Optional[str] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

    # forward refs
    product: Optional["ProductOut"] = None
    user: Optional["UserOut"] = None
    rental: Optional["RentalOut"] = None

    model_config = {"from_attributes": True}


# ===== Forward-Ref 해소(필요 시) =====
# Pydantic v2에서 순환참조가 있는 경우 model_rebuild()를 호출해 안전하게 해결
ProductOut.model_rebuild()
RentalOut.model_rebuild()
ReviewOut.model_rebuild()
