# FILE: app/settings.py
from datetime import timedelta

# 하나의 소스에서만 관리
SECRET_KEY = "dev_secret_change_me"  # 운영에서는 환경변수로!
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24  # 24h

def jwt_exp_delta():
    return timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
