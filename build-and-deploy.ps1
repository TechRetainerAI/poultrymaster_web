# Build and Deploy Frontend Script
# This script builds the Next.js application for production

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Building Frontend for Production" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if Node.js is installed
try {
    $nodeVersion = node --version
    Write-Host "✅ Node.js version: $nodeVersion" -ForegroundColor Green
} catch {
    Write-Host "❌ Node.js is not installed. Please install Node.js first." -ForegroundColor Red
    exit 1
}

# Check if npm is installed
try {
    $npmVersion = npm --version
    Write-Host "✅ npm version: $npmVersion" -ForegroundColor Green
} catch {
    Write-Host "❌ npm is not installed. Please install npm first." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Step 1: Installing dependencies..." -ForegroundColor Yellow
npm install

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to install dependencies" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Step 2: Building Next.js application..." -ForegroundColor Yellow
npm run build

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Build failed. Please check the errors above." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "✅ Build completed successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Build output is in: .next folder" -ForegroundColor Cyan
Write-Host ""
Write-Host "To run the production server locally:" -ForegroundColor Yellow
Write-Host "  npm run start" -ForegroundColor White
Write-Host ""
Write-Host "To deploy:" -ForegroundColor Yellow
Write-Host "  1. Upload the entire project folder to your hosting" -ForegroundColor White
Write-Host "  2. Run 'npm install --production' on the server" -ForegroundColor White
Write-Host "  3. Run 'npm run start' to start the server" -ForegroundColor White
Write-Host "  4. Or use a process manager like PM2" -ForegroundColor White
Write-Host ""

