"""
Cloudflared Deployer for LMArena
=================================
Installs cloudflared, opens a tunnel to the LMArena server,
and can serve JSX/HTML/JS files through temporary trycloudflare.com URLs.

Usage:
    python -m DEPLOY.cloudflared_deployer              # tunnel to LMArena server
    python -m DEPLOY.cloudflared_deployer --file app.js  # deploy a JSX/JS/HTML file
    python -m DEPLOY.cloudflared_deployer --install       # just install cloudflared
"""

import asyncio
import json
import logging
import os
import platform
import shutil
import stat
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("cloudflared_deployer")

CF_REPO = "cloudflare/cloudflared"
CF_BINARY_DIR = os.path.join(tempfile.gettempdir(), "lmarena_cf")
CF_BINARY = os.path.join(CF_BINARY_DIR, "cloudflared")
VERSIONS_PER_PAGE = 5


def _arch():
    m = platform.machine().lower()
    if "arm" in m or "aarch64" in m:
        return "arm64"
    return "amd64"


def _escape(text):
    if not text:
        return ""
    return str(text).replace("&", "&").replace("<", "<").replace(">", ">")


# ─── cloudflared installation ─────────────────────────────────────────

def cf_installed():
    return os.path.isfile(CF_BINARY) and os.access(CF_BINARY, os.X_OK)


def cf_version():
    if not cf_installed():
        return None
    try:
        r = subprocess.run([CF_BINARY, "--version"], capture_output=True, text=True, timeout=10)
        return r.stdout.strip().split("\n")[0]
    except Exception:
        return "unknown"


async def _curl_json(url, headers=None, timeout=15):
    cmd = ["curl", "-sL", "--max-time", str(timeout)]
    if headers:
        for h in headers:
            cmd += ["-H", h]
    cmd.append(url)
    p = await asyncio.create_subprocess_exec(
        *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
    )
    out, _ = await p.communicate()
    if p.returncode != 0:
        return None
    try:
        return json.loads(out.decode())
    except Exception:
        return None


async def fetch_releases(gh_token=""):
    headers = []
    if gh_token:
        headers.append(f"Authorization: Bearer {gh_token}")
    return await _curl_json(
        f"https://api.github.com/repos/{CF_REPO}/releases",
        headers=headers or None,
    ) or []


async def install_cloudflared(tag="latest", gh_token=""):
    """Download and install cloudflared binary."""
    os.makedirs(CF_BINARY_DIR, exist_ok=True)

    if tag == "latest":
        releases = await fetch_releases(gh_token)
        if not releases:
            return False, "Failed to fetch releases from GitHub"
        tag = releases[0].get("tag_name", "")
        if not tag:
            return False, "No tag_name in latest release"
    else:
        data = await _curl_json(
            f"https://api.github.com/repos/{CF_REPO}/releases/tags/{tag}",
            headers=[f"Authorization: Bearer {gh_token}"] if gh_token else None,
        )
        if not data:
            return False, f"GitHub API request failed for tag {tag}"

    arch = _arch()
    asset_name = f"cloudflared-linux-{arch}"

    # Find the asset
    if "assets" in data:
        assets = data["assets"]
    else:
        releases = await fetch_releases(gh_token)
        assets = []
        for r in releases:
            if r.get("tag_name") == tag:
                assets = r.get("assets", [])
                break

    download_url = None
    for asset in assets:
        if asset.get("name") == asset_name:
            download_url = asset["browser_download_url"]
            break

    if not download_url:
        return False, f"No '{asset_name}' binary found in {tag} assets"

    logger.info(f"Downloading cloudflared {tag} ({arch})...")
    p = await asyncio.create_subprocess_exec(
        "wget", "-q", "--max-redirect=15", "-O", CF_BINARY, download_url,
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
    )
    await asyncio.wait_for(p.communicate(), timeout=300)

    size = os.path.getsize(CF_BINARY) if os.path.isfile(CF_BINARY) else 0
    if p.returncode != 0 or size < 100_000:
        return False, f"Download failed (size={size})"

    os.chmod(CF_BINARY, os.stat(CF_BINARY).st_mode | stat.S_IEXEC)
    logger.info(f"✅ cloudflared {tag} installed at {CF_BINARY}")
    return True, tag


# ─── Tunnel management ────────────────────────────────────────────────

_active_tunnels = {}


def start_tunnel(port, timeout=30):
    """Start a cloudflared tunnel to a local port. Returns the trycloudflare URL or None."""
    if not cf_installed():
        logger.error("cloudflared not installed. Run with --install first.")
        return None

    holder = []

    def _run():
        try:
            proc = subprocess.Popen(
                [CF_BINARY, "tunnel", "--url", f"http://localhost:{port}", "--no-autoupdate"],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            )
            holder.append(proc)
            for line in proc.stdout:
                if "trycloudflare.com" in line:
                    for part in line.split():
                        if part.startswith("https://") and "trycloudflare.com" in part:
                            holder.insert(0, part.strip())
                            return
        except Exception as e:
            logger.error(f"Tunnel error: {e}")

    t = threading.Thread(target=_run, daemon=True)
    t.start()

    for _ in range(timeout):
        time.sleep(1)
        if holder and isinstance(holder[0], str):
            url = holder[0]
            _active_tunnels[port] = {"url": url, "proc": holder[-1] if len(holder) > 1 else None}
            logger.info(f"🌍 Tunnel: {url}")
            return url

    logger.error(f"Failed to get tunnel URL in {timeout}s")
    return None


def stop_tunnel(port):
    info = _active_tunnels.pop(port, None)
    if info and info.get("proc"):
        try:
            info["proc"].terminate()
        except Exception:
            pass


def stop_all_tunnels():
    for port in list(_active_tunnels.keys()):
        stop_tunnel(port)


# ─── JSX/HTML/JS file serving ────────────────────────────────────────

def build_html_from_jsx(js_path, filename):
    """Wrap a JSX/JS file in a full HTML page with React + Babel CDN."""
    with open(js_path, "r", encoding="utf-8", errors="replace") as f:
        js_code = f.read()
    return f"""<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1.0"/>
<title>{_escape(filename)}</title>
<script src="https://telegram.org/js/telegram-web-app.js"></script>
<script src="https://unpkg.com/react@18/umd/react.development.js"></script>
<script src="https://unpkg.com/react-dom@18/umd/react-dom.development.js"></script>
<script src="https://unpkg.com/@babel/standalone/babel.min.js"></script>
</head>
<body>
<div id="root"></div>
<script type="text/babel">
{js_code}
const domNode = document.getElementById('root');
const root = ReactDOM.createRoot(domNode);
if (typeof App !== 'undefined') {{
  root.render(React.createElement(App));
}}
</script>
</body>
</html>"""


def serve_file(filepath, tunnel=True):
    """Serve a JS/JSX/HTML file through a cloudflared tunnel.
    Returns (url, http_proc, port) or (None, None, None) on failure.
    """
    ext = filepath.rsplit(".", 1)[-1].lower()
    if ext not in ("js", "jsx", "html"):
        logger.error(f"File must be .js, .jsx or .html, got .{ext}")
        return None, None, None

    # Create temp dir for the site
    site_dir = tempfile.mkdtemp(prefix="lmarena_deploy_")
    filename = os.path.basename(filepath)

    if ext in ("js", "jsx"):
        html = build_html_from_jsx(filepath, filename)
        with open(os.path.join(site_dir, "index.html"), "w", encoding="utf-8") as f:
            f.write(html)
    else:
        shutil.copy2(filepath, os.path.join(site_dir, "index.html"))

    # Start HTTP server
    import socket
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.bind(("0.0.0.0", 0))
    port = sock.getsockname()[1]
    sock.close()

    http_proc = subprocess.Popen(
        [sys.executable, "-m", "http.server", str(port), "--directory", site_dir],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    time.sleep(1)

    if not tunnel:
        return f"http://localhost:{port}", http_proc, port

    # Start cloudflared tunnel
    url = start_tunnel(port)
    if not url:
        http_proc.terminate()
        shutil.rmtree(site_dir, ignore_errors=True)
        return None, None, None

    return url, http_proc, port


# ─── CLI ──────────────────────────────────────────────────────────────

async def main():
    import argparse
    parser = argparse.ArgumentParser(description="LMArena Cloudflared Deployer")
    parser.add_argument("--install", action="store_true", help="Install/update cloudflared")
    parser.add_argument("--file", type=str, help="Deploy a .js/.jsx/.html file")
    parser.add_argument("--port", type=int, default=None, help="Tunnel to a specific local port")
    parser.add_argument("--gh-token", type=str, default="", help="GitHub token for API rate limits")
    parser.add_argument("--version", type=str, default="latest", help="cloudflared version to install")
    args = parser.parse_args()

    if args.install:
        ok, result = await install_cloudflared(args.version, args.gh_token)
        if ok:
            print(f"✅ cloudflared {result} installed")
        else:
            print(f"❌ Install failed: {result}")
        return

    if not cf_installed():
        print("cloudflared not installed. Installing...")
        ok, result = await install_cloudflared("latest", args.gh_token)
        if not ok:
            print(f"❌ {result}")
            return

    if args.file:
        if not os.path.isfile(args.file):
            print(f"File not found: {args.file}")
            return
        print(f"Deploying {args.file}...")
        url, http_proc, port = serve_file(args.file)
        if url:
            print(f"✅ Deployed: {url}")
            try:
                while True:
                    time.sleep(1)
            except KeyboardInterrupt:
                print("\nStopping...")
                http_proc.terminate()
                stop_tunnel(port)
        return

    # Default: tunnel to LMArena server port
    # Try to read port from configurator
    try:
        sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        from BRIDGE.configurator import resolve_port
        port = args.port or resolve_port()
    except Exception:
        port = args.port or 6767

    print(f"Starting tunnel to localhost:{port}...")
    url = start_tunnel(port)
    if url:
        print(f"✅ Tunnel active: {url}")
        print(f"   LMArena API: {url}/api/v1")
        print(f"   Dashboard:   {url}/dashboard")
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            print("\nStopping tunnel...")
            stop_tunnel(port)
    else:
        print("❌ Failed to establish tunnel")


if __name__ == "__main__":
    asyncio.run(main())
