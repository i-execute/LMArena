#!/usr/bin/env bash
set -euo pipefail

# Installer / helper for LMArena WEB + cloudflared tunnel
# Prompts for BOT_TOKEN, optionally GH token (not required), installs cloudflared
# to ~/.local/bin, updates WEB/.env with BOT_TOKEN and ADMIN_ID, runs echo-id mode
# to capture admin id, and starts a temporary Cloudflare tunnel exposing :8787.

WEB_DIR="$(pwd)/WEB"
ENV_FILE="$WEB_DIR/.env"
LOCAL_BIN="$HOME/.local/bin"
CLOUDFLARED="$LOCAL_BIN/cloudflared"

mkdir -p "$LOCAL_BIN"
export PATH="$LOCAL_BIN:$PATH"

read -rp "Enter Telegram BOT_TOKEN (will be stored in $ENV_FILE): " BOT_TOKEN
read -rp "Do you want to auto-run echo-id to capture an admin id? (y/N): " RUN_ECHO
RUN_ECHO=${RUN_ECHO:-N}
read -rp "Enter ADMIN_ID to allow access (press Enter to skip and run echo-id to capture it): " ADMIN_ID
# If ADMIN_ID left empty and user chose to run echo, we'll capture it interactively later
ADMIN_ID=${ADMIN_ID:-}

read -rp "(Optional) Enter GitHub token to store in .env (press Enter to skip): " GITHUB_TOKEN
GITHUB_TOKEN=${GITHUB_TOKEN:-}

# Update .env
if [ ! -f "$ENV_FILE" ]; then
  echo "Creating $ENV_FILE"
  cp "$WEB_DIR/.env.example" "$ENV_FILE"
fi

# Replace or append BOT_TOKEN
if grep -q '^BOT_TOKEN=' "$ENV_FILE"; then
  sed -i "s|^BOT_TOKEN=.*|BOT_TOKEN=${BOT_TOKEN}|" "$ENV_FILE"
else
  echo "BOT_TOKEN=${BOT_TOKEN}" >> "$ENV_FILE"
fi

# Optionally append ADMIN_ID (if provided)
if [ -n "${ADMIN_ID}" ]; then
  if grep -q '^ADMIN_ID=' "$ENV_FILE"; then
    sed -i "s|^ADMIN_ID=.*|ADMIN_ID=${ADMIN_ID}|" "$ENV_FILE"
  else
    echo "ADMIN_ID=${ADMIN_ID}" >> "$ENV_FILE"
  fi
fi

# Optionally append GITHUB_TOKEN
if [ -n "${GITHUB_TOKEN}" ]; then
  if grep -q '^GITHUB_TOKEN=' "$ENV_FILE"; then
    sed -i "s|^GITHUB_TOKEN=.*|GITHUB_TOKEN=${GITHUB_TOKEN}|" "$ENV_FILE"
  else
    echo "GITHUB_TOKEN=${GITHUB_TOKEN}" >> "$ENV_FILE"
  fi
fi

# If ADMIN_ID not provided but RUN_ECHO requested, leave capture to interactive phase
if [ -z "${ADMIN_ID}" ] && [ "$RUN_ECHO" != "y" ] && [ "$RUN_ECHO" != "Y" ]; then
  echo "No ADMIN_ID provided and echo-id run skipped. You must set ADMIN_ID in $ENV_FILE to restrict access."
fi

echo "Updated $ENV_FILE"

# Install cloudflared to ~/.local/bin if not present
if [ ! -x "$CLOUDFLARED" ]; then
  echo "Downloading cloudflared to $CLOUDFLARED"
  curl -fsSL -o "$CLOUDFLARED" "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
  chmod +x "$CLOUDFLARED"
  echo "cloudflared installed to $CLOUDFLARED"
else
  echo "cloudflared already present at $CLOUDFLARED"
fi

# Install Python deps for OBHOD echo mode if needed
if command -v python3 >/dev/null 2>&1; then
  PY="python3"
else
  echo "python3 not found. Please install Python 3.12+ and retry." >&2
  exit 1
fi

# Optionally run echo-id mode to capture admin id
ECHO_PID=""
if [ "$RUN_ECHO" = "y" ] || [ "$RUN_ECHO" = "Y" ]; then
  echo "Starting echo-id mode. Send /start to your bot from the admin account to receive your numeric id back."
  "$PY" "$WEB_DIR/echo_id.py" "$BOT_TOKEN" > /tmp/echo_id.log 2>&1 &
  ECHO_PID=$!
  echo "echo-id started (pid: $ECHO_PID). Logs: /tmp/echo_id.log"
fi

# Start cloudflared tunnel
echo "Starting cloudflared tunnel (temporary public URL)."
# Run cloudflared in background and capture its stdout to a temp file
CF_LOG="/tmp/cloudflared_lmarena.log"
"$CLOUDFLARED" tunnel --url http://localhost:8787 --no-autoupdate > "$CF_LOG" 2>&1 &
CF_PID=$!

# Wait for cloudflared to output the url
echo "Waiting for tunnel URL (check $CF_LOG) ..."
URL=""
for i in {1..30}; do
  if grep -q "trycloudflare.com" "$CF_LOG" 2>/dev/null; then
    URL=$(grep -oE "https://[a-z0-9.-]+trycloudflare.com" "$CF_LOG" | head -n1 || true)
  fi
  if [ -n "$URL" ]; then break; fi
  sleep 1
done

if [ -n "$URL" ]; then
  echo "Tunnel URL: $URL"
else
  echo "Could not find tunnel URL in $CF_LOG. Tail of log:" && tail -n 50 "$CF_LOG"
fi

echo "echo-id pid: $ECHO_PID  (kill to stop)
cloudflared pid: $CF_PID  (kill to stop)"

echo "Done. If you received your admin id via echo-id, press Ctrl-C in that client to stop the echo script, then restart the Node server if needed." 

# End of script
