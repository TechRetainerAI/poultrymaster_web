#!/bin/bash
# PoultryPro Backend Build and Publish Script (Linux/Mac)
# This script builds and publishes both APIs for deployment

set -e  # Exit on error

CONFIGURATION="${1:-Release}"
OUTPUT_PATH="${2:-./publish}"
BUILD_ONLY="${3:-false}"

echo "========================================"
echo "PoultryPro Backend Build & Publish"
echo "========================================"
echo ""

# Check if .NET SDK is installed
echo "Checking .NET SDK..."
if ! command -v dotnet &> /dev/null; then
    echo "✗ .NET SDK not found. Please install .NET 8.0 SDK"
    exit 1
fi

DOTNET_VERSION=$(dotnet --version)
echo "✓ .NET SDK Version: $DOTNET_VERSION"

# Clean previous builds
echo ""
echo "Cleaning previous builds..."
dotnet clean PoultryPro.sln --configuration $CONFIGURATION
echo "✓ Clean completed"

# Restore packages
echo ""
echo "Restoring NuGet packages..."
dotnet restore PoultryPro.sln
echo "✓ Packages restored"

# Build solution
echo ""
echo "Building solution..."
dotnet build PoultryPro.sln --configuration $CONFIGURATION --no-restore
echo "✓ Build completed"

if [ "$BUILD_ONLY" = "true" ]; then
    echo ""
    echo "Build only mode - skipping publish"
    exit 0
fi

# Create output directories
LOGIN_API_PATH="$OUTPUT_PATH/LoginAPI"
FARM_API_PATH="$OUTPUT_PATH/PoultryFarmAPI"

echo ""
echo "Creating publish directories..."
mkdir -p "$LOGIN_API_PATH"
mkdir -p "$FARM_API_PATH"
echo "✓ Directories created"

# Publish LoginAPI
echo ""
echo "Publishing LoginAPI (User.Management.API)..."
echo "  Output: $LOGIN_API_PATH"
dotnet publish "LoginAPI/User.Management.API/User.Management.API.csproj" \
    --configuration $CONFIGURATION \
    --output "$LOGIN_API_PATH" \
    --no-build \
    --self-contained false \
    --runtime linux-x64

echo "✓ LoginAPI published successfully"

# Publish PoultryFarmAPI
echo ""
echo "Publishing PoultryFarmAPI..."
echo "  Output: $FARM_API_PATH"
dotnet publish "PoultryFarmAPI/PoultryFarmAPI.csproj" \
    --configuration $CONFIGURATION \
    --output "$FARM_API_PATH" \
    --no-build \
    --self-contained false \
    --runtime linux-x64

echo "✓ PoultryFarmAPI published successfully"

# Summary
echo ""
echo "========================================"
echo "Publish Complete!"
echo "========================================"
echo ""
echo "Published files:"
echo "  LoginAPI:      $LOGIN_API_PATH"
echo "  PoultryFarmAPI: $FARM_API_PATH"
echo ""
echo "Next steps:"
echo "  1. Update appsettings.json files with production values"
echo "  2. Copy published folders to your server"
echo "  3. Configure Nginx/Apache or run as systemd service"
echo "  4. Set up SSL certificates"
echo "  5. Configure firewall rules"
echo ""

