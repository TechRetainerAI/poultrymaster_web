# PoultryPro Backend Build and Publish Script
# This script builds and publishes both APIs for deployment

param(
    [string]$Configuration = "Release",
    [string]$OutputPath = ".\publish",
    [switch]$BuildOnly = $false
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PoultryPro Backend Build & Publish" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Set error handling
$ErrorActionPreference = "Stop"

# Check if .NET SDK is installed
Write-Host "Checking .NET SDK..." -ForegroundColor Yellow
try {
    $dotnetVersion = dotnet --version
    Write-Host "✓ .NET SDK Version: $dotnetVersion" -ForegroundColor Green
} catch {
    Write-Host "✗ .NET SDK not found. Please install .NET 8.0 SDK" -ForegroundColor Red
    exit 1
}

# Clean previous builds
Write-Host ""
Write-Host "Cleaning previous builds..." -ForegroundColor Yellow
dotnet clean PoultryPro.sln --configuration $Configuration
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Clean failed" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Clean completed" -ForegroundColor Green

# Restore packages
Write-Host ""
Write-Host "Restoring NuGet packages..." -ForegroundColor Yellow
dotnet restore PoultryPro.sln
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Restore failed" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Packages restored" -ForegroundColor Green

# Build solution
Write-Host ""
Write-Host "Building solution..." -ForegroundColor Yellow
dotnet build PoultryPro.sln --configuration $Configuration --no-restore
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Build failed" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Build completed" -ForegroundColor Green

if ($BuildOnly) {
    Write-Host ""
    Write-Host "Build only mode - skipping publish" -ForegroundColor Yellow
    exit 0
}

# Create output directories
$publishPath = Join-Path $PSScriptRoot $OutputPath
$loginApiPath = Join-Path $publishPath "LoginAPI"
$farmApiPath = Join-Path $publishPath "PoultryFarmAPI"

Write-Host ""
Write-Host "Creating publish directories..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path $loginApiPath | Out-Null
New-Item -ItemType Directory -Force -Path $farmApiPath | Out-Null
Write-Host "✓ Directories created" -ForegroundColor Green

# Publish LoginAPI
Write-Host ""
Write-Host "Publishing LoginAPI (User.Management.API)..." -ForegroundColor Yellow
Write-Host "  Output: $loginApiPath" -ForegroundColor Gray
dotnet publish "LoginAPI\User.Management.API\User.Management.API.csproj" `
    --configuration $Configuration `
    --output $loginApiPath `
    --no-build `
    --self-contained false `
    --runtime win-x64

if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ LoginAPI publish failed" -ForegroundColor Red
    exit 1
}
Write-Host "✓ LoginAPI published successfully" -ForegroundColor Green

# Publish PoultryFarmAPI
Write-Host ""
Write-Host "Publishing PoultryFarmAPI..." -ForegroundColor Yellow
Write-Host "  Output: $farmApiPath" -ForegroundColor Gray
dotnet publish "PoultryFarmAPI\PoultryFarmAPI.csproj" `
    --configuration $Configuration `
    --output $farmApiPath `
    --no-build `
    --self-contained false `
    --runtime win-x64

if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ PoultryFarmAPI publish failed" -ForegroundColor Red
    exit 1
}
Write-Host "✓ PoultryFarmAPI published successfully" -ForegroundColor Green

# Copy web.config to PoultryFarmAPI if it exists
$webConfigPath = Join-Path $PSScriptRoot "PoultryFarmAPI\web.config"
$webConfigDest = Join-Path $farmApiPath "web.config"
if (Test-Path $webConfigPath) {
    Write-Host ""
    Write-Host "Copying web.config for Plesk/IIS..." -ForegroundColor Yellow
    Copy-Item $webConfigPath $webConfigDest -Force
    Write-Host "✓ web.config copied" -ForegroundColor Green
}

# Copy appsettings.Production.json if it exists
$prodSettingsPath = Join-Path $PSScriptRoot "PoultryFarmAPI\appsettings.Production.json"
$prodSettingsDest = Join-Path $farmApiPath "appsettings.Production.json"
if (Test-Path $prodSettingsPath) {
    Write-Host ""
    Write-Host "Copying appsettings.Production.json..." -ForegroundColor Yellow
    Copy-Item $prodSettingsPath $prodSettingsDest -Force
    Write-Host "✓ appsettings.Production.json copied" -ForegroundColor Green
}

# Create logs directory
$logsPath = Join-Path $farmApiPath "logs"
if (-not (Test-Path $logsPath)) {
    New-Item -ItemType Directory -Force -Path $logsPath | Out-Null
    Write-Host "✓ Logs directory created" -ForegroundColor Green
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Publish Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Published files:" -ForegroundColor Yellow
Write-Host "  LoginAPI:      $loginApiPath" -ForegroundColor White
Write-Host "  PoultryFarmAPI: $farmApiPath" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Update appsettings.json files with production values" -ForegroundColor White
Write-Host "  2. Copy published folders to your server" -ForegroundColor White
Write-Host "  3. Configure IIS or run as Windows Service" -ForegroundColor White
Write-Host "  4. Set up SSL certificates" -ForegroundColor White
Write-Host "  5. Configure firewall rules" -ForegroundColor White
Write-Host ""

