from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional

from ..database import get_db
from ..deps import get_current_user
from .. import models

router = APIRouter(prefix="/payments", tags=["payments"])

# ---- Request/Response Schemas ----
class PayIn(BaseModel):
    rental_id: int
    amount: Optional[float] = None   # ⬅️ 프런트가 보낸 결제금액(옵션)
    method: Optional[str] = "mock"

class PayOut(BaseModel):
    ok: bool
    rental_id: int
    charged_amount: float
    method: str
    message: str

def _calc_expected_amount(r: models.Rental) -> float:
    # 데모: 대여료 합계 + 보증금 기준 (모델에 이미 total_price, deposit 존재)
    return float((r.total_price or 0) + (r.deposit or 0))

def _do_checkout(payload: PayIn, db: Session, user: models.User) -> PayOut:
    r = db.get(models.Rental, payload.rental_id)
    if not r:
        raise HTTPException(status_code=404, detail="Rental not found")
    if r.user_id != user.id:
        raise HTTPException(status_code=403, detail="Forbidden")

    # 실제 결제 로직은 없음. 시뮬레이터로 금액만 확정/에코
    expected = _calc_expected_amount(r)
    charged = float(payload.amount) if payload.amount is not None else expected

    # 여기서 결제 로그 저장/검증을 하고 싶다면, 별도 Payment 테이블을 만들면 됨.
    # 현재는 데모이므로 상태 변경 없이 메시지 반환만 수행.

    return PayOut(
        ok=True,
        rental_id=r.id,
        charged_amount=charged,
        method=payload.method or "mock",
        message="결제가 완료되었습니다 (시뮬레이터)."
    )

# ---- Main endpoint ----
@router.post("/checkout", response_model=PayOut)
def checkout(
    payload: PayIn,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    return _do_checkout(payload, db, user)

# ---- Compatibility endpoint for the app (ApiService.simulatePayment) ----
@router.post("/simulate", response_model=PayOut)
def simulate(
    payload: PayIn,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    return _do_checkout(payload, db, user)
