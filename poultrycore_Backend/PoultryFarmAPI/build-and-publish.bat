@echo off
cd /d "%~dp0"
echo Building PoultryFarmAPI (Release)...
dotnet build -c Release
if errorlevel 1 exit /b 1
echo.
echo Publishing to publish folder...
dotnet publish -c Release -o .\publish
if errorlevel 1 exit /b 1
echo.
echo Done. Deploy folder: %~dp0publish
echo Copy the publish folder to your server to deploy.
pause
