@echo off
cd /d "%~dp0"
echo Building Next.js app...
call npm run build
if errorlevel 1 exit /b 1

echo.
echo Preparing deploy folder...
if exist deploy rmdir /s /q deploy
mkdir deploy

xcopy /e /i /y ".next\standalone\*" "deploy\"
xcopy /e /i /y ".next\static" "deploy\.next\static\"
if exist public xcopy /e /i /y "public" "deploy\public\"

echo.
echo Deploy folder ready: %~dp0deploy
echo To run: cd deploy ^&^& node server.js
pause
