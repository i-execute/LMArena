#!/bin/bash
set -e

# LMArena Bridge Installer
# ========================
# Installs the LMArena bridge on a fresh Linux VPS.
# Asks for: Telegram user ID, bot token, GitHub token (optional).
# Sets up a Python venv, installs all deps, creates a systemd service.

if [ "$(id -u)" -ne 0 ]; then
    echo "run as root (sudo bash Setuper.sh)"
    exit 1
fi

LMARENA_USER="lmarena"
INSTALL_DIR="/home/$LMARENA_USER"
REPO_URL="https://github.com/i-execute/LMArena.git"
SERVICE_NAME="lmarena-bridge"
VENV_DIR="$INSTALL_DIR/venv"
ENV_FILE="$INSTALL_DIR/.env"
CONFIG_FILE="$INSTALL_DIR/config.json"

echo ""
echo "=========================================="
echo "  LMArena Bridge Installer"
echo "=========================================="
echo ""

# ─── System packages ─────────────────────────────────────────────────

echo "[1/7] Installing system packages..."
apt install -qq -y python3 python3-pip python3-venv git curl wget jq

# ─── User ─────────────────────────────────────────────────────────────

echo "[2/7] Creating user '$LMARENA_USER'..."
if ! id "$LMARENA_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$LMARENA_USER"
fi
loginctl enable-linger "$LMARENA_USER" || true

# ─── Clone / update ────────────────────────────────────────────────────

echo "[3/7] Cloning repository..."
if [ -d "$INSTALL_DIR/LMArena/.git" ]; then
    sudo -u "$LMARENA_USER" bash -c "cd $INSTALL_DIR/LMArena && git fetch origin main && git reset --hard origin/main"
else
    sudo -u "$LMARENA_USER" git clone "$REPO_URL" "$INSTALL_DIR/LMArena"
fi

LMARENA_DIR="$INSTALL_DIR/LMArena"

# ─── venv + deps ───────────────────────────────────────────────────────

echo "[4/7] Creating Python venv and installing dependencies..."
sudo -u "$LMARENA_USER" python3 -m venv "$VENV_DIR"
sudo -u "$LMARENA_USER" "$VENV_DIR/bin/pip" install --quiet --upgrade pip

# Core deps
sudo -u "$LMARENA_USER" "$VENV_DIR/bin/pip" install --quiet \
    fastapi uvicorn camoufox playwright httpx cloudscraper python-multipart

# Playwright browser
echo "[4a/7] Installing Playwright Chromium..."
sudo -u "$LMARENA_USER" "$VENV_DIR/bin/python" -m playwright install chromium --with-deps 2>/dev/null || true

# ─── Interactive setup ────────────────────────────────────────────────

echo ""
echo "[5/7] Configuration"
echo "=========================================="
echo ""

# Bot Token (required)
read -rp "Telegram Bot Token (from @BotFather): " BOT_TOKEN < /dev/tty
if [ -z "$BOT_TOKEN" ]; then
    echo "Bot token is required."
    exit 1
fi

# Validate token
ME_JSON=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getMe")
OK=$(echo "$ME_JSON" | jq -r '.ok')
if [ "$OK" != "true" ]; then
    echo "Invalid bot token."
    exit 1
fi
BOT_USERNAME=$(echo "$ME_JSON" | jq -r '.result.username')
echo "✅ Connected to @$BOT_USERNAME"

# User ID (required)
echo ""
echo "Send ANY message to @$BOT_USERNAME in Telegram to learn your numeric user ID."
echo "You can find it via other bots too (e.g. @userinfobot, @getmyid_bot)."
echo ""
read -rp "Your Telegram User ID: " TG_USER_ID < /dev/tty
if ! [[ "$TG_USER_ID" =~ ^[0-9]+$ ]]; then
    echo "Invalid user ID. Must be numeric."
    exit 1
fi
echo "✅ User ID: $TG_USER_ID"

# GitHub Token (optional)
echo ""
read -rp "GitHub Token (optional, raises API rate limit for cloudflared installs): " GH_TOKEN < /dev/tty

# ─── Write .env ───────────────────────────────────────────────────────

echo ""
echo "[6/7] Writing configuration..."
cat > "$ENV_FILE" <<EOF
BOT_TOKEN=$BOT_TOKEN
TG_USER_ID=$TG_USER_ID
GH_TOKEN=${GH_TOKEN:-}
EOF
chown "$LMARENA_USER:$LMARENA_USER" "$ENV_FILE"
chmod 600 "$ENV_FILE"

# ─── Config.json ──────────────────────────────────────────────────────

if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" <<EOF
{
    "password": "admin",
    "auth_token": "",
    "auth_tokens": [],
    "cf_clearance": "",
    "api_keys": [
        {
            "name": "Default Key",
            "key": "sk-lmab-$(head -c 8 /dev/urandom | xxd -p)-$(head -c 4 /dev/urandom | xxd -p)-$(head -c 4 /dev/urandom | xxd -p)-$(head -c 4 /dev/urandom | xxd -p)-$(head -c 12 /dev/urandom | xxd -p)",
            "rpm": 60,
            "created": $(date +%s)
        }
    ],
    "usage_stats": {},
    "prune_invalid_tokens": false,
    "persist_arena_auth_cookie": true,
    "camoufox_proxy_window_mode": "hide",
    "camoufox_fetch_window_mode": "hide",
    "chrome_fetch_window_mode": "hide"
}
EOF
    chown "$LMARENA_USER:$LMARENA_USER" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    echo "✅ config.json created with generated API key"
else
    echo "✅ config.json already exists, skipping"
fi

# Show API key
API_KEY=$(jq -r '.api_keys[0].key' "$CONFIG_FILE" 2>/dev/null)
if [ -n "$API_KEY" ]; then
    echo "   API Key: $API_KEY"
fi

# ─── systemd service ─────────────────────────────────────────────────

echo "[7/7] Setting up systemd service..."
LMARENA_UID=$(id -u "$LMARENA_USER")
export XDG_RUNTIME_DIR="/run/user/$LMARENA_UID"

UNIT_DIR="/home/$LMARENA_USER/.config/systemd/user"
sudo -u "$LMARENA_USER" mkdir -p "$UNIT_DIR"

cat > "$UNIT_DIR/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=LMArena Bridge

[Service]
WorkingDirectory=$LMARENA_DIR
EnvironmentFile=$ENV_FILE
ExecStart=$VENV_DIR/bin/python -m BRIDGE.main
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

chown -R "$LMARENA_USER:$LMARENA_USER" "$UNIT_DIR"
sudo -u "$LMARENA_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user daemon-reload
sudo -u "$LMARENA_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user enable --now "$SERVICE_NAME"

# ─── Done ────────────────────────────────────────────────────────────

echo ""
echo "=========================================="
echo "  ✅ LMArena Bridge installed!"
echo "=========================================="
echo ""
echo "  API Base URL: http://localhost:6767/api/v1"
echo "  Dashboard:    http://localhost:6767/dashboard"
echo "  Login:        http://localhost:6767/login"
echo ""
echo "  Status:  sudo -u $LMARENA_USER XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR systemctl --user status $SERVICE_NAME"
echo "  Logs:    sudo -u $LMARENA_USER XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR journalctl --user -u $SERVICE_NAME -f"
echo "  Restart: sudo -u $LMARENA_USER XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR systemctl --user restart $SERVICE_NAME"
echo ""
