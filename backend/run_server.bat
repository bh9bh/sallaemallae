@echo off
REM -------------------------
REM FastAPI 서버 실행 스크립트
REM -------------------------

REM 현재 스크립트가 있는 backend 폴더로 이동
cd /d "%~dp0"

REM 가상환경 활성화
call .venv\Scripts\activate

REM FastAPI 서버 실행
python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
