# FILE: app/routers/rentals.py
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy.orm import Session
from sqlalchemy import and_
from datetime import datetime, date, timezone, timedelta
from typing import List, Optional, Dict, Any, Union
import base64
import json

from .. import models, schemas
from ..database import get_db
from ..deps import get_current_user

router = APIRouter(prefix="/rentals", tags=["rentals"])

# ---------- TZ & util ----------
try:
    from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
    try:
        KST = ZoneInfo("Asia/Seoul")
    except ZoneInfoNotFoundError:
        KST = timezone(timedelta(hours=9))  # UTC+9 fixed
except Exception:
    KST = timezone(timedelta(hours=9))      # UTC+9 fixed

DateLike = Union[date, datetime]


def _as_date(x: Optional[DateLike]) -> date:
    if x is None:
        raise ValueError("date value is None")
    if isinstance(x, datetime):
        return x.date()
    return x


def _days_between(a: DateLike, b: DateLike) -> int:
    da, db = _as_date(a), _as_date(b)
    days = (db - da).days
    return max(1, days)


def _status(name: str):
    return getattr(models.RentalStatus, name, None)


_EXPIRED = _status("EXPIRED")
_CLOSED = models.RentalStatus.CLOSED
_INACTIVE_SET = tuple([_CLOSED] + ([_EXPIRED] if _EXPIRED else []))


def _encode_cursor_payload(payload: Dict[str, Any]) -> str:
    return base64.urlsafe_b64encode(json.dumps(payload).encode()).decode()


def _decode_cursor_payload(s: Optional[str]) -> Optional[Dict[str, Any]]:
    if not s:
        return None
    try:
        return json.loads(base64.urlsafe_b64decode(s.encode()).decode())
    except Exception:
        return None


def _to_local(dt: datetime) -> datetime:
    if dt is None:
        return dt
    return (dt.replace(tzinfo=KST) if dt.tzinfo is None else dt.astimezone(KST))


def _to_utc(dt: datetime) -> datetime:
    if dt is None:
        return dt
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=KST)
    return dt.astimezone(timezone.utc)


# ---------- create / availability ----------
@router.post("", response_model=schemas.RentalOut, status_code=201)
@router.post("/", response_model=schemas.RentalOut, status_code=201)
def create_rental(
    payload: schemas.RentalCreate,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    """
    End date is treated as exclusive. Overlap condition:
    (exist.start < new.end) AND (exist.end > new.start)
    """
    product = db.get(models.Product, payload.product_id)
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")

    # ✅ 가격 필드 자동 감지
    price = getattr(product, "price_per_day", None)
    if price is None:
        raise HTTPException(status_code=500, detail="Product has no price_per_day field")

    # ✅ 보증금 유연 처리 (deposit or security_deposit)
    deposit = getattr(product, "deposit", None)
    if deposit is None:
        deposit = getattr(product, "security_deposit", None)

    start = _as_date(payload.start_date)
    end = _as_date(payload.end_date)

    if end <= start:
        raise HTTPException(status_code=400, detail="Invalid date range")

    # Overlap check
    overlap = (
        db.query(models.Rental)
        .filter(
            models.Rental.product_id == payload.product_id,
            models.Rental.status.notin_(_INACTIVE_SET),
            models.Rental.start_date < end,
            models.Rental.end_date > start,
        )
        .first()
    )
    if overlap:
        raise HTTPException(status_code=409, detail="This product is already booked for the selected dates")

    days = _days_between(start, end)

    rental = models.Rental(
        user_id=user.id,
        product_id=product.id,
        start_date=start,
        end_date=end,
        total_price=price * days,   # ✅ FIXED
        deposit=deposit,
        status=models.RentalStatus.PENDING,
    )
    db.add(rental)
    db.commit()
    db.refresh(rental)
    return rental


@router.get("/availability")
@router.get("/availability/")
def check_availability(
    product_id: int,
    start: date,
    end: date,
    db: Session = Depends(get_db),
):
    """Check availability for a single range (end exclusive)."""
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


# ---------- blocked dates ----------
@router.get("/blocked-dates")
@router.get("/blocked-dates/")
def get_blocked_dates(
    product_id: int,
    expand: bool = Query(False, description="If true, returns list of 'YYYY-MM-DD' (end exclusive)"),
    db: Session = Depends(get_db),
):
    """
    Returns all non-closed ranges [start, end) for the product.

    - expand=False (default): [{"start": "...", "end": "..."}]
    - expand=True : ["YYYY-MM-DD", ...] (unique, sorted)
    """
    rows = (
        db.query(models.Rental)
        .filter(
            models.Rental.product_id == product_id,
            models.Rental.status.notin_(_INACTIVE_SET),
        )
        .all()
    )

    if not expand:
        return [
            {
                "start": (r.start_date.isoformat() if isinstance(r.start_date, (date, datetime)) else str(r.start_date)),
                "end": (r.end_date.isoformat() if isinstance(r.end_date, (date, datetime)) else str(r.end_date)),
            }
            for r in rows
        ]

    out_dates = set()
    for r in rows:
        s = _as_date(r.start_date)
        e = _as_date(r.end_date)
        cur = s
        while cur < e:  # exclusive
            out_dates.add(cur.isoformat())
            cur = cur + timedelta(days=1)

    return sorted(out_dates)


# ---------- expire update ----------
def _expire_overdue_for_user(db: Session, user_id: int) -> None:
    """Mark ended ACTIVE/PENDING as EXPIRED (or CLOSED) by KST today."""
    today_local = datetime.now(KST).date()
    rows_to_expire = (
        db.query(models.Rental)
        .filter(
            models.Rental.user_id == user_id,
            models.Rental.status.notin_(_INACTIVE_SET),
        )
        .all()
    )
    changed = False
    for r in rows_to_expire:
        if _to_local(datetime.combine(r.end_date, datetime.min.time())).date() < today_local:
            r.status = _EXPIRED or _CLOSED
            db.add(r)
            changed = True
    if changed:
        db.commit()


# ---------- list / get ----------
@router.get("/me", response_model=List[schemas.RentalOut])
@router.get("/me/", response_model=List[schemas.RentalOut])
def list_my_rentals(
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
    skip: int = 0,
    limit: int = 50,
    include_inactive: Optional[bool] = None,
    include_closed: Optional[bool] = Query(None, description="Deprecated. Use include_inactive"),
):
    if include_closed is not None:
        include_inactive = include_closed
    include_inactive = bool(include_inactive) if include_inactive is not None else False

    _expire_overdue_for_user(db, user.id)

    q = db.query(models.Rental).filter(models.Rental.user_id == user.id)
    if not include_inactive:
        q = q.filter(models.Rental.status.notin_(_INACTIVE_SET))

    rows = q.order_by(models.Rental.id.desc()).offset(skip).limit(limit).all()
    return rows


@router.get("/my", response_model=List[schemas.RentalOut])
@router.get("/my/", response_model=List[schemas.RentalOut])
def list_my_rentals_alias(
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
    skip: int = 0,
    limit: int = 50,
    include_inactive: Optional[bool] = None,
    include_closed: Optional[bool] = Query(None),
):
    return list_my_rentals(
        db=db,
        user=user,
        skip=skip,
        limit=limit,
        include_inactive=include_inactive,
        include_closed=include_closed,
    )


@router.get("/me/page")
@router.get("/me/page/")
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

    _expire_overdue_for_user(db, user.id)

    cur = _decode_cursor_payload(cursor) or {}
    last_id = cur.get("last_id")

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
    next_cursor = _encode_cursor_payload({"last_id": items[-1].id}) if has_more and items else None

    return {
        "items": [schemas.RentalOut.model_validate(r).model_dump() for r in items],
        "next_cursor": next_cursor,
    }


@router.get("")
@router.get("/")
def list_rentals_root_compat(
    request: Request,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
    skip: int = 0,
    limit: int = 50,
    include_inactive: Optional[bool] = None,
    include_closed: Optional[bool] = Query(None),
    user_param: Optional[str] = Query(None, alias="user"),
):
    if user_param and user_param.lower() == "me":
        return list_my_rentals(
            db=db, user=user, skip=skip, limit=limit,
            include_inactive=include_inactive, include_closed=include_closed
        )
    raise HTTPException(status_code=400, detail="Unsupported query. Use /rentals/me or /rentals/my")


@router.get("/{rental_id}", response_model=schemas.RentalOut)
def get_rental(
    rental_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    r = db.get(models.Rental, rental_id)
    if not r:
        raise HTTPException(status_code=404, detail="Rental not found")

    if (user.id != r.user_id) and (not getattr(user, "is_admin", False)):
        raise HTTPException(status_code=403, detail="Forbidden")

    today_local = datetime.now(KST).date()
    if r.status not in _INACTIVE_SET and _to_local(datetime.combine(r.end_date, datetime.min.time())).date() < today_local:
        r.status = _EXPIRED or _CLOSED
        db.add(r)
        db.commit()
        db.refresh(r)
    return r


# ---------- status actions ----------
def _ensure_owner_or_admin(r: models.Rental, user: models.User):
    if (user.id != r.user_id) and (not getattr(user, "is_admin", False)):
        raise HTTPException(status_code=403, detail="Forbidden")


@router.patch("/{rental_id}/cancel", response_model=schemas.RentalOut)
@router.patch("/{rental_id}/cancel/", response_model=schemas.RentalOut)
def cancel_rental(
    rental_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    r = db.get(models.Rental, rental_id)
    if not r:
        raise HTTPException(status_code=404, detail="Rental not found")
    _ensure_owner_or_admin(r, user)

    today_local = datetime.now(KST).date()
    if r.status not in (models.RentalStatus.PENDING, models.RentalStatus.ACTIVE):
        raise HTTPException(status_code=400, detail="Only PENDING or ACTIVE rentals can be canceled")
    if _to_local(datetime.combine(r.start_date, datetime.min.time())).date() <= today_local:
        raise HTTPException(status_code=400, detail="Cannot cancel on/after start date")

    r.status = _CLOSED
    db.add(r)
    db.commit()
    db.refresh(r)
    return r


@router.post("/{rental_id}/cancel", response_model=schemas.RentalOut)
@router.post("/{rental_id}/cancel/", response_model=schemas.RentalOut)
def cancel_rental_post_alias(
    rental_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    return cancel_rental(rental_id, db, user)


@router.patch("/{rental_id}/request-return", response_model=schemas.RentalOut)
@router.patch("/{rental_id}/request-return/", response_model=schemas.RentalOut)
def request_return(
    rental_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    r = db.get(models.Rental, rental_id)
    if not r:
        raise HTTPException(status_code=404, detail="Rental not found")
    _ensure_owner_or_admin(r, user)

    today_local = datetime.now(KST).date()
    if r.status != models.RentalStatus.ACTIVE:
        raise HTTPException(status_code=400, detail="Only ACTIVE rentals can request return")
    if _to_local(datetime.combine(r.start_date, datetime.min.time())).date() > today_local:
        raise HTTPException(status_code=400, detail="Cannot request return before rental period starts")

    r.status = models.RentalStatus.RETURN_REQUESTED
    db.add(r)
    db.commit()
    db.refresh(r)
    return r


@router.post("/{rental_id}/request-return", response_model=schemas.RentalOut)
@router.post("/{rental_id}/request-return/", response_model=schemas.RentalOut)
def request_return_post_alias(
    rental_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    return request_return(rental_id, db, user)


@router.patch("/{rental_id}/confirm-return", response_model=schemas.RentalOut)
@router.patch("/{rental_id}/confirm-return/", response_model=schemas.RentalOut)
def confirm_return(
    rental_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    r = db.get(models.Rental, rental_id)
    if not r:
        raise HTTPException(status_code=404, detail="Rental not found")
    _ensure_owner_or_admin(r, user)

    if r.status != models.RentalStatus.RETURN_REQUESTED:
        raise HTTPException(status_code=400, detail="Only RETURN_REQUESTED rentals can be closed")

    r.status = _CLOSED
    db.add(r)
    db.commit()
    db.refresh(r)
    return r


@router.post("/{rental_id}/confirm-return", response_model=schemas.RentalOut)
@router.post("/{rental_id}/confirm-return/", response_model=schemas.RentalOut)
def confirm_return_post_alias(
    rental_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    return confirm_return(rental_id, db, user)
