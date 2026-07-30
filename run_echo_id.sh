#!/usr/bin/env bash
set -euo pipefail
if [ -z "${1-}" ]; then
  echo "Usage: $0 <BOT_TOKEN>"
  exit 2
fi
TOKEN="$1"
exec python3 "$(dirname "$0")/WEB/echo_id.py" "$TOKEN"
