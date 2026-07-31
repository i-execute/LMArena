#!/bin/bash
set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "run as root (sudo bash install.sh)"
    exit 1
fi

LMARENA_USER="lmarena"
INSTALL_DIR="/home/$LMARENA_USER/LMArena"
ENV_FILE="$INSTALL_DIR/WEB/.env"
REPO_URL="https://github.com/i-execute/LMArena.git"
BRANCH="main"
SERVICE_PREFIX="lmarena"

echo "=== LMArena Bridge Installer ==="
echo ""

# Install dependencies
apt install -qq -y python3 python3-pip python3-venv nodejs npm git curl jq

# Install cloudflared
if ! command -v cloudflared &>/dev/null; then
    echo "Installing cloudflared..."
    curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
    chmod +x /usr/local/bin/cloudflared
fi

# Create user
if ! id "$LMARENA_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$LMARENA_USER"
fi
loginctl enable-linger "$LMARENA_USER" || true

# Clone/update repo
if [ -d "$INSTALL_DIR/.git" ]; then
    sudo -u "$LMARENA_USER" bash -c "cd $INSTALL_DIR && git fetch origin $BRANCH && git reset --hard origin/$BRANCH"
else
    sudo -u "$LMARENA_USER" git clone -b "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
fi

# Setup Python venv
sudo -u "$LMARENA_USER" python3 -m venv "$INSTALL_DIR/venv"
sudo -u "$LMARENA_USER" "$INSTALL_DIR/venv/bin/pip" install --quiet --upgrade pip
if [ -f "$INSTALL_DIR/requirements.txt" ]; then
    sudo -u "$LMARENA_USER" "$INSTALL_DIR/venv/bin/pip" install --quiet -r "$INSTALL_DIR/requirements.txt"
fi

# Setup Node.js dependencies
sudo -u "$LMARENA_USER" bash -c "cd $INSTALL_DIR/WEB && npm install --production"

# Create log directories
sudo -u "$LMARENA_USER" mkdir -p /tmp/lmarena_logs /tmp/lmarena_pids

# Systemd units
UNIT_DIR="/home/$LMARENA_USER/.config/systemd/user"
LMARENA_UID=$(id -u "$LMARENA_USER")
export XDG_RUNTIME_DIR="/run/user/$LMARENA_UID"

install_units() {
    sudo -u "$LMARENA_USER" mkdir -p "$UNIT_DIR"

    # Web server
    cat > "$UNIT_DIR/${SERVICE_PREFIX}-web.service" <<EOF
[Unit]
Description=LMArena Bridge Web Server
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR/WEB
Environment="PATH=$INSTALL_DIR/venv/bin:/usr/local/bin:/usr/bin:/bin"
Environment="NODE_ENV=production"
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF

    # Bot log forwarder
    cat > "$UNIT_DIR/${SERVICE_PREFIX}-bot.service" <<EOF
[Unit]
Description=LMArena Bridge Bot Log Forwarder
After=network.target ${SERVICE_PREFIX}-web.service

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart=$INSTALL_DIR/venv/bin/python3 $INSTALL_DIR/BOT/main.py --mode forward --logs /tmp/lmarena_logs/web_server.log /tmp/client_errors.log /tmp/auth_times.log
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF

    # Cloudflared tunnel
    cat > "$UNIT_DIR/${SERVICE_PREFIX}-tunnel.service" <<EOF
[Unit]
Description=LMArena Bridge Cloudflare Tunnel
After=network.target ${SERVICE_PREFIX}-web.service

[Service]
Type=simple
ExecStart=/usr/local/bin/cloudflared tunnel --url http://localhost:8787 --no-autoupdate
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF

    chown -R "$LMARENA_USER:$LMARENA_USER" "$UNIT_DIR"
    sudo -u "$LMARENA_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user daemon-reload
}

if [ ! -f "$ENV_FILE" ]; then
    echo ""
    echo "=== Configuration ==="
    echo ""

    # Bot token
    while true; do
        read -rp "BOT_TOKEN: " BOT_TOKEN < /dev/tty
        if [ -z "$BOT_TOKEN" ]; then
            echo "no token provided"
            exit 1
        fi
        ME_JSON=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getMe")
        OK=$(echo "$ME_JSON" | jq -r '.ok')
        if [ "$OK" = "true" ]; then
            USERNAME=$(echo "$ME_JSON" | jq -r '.result.username')
            echo "✅ Connected to @$USERNAME"
            break
        else
            echo "❌ Invalid token, try again"
        fi
    done

    # Owner ID
    echo ""
    echo ">> Send ANY message to @$USERNAME in DM now."
    echo ">> The bot will reply with your numeric user ID."
    echo ""

    while true; do
        read -rp "OWNER_ID: " OWNER_ID < /dev/tty
        if [[ "$OWNER_ID" =~ ^[0-9]+$ ]]; then
            break
        fi
        echo "❌ Invalid ID, must be a number"
    done

    # GitHub token (optional)
    echo ""
    read -rp "GITHUB_TOKEN (optional, press Enter to skip): " GITHUB_TOKEN < /dev/tty

    # Session secret
    SESSION_SECRET=$(openssl rand -hex 32)

    # Write .env
    cat > "$ENV_FILE" <<EOF
BOT_TOKEN=$BOT_TOKEN
ADMIN_ID=$OWNER_ID
SESSION_JWT_SECRET=$SESSION_SECRET
SESSION_TTL_HOURS=24
INITDATA_MAX_AGE_HOURS=24
CORS_ORIGINS=*
PORT=8787
DATA_FILE=./data/config.json
EOF
    chown "$LMARENA_USER:$LMARENA_USER" "$ENV_FILE"
    chmod 600 "$ENV_FILE"

    # Create initial config
    sudo -u "$LMARENA_USER" mkdir -p "$INSTALL_DIR/WEB/data"
    API_KEY="sk-lmab-$(cat /proc/sys/kernel/random/uuid)"
    sudo -u "$LMARENA_USER" bash -c "cat > $INSTALL_DIR/WEB/data/config.json" <<EOF
{
  "api_keys": [
    {
      "name": "Default Key",
      "key": "$API_KEY",
      "rpm": 60,
      "created": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
    }
  ],
  "auth_tokens": [],
  "cf_clearance": null,
  "models": [],
  "usage": {}
}
EOF

    install_units
    sudo -u "$LMARENA_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user enable --now "${SERVICE_PREFIX}-web"
    sleep 3
    sudo -u "$LMARENA_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user enable --now "${SERVICE_PREFIX}-bot"
    sudo -u "$LMARENA_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user enable --now "${SERVICE_PREFIX}-tunnel"

    echo ""
    echo "✅ Installation complete!"
    echo ""
    echo "Default API Key: $API_KEY"
    echo ""
else
    install_units
    sudo -u "$LMARENA_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user enable --now "${SERVICE_PREFIX}-web"
    sudo -u "$LMARENA_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user enable --now "${SERVICE_PREFIX}-bot"
    sudo -u "$LMARENA_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user enable --now "${SERVICE_PREFIX}-tunnel"
fi

echo ""
echo ">> Service management:"
echo "   status  : sudo -u $LMARENA_USER XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR systemctl --user status ${SERVICE_PREFIX}-web"
echo "   logs    : sudo -u $LMARENA_USER XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR journalctl --user -u ${SERVICE_PREFIX}-web -f"
echo "   restart : sudo -u $LMARENA_USER XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR systemctl --user restart ${SERVICE_PREFIX}-web"
echo ""
echo ">> Web UI will be available at the cloudflared tunnel URL (check logs)."
echo "   Local: http://localhost:8787"
