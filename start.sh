#!/bin/bash
# LMArena Bridge - Production Startup Script
# Starts web server, bot log forwarder, and cloudflared tunnel

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_DIR="$SCRIPT_DIR/WEB"
BOT_DIR="$SCRIPT_DIR/BOT"
LOG_DIR="/tmp/lmarena_logs"
PID_DIR="/tmp/lmarena_pids"

# Create directories
mkdir -p "$LOG_DIR" "$PID_DIR"

# Configuration (override with environment variables)
BOT_TOKEN="${BOT_TOKEN:-8830513815:AAEYeAinDuLLBzBpi0U4_fxJoVgRZ93EdCw}"
OWNER_ID="${OWNER_ID:-7610246474}"
WEB_PORT="${WEB_PORT:-8787}"

echo "=== LMArena Bridge Startup ==="
echo "Bot Token: ${BOT_TOKEN:0:10}..."
echo "Owner ID: $OWNER_ID"
echo "Web Port: $WEB_PORT"
echo ""

# Function to stop all services
cleanup() {
    echo "Stopping services..."
    for pidfile in "$PID_DIR"/*.pid; do
        if [ -f "$pidfile" ]; then
            pid=$(cat "$pidfile")
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null || true
            fi
            rm -f "$pidfile"
        fi
    done
    pkill -f "cloudflared tunnel" 2>/dev/null || true
    echo "All services stopped."
}

trap cleanup EXIT INT TERM

# Kill any existing processes
echo "Cleaning up existing processes..."
pkill -f "node server.js" 2>/dev/null || true
pkill -f "BOT/main.py" 2>/dev/null || true
pkill -f "cloudflared tunnel" 2>/dev/null || true
sleep 2

# Start web server
echo "Starting web server on port $WEB_PORT..."
cd "$WEB_DIR"
PORT=$WEB_PORT setsid node server.js > "$LOG_DIR/web_server.log" 2>&1 &
echo $! > "$PID_DIR/web_server.pid"
sleep 3

# Check if web server started
if ss -tlnp | grep -q ":$WEB_PORT"; then
    echo "✓ Web server started on port $WEB_PORT"
else
    echo "✗ Web server failed to start"
    cat "$LOG_DIR/web_server.log"
    exit 1
fi

# Start bot log forwarder
echo "Starting bot log forwarder..."
cd "$SCRIPT_DIR"
setsid python3 "$BOT_DIR/main.py" \
    --mode forward \
    --token "$BOT_TOKEN" \
    --owner "$OWNER_ID" \
    --logs "$LOG_DIR/web_server.log" "/tmp/client_errors.log" "/tmp/auth_times.log" \
    > "$LOG_DIR/bot.log" 2>&1 &
echo $! > "$PID_DIR/bot.pid"
sleep 2

if ps -p $(cat "$PID_DIR/bot.pid") > /dev/null 2>&1; then
    echo "✓ Bot log forwarder started"
else
    echo "✗ Bot log forwarder failed to start"
    cat "$LOG_DIR/bot.log"
fi

# Start cloudflared tunnel
echo "Starting cloudflared tunnel..."
setsid cloudflared tunnel --url "http://localhost:$WEB_PORT" --no-autoupdate > "$LOG_DIR/cloudflared.log" 2>&1 &
echo $! > "$PID_DIR/cloudflared.pid"
sleep 12

# Extract tunnel URL
TUNNEL_URL=$(grep -oE "https://[a-zA-Z0-9-]+\.trycloudflare\.com" "$LOG_DIR/cloudflared.log" | tail -1)
if [ -n "$TUNNEL_URL" ]; then
    echo "✓ Cloudflared tunnel started: $TUNNEL_URL"
else
    echo "✗ Cloudflared tunnel failed to get URL"
    cat "$LOG_DIR/cloudflared.log"
fi

echo ""
echo "=== All services started ==="
echo "Web UI: $TUNNEL_URL"
echo "Local: http://localhost:$WEB_PORT"
echo ""
echo "Logs: $LOG_DIR/"
echo "PIDs: $PID_DIR/"
echo ""
echo "Press Ctrl+C to stop all services"

# Keep script running
wait
