# FILE: app/main.py
import os
import base64
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.routing import APIRoute

# ✅ 절대 임포트
from app.database import Base, engine
from app import models  # 모델 등록용 (create_all 전에 임포트)
from app.routers import auth, products, rentals, photos
from app.routers import payments, reviews
from app.routers import products_popular  # 인기 상품 라우터
from app.routers.reviews_summary import router as reviews_summary_router  # ✅ 리뷰 요약

# --- DB schema bootstrap ---
Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="Sallae Mallae API",
    version="0.2.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

# --- CORS (dev: allow all origins) ---
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 운영 시 특정 도메인만 허용 권장
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- (선택) 응답 압축 ---
app.add_middleware(GZipMiddleware, minimum_size=1024)

# --- Health check ---
@app.get("/")
def root():
    return {"status": "ok", "service": "sallae-mallae", "version": "0.2.0"}

# --- Static files ---
# /static/*  -> 실제 파일 경로: ./uploads/*
UPLOAD_ROOT = "uploads"
PRODUCTS_DIR = os.path.join(UPLOAD_ROOT, "products")
PHOTOS_DIR = os.path.join(UPLOAD_ROOT, "photos")

def _ensure_upload_tree() -> None:
    os.makedirs(UPLOAD_ROOT, exist_ok=True)
    os.makedirs(PRODUCTS_DIR, exist_ok=True)
    os.makedirs(PHOTOS_DIR, exist_ok=True)

def _ensure_placeholder_png(dst_path: str) -> None:
    """
    1x1 투명 PNG를 dst_path에 생성 (이미 있으면 스킵)
    """
    if os.path.exists(dst_path):
        return
    # 1x1 transparent PNG
    b64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII="
    try:
        with open(dst_path, "wb") as f:
            f.write(base64.b64decode(b64))
    except Exception as e:
        print("[main] placeholder create failed:", repr(e))

# 업로드 트리 보장 + 플레이스홀더 생성
_ensure_upload_tree()
_ensure_placeholder_png(os.path.join(PRODUCTS_DIR, "placeholder.png"))
# (선택) photos에도 플레이스홀더 하나 넣어둠
_ensure_placeholder_png(os.path.join(PHOTOS_DIR, "placeholder.png"))

# /static → uploads 마운트
app.mount("/static", StaticFiles(directory=UPLOAD_ROOT), name="static")

# --- Routers ---
app.include_router(auth.router)
app.include_router(products.router)
app.include_router(rentals.router)
app.include_router(photos.router)
app.include_router(payments.router)
app.include_router(reviews.router)
app.include_router(products_popular.router)
app.include_router(reviews_summary_router)

# --- Debug: print registered routes on startup ---
def _dump_routes() -> None:
    print("\n[ROUTES] Registered routes:")
    for r in app.routes:
        if isinstance(r, APIRoute):
            methods = ",".join(sorted(r.methods))
            print(f"  {methods:15s} {r.path}")
    print()

@app.on_event("startup")
def _on_startup():
    _dump_routes()
