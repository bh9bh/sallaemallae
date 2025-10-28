# backend/scripts/quick_migrate_sqlite.py
import os, sqlite3, sys

DB_PATH = os.path.join(os.path.dirname(__file__), "..", "app.db")
DB_PATH = os.path.abspath(DB_PATH)

print(f"[INFO] Using DB: {DB_PATH}")
if not os.path.exists(DB_PATH):
    print("[ERROR] DB file not found. Expected at:", DB_PATH)
    sys.exit(1)

conn = sqlite3.connect(DB_PATH)
conn.execute("PRAGMA foreign_keys=ON")
cur = conn.cursor()

def has_column(table, column):
    cur.execute(f"PRAGMA table_info({table})")
    return any(row[1] == column for row in cur.fetchall())

def safe_add_column(sql):
    print("  ->", sql)
    cur.execute(sql)
    conn.commit()

# 1) users.is_admin
if not has_column("users", "is_admin"):
    safe_add_column("ALTER TABLE users ADD COLUMN is_admin BOOLEAN NOT NULL DEFAULT 0")

# 2) products.avg_rating
if not has_column("products", "avg_rating"):
    safe_add_column("ALTER TABLE products ADD COLUMN avg_rating FLOAT NOT NULL DEFAULT 0.0")

# 3) products.review_count
if not has_column("products", "review_count"):
    safe_add_column("ALTER TABLE products ADD COLUMN review_count INTEGER NOT NULL DEFAULT 0")

print("[DONE] Quick migration completed.")
conn.close()
