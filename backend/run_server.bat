@echo off
chcp 65001 >nul
cd /d "%~dp0"

set "PY=.\.venv\Scripts\python.exe"
if not exist "%PY%" set "PY=py"

echo Starting Uvicorn...
"%PY%" -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

echo(
echo Server exited. ErrorLevel=%errorlevel%
pause
