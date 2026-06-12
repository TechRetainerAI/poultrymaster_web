# Docker Testing Script for Windows PowerShell
# Run this script to build, start, and test your Docker container

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Docker Testing Script for Frontend   " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Check if Docker is running
Write-Host "[1/6] Checking Docker..." -ForegroundColor Yellow
try {
    $dockerVersion = docker --version
    Write-Host "✓ Docker is installed: $dockerVersion" -ForegroundColor Green
} catch {
    Write-Host "✗ Docker is not running or not installed!" -ForegroundColor Red
    Write-Host "  Please install Docker Desktop and try again." -ForegroundColor Red
    exit 1
}

# Step 2: Stop existing container if running
Write-Host ""
Write-Host "[2/6] Cleaning up existing containers..." -ForegroundColor Yellow
docker compose down 2>$null
Write-Host "✓ Cleanup complete" -ForegroundColor Green

# Step 3: Build the Docker image
Write-Host ""
Write-Host "[3/6] Building Docker image..." -ForegroundColor Yellow
Write-Host "  This may take several minutes on first build..." -ForegroundColor Gray
docker compose build
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Build failed! Check errors above." -ForegroundColor Red
    exit 1
}
Write-Host "✓ Build successful!" -ForegroundColor Green

# Step 4: Start the container
Write-Host ""
Write-Host "[4/6] Starting container..." -ForegroundColor Yellow
docker compose up -d
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Failed to start container!" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Container started!" -ForegroundColor Green

# Step 5: Wait for container to be ready
Write-Host ""
Write-Host "[5/6] Waiting for application to start..." -ForegroundColor Yellow
$maxAttempts = 30
$attempt = 0
$isReady = $false

while ($attempt -lt $maxAttempts -and -not $isReady) {
    Start-Sleep -Seconds 2
    $attempt++
    
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:3000" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            $isReady = $true
        }
    } catch {
        # Still loading, continue waiting
    }
    
    Write-Host "  Attempt $attempt/$maxAttempts..." -ForegroundColor Gray
}

if (-not $isReady) {
    Write-Host "✗ Application did not start in time. Check logs:" -ForegroundColor Red
    Write-Host "  docker compose logs frontend" -ForegroundColor Yellow
    exit 1
}

Write-Host "✓ Application is ready!" -ForegroundColor Green

# Step 6: Test the application
Write-Host ""
Write-Host "[6/6] Testing application endpoints..." -ForegroundColor Yellow

# Test homepage
try {
    $homepage = Invoke-WebRequest -Uri "http://localhost:3000" -UseBasicParsing -ErrorAction Stop
    Write-Host "✓ Homepage: HTTP $($homepage.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "✗ Homepage test failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test login page
try {
    $login = Invoke-WebRequest -Uri "http://localhost:3000/login" -UseBasicParsing -ErrorAction Stop
    Write-Host "✓ Login page: HTTP $($login.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "✗ Login page test failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Check container status
Write-Host ""
Write-Host "Container Status:" -ForegroundColor Cyan
docker ps --filter "name=poultry-frontend" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Testing Complete!                    " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "📋 Useful Commands:" -ForegroundColor Yellow
Write-Host "  View logs:      docker compose logs -f frontend" -ForegroundColor White
Write-Host "  Stop container: docker compose down" -ForegroundColor White
Write-Host "  Restart:        docker compose restart" -ForegroundColor White
Write-Host "  Container shell: docker exec -it poultry-frontend sh" -ForegroundColor White
Write-Host ""
Write-Host "🌐 Open in browser:" -ForegroundColor Yellow
Write-Host "  Frontend: http://localhost:3000" -ForegroundColor White
Write-Host "  Login:    http://localhost:3000/login" -ForegroundColor White
Write-Host ""

