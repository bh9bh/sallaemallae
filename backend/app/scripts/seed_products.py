# FILE: app/scripts/seed_products.py
import os
from typing import List, Dict, Optional
from sqlalchemy.orm import Session
from sqlalchemy import select
from app.database import SessionLocal, engine
from app import models
from app.constants.categories import CATEGORIES

# idempotent (단, 기존 테이블에 새 컬럼 추가는 안 함)
models.Base.metadata.create_all(bind=engine)

SEED: Dict[str, List[Dict]] = {
    "living": [
        {"title": "다이슨 무선청소기 V10", "daily_price": 7000, "deposit": 50000},
        {"title": "샤오미 공기청정기", "daily_price": 5000, "deposit": 30000},
        {"title": "발뮤다 토스터", "daily_price": 6000, "deposit": 30000},
        {"title": "코드제로 스팀다리미", "daily_price": 4000, "deposit": 20000},
        {"title": "샤오미 선풍기", "daily_price": 3000, "deposit": 15000},
    ],
    "kitchen": [
        {"title": "쿠쿠 전기밥솥 6인용", "daily_price": 4000, "deposit": 20000},
        {"title": "브라운 핸드블렌더", "daily_price": 3000, "deposit": 10000},
        {"title": "에어프라이어 5L", "daily_price": 4000, "deposit": 20000},
        {"title": "네스프레소 커피머신", "daily_price": 5000, "deposit": 25000},
        {"title": "해피콜 프라이팬 세트", "daily_price": 3000, "deposit": 10000},
    ],
    "electronics": [
        {"title": "맥북 프로 14인치", "daily_price": 20000, "deposit": 200000},
        {"title": "아이패드 에어", "daily_price": 12000, "deposit": 100000},
        {"title": "휴대용 모니터 15.6", "daily_price": 8000, "deposit": 80000},
        {"title": "로지텍 키보드+마우스", "daily_price": 3000, "deposit": 20000},
        {"title": "빔프로젝터 미니", "daily_price": 10000, "deposit": 100000},
    ],
    "creator": [
        {"title": "소니 ZV-E10 Vlog 세트", "daily_price": 18000, "deposit": 150000},
        {"title": "고프로 Hero11", "daily_price": 15000, "deposit": 120000},
        {"title": "콘덴서 마이크 세트", "daily_price": 7000, "deposit": 50000},
        {"title": "LED 촬영 조명", "daily_price": 6000, "deposit": 40000},
        {"title": "알루미늄 삼각대", "daily_price": 4000, "deposit": 30000},
    ],
    "camping": [
        {"title": "2~3인용 텐트", "daily_price": 8000, "deposit": 60000},
        {"title": "캠핑 감성 랜턴", "daily_price": 3000, "deposit": 20000},
        {"title": "버너+코펠 세트", "daily_price": 5000, "deposit": 30000},
        {"title": "캠핑 테이블/의자 세트", "daily_price": 6000, "deposit": 40000},
        {"title": "침낭(봄·가을)", "daily_price": 4000, "deposit": 20000},
    ],
    "fashion": [
        {"title": "남성 클래식 정장 세트", "daily_price": 10000, "deposit": 80000},
        {"title": "여성 트렌치 코트", "daily_price": 8000, "deposit": 60000},
        {"title": "포멀 구두(남)", "daily_price": 5000, "deposit": 40000},
        {"title": "클러치/파티백", "daily_price": 4000, "deposit": 30000},
        {"title": "남성 코트(울)", "daily_price": 9000, "deposit": 70000},
    ],
    "hobby": [
        {"title": "닌텐도 스위치 본체", "daily_price": 12000, "deposit": 100000},
        {"title": "보드게임 3종 세트", "daily_price": 6000, "deposit": 30000},
        {"title": "전자피아노 61건", "daily_price": 10000, "deposit": 80000},
        {"title": "드론 입문 기체", "daily_price": 12000, "deposit": 100000},
        {"title": "레고 크리에이터 세트", "daily_price": 8000, "deposit": 60000},
    ],
    "kids": [
        {"title": "휴대용 유모차", "daily_price": 10000, "deposit": 120000},
        {"title": "카시트 ISOFIX", "daily_price": 8000, "deposit": 100000},
        {"title": "아기체육관", "daily_price": 5000, "deposit": 40000},
        {"title": "전동 바운서", "daily_price": 7000, "deposit": 80000},
        {"title": "젖병 소독기", "daily_price": 6000, "deposit": 50000},
    ],
}

DEFAULT_REGION = "서울/전체"
DEFAULT_IMG = "/static/products/placeholder.png"


def _has(model_cls, field: str) -> bool:
    return getattr(model_cls, field, None) is not None


def _set_if_exists(obj, field: str, value):
    if _has(type(obj), field):
        setattr(obj, field, value)


def _price_assign_dict(d: Dict, daily_price_value: float):
    """
    모델에 daily_price가 있으면 거기에, 없으면 price_per_day에 대입
    """
    if _has(models.Product, "daily_price"):
        d["daily_price"] = int(daily_price_value)
    elif _has(models.Product, "price_per_day"):
        d["price_per_day"] = int(daily_price_value)


def _safe_product_query_by_name(db: Session, name_value: str) -> Optional[models.Product]:
    # name 또는 title 컬럼 존재 상황 모두 지원
    if _has(models.Product, "name"):
        stmt = select(models.Product).where(models.Product.name == name_value)
    elif _has(models.Product, "title"):
        stmt = select(models.Product).where(models.Product.title == name_value)
    else:
        return None
    return db.execute(stmt).scalar_one_or_none()


def upsert_product(db: Session, item: Dict, category_key: str):
    # 시드 데이터는 title만 있으므로 name으로 정규화
    name_value = item.get("name") or item["title"]

    exists = _safe_product_query_by_name(db, name_value)
    if exists:
        # 카테고리/가격/보증금 등 "존재하는 컬럼만" 갱신
        if _has(models.Product, "category"):
            exists.category = category_key
        # 가격
        _set_if_exists(exists, "daily_price", int(item["daily_price"]))
        if not _has(models.Product, "daily_price"):
            _set_if_exists(exists, "price_per_day", int(item["daily_price"]))
        # 보증금
        _set_if_exists(exists, "deposit", int(item["deposit"]))
        db.add(exists)
        return exists

    # 신규 생성: 존재하는 컬럼만 담아 생성 dict 구성
    create_dict = {}

    # 이름
    if _has(models.Product, "name"):
        create_dict["name"] = name_value
    elif _has(models.Product, "title"):
        create_dict["title"] = name_value

    # 설명
    if _has(models.Product, "description"):
        desc = item.get("description")
        if desc is not None:
            create_dict["description"] = desc

    # 이미지
    if _has(models.Product, "image_url"):
        create_dict["image_url"] = item.get("image_url") or DEFAULT_IMG

    # 카테고리/지역
    if _has(models.Product, "category"):
        create_dict["category"] = category_key
    if _has(models.Product, "region"):
        create_dict["region"] = item.get("region") or DEFAULT_REGION

    # 가격
    _price_assign_dict(create_dict, item["daily_price"])

    # 보증금
    if _has(models.Product, "deposit"):
        create_dict["deposit"] = int(item["deposit"])

    # 기타 플래그(있을 때만)
    for flag in ("is_rentable", "is_purchasable", "is_active"):
        if _has(models.Product, flag) and (flag in item):
            create_dict[flag] = bool(item[flag])

    p = models.Product(**create_dict)
    db.add(p)
    return p


def run():
    with SessionLocal() as db:
        cnt = 0
        for cat in CATEGORIES:
            key = cat["key"]
            for it in SEED.get(key, []):
                upsert_product(db, it, key)
                cnt += 1
        db.commit()
        print(f"[seed] upserted {cnt} products.")


if __name__ == "__main__":
    run()
