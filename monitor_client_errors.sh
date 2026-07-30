#!/usr/bin/env bash
# Monitors /tmp/client_errors.log for new entries and forwards them to admin via Telegram
set -euo pipefail
ENV_FILE="/home/forget/LMArena/WEB/.env"
if [ -f "$ENV_FILE" ]; then
  BOT_TOKEN=$(grep '^BOT_TOKEN=' "$ENV_FILE" | cut -d'=' -f2- || true)
  ADMIN_ID=$(grep '^ADMIN_ID=' "$ENV_FILE" | cut -d'=' -f2- || true)
fi
if [ -z "${BOT_TOKEN}" ] || [ -z "${ADMIN_ID}" ]; then
  echo "BOT_TOKEN or ADMIN_ID missing in $ENV_FILE" >&2
  exit 1
fi
CLIENT_LOG=/tmp/client_errors.log
mkdir -p $(dirname "$CLIENT_LOG")
# Ensure file exists
: > "$CLIENT_LOG"

# Use tail -F to follow file
tail -n 0 -F "$CLIENT_LOG" | while read -r line; do
  # send to telegram
  text="[Client error] ${line}"
  curl -sS -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d chat_id=${ADMIN_ID} -d text="$text" >/dev/null 2>&1 || true
done
