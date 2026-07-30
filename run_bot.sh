#!/usr/bin/env bash
set -euo pipefail
# Interactive installer: capture owner id via echo mode, optionally run setup, then start forwarder
ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
BOT_PY="$ROOT_DIR/BOT/main.py"
WEB_ENV="$ROOT_DIR/WEB/.env"

read -p "Bot token (from @BotFather): " BOT_TOKEN
if [ -z "$BOT_TOKEN" ]; then echo "Bot token required"; exit 2; fi

# Start echo bot in background
LOG=/tmp/bot_echo.log
python3 "$BOT_PY" --mode echo --token "$BOT_TOKEN" > "$LOG" 2>&1 &
ECHO_PID=$!
echo $ECHO_PID > /tmp/bot_echo.pid

echo "Echo bot started (pid $ECHO_PID). Please open a chat with the bot and send any message (e.g., /start). Waiting up to 120s to capture your id..."
# Poll getUpdates for up to 120s
OFFSET=
OWNER_ID=
END=$((SECONDS+120))
while [ $SECONDS -lt $END ]; do
  sleep 2
  # fetch updates
  UPDATES=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates?offset=$OFFSET&timeout=1") || true
  if echo "$UPDATES" | grep -q '"result": \['; then
    # parse last update
    CHAT_ID=$(echo "$UPDATES" | tr '\n' ' ' | sed -n 's/.*"message".*"chat".*"id":\([0-9]*\).*/\1/p' | tail -n1)
    SENDER_ID=$(echo "$UPDATES" | tr '\n' ' ' | sed -n 's/.*"from".*"id":\([0-9]*\).*/\1/p' | tail -n1)
    if [ -n "$SENDER_ID" ]; then
      OWNER_ID=$SENDER_ID
      echo "Captured OWNER_ID=$OWNER_ID"
      break
    fi
  fi
done

if [ -z "$OWNER_ID" ]; then
  echo "Failed to capture owner id. You can run: python3 BOT/main.py --mode echo --token <token> manually to capture it. Exiting."
  kill $ECHO_PID 2>/dev/null || true
  exit 1
fi

# Stop echo bot
kill $ECHO_PID 2>/dev/null || true
rm -f /tmp/bot_echo.pid

# Confirm and persist
read -p "Save OWNER_ID=$OWNER_ID to WEB/.env? (y/n) " yn
if [ "${yn,,}" = "y" ] || [ -z "$yn" ]; then
  if [ -f "$WEB_ENV" ]; then
    # replace or add ADMIN_ID
    if grep -q "^ADMIN_ID=" "$WEB_ENV"; then
      sed -i "s/^ADMIN_ID=.*/ADMIN_ID=$OWNER_ID/" "$WEB_ENV"
    else
      echo "ADMIN_ID=$OWNER_ID" >> "$WEB_ENV"
    fi
    echo "Saved to $WEB_ENV"
  else
    echo "ADMIN_ID=$OWNER_ID" > "$WEB_ENV"
    echo "Created $WEB_ENV with ADMIN_ID"
  fi
fi

# Ask for GitHub token (optional) to perform setup (camoufox etc.)
read -p "Optionally enter GitHub token to allow installing Camoufox (press Enter to skip): " GITHUB_TOKEN
if [ -n "$GITHUB_TOKEN" ]; then
  # persist to WEB/.env as GITHUB_TOKEN (user chose to provide it explicitly)
  if grep -q "^GITHUB_TOKEN=" "$WEB_ENV" 2>/dev/null; then
    sed -i "s/^GITHUB_TOKEN=.*/GITHUB_TOKEN=$GITHUB_TOKEN/" "$WEB_ENV"
  else
    echo "GITHUB_TOKEN=$GITHUB_TOKEN" >> "$WEB_ENV"
  fi
  echo "Saved GITHUB_TOKEN to $WEB_ENV"
  read -p "Run setup_web.sh now to install dependencies and start tunnel? (y/n) " runsetup
  if [ "${runsetup,,}" = "y" ] || [ -z "$runsetup" ]; then
    echo "Running setup_web.sh (may require sudo)..."
    bash "$ROOT_DIR/setup_web.sh" || echo "setup_web.sh exited with non-zero status"
  fi
fi

# Start forwarder bot to send logs to owner
nohup python3 "$BOT_PY" --mode forward --token "$BOT_TOKEN" --owner "$OWNER_ID" > /tmp/bot_forward.log 2>&1 &
FORWARD_PID=$!
echo $FORWARD_PID > /tmp/bot_forward.pid

echo "Forwarder started (pid $FORWARD_PID). Logs will be sent to $OWNER_ID."

# Try to detect tunnel URL from cloudflared log
CF_LOG=/tmp/cloudflared_lmarena.log
if [ -f "$CF_LOG" ]; then
  URL=$(grep -Eo "https?://[a-z0-9-]+\.trycloudflare\.com" "$CF_LOG" | head -n1 || true)
  if [ -n "$URL" ]; then
    # notify owner via bot
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d chat_id="$OWNER_ID" -d text="Tunnel ready: $URL" >/dev/null || true
    echo "Notified owner with tunnel URL: $URL"
  fi
fi

exit 0
