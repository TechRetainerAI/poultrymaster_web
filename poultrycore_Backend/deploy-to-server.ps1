# PoultryFarmAPI Deployment Script
# This script helps deploy the published files to your server

param(
    [Parameter(Mandatory=$true)]
    [string]$ServerPath,
    
    [string]$ServerType = "Local",  # Local, FTP, or Network
    [string]$FtpServer = "",
    [string]$FtpUsername = "",
    [string]$FtpPassword = "",
    [switch]$Backup = $true
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PoultryFarmAPI Deployment Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Source path
$sourcePath = Join-Path $PSScriptRoot "publish\PoultryFarmAPI"

if (-not (Test-Path $sourcePath)) {
    Write-Host "✗ Source path not found: $sourcePath" -ForegroundColor Red
    Write-Host "Please run 'dotnet publish' first" -ForegroundColor Yellow
    exit 1
}

Write-Host "Source: $sourcePath" -ForegroundColor Green
Write-Host "Target: $ServerPath" -ForegroundColor Green
Write-Host ""

# Backup existing deployment if requested
if ($Backup -and (Test-Path $ServerPath)) {
    $backupPath = "$ServerPath.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Write-Host "Creating backup..." -ForegroundColor Yellow
    Copy-Item -Path $ServerPath -Destination $backupPath -Recurse -Force
    Write-Host "✓ Backup created: $backupPath" -ForegroundColor Green
    Write-Host ""
}

# Deploy based on server type
switch ($ServerType) {
    "Local" {
        Write-Host "Deploying to local path..." -ForegroundColor Yellow
        
        # Create target directory if it doesn't exist
        if (-not (Test-Path $ServerPath)) {
            New-Item -ItemType Directory -Path $ServerPath -Force | Out-Null
            Write-Host "✓ Created target directory" -ForegroundColor Green
        }
        
        # Copy files
        Write-Host "Copying files..." -ForegroundColor Yellow
        Copy-Item -Path "$sourcePath\*" -Destination $ServerPath -Recurse -Force
        Write-Host "✓ Files copied successfully" -ForegroundColor Green
    }
    
    "Network" {
        Write-Host "Deploying to network path..." -ForegroundColor Yellow
        
        if (-not (Test-Path $ServerPath)) {
            Write-Host "✗ Network path not accessible: $ServerPath" -ForegroundColor Red
            exit 1
        }
        
        Write-Host "Copying files..." -ForegroundColor Yellow
        Copy-Item -Path "$sourcePath\*" -Destination $ServerPath -Recurse -Force
        Write-Host "✓ Files copied successfully" -ForegroundColor Green
    }
    
    "FTP" {
        Write-Host "FTP deployment not yet implemented" -ForegroundColor Yellow
        Write-Host "Please use FileZilla, WinSCP, or similar tool" -ForegroundColor Yellow
        exit 1
    }
    
    default {
        Write-Host "✗ Unknown server type: $ServerType" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Update appsettings.Production.json with production values" -ForegroundColor White
Write-Host "  2. Restart IIS application pool or Windows Service" -ForegroundColor White
Write-Host "  3. Test the API endpoint" -ForegroundColor White
Write-Host "  4. Check logs for any errors" -ForegroundColor White
Write-Host ""

