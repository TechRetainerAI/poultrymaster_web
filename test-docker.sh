#!/bin/bash

# Docker Testing Script for Linux/Mac
# Run this script to build, start, and test your Docker container

echo "========================================"
echo "  Docker Testing Script for Frontend   "
echo "========================================"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Step 1: Check if Docker is running
echo -e "${YELLOW}[1/6] Checking Docker...${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker is not installed!${NC}"
    echo "  Please install Docker and try again."
    exit 1
fi

if ! docker info &> /dev/null; then
    echo -e "${RED}✗ Docker is not running!${NC}"
    echo "  Please start Docker and try again."
    exit 1
fi

echo -e "${GREEN}✓ Docker is installed and running${NC}"

# Step 2: Stop existing container if running
echo ""
echo -e "${YELLOW}[2/6] Cleaning up existing containers...${NC}"
docker compose down 2>/dev/null
echo -e "${GREEN}✓ Cleanup complete${NC}"

# Step 3: Build the Docker image
echo ""
echo -e "${YELLOW}[3/6] Building Docker image...${NC}"
echo "  This may take several minutes on first build..."
if ! docker compose build; then
    echo -e "${RED}✗ Build failed! Check errors above.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Build successful!${NC}"

# Step 4: Start the container
echo ""
echo -e "${YELLOW}[4/6] Starting container...${NC}"
if ! docker compose up -d; then
    echo -e "${RED}✗ Failed to start container!${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Container started!${NC}"

# Step 5: Wait for container to be ready
echo ""
echo -e "${YELLOW}[5/6] Waiting for application to start...${NC}"
max_attempts=30
attempt=0
is_ready=false

while [ $attempt -lt $max_attempts ] && [ "$is_ready" = false ]; do
    sleep 2
    attempt=$((attempt + 1))
    
    if curl -f http://localhost:3000 > /dev/null 2>&1; then
        is_ready=true
    fi
    
    echo "  Attempt $attempt/$max_attempts..."
done

if [ "$is_ready" = false ]; then
    echo -e "${RED}✗ Application did not start in time. Check logs:${NC}"
    echo "  docker compose logs frontend"
    exit 1
fi

echo -e "${GREEN}✓ Application is ready!${NC}"

# Step 6: Test the application
echo ""
echo -e "${YELLOW}[6/6] Testing application endpoints...${NC}"

# Test homepage
if curl -f http://localhost:3000 > /dev/null 2>&1; then
    status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000)
    echo -e "${GREEN}✓ Homepage: HTTP $status${NC}"
else
    echo -e "${RED}✗ Homepage test failed${NC}"
fi

# Test login page
if curl -f http://localhost:3000/login > /dev/null 2>&1; then
    status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/login)
    echo -e "${GREEN}✓ Login page: HTTP $status${NC}"
else
    echo -e "${RED}✗ Login page test failed${NC}"
fi

# Check container status
echo ""
echo -e "${CYAN}Container Status:${NC}"
docker ps --filter "name=poultry-frontend" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "========================================"
echo "  Testing Complete!                    "
echo "========================================"
echo ""
echo -e "${YELLOW}📋 Useful Commands:${NC}"
echo "  View logs:      docker compose logs -f frontend"
echo "  Stop container: docker compose down"
echo "  Restart:        docker compose restart"
echo "  Container shell: docker exec -it poultry-frontend sh"
echo ""
echo -e "${YELLOW}🌐 Open in browser:${NC}"
echo "  Frontend: http://localhost:3000"
echo "  Login:    http://localhost:3000/login"
echo ""

