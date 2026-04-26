# Build and prepare frontend for deployment
# Output: ./deploy folder (ready to host)

$ErrorActionPreference = "Stop"
$rootDir = $PSScriptRoot
$deployDir = Join-Path $rootDir "deploy"
$standaloneDir = Join-Path $rootDir ".next\standalone"

Write-Host "Building Next.js app..." -ForegroundColor Cyan
Set-Location $rootDir
npm run build
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`nPreparing deploy folder..." -ForegroundColor Cyan
if (Test-Path $deployDir) { Remove-Item $deployDir -Recurse -Force }
New-Item -ItemType Directory -Path $deployDir | Out-Null

# Copy standalone output
Copy-Item -Path "$standaloneDir\*" -Destination $deployDir -Recurse -Force

# Copy static assets (required for standalone)
$staticSrc = Join-Path $rootDir ".next\static"
$staticDst = Join-Path $deployDir ".next\static"
if (Test-Path $staticSrc) {
    New-Item -ItemType Directory -Path (Split-Path $staticDst) -Force | Out-Null
    Copy-Item -Path $staticSrc -Destination $staticDst -Recurse -Force
}

# Copy public folder if exists
$publicSrc = Join-Path $rootDir "public"
if (Test-Path $publicSrc) {
    Copy-Item -Path $publicSrc -Destination (Join-Path $deployDir "public") -Recurse -Force
}

Write-Host "`nDeploy folder ready: $deployDir" -ForegroundColor Green
Write-Host "To run: cd deploy; node server.js" -ForegroundColor Yellow
