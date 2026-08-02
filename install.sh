#!/bin/bash
set -e

# =============================================================================
# LMArena Bridge - Full Installer
# Installs: Python bridge, Node.js dashboard, Telegram bot, Cloudflare tunnel,
#           Camoufox + Playwright browsers
#
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/i-execute/LMArena/main/install.sh)
# =============================================================================

SOURCE_URL="https://raw.githubusercontent.com/i-execute/LMArena/main/install.sh"

# Bootstrap: if running from /dev/fd (process substitution), copy to temp file and re-exec
if [ ! -f "$0" ] || [[ "$0" == /dev/fd/* ]] || [[ "$0" == /proc/*/fd/* ]]; then
    TMPSCRIPT=$(mktemp /tmp/lmarena-install.XXXXXX.sh)
    curl -fsSL "$SOURCE_URL" -o "$TMPSCRIPT"
    chmod +x "$TMPSCRIPT"
    exec sudo bash "$TMPSCRIPT" "$@"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Run as root: sudo bash install.sh${NC}"
    exit 1
fi

# Config
LMARENA_USER="lmarena"
INSTALL_DIR="/home/$LMARENA_USER/LMArena"
ENV_FILE="$INSTALL_DIR/WEB/.env"
REPO_URL="https://github.com/i-execute/LMArena.git"
BRANCH="main"
SERVICE_PREFIX="lmarena"
LOG_DIR="/tmp/lmarena_logs"
PID_DIR="/tmp/lmarena_pids"

echo -e "${CYAN}=== LMArena Bridge - Full Installer ===${NC}"
echo ""

# Detect package manager
if command -v apt-get &>/dev/null; then
    PKG_UPDATE="apt-get update -qq"
    PKG_INSTALL="apt-get install -qq -y"
elif command -v dnf &>/dev/null; then
    PKG_UPDATE="dnf check-update || true"
    PKG_INSTALL="dnf install -y -q"
elif command -v yum &>/dev/null; then
    PKG_UPDATE="yum check-update || true"
    PKG_INSTALL="yum install -y -q"
elif command -v pacman &>/dev/null; then
    PKG_UPDATE="pacman -Sy --noconfirm"
    PKG_INSTALL="pacman -S --noconfirm --needed"
else
    echo -e "${RED}Unsupported package manager${NC}"
    exit 1
fi

# [1/9] System dependencies
echo -e "${YELLOW}[1/9] Installing system dependencies...${NC}"
$PKG_UPDATE
$PKG_INSTALL python3 python3-pip python3-venv git curl jq

# Playwright system deps (libglib, libnss, etc.)
if command -v apt-get &>/dev/null; then
    $PKG_INSTALL libglib2.0-0 libnss3 libnspr4 libdbus-1-3 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libgbm1 libpango-1.0-0 libcairo2 libasound2 libatspi2.0-0 2>/dev/null || true
fi

# [2/9] Node.js
if ! command -v node &>/dev/null; then
    echo -e "${YELLOW}[2/9] Installing Node.js...${NC}"
    if command -v apt-get &>/dev/null; then
        curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
        apt-get install -y -qq nodejs
    elif command -v dnf &>/dev/null || command -v yum &>/dev/null; then
        curl -fsSL https://rpm.nodesource.com/setup_22.x | bash -
        $PKG_INSTALL nodejs
    else
        echo -e "${RED}Please install Node.js 22+ manually${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}[2/9] Node.js $(node --version) already installed${NC}"
fi
if ! command -v npm &>/dev/null; then
    $PKG_INSTALL npm
fi

# [3/9] cloudflared
if ! command -v cloudflared &>/dev/null; then
    echo -e "${YELLOW}[3/9] Installing cloudflared...${NC}"
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then CF_ARCH="amd64"
    elif [ "$ARCH" = "aarch64" ]; then CF_ARCH="arm64"
    else echo -e "${RED}Unsupported arch: $ARCH${NC}"; exit 1
    fi
    curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}" -o /usr/local/bin/cloudflared
    chmod +x /usr/local/bin/cloudflared
else
    echo -e "${GREEN}[3/9] cloudflared already installed${NC}"
fi

# [4/9] Create user
echo -e "${YELLOW}[4/9] Setting up user...${NC}"
if ! id "$LMARENA_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$LMARENA_USER"
    echo -e "${GREEN}Created user $LMARENA_USER${NC}"
else
    echo -e "${GREEN}User $LMARENA_USER exists${NC}"
fi
loginctl enable-linger "$LMARENA_USER" 2>/dev/null || true

# [5/9] Clone/update repo
echo -e "${YELLOW}[5/9] Setting up repository...${NC}"
if [ -d "$INSTALL_DIR/.git" ]; then
    sudo -u "$LMARENA_USER" bash -c "cd $INSTALL_DIR && git fetch origin $BRANCH && git reset --hard origin/$BRANCH"
else
    sudo -u "$LMARENA_USER" git clone -b "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
fi

# [6/9] Python venv + deps
echo -e "${YELLOW}[6/9] Setting up Python environment...${NC}"
if [ ! -d "$INSTALL_DIR/venv" ]; then
    sudo -u "$LMARENA_USER" python3 -m venv "$INSTALL_DIR/venv"
fi
sudo -u "$LMARENA_USER" "$INSTALL_DIR/venv/bin/pip" install --quiet --upgrade pip

# Install bridge requirements from root requirements.txt
REQ_FILE="$INSTALL_DIR/requirements.txt"
if [ -f "$REQ_FILE" ]; then
    sudo -u "$LMARENA_USER" "$INSTALL_DIR/venv/bin/pip" install --quiet -r "$REQ_FILE"
fi

# Install Playwright chromium browser
echo -e "${YELLOW}Installing Playwright browsers...${NC}"
sudo -u "$LMARENA_USER" "$INSTALL_DIR/venv/bin/python" -m playwright install chromium 2>/dev/null || true

# [7/9] Node.js deps
echo -e "${YELLOW}[7/9] Setting up Node.js dependencies...${NC}"
sudo -u "$LMARENA_USER" bash -c "cd $INSTALL_DIR/WEB && npm install --production"

# Create config.json symlink (bridge expects it in repo root)
sudo -u "$LMARENA_USER" ln -sf WEB/data/config.json "$INSTALL_DIR/config.json"

# [8/9] Configuration
echo -e "${YELLOW}[8/9] Configuration...${NC}"
echo ""
echo -e "${CYAN}=== Telegram Configuration ===${NC}"
echo ""

# Bot token
while true; do
    echo -e "${YELLOW}Enter your Telegram Bot Token:${NC}"
    read -r BOT_TOKEN
    if [ -z "$BOT_TOKEN" ]; then
        echo -e "${RED}No token provided${NC}"
        exit 1
    fi
    ME_JSON=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getMe")
    OK=$(echo "$ME_JSON" | jq -r '.ok')
    if [ "$OK" = "true" ]; then
        USERNAME=$(echo "$ME_JSON" | jq -r '.result.username')
        echo -e "${GREEN}Connected to @$USERNAME${NC}"
        break
    else
        echo -e "${RED}Invalid token, try again${NC}"
    fi
done

# Owner ID
echo ""
echo -e "${YELLOW}>> Send ANY message to @$USERNAME in DM now.${NC}"
echo -e "${YELLOW}>> The bot will reply with your numeric user ID.${NC}"
echo ""
while true; do
    echo -e "${YELLOW}Enter your Telegram User ID:${NC}"
    read -r OWNER_ID
    if [[ "$OWNER_ID" =~ ^[0-9]+$ ]]; then
        break
    fi
    echo -e "${RED}Invalid ID, must be a number${NC}"
done

# Session secret
SESSION_SECRET=$(openssl rand -hex 32)

# Write .env
sudo -u "$LMARENA_USER" bash -c "cat > '$ENV_FILE'" <<EOF
BOT_TOKEN=$BOT_TOKEN
ADMIN_ID=$OWNER_ID
SESSION_JWT_SECRET=$SESSION_SECRET
SESSION_TTL_HOURS=24
INITDATA_MAX_AGE_HOURS=24
CORS_ORIGINS=*
PORT=8787
DATA_FILE=./data/config.json
EOF
chmod 600 "$ENV_FILE"

# Create initial config
sudo -u "$LMARENA_USER" mkdir -p "$INSTALL_DIR/WEB/data"
API_KEY="sk-lmab-$(cat /proc/sys/kernel/random/uuid)"
sudo -u "$LMARENA_USER" bash -c "cat > '$INSTALL_DIR/WEB/data/config.json'" <<EOF
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

# Re-create symlink after config write
sudo -u "$LMARENA_USER" ln -sf WEB/data/config.json "$INSTALL_DIR/config.json"

# Create log/pid dirs
sudo -u "$LMARENA_USER" mkdir -p "$LOG_DIR" "$PID_DIR"
chmod 777 "$LOG_DIR" "$PID_DIR"

# [9/9] Systemd services
echo -e "${YELLOW}[9/9] Installing systemd services...${NC}"
UNIT_DIR="/home/$LMARENA_USER/.config/systemd/user"
LMARENA_UID=$(id -u "$LMARENA_USER")
XDG_RUNTIME_DIR="/run/user/$LMARENA_UID"

sudo -u "$LMARENA_USER" mkdir -p "$UNIT_DIR"

# Web server (Node.js dashboard on port 8787)
cat > "$UNIT_DIR/${SERVICE_PREFIX}-web.service" <<EOF
[Unit]
Description=LMArena Bridge Web Dashboard
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

# Python bridge (FastAPI on port 6767)
cat > "$UNIT_DIR/${SERVICE_PREFIX}-bridge.service" <<EOF
[Unit]
Description=LMArena Python Bridge (FastAPI)
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart=$INSTALL_DIR/venv/bin/python3 -m BRIDGE.main
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF

# Bot log forwarder
cat > "$UNIT_DIR/${SERVICE_PREFIX}-bot.service" <<EOF
[Unit]
Description=LMArena Bridge Telegram Log Forwarder
After=network.target ${SERVICE_PREFIX}-web.service

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart=$INSTALL_DIR/venv/bin/python3 $INSTALL_DIR/BOT/main.py --mode forward --token $BOT_TOKEN --owner $OWNER_ID --logs $LOG_DIR/web_server.log /tmp/client_errors.log /tmp/auth_times.log
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF

# Cloudflare tunnel
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

# Start all services
echo -e "${YELLOW}Starting all services...${NC}"
sudo -u "$LMARENA_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user enable --now "${SERVICE_PREFIX}-web"
sleep 2
sudo -u "$LMARENA_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user enable --now "${SERVICE_PREFIX}-bridge"
sleep 2
sudo -u "$LMARENA_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user enable --now "${SERVICE_PREFIX}-bot"
sudo -u "$LMARENA_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user enable --now "${SERVICE_PREFIX}-tunnel"

echo ""
echo -e "${GREEN}=== Installation Complete ===${NC}"
echo ""
echo -e "Default API Key: ${YELLOW}$API_KEY${NC}"
echo ""
echo -e "${CYAN}Services:${NC}"
echo "  lmarena-web     — Node.js dashboard (port 8787)"
echo "  lmarena-bridge  — Python FastAPI bridge (port 6767)"
echo "  lmarena-bot     — Telegram log forwarder"
echo "  lmarena-tunnel  — Cloudflare tunnel"
echo ""
echo -e "${CYAN}Service Management:${NC}"
echo "  status  : sudo -u $LMARENA_USER XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR systemctl --user status ${SERVICE_PREFIX}-web"
echo "  logs    : sudo -u $LMARENA_USER XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR journalctl --user -u ${SERVICE_PREFIX}-web -f"
echo "  restart : sudo -u $LMARENA_USER XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR systemctl --user restart ${SERVICE_PREFIX}-web"
echo "  stop    : sudo -u $LMARENA_USER XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR systemctl --user stop ${SERVICE_PREFIX}-{web,bridge,bot,tunnel}"
echo ""
echo -e "Web UI: ${GREEN}http://localhost:8787${NC}"
echo "Tunnel URL: check logs with the command above"
