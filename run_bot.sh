#!/usr/bin/env bash
set -euo pipefail
if [ -z "${1-}" ]; then
  echo "Usage: $0 <mode>\nModes: echo, forward"
  exit 2
fi
MODE="$1"
read -p "BOT_TOKEN: " BOT_TOKEN
if [ "$MODE" = "forward" ]; then
  read -p "OWNER_ID: " OWNER_ID
  python3 BOT/main.py --mode forward --token "$BOT_TOKEN" --owner "$OWNER_ID"
else
  python3 BOT/main.py --mode echo --token "$BOT_TOKEN"
fi
