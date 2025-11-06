from sqlalchemy import (
    Column, Integer, String, Float, Text, Boolean, ForeignKey,
    DateTime, Enum, Index
)
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from datetime import datetime
import enum

from .database import Base


# -------------------------------- Users --------------------------------
class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    email = Column(String(255), unique=True, index=True, nullable=False)
    hashed_password = Column(String(255), nullable=False)
    name = Column(String(100), nullable=True)
    is_active = Column(Boolean, default=True, nullable=False)
    # ⬇️ 관리자 플래그 추가 (발표용 관리자 화면/엔드포인트에서 사용)
    is_admin = Column(Boolean, default=False, nullable=False)

    rentals = relationship("Rental", back_populates="user")
    # 사용자가 작성한 리뷰
    reviews = relationship("Review", back_populates="user")


# ------------------------------- Products ------------------------------
class Product(Base):
    __tablename__ = "products"
    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(200), nullable=False)
    description = Column(Text, nullable=True)
    image_url = Column(String(500), nullable=True)
    category = Column(String(100), index=True)
    region = Column(String(100), index=True)
    daily_price = Column(Float, nullable=False)
    deposit = Column(Float, nullable=False)
    acquisition_price = Column(Float, nullable=True)
    is_rentable = Column(Boolean, default=True, nullable=False)
    is_purchasable = Column(Boolean, default=True, nullable=False)
    # ✅ DB 서버 기본시간 사용(naive) — 이 파일은 naive 전략 유지
    created_at = Column(DateTime, server_default=func.now(), nullable=False)

    rentals = relationship("Rental", back_populates="product")
    reviews = relationship("Review", back_populates="product")

    # ⬇️ 발표용 지표(평균 평점/리뷰 수) — 선택적 활용 (관리자/리스트에 표시)
    avg_rating = Column(Float, nullable=False, default=0.0)
    review_count = Column(Integer, nullable=False, default=0)


# ------------------------------ Rentals --------------------------------
class RentalStatus(str, enum.Enum):
    PENDING = "PENDING"
    ACTIVE = "ACTIVE"
    RETURN_REQUESTED = "RETURN_REQUESTED"
    REJECTED = "REJECTED"          # ⬅️ 추가
    CLOSED = "CLOSED"


class Rental(Base):
    __tablename__ = "rentals"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    product_id = Column(Integer, ForeignKey("products.id"), nullable=False)

    # ✅ naive UTC 기준(라우터도 datetime.utcnow 사용)
    start_date = Column(DateTime, nullable=False)
    end_date = Column(DateTime, nullable=False)

    total_price = Column(Float, nullable=False)
    deposit = Column(Float, nullable=False)
    status = Column(Enum(RentalStatus), default=RentalStatus.PENDING, nullable=False)
    created_at = Column(DateTime, server_default=func.now(), nullable=False)

    user = relationship("User", back_populates="rentals")
    product = relationship("Product", back_populates="rentals")

    # ✅ 렌탈 삭제 시 사진도 같이 삭제
    photos = relationship(
        "Photo",
        back_populates="rental",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )

    # 결제 기록(시뮬레이터)
    payments = relationship(
        "Payment",
        back_populates="rental",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )

    # 리뷰(거래 종료 후 1개 작성 가정)
    review = relationship(
        "Review",
        back_populates="rental",
        uselist=False,
        cascade="all, delete-orphan",
        passive_deletes=True,
    )

    # ✅ 겹침/목록 성능 인덱스
    __table_args__ = (
        Index("ix_rental_product_period", "product_id", "start_date", "end_date"),
    )


# ------------------------------ Photos ---------------------------------
class Photo(Base):
    __tablename__ = "photos"
    id = Column(Integer, primary_key=True, index=True)
    rental_id = Column(Integer, ForeignKey("rentals.id", ondelete="CASCADE"), nullable=False)
    phase = Column(String(10), nullable=False)      # "BEFORE" / "AFTER"
    file_url = Column(String(255), nullable=False)  # /static/photos/...
    created_at = Column(DateTime, server_default=func.now(), nullable=False)

    rental = relationship("Rental", back_populates="photos")


# ------------------------------ Payments --------------------------------
class PaymentStatus(str, enum.Enum):
    PENDING = "PENDING"
    PAID = "PAID"
    FAILED = "FAILED"
    REFUNDED = "REFUNDED"


class Payment(Base):
    __tablename__ = "payments"
    id = Column(Integer, primary_key=True, index=True)
    rental_id = Column(Integer, ForeignKey("rentals.id", ondelete="CASCADE"), nullable=False)
    amount = Column(Float, nullable=False)               # 결제 금액(총액 or 일부)
    status = Column(Enum(PaymentStatus), default=PaymentStatus.PENDING, nullable=False)
    provider = Column(String(50), nullable=False, default="SIMULATOR")  # 시뮬레이터/PG사명 등
    tx_id = Column(String(100), nullable=True)           # 외부 트랜잭션ID(시뮬레이터는 랜덤)
    created_at = Column(DateTime, server_default=func.now(), nullable=False)

    rental = relationship("Rental", back_populates="payments")

    __table_args__ = (
        Index("ix_payment_rental", "rental_id"),
    )


# ------------------------------ Reviews ---------------------------------
class Review(Base):
    __tablename__ = "reviews"
    id = Column(Integer, primary_key=True, index=True)
    rental_id = Column(Integer, ForeignKey("rentals.id", ondelete="CASCADE"), nullable=False)
    product_id = Column(Integer, ForeignKey("products.id", ondelete="CASCADE"), nullable=False)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)

    rating = Column(Integer, nullable=False)  # 1~5
    comment = Column(Text, nullable=True)
    created_at = Column(DateTime, server_default=func.now(), nullable=False)

    rental = relationship("Rental", back_populates="review")
    product = relationship("Product", back_populates="reviews")
    user = relationship("User", back_populates="reviews")

    __table_args__ = (
        Index("ix_review_product", "product_id"),
        Index("ix_review_user", "user_id"),
    )
