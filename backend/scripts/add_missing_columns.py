from app.database import engine

print(engine.url)  # sqlite:///./dev.db 확인

with engine.begin() as conn:
    conn.exec_driver_sql("PRAGMA foreign_keys=ON")

    # users 컬럼 점검
    users_rows = conn.exec_driver_sql("PRAGMA table_info(users)").fetchall()
    users_cols = [r[1] for r in users_rows]
    print("users columns:", users_cols)
    if "is_admin" not in users_cols:
        conn.exec_driver_sql("ALTER TABLE users ADD COLUMN is_admin BOOLEAN NOT NULL DEFAULT 0")
        print("✅ added users.is_admin")
    else:
        print("ℹ️ users.is_admin already exists")

    # products 컬럼 점검
    products_rows = conn.exec_driver_sql("PRAGMA table_info(products)").fetchall()
    products_cols = [r[1] for r in products_rows]
    print("products columns:", products_cols)

    if "avg_rating" not in products_cols:
        conn.exec_driver_sql("ALTER TABLE products ADD COLUMN avg_rating FLOAT NOT NULL DEFAULT 0.0")
        print("✅ added products.avg_rating")
    else:
        print("ℹ️ products.avg_rating already exists")

    if "review_count" not in products_cols:
        conn.exec_driver_sql("ALTER TABLE products ADD COLUMN review_count INTEGER NOT NULL DEFAULT 0")
        print("✅ added products.review_count")
    else:
        print("ℹ️ products.review_count already exists")
