@echo off
setlocal
cd /d "%~dp0"

REM The web-admin needs Administrator rights because it queries Hyper-V (Get-VM).
REM Self-elevate if we're not already elevated.
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

if not exist "node_modules" (
    echo Installing dependencies ^(first run^)...
    call npm install
    if errorlevel 1 (
        echo.
        echo npm install failed. Make sure Node.js is installed and on PATH.
        pause
        exit /b 1
    )
)

echo Starting Dune Awakening web-admin...
node server\index.js
echo.
echo Server stopped.
pause
