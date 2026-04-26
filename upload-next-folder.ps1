# Script to help identify and prepare .next folder for upload
# Run this on your local machine before uploading to Plesk

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Checking .next Folder for Plesk Upload" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$nextPath = ".next"

# Check if .next folder exists
if (Test-Path $nextPath) {
    Write-Host "✅ .next folder found!" -ForegroundColor Green
    Write-Host ""
    
    # Get folder size
    $folderSize = (Get-ChildItem -Path $nextPath -Recurse | Measure-Object -Property Length -Sum).Sum
    $sizeMB = [math]::Round($folderSize / 1MB, 2)
    Write-Host "Folder size: $sizeMB MB" -ForegroundColor Yellow
    Write-Host ""
    
    # Check for required files/folders
    Write-Host "Checking required files..." -ForegroundColor Yellow
    
    $requiredItems = @(
        "BUILD_ID",
        "server",
        "static"
    )
    
    $allFound = $true
    foreach ($item in $requiredItems) {
        $itemPath = Join-Path $nextPath $item
        if (Test-Path $itemPath) {
            Write-Host "  ✅ $item" -ForegroundColor Green
        } else {
            Write-Host "  ❌ $item - MISSING!" -ForegroundColor Red
            $allFound = $false
        }
    }
    
    Write-Host ""
    
    if ($allFound) {
        Write-Host "✅ .next folder is complete and ready to upload!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Upload this folder to:" -ForegroundColor Yellow
        Write-Host "  C:\Inetpub\vhosts\poultrycore.com\dev-app.poultrycore.com\.next\" -ForegroundColor White
        Write-Host ""
        Write-Host "Or via Plesk File Manager:" -ForegroundColor Yellow
        Write-Host "  Navigate to: httpdocs/.next/" -ForegroundColor White
        Write-Host "  Upload the entire .next folder" -ForegroundColor White
    } else {
        Write-Host "❌ .next folder is incomplete!" -ForegroundColor Red
        Write-Host ""
        Write-Host "You need to rebuild:" -ForegroundColor Yellow
        Write-Host "  npm run build" -ForegroundColor White
    }
} else {
    Write-Host "❌ .next folder NOT FOUND!" -ForegroundColor Red
    Write-Host ""
    Write-Host "You need to build the application first:" -ForegroundColor Yellow
    Write-Host "  npm run build" -ForegroundColor White
    Write-Host ""
    Write-Host "After building, run this script again to verify." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan

