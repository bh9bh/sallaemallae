from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import and_
from datetime import datetime, timezone, timedelta
from typing import List, Optional, Dict, Any
import base64, json

from .. import models, schemas
from ..database import get_db
from ..deps import get_current_user
# from ._guards import assert_owner_or_admin  # 공통가드가 있으면 이 라인 주석 해제 후 사용

router = APIRouter(prefix="/rentals", tags=["rentals"])

# ---------- TZ & 유틸 ----------
# ZoneInfo가 없거나 tzdata가 없는 환경(Windows)에서도 안전하게 동작하도록 폴백
try:
    from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
    try:
        KST = ZoneInfo("Asia/Seoul")
    except ZoneInfoNotFoundError:
        KST = timezone(timedelta(hours=9))  # UTC+9 고정
except Exception:
    KST = timezone(timedelta(hours=9))      # UTC+9 고정

def _days_between(a: datetime, b: datetime) -> int:
    if not a or not b:
        return 1
    days = (b.date() - a.date()).days
    return max(1, days)

def _status(name: str):
    # RentalStatus에 없으면 None
    return getattr(models.RentalStatus, name, None)

# EXPIRED가 없을 수도 있으니 안전하게 구성
_EXPIRED = _status("EXPIRED")
_CLOSED = models.RentalStatus.CLOSED
_INACTIVE_SET = ([_CLOSED] + ([_EXPIRED] if _EXPIRED else []))

def _encode_cursor_payload(payload: Dict[str, Any]) -> str:
    return base64.urlsafe_b64encode(json.dumps(payload).encode()).decode()

def _decode_cursor_payload(s: Optional[str]) -> Optional[Dict[str, Any]]:
    if not s:
        return None
    return json.loads(base64.urlsafe_b64decode(s.encode()).decode())

def _to_local(dt: datetime) -> datetime:
    """naive -> KST로 해석, aware -> KST로 변환"""
    if dt is None:
        return dt
    return (dt.replace(tzinfo=KST) if dt.tzinfo is None else dt.astimezone(KST))

def _to_utc(dt: datetime) -> datetime:
    """naive -> KST로 해석 후 UTC 변환, aware -> UTC 변환"""
    if dt is None:
        return dt
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=KST)
    return dt.astimezone(timezone.utc)


# ---------- 예약 생성/가용성 ----------
@router.post("", response_model=schemas.RentalOut, status_code=201)
def create_rental(
    payload: schemas.RentalCreate,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    product = db.get(models.Product, payload.product_id)
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")
    if payload.end_date <= payload.start_date:
        raise HTTPException(status_code=400, detail="Invalid date range")

    # '닿는 것'은 허용. 겹침: (exist.start < new.end) AND (exist.end > new.start)
    overlap = (
        db.query(models.Rental)
        .filter(
            models.Rental.product_id == payload.product_id,
            models.Rental.status.notin_(_INACTIVE_SET),
            models.Rental.start_date < payload.end_date,
            models.Rental.end_date > payload.start_date,
        )
        .first()
    )
    if overlap:
        raise HTTPException(status_code=409, detail="This product is already booked for the selected dates")

    days = _days_between(payload.start_date, payload.end_date)
    rental = models.Rental(
        user_id=user.id,
        product_id=product.id,
        start_date=payload.start_date,
        end_date=payload.end_date,
        total_price=product.daily_price * days,
        deposit=product.deposit,
        # 🔁 관리자 승인 플로우를 위해 기본 상태를 PENDING으로 설정
        status=models.RentalStatus.PENDING,
    )
    db.add(rental)
    db.commit()
    db.refresh(rental)
    return rental


@router.get("/availability")
def check_availability(
    product_id: int,
    start: datetime,
    end: datetime,
    db: Session = Depends(get_db),
):
    if end <= start:
        raise HTTPException(status_code=400, detail="Invalid date range")

    exists = (
        db.query(models.Rental)
        .filter(
            models.Rental.product_id == product_id,
            models.Rental.status.notin_(_INACTIVE_SET),
            models.Rental.start_date < end,
            models.Rental.end_date > start,
        )
        .first()
    )
    return {"available": exists is None}


# ---------- 예약 불가 날짜(정적 경로: 동적 경로보다 위에 선언 필수) ----------
@router.get("/blocked-dates")
def get_blocked_dates(
    product_id: int,
    db: Session = Depends(get_db),
):
    """
    해당 상품에 대해 '대여 불가(겹치는) 날짜 구간' 반환.
    CLOSED/EXPIRED가 아닌 모든 렌탈의 [start, end]를 그대로 돌려준다.
    프런트는 이 구간들을 일자 단위로 펼쳐 달력 비활성화 처리.
    """
    rows = (
        db.query(models.Rental)
        .filter(
            models.Rental.product_id == product_id,
            models.Rental.status.notin_(_INACTIVE_SET),
        )
        .all()
    )
    return [
        {
            "start": r.start_date.isoformat(),
            "end": r.end_date.isoformat(),
        }
        for r in rows
    ]


# ---------- 목록/조회 ----------
@router.get("/me", response_model=List[schemas.RentalOut])
def list_my_rentals(
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
    skip: int = 0,
    limit: int = 50,
    include_inactive: Optional[bool] = None,
    include_closed: Optional[bool] = Query(None, description="Deprecated. Use include_inactive"),
):
    # 프런트 하위 호환: include_closed → include_inactive로 매핑
    if include_closed is not None:
        include_inactive = include_closed
    include_inactive = bool(include_inactive) if include_inactive is not None else False

    # KST '날짜' 기준으로 만료 갱신 (쿼리 안에서 tz 다루지 않음)
    today_local = datetime.now(KST).date()
    rows_to_expire = (
        db.query(models.Rental)
        .filter(
            models.Rental.user_id == user.id,
            models.Rental.status.notin_(_INACTIVE_SET),
        )
        .all()
    )
    changed = False
    for r in rows_to_expire:
        if _to_local(r.end_date).date() < today_local:
            r.status = _EXPIRED or _CLOSED
            db.add(r)
            changed = True
    if changed:
        db.commit()

    q = db.query(models.Rental).filter(models.Rental.user_id == user.id)
    if not include_inactive:
        q = q.filter(models.Rental.status.notin_(_INACTIVE_SET))

    rows = q.order_by(models.Rental.id.desc()).offset(skip).limit(limit).all()
    return rows


@router.get("/me/page")
def list_my_rentals_paged(
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
    limit: int = Query(20, ge=1, le=100),
    cursor: Optional[str] = Query(None),
    status: Optional[models.RentalStatus] = Query(None),
    include_inactive: Optional[bool] = None,
    include_closed: Optional[bool] = Query(None, description="Deprecated. Use include_inactive"),
):
    if include_closed is not None:
        include_inactive = include_closed
    include_inactive = bool(include_inactive) if include_inactive is not None else False

    # 동일하게 파이썬 레벨에서 만료 갱신
    today_local = datetime.now(KST).date()
    rows_to_expire = (
        db.query(models.Rental)
        .filter(
            models.Rental.user_id == user.id,
            models.Rental.status.notin_(_INACTIVE_SET),
        )
        .all()
    )
    changed = False
    for r in rows_to_expire:
        if _to_local(r.end_date).date() < today_local:
            r.status = _EXPIRED or _CLOSED
            db.add(r)
            changed = True
    if changed:
        db.commit()

    # 커서 해석
    cur = json.loads(base64.urlsafe_b64decode(cursor.encode()).decode()) if cursor else {}
    last_id = cur.get("last_id")

    # 조건 구성
    conds = [models.Rental.user_id == user.id]
    if status:
        conds.append(models.Rental.status == status)
    elif not include_inactive:
        conds.append(models.Rental.status.notin_(_INACTIVE_SET))

    stmt = db.query(models.Rental).filter(and_(*conds))
    if last_id:
        stmt = stmt.filter(models.Rental.id < last_id)
    rows = stmt.order_by(models.Rental.id.desc()).limit(limit + 1).all()

    has_more = len(rows) > limit
    items = rows[:limit]
    next_cursor = base64.urlsafe_b64encode(json.dumps({"last_id": items[-1].id}).encode()).decode() if has_more else None

    return {
        "items": [schemas.RentalOut.model_validate(r).model_dump() for r in items],
        "next_cursor": next_cursor,
    }


@router.get("/{rental_id}", response_model=schemas.RentalOut)
def get_rental(
    rental_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    r = db.get(models.Rental, rental_id)
    if not r:
        raise HTTPException(status_code=404, detail="Rental not found")

    # 공통가드 있으면 사용:
    # assert_owner_or_admin(r.user_id, user)
    if (user.id != r.user_id) and (not getattr(user, "is_admin", False)):
        raise HTTPException(status_code=403, detail="Forbidden")

    # 단건 조회도 KST 날짜 기준으로 만료 갱신
    today_local = datetime.now(KST).date()
    if r.status not in _INACTIVE_SET and _to_local(r.end_date).date() < today_local:
        r.status = _EXPIRED or _CLOSED
        db.add(r)
        db.commit()
        db.refresh(r)
    return r


# ---------- 상태 액션 ----------
@router.patch("/{rental_id}/cancel", response_model=schemas.RentalOut)
def cancel_rental(
    rental_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    r = db.get(models.Rental, rental_id)
    if not r:
        raise HTTPException(status_code=404, detail="Rental not found")
    if (user.id != r.user_id) and (not getattr(user, "is_admin", False)):
        raise HTTPException(status_code=403, detail="Forbidden")

    # 취소는 '시작일 당일 포함 불가' → KST 날짜 기준
    today_local = datetime.now(KST).date()

    # 🔁 PENDING도 취소 가능하도록 허용 (발표 데모 UX)
    if r.status not in (models.RentalStatus.PENDING, models.RentalStatus.ACTIVE):
        raise HTTPException(status_code=400, detail="Only PENDING or ACTIVE rentals can be canceled")

    if _to_local(r.start_date).date() <= today_local:
        raise HTTPException(status_code=400, detail="Cannot cancel on/after start date")

    r.status = _CLOSED
    db.add(r)
    db.commit()
    db.refresh(r)
    return r


@router.patch("/{rental_id}/request-return", response_model=schemas.RentalOut)
def request_return(
    rental_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    r = db.get(models.Rental, rental_id)
    if not r:
        raise HTTPException(status_code=404, detail="Rental not found")
    if (user.id != r.user_id) and (not getattr(user, "is_admin", False)):
        raise HTTPException(status_code=403, detail="Forbidden")

    # 반납요청은 '시작일 당일부터 가능' → KST 날짜 기준
    today_local = datetime.now(KST).date()
    if r.status != models.RentalStatus.ACTIVE:
        raise HTTPException(status_code=400, detail="Only ACTIVE rentals can request return")
    if _to_local(r.start_date).date() > today_local:
        raise HTTPException(status_code=400, detail="Cannot request return before rental period starts")

    r.status = models.RentalStatus.RETURN_REQUESTED
    db.add(r)
    db.commit()
    db.refresh(r)
    return r


@router.patch("/{rental_id}/confirm-return", response_model=schemas.RentalOut)
def confirm_return(
    rental_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    r = db.get(models.Rental, rental_id)
    if not r:
        raise HTTPException(status_code=404, detail="Rental not found")
    if (user.id != r.user_id) and (not getattr(user, "is_admin", False)):
        raise HTTPException(status_code=403, detail="Forbidden")

    if r.status != models.RentalStatus.RETURN_REQUESTED:
        raise HTTPException(status_code=400, detail="Only RETURN_REQUESTED rentals can be closed")

    r.status = _CLOSED
    db.add(r)
    db.commit()
    db.refresh(r)
    return r
