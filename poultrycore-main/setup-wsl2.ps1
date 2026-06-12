# WSL 2 Setup Script
# Run this AFTER restarting your computer

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  WSL 2 Setup Script                   " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "⚠️  This script requires Administrator privileges!" -ForegroundColor Yellow
    Write-Host "   Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    Write-Host ""
    pause
    exit 1
}

# Step 1: Set WSL 2 as default version
Write-Host "[1/3] Setting WSL 2 as default version..." -ForegroundColor Yellow
wsl --set-default-version 2

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ WSL 2 set as default version" -ForegroundColor Green
} else {
    Write-Host "⚠️  Note: You may need to install WSL 2 kernel update first" -ForegroundColor Yellow
    Write-Host "   Download from: https://aka.ms/wsl2kernel" -ForegroundColor Cyan
}

Write-Host ""

# Step 2: Check WSL status
Write-Host "[2/3] Checking WSL status..." -ForegroundColor Yellow
wsl --status

Write-Host ""

# Step 3: List WSL distributions
Write-Host "[3/3] Checking installed WSL distributions..." -ForegroundColor Yellow
wsl --list --verbose

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Next Steps:                          " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Install WSL 2 Kernel Update:" -ForegroundColor Yellow
Write-Host "   Download: https://aka.ms/wsl2kernel" -ForegroundColor White
Write-Host ""
Write-Host "2. (Optional) Install Ubuntu from Microsoft Store" -ForegroundColor Yellow
Write-Host "   Search 'Ubuntu' in Microsoft Store" -ForegroundColor White
Write-Host ""
Write-Host "3. Download Docker Desktop:" -ForegroundColor Yellow
Write-Host "   https://www.docker.com/products/docker-desktop/" -ForegroundColor White
Write-Host ""
Write-Host "4. After installing Docker, verify with:" -ForegroundColor Yellow
Write-Host "   docker --version" -ForegroundColor White
Write-Host ""


