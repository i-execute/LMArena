#!/bin/bash
# =============================================================================
# LMArena Bridge - Production Installation Script
# =============================================================================
# One-command installation for LMArena Bridge
# 
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/your-repo/install.sh | bash
#   or
#   bash install.sh
#
# This script will:
#   1. Check system requirements
#   2. Install dependencies (Python, Node.js, cloudflared)
#   3. Clone/download the repository
#   4. Configure the bridge with your credentials
#   5. Start all services
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
INSTALL_DIR="$HOME/LMArenaBridge"
PYTHON_VERSION="3.12"
NODE_VERSION="22"

# =============================================================================
# Helper functions
# =============================================================================

print_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              LMArena Bridge - Production Installer          ║"
    echo "║                                                              ║"
    echo "║  OpenAI-compatible API bridge to LM Arena                    ║"
    echo "║  with Telegram notifications and Cloudflare tunnel           ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_command() {
    command -v "$1" >/dev/null 2>&1
}

# =============================================================================
# System checks
# =============================================================================

check_system() {
    log_info "Checking system requirements..."
    
    # Check OS
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        log_error "This script requires Linux. Detected: $OSTYPE"
        exit 1
    fi
    
    # Check architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" != "x86_64" && "$ARCH" != "aarch64" ]]; then
        log_warn "Architecture $ARCH may not be fully supported"
    fi
    
    # Check disk space (need at least 1GB)
    AVAILABLE=$(df -BG "$HOME" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$AVAILABLE" -lt 1 ]; then
        log_error "Insufficient disk space. Need at least 1GB, have ${AVAILABLE}GB"
        exit 1
    fi
    
    log_success "System check passed"
}

# =============================================================================
# Install dependencies
# =============================================================================

install_python() {
    if check_command python3; then
        CURRENT_PY=$(python3 --version | cut -d' ' -f2 | cut -d'.' -f1,2)
        log_info "Python $CURRENT_PY found"
    else
        log_info "Installing Python $PYTHON_VERSION..."
        sudo apt-get update -qq
        sudo apt-get install -y -qq python${PYTHON_VERSION} python${PYTHON_VERSION}-venv python3-pip
        log_success "Python installed"
    fi
}

install_node() {
    if check_command node; then
        CURRENT_NODE=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
        log_info "Node.js v$CURRENT_NODE found"
    else
        log_info "Installing Node.js $NODE_VERSION..."
        curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | sudo -E bash -
        sudo apt-get install -y -qq nodejs
        log_success "Node.js installed"
    fi
}

install_cloudflared() {
    if check_command cloudflared; then
        log_info "cloudflared found"
    else
        log_info "Installing cloudflared..."
        curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /tmp/cloudflared
        sudo install -o root -g root -m 0755 /tmp/cloudflared /usr/local/bin/cloudflared
        rm /tmp/cloudflared
        log_success "cloudflared installed"
    fi
}

install_git() {
    if check_command git; then
        log_info "git found"
    else
        log_info "Installing git..."
        sudo apt-get install -y -qq git
        log_success "git installed"
    fi
}

# =============================================================================
# Get user configuration
# =============================================================================

get_config() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                    Configuration Setup                       ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Telegram Bot Token
    while true; do
        echo -e "${YELLOW}Enter your Telegram Bot Token:${NC}"
        echo -e "(Get from @BotFather on Telegram)"
        read -r BOT_TOKEN
        if [[ "$BOT_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
            break
        fi
        log_error "Invalid token format. Expected: 123456789:ABCdefGHIjklMNOpqrsTUVwxyz"
    done
    
    # Owner Telegram ID
    while true; do
        echo ""
        echo -e "${YELLOW}Enter your Telegram User ID:${NC}"
        echo -e "(Send /start to @userinfobot to get your ID)"
        read -r OWNER_ID
        if [[ "$OWNER_ID" =~ ^[0-9]+$ ]]; then
            break
        fi
        log_error "Invalid ID. Must be a number."
    done
    
    # GitHub Token (optional)
    echo ""
    echo -e "${YELLOW}Enter GitHub Token (optional, press Enter to skip):${NC}"
    echo -e "(Needed for fetching Camoufox releases)"
    read -r GITHUB_TOKEN
    
    # Session Secret
    SESSION_SECRET=$(openssl rand -hex 32)
    
    # API Key
    API_KEY="sk-lmab-$(uuidgen | tr '[:upper:]' '[:lower:]')"
    
    log_success "Configuration complete"
}

# =============================================================================
# Setup application
# =============================================================================

setup_app() {
    log_info "Setting up application..."
    
    # Create installation directory
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    # Download/copy files
    if [ -d "/home/forget/LMArena" ]; then
        log_info "Copying from existing installation..."
        cp -r /home/forget/LMArena/* "$INSTALL_DIR/" 2>/dev/null || true
        cp -r /home/forget/LMArena/.* "$INSTALL_DIR/" 2>/dev/null || true
    else
        log_info "Downloading latest release..."
        # TODO: Add git clone or download from release
        log_warn "Manual installation required - clone the repository"
    fi
    
    # Create .env file
    cat > "$INSTALL_DIR/WEB/.env" << EOF
BOT_TOKEN=$BOT_TOKEN
ADMIN_ID=$OWNER_ID
SESSION_JWT_SECRET=$SESSION_SECRET
SESSION_TTL_HOURS=24
INITDATA_MAX_AGE_HOURS=24
CORS_ORIGINS=*
PORT=8787
DATA_FILE=./data/config.json
EOF
    
    # Create initial config
    mkdir -p "$INSTALL_DIR/WEB/data"
    cat > "$INSTALL_DIR/WEB/data/config.json" << EOF
{
  "api_keys": [
    {
      "name": "Default Key",
      "key": "$API_KEY",
      "rpm": 60,
      "created": "$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")"
    }
  ],
  "auth_tokens": [],
  "cf_clearance": null,
  "models": [],
  "usage": {}
}
EOF
    
    # Install npm dependencies
    log_info "Installing Node.js dependencies..."
    cd "$INSTALL_DIR/WEB"
    npm install --production
    
    # Setup Python virtual environment
    log_info "Setting up Python environment..."
    cd "$INSTALL_DIR"
    python3 -m venv venv
    source venv/bin/activate
    
    # Install Python dependencies
    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt
    fi
    
    # Make scripts executable
    chmod +x "$INSTALL_DIR/start.sh"
    chmod +x "$INSTALL_DIR/install.sh" 2>/dev/null || true
    
    log_success "Application setup complete"
}

# =============================================================================
# Create systemd services
# =============================================================================

create_services() {
    log_info "Creating systemd services..."
    
    # Web server service
    sudo tee /etc/systemd/system/lmarena-web.service > /dev/null << EOF
[Unit]
Description=LMArena Bridge Web Server
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$INSTALL_DIR/WEB
Environment="PATH=$INSTALL_DIR/venv/bin:/usr/local/bin:/usr/bin:/bin"
Environment="NODE_ENV=production"
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    # Bot log forwarder service
    sudo tee /etc/systemd/system/lmarena-bot.service > /dev/null << EOF
[Unit]
Description=LMArena Bridge Bot Log Forwarder
After=network.target lmarena-web.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart=$INSTALL_DIR/venv/bin/python3 $INSTALL_DIR/BOT/main.py --mode forward --token $BOT_TOKEN --owner $OWNER_ID --logs /tmp/lmarena_logs/web_server.log /tmp/client_errors.log /tmp/auth_times.log
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    # Cloudflared tunnel service
    sudo tee /etc/systemd/system/lmarena-tunnel.service > /dev/null << EOF
[Unit]
Description=LMArena Bridge Cloudflare Tunnel
After=network.target lmarena-web.service

[Service]
Type=simple
User=$USER
ExecStart=/usr/local/bin/cloudflared tunnel --url http://localhost:8787 --no-autoupdate
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd
    sudo systemctl daemon-reload
    
    # Enable services
    sudo systemctl enable lmarena-web.service
    sudo systemctl enable lmarena-bot.service
    sudo systemctl enable lmarena-tunnel.service
    
    log_success "Systemd services created"
}

# =============================================================================
# Start services
# =============================================================================

start_services() {
    log_info "Starting services..."
    
    sudo systemctl start lmarena-web.service
    sleep 3
    
    sudo systemctl start lmarena-bot.service
    sleep 2
    
    sudo systemctl start lmarena-tunnel.service
    sleep 12
    
    # Get tunnel URL
    TUNNEL_URL=$(journalctl -u lmarena-tunnel.service --no-pager -n 50 | grep -oE "https://[a-zA-Z0-9-]+\.trycloudflare\.com" | tail -1)
    
    log_success "All services started"
}

# =============================================================================
# Print summary
# =============================================================================

print_summary() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}              Installation Complete!                          ${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}Access URLs:${NC}"
    if [ -n "$TUNNEL_URL" ]; then
        echo -e "  Web UI (Public):  ${GREEN}$TUNNEL_URL${NC}"
    fi
    echo -e "  Web UI (Local):   ${GREEN}http://localhost:8787${NC}"
    echo -e "  Dashboard:        ${GREEN}http://localhost:8787/dashboard${NC}"
    echo ""
    echo -e "${CYAN}Default API Key:${NC}"
    echo -e "  ${YELLOW}$API_KEY${NC}"
    echo ""
    echo -e "${CYAN}Service Management:${NC}"
    echo -e "  Status:    ${YELLOW}sudo systemctl status lmarena-{web,bot,tunnel}${NC}"
    echo -e "  Restart:   ${YELLOW}sudo systemctl restart lmarena-web${NC}"
    echo -e "  Logs:      ${YELLOW}journalctl -u lmarena-web -f${NC}"
    echo -e "  Stop:      ${YELLOW}sudo systemctl stop lmarena-{web,bot,tunnel}${NC}"
    echo ""
    echo -e "${CYAN}Files:${NC}"
    echo -e "  Install Dir:  $INSTALL_DIR"
    echo -e "  Config:       $INSTALL_DIR/WEB/data/config.json"
    echo -e "  Logs:         /tmp/lmarena_logs/"
    echo ""
    echo -e "${CYAN}Next Steps:${NC}"
    echo -e "  1. Open the Web UI and login with your Telegram"
    echo -e "  2. Add your LMArena auth tokens in the dashboard"
    echo -e "  3. Click 'Refresh tokens & models' to load available models"
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
}

# =============================================================================
# Main
# =============================================================================

main() {
    print_banner
    
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        log_error "Do not run this script as root"
        exit 1
    fi
    
    check_system
    
    # Install dependencies
    log_info "Installing system dependencies..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq curl wget uuid-runtime openssl
    
    install_git
    install_python
    install_node
    install_cloudflared
    
    get_config
    setup_app
    create_services
    start_services
    print_summary
    
    # Send notification to Telegram
    if [ -n "$TUNNEL_URL" ]; then
        curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
            -d chat_id="$OWNER_ID" \
            -d text="LMArena Bridge installed! URL: $TUNNEL_URL" > /dev/null 2>&1 || true
    fi
}

# Run main function
main "$@"
