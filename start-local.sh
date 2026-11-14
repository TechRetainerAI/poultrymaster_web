#!/usr/bin/env bash
# Start all local dev servers for VisibilityCore.
# Usage: bash start-local.sh
#
# Starts: Login API (port 7010), Farm API (port 7190), Frontend (port 3000)
# All output goes to the terminal. Ctrl+C stops everything.

set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
export NODE_TLS_REJECT_UNAUTHORIZED=0
export PATH="/c/Program Files/nodejs:$PATH"

echo "============================================="
echo " VisibilityCore Local Dev Servers"
echo "============================================="
echo ""

# Kill any existing processes on our ports
echo "[1/4] Cleaning up old processes..."
for port in 3000 7010 7190; do
  pid=$(netstat -ano 2>/dev/null | grep ":$port.*LISTENING" | awk '{print $NF}' | head -1)
  if [ -n "$pid" ] && [ "$pid" != "0" ]; then
    taskkill //F //PID "$pid" 2>/dev/null && echo "  Killed PID $pid on port $port" || true
  fi
done
sleep 1

# Start Login API (must be first — handles auth)
echo "[2/4] Starting Login API on port 7010..."
cd "$ROOT/poultrycore_Backend/LoginAPI/User.Management.API"
dotnet run &
LOGIN_PID=$!

# Start Farm API
echo "[3/4] Starting Farm API on port 7190..."
cd "$ROOT/poultrycore_Backend/PoultryFarmAPI"
dotnet run --urls "http://localhost:7190" &
FARM_PID=$!

# Wait for APIs to start
echo "  Waiting for APIs to start..."
sleep 8

# Start Frontend
echo "[4/4] Starting Frontend on port 3000..."
cd "$ROOT/poultrycore-main"
npm run dev &
NEXT_PID=$!

echo ""
echo "============================================="
echo " All servers starting!"
echo "  Frontend:  http://localhost:3000"
echo "  Farm API:  http://localhost:7190"
echo "  Login API: https://localhost:7010"
echo ""
echo "  Login: mazytech / 123456"
echo "  Press Ctrl+C to stop all servers"
echo "============================================="

# Wait for any process to exit
wait $LOGIN_PID $FARM_PID $NEXT_PID
