# app/routers/_guards.py
from fastapi import HTTPException, status

def assert_owner_or_admin(resource_owner_id: int, user) -> None:
    """
    리소스 소유자이거나 관리자일 때만 통과.
    아니면 403 Forbidden 발생.
    """
    if (getattr(user, "id", None) != resource_owner_id) and (not getattr(user, "is_admin", False)):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Forbidden")


def require_admin(user) -> None:
    """
    관리자만 허용해야 하는 엔드포인트에서 사용.
    """
    if not getattr(user, "is_admin", False):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin only")
