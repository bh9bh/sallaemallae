from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.routing import APIRoute
import os

from .database import Base, engine
from .routers import auth, products, rentals, photos
# ⬇️ 새로 추가된 라우터들
from .routers import payments, admin, reviews
from . import models

# --- DB schema bootstrap (idempotent) ---
Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="Sallae Mallae API",
    version="0.1.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

# --- CORS (dev: allow all origins) ---
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- Health check ---
@app.get("/")
def root():
    return {"status": "ok", "service": "sallae-mallae", "version": "0.1.0"}

# --- Static files ---
#   /static/products/... , /static/photos/...
#   (uploads/ 디렉토리가 없으면 StaticFiles가 에러를 내므로 사전 생성)
os.makedirs("uploads", exist_ok=True)
app.mount("/static", StaticFiles(directory="uploads"), name="static")

# --- Routers ---
app.include_router(auth.router)
app.include_router(products.router)
app.include_router(rentals.router)
app.include_router(photos.router)

# ⬇️ 새로 추가: 결제 시뮬레이터 / 관리자 승인 / 리뷰
app.include_router(payments.router)
app.include_router(admin.router)
app.include_router(reviews.router)


# ---------------- Debug: print registered routes on startup ----------------
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
# ---------------------------------------------------------------------------
