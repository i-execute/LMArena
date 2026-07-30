#!/usr/bin/env bash
# Redeploy helper: stop all active cloudflared sites and launch a new serve for WEB/ with the current files.
# WARNING: This script will attempt to remove site dirs tracked in the deployer sites file.
# It then runs the deployer in foreground. Run interactively to see logs.
set -e
PYTHON=$(python3 -c "import sys; print(sys.executable)")
SITES_FILE="$(python3 - <<'PY'
import tempfile, os
print(os.path.join(tempfile.gettempdir(), 'lmarena_deployer_sites.json'))
PY
)"
if [ -f "$SITES_FILE" ]; then
  echo "Stopping and removing active sites listed in $SITES_FILE..."
  python3 - <<PY
import json, os, shutil
s='''"$SITES_FILE"'''
try:
    sites=json.load(open(s))
except Exception:
    sites={}
for sid,info in list(sites.items()):
    d=info.get('dir')
    if d and os.path.isdir(d):
        print('Removing', d)
        shutil.rmtree(d, ignore_errors=True)
sites.clear()
json.dump(sites, open(s, 'w'), indent=2)
print('Cleared sites file')
PY
else
  echo "No sites file found; nothing to stop."
fi
# Start serving WEB/ directory via cloudflared deployer.
# Run interactively: it will install cloudflared if needed and open a tunnel.
echo "To start a new tunnel with the updated track, run:" 
echo "  python -m DEPLOY.cloudflared_deployer serve WEB --port 8080"
echo "Or run it in background and capture logs:"
echo "  nohup python -m DEPLOY.cloudflared_deployer serve WEB --port 8080 > /tmp/redeploy.log 2>&1 &"

echo "Redeploy script finished." 
