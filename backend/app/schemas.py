# FILE: app/schemas.py
from __future__ import annotations

from datetime import date, datetime
from typing import List, Optional

from pydantic import BaseModel, ConfigDict, EmailStr, Field

from .models import RentalStatus, PhotoKind


# ---------------------------------
# 공통 베이스 (Pydantic v2)
# ---------------------------------
class ORMSchema(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# ---------------------------------
# Auth / Token
# ---------------------------------
class Token(ORMSchema):
    access_token: str
    token_type: str = "bearer"


class TokenData(ORMSchema):
    user_id: Optional[int] = None
    email: Optional[EmailStr] = None
    is_admin: Optional[bool] = None


# ---------------------------------
# User
# ---------------------------------
class UserBase(ORMSchema):
    email: EmailStr
    full_name: Optional[str] = None


class UserCreate(UserBase):
    password: str = Field(min_length=6)


class UserLogin(ORMSchema):
    email: EmailStr
    password: str


class UserUpdate(ORMSchema):
    full_name: Optional[str] = None
    password: Optional[str] = Field(default=None, min_length=6)


class UserOut(UserBase):
    id: int
    is_admin: bool
    created_at: datetime
    updated_at: datetime


# ---------------------------------
# Product
# ---------------------------------
# ✅ name/title, price_per_day/daily_price, category/category_key 모두 허용 · 하위호환 유지
class ProductCreate(ORMSchema):
    # 이름: 둘 중 하나만 와도 저장 가능
    name: Optional[str] = None
    title: Optional[str] = None

    description: Optional[str] = None
    image_url: Optional[str] = None

    # 카테고리: 라벨/키 모두 허용
    category: Optional[str] = None
    category_key: Optional[str] = None
    region: Optional[str] = None

    # 가격: 두 키 모두 허용
    price_per_day: Optional[int] = None
    daily_price: Optional[float] = None

    deposit: Optional[int] = None
    owner_id: Optional[int] = None


class ProductUpdate(ORMSchema):
    # 부분 업데이트
    name: Optional[str] = None
    title: Optional[str] = None

    description: Optional[str] = None
    image_url: Optional[str] = None

    category: Optional[str] = None
    category_key: Optional[str] = None
    region: Optional[str] = None

    price_per_day: Optional[int] = None
    daily_price: Optional[float] = None

    deposit: Optional[int] = None
    owner_id: Optional[int] = None


class ProductOut(ORMSchema):
    id: int

    # ✅ 응답에 name과 title 둘 다 포함(프론트 하위호환)
    name: Optional[str] = None
    title: Optional[str] = None

    description: Optional[str] = None
    image_url: Optional[str] = None

    category: Optional[str] = None
    category_key: Optional[str] = None
    region: Optional[str] = None

    # ✅ 가격도 두 키 모두 제공
    price_per_day: Optional[int] = None
    daily_price: Optional[float] = None

    deposit: Optional[int] = None
    owner_id: Optional[int] = None

    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


# ---------------------------------
# Rental
# ---------------------------------
class RentalBase(ORMSchema):
    start_date: date
    end_date: date


class RentalCreate(RentalBase):
    product_id: int
    total_price: Optional[int] = None
    deposit: Optional[int] = None


class RentalUpdate(ORMSchema):
    status: Optional[RentalStatus] = None
    start_date: Optional[date] = None
    end_date: Optional[date] = None
    total_price: Optional[int] = None
    deposit: Optional[int] = None


class RentalOut(RentalBase):
    id: int
    user_id: int
    product_id: int
    status: RentalStatus
    total_price: Optional[int] = None
    deposit: Optional[int] = None
    created_at: datetime
    updated_at: datetime


# ---------------------------------
# Photo
# ---------------------------------
class PhotoBase(ORMSchema):
    kind: PhotoKind
    file_path: Optional[str] = None
    url: Optional[str] = None


class PhotoCreate(PhotoBase):
    rental_id: int
    user_id: Optional[int] = None


class PhotoOut(PhotoBase):
    id: int
    rental_id: int
    user_id: Optional[int] = None
    created_at: datetime


# ---------------------------------
# Review
# ---------------------------------
class ReviewBase(ORMSchema):
    rating: int = Field(ge=1, le=5)
    comment: Optional[str] = None


class ReviewCreate(ReviewBase):
    product_id: int
    rental_id: Optional[int] = None  # 특정 대여에 대한 리뷰라면 제공


class ReviewUpdate(ORMSchema):
    rating: Optional[int] = Field(default=None, ge=1, le=5)
    comment: Optional[str] = None


class ReviewOut(ReviewBase):
    id: int
    product_id: int
    user_id: int
    rental_id: Optional[int] = None
    created_at: datetime
    updated_at: datetime


# ---------------------------------
# Paginations / Common responses
# ---------------------------------
class PageMeta(ORMSchema):
    total: int
    limit: int
    offset: int


class ProductList(ORMSchema):
    items: List[ProductOut]
    meta: PageMeta


class RentalList(ORMSchema):
    items: List[RentalOut]
    meta: PageMeta


class ReviewList(ORMSchema):
    items: List[ReviewOut]
    meta: PageMeta
