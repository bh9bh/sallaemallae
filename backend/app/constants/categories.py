# FILE: app/constants/categories.py
from typing import List, Dict

# DB에 저장할 key(영문) ↔ UI 표시명(한글)
CATEGORIES: List[Dict[str, str]] = [
    {"key": "living",      "label": "생활/가전"},
    {"key": "kitchen",     "label": "주방/요리"},
    {"key": "electronics", "label": "PC/전자기기"},
    {"key": "creator",     "label": "촬영/크리에이터"},
    {"key": "camping",     "label": "캠핑/레저"},
    {"key": "fashion",     "label": "의류/패션 소품"},
    {"key": "hobby",       "label": "취미/게임"},
    {"key": "kids",        "label": "유아/키즈"},
]

CATEGORY_KEYS = [c["key"] for c in CATEGORIES]
LABEL_BY_KEY = {c["key"]: c["label"] for c in CATEGORIES}
KEY_BY_LABEL = {c["label"]: c["key"] for c in CATEGORIES}
