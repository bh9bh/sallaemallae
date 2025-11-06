# FILE: app/models.py
from __future__ import annotations

from datetime import datetime, date
from enum import Enum as PyEnum
from typing import List, Optional

from sqlalchemy import (
    Integer,
    String,
    Boolean,
    Date,
    DateTime,
    Enum,
    ForeignKey,
    Text,
    Index,
)
from sqlalchemy.orm import relationship, Mapped, mapped_column

from .database import Base

# ---------------------------
# Enums
# ---------------------------

class RentalStatus(PyEnum):
    PENDING = "PENDING"      # 신청됨 (승인 대기)
    ACTIVE = "ACTIVE"        # 대여 진행 중 (수령 완료)
    RETURN_REQUESTED = "RETURN_REQUESTED"  # 반납 요청됨
    CLOSED = "CLOSED"        # 정상 종료(반납 완료)
    CANCELED = "CANCELED"    # 취소됨
    EXPIRED = "EXPIRED"      # 기간 만료/자동 종료 등


class PhotoKind(PyEnum):
    BEFORE = "BEFORE"
    AFTER = "AFTER"


# ---------------------------
# Models
# ---------------------------

class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True, nullable=False)
    hashed_password: Mapped[str] = mapped_column(String(255), nullable=False)
    is_admin: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    full_name: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, nullable=False, index=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )

    # 관계
    rentals: Mapped[List["Rental"]] = relationship(
        "Rental", back_populates="user", cascade="all,delete-orphan"
    )
    products: Mapped[List["Product"]] = relationship(
        "Product", back_populates="owner"
    )
    photos: Mapped[List["Photo"]] = relationship(
        "Photo", back_populates="user"
    )
    reviews: Mapped[List["Review"]] = relationship(
        "Review", back_populates="user", cascade="all,delete-orphan"
    )


class Product(Base):
    __tablename__ = "products"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False, index=True)
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    # 가격/보증금
    price_per_day: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    deposit: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)  # ← 보증금(옵션)

    # 카테고리 (키/라벨 모두 저장해서 클라/서버 어떤 표기든 대응)
    category: Mapped[Optional[str]] = mapped_column(String(100), nullable=True, index=True)       # 라벨(예: '촬영/크리에이터')
    category_key: Mapped[Optional[str]] = mapped_column(String(50), nullable=True, index=True)    # 키(예: 'creator')

    # 노출/검색용 메타
    region: Mapped[Optional[str]] = mapped_column(String(100), nullable=True, index=True)
    image_url: Mapped[Optional[str]] = mapped_column(String(1000), nullable=True)

    # 소유자 (등록자)
    owner_id: Mapped[Optional[int]] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, nullable=False, index=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )

    # 관계
    owner: Mapped[Optional[User]] = relationship("User", back_populates="products")
    rentals: Mapped[List["Rental"]] = relationship(
        "Rental", back_populates="product", cascade="all,delete-orphan"
    )
    reviews: Mapped[List["Review"]] = relationship(
        "Review", back_populates="product", cascade="all,delete-orphan"
    )

    __table_args__ = (
        Index("ix_products_owner_created", "owner_id", "created_at"),
        Index("ix_products_category_key_created", "category_key", "created_at"),
        Index("ix_products_category_created", "category", "created_at"),
        Index("ix_products_region_created", "region", "created_at"),
    )


class Rental(Base):
    __tablename__ = "rentals"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)

    user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False)
    product_id: Mapped[int] = mapped_column(Integer, ForeignKey("products.id", ondelete="CASCADE"), index=True, nullable=False)

    start_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    end_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)

    status: Mapped[RentalStatus] = mapped_column(
        Enum(RentalStatus), default=RentalStatus.PENDING, nullable=False, index=True
    )

    total_price: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    deposit: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, nullable=False, index=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )

    # 관계
    user: Mapped[User] = relationship("User", back_populates="rentals")
    product: Mapped[Product] = relationship("Product", back_populates="rentals")
    photos: Mapped[List["Photo"]] = relationship(
        "Photo", back_populates="rental", cascade="all,delete-orphan"
    )
    reviews: Mapped[List["Review"]] = relationship(
        "Review", back_populates="rental", cascade="all,delete-orphan"
    )

    __table_args__ = (
        Index("ix_rentals_product_period", "product_id", "start_date", "end_date"),
    )


class Photo(Base):
    __tablename__ = "photos"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)

    rental_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("rentals.id", ondelete="CASCADE"), index=True, nullable=False
    )
    user_id: Mapped[Optional[int]] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), index=True, nullable=True
    )

    kind: Mapped[PhotoKind] = mapped_column(Enum(PhotoKind), nullable=False, index=True)

    file_path: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    url: Mapped[Optional[str]] = mapped_column(String(1000), nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, nullable=False, index=True
    )

    rental: Mapped[Rental] = relationship("Rental", back_populates="photos")
    user: Mapped[Optional[User]] = relationship("User", back_populates="photos")


class Review(Base):
    """
    상품 리뷰 및 평점 (선택적으로 특정 렌탈과 연결)
    - 기본: product_id, user_id 필수
    - rental_id: 해당 대여 건에 대한 리뷰인 경우 연결(없어도 가능)
    - rating: 1~5 정수
    """
    __tablename__ = "reviews"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)

    product_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("products.id", ondelete="CASCADE"), index=True, nullable=False
    )
    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    rental_id: Mapped[Optional[int]] = mapped_column(
        Integer, ForeignKey("rentals.id", ondelete="SET NULL"), index=True, nullable=True
    )

    rating: Mapped[int] = mapped_column(Integer, nullable=False)  # 1~5
    comment: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, nullable=False, index=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )

    # 관계
    product: Mapped[Product] = relationship("Product", back_populates="reviews")
    user: Mapped[User] = relationship("User", back_populates="reviews")
    rental: Mapped[Optional[Rental]] = relationship("Rental", back_populates="reviews")

    __table_args__ = (
        Index("ix_reviews_product_created", "product_id", "created_at"),
        Index("ix_reviews_user_created", "user_id", "created_at"),
    )


__all__ = [
    "User",
    "Product",
    "Rental",
    "Photo",
    "Review",
    "RentalStatus",
    "PhotoKind",
]
