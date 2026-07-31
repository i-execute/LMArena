# LMArena Bridge

OpenAI-compatible API bridge to [LM Arena](https://arena.ai). Access 278+ models through a standard API endpoint with automatic Cloudflare bypass, reCAPTCHA solving, and Telegram notifications.

## Quick Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/i-execute/LMArena/main/install.sh)
```

The installer will:
- Install all dependencies (Python, Node.js, cloudflared)
- Create a dedicated `lmarena` user
- Clone the repository
- Configure your Telegram bot
- Start all services as systemd units

You'll need:
- **Bot Token** from [@BotFather](https://t.me/BotFather)
- **Your Telegram User ID** (send `/start` to [@userinfobot](https://t.me/userinfobot))

## Manual Install

```bash
git clone https://github.com/i-execute/LMArena.git
cd LMArena
sudo bash install.sh
```

## Architecture

```
LMArena/
├── BRIDGE/           # Python bridge (FastAPI) - core API logic
│   ├── main.py       # Main server (~4700 lines)
│   ├── auth.py       # Token management
│   ├── transport.py  # Browser automation (Chrome/Camoufox)
│   ├── recaptcha.py  # reCAPTCHA solving
│   └── anti_detect.py # Anti-detection patches
├── WEB/              # Node.js dashboard
│   ├── server.js     # Express API server
│   ├── App.js        # React frontend
│   └── .env          # Configuration
├── BOT/              # Telegram log forwarder
├── DEPLOY/           # Deployment utilities
└── install.sh        # One-click installer
```

## Services

After installation, three systemd services run automatically:

| Service | Description |
|---------|-------------|
| `lmarena-web` | Node.js dashboard server (port 8787) |
| `lmarena-bot` | Telegram log forwarder |
| `lmarena-tunnel` | Cloudflare tunnel for public access |

## Service Management

```bash
# Check status
sudo -u lmarena XDG_RUNTIME_DIR=/run/user/$(id -u lmarena) systemctl --user status lmarena-web

# View logs
sudo -u lmarena XDG_RUNTIME_DIR=/run/user/$(id -u lmarena) journalctl --user -u lmarena-web -f

# Restart
sudo -u lmarena XDG_RUNTIME_DIR=/run/user/$(id -u lmarena) systemctl --user restart lmarena-web

# Stop all
sudo -u lmarena XDG_RUNTIME_DIR=/run/user/$(id -u lmarena) systemctl --user stop lmarena-{web,bot,tunnel}
```

## Configuration

Edit `/home/lmarena/LMArena/WEB/.env`:

```env
BOT_TOKEN=your_bot_token
ADMIN_ID=your_telegram_id
SESSION_JWT_SECRET=auto_generated
PORT=8787
```

## API Usage

### Chat Completions

```bash
curl -X POST http://localhost:8787/api/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-lmab-your-api-key" \
  -d '{
    "model": "gpt-4",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

### List Models

```bash
curl http://localhost:8000/api/v1/models
```

## Web Dashboard

Access at `http://localhost:8787` or via the Cloudflare tunnel URL.

Features:
- API key management
- Auth token management
- Model list
- Usage statistics
- Telegram login

## Anti-Detection

The bridge includes comprehensive anti-detection measures:
- WebDriver property removal
- Navigator plugin spoofing
- Canvas fingerprint noise
- WebGL vendor spoofing
- Screen resolution spoofing
- Timezone rotation

## Troubleshooting

**Server won't start**
```bash
sudo -u lmarena XDG_RUNTIME_DIR=/run/user/$(id -u lmarena) journalctl --user -u lmarena-web -n 50
```

**No models showing**
- Click "Refresh tokens & models" in the dashboard
- Or restart: `sudo -u lmarena XDG_RUNTIME_DIR=/run/user/$(id -u lmarena) systemctl --user restart lmarena-web`

**Tunnel not working**
- Check cloudflared logs
- Restart: `sudo -u lmarena XDG_RUNTIME_DIR=/run/user/$(id -u lmarena) systemctl --user restart lmarena-tunnel`

## License

GNU General Public License v3.0
