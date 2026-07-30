#!/usr/bin/env python3
"""Simple log forwarder: tails selected log files and forwards new lines to OWNER via Telegram bot.
Usage: TELEGRAM_BOT_TOKEN=... OWNER_ID=... python3 telegram_log_bot.py
"""
import os
import sys
import time
from pathlib import Path
import urllib.request
import urllib.parse
import json

OBHOD_DIR = Path(__file__).resolve().parents[1] / 'OBHOD' / 'BOT'
LOG_FILES = [
    '/tmp/web_server.log',
    '/tmp/client_errors.log',
    '/tmp/auth_times.log',
    str(OBHOD_DIR / 'obhod.log'),
]

TOKEN = os.environ.get('TELEGRAM_BOT_TOKEN') or os.environ.get('BOT_TOKEN')
OWNER = os.environ.get('OWNER_ID')

if not TOKEN or not OWNER:
    print('Usage: TELEGRAM_BOT_TOKEN=<token> OWNER_ID=<id> python3 telegram_log_bot.py')
    sys.exit(2)

OWNER = int(OWNER)

TELEGRAM_URL = f'https://api.telegram.org/bot{TOKEN}/sendMessage'


def send_message(chat_id, text):
    data = {'chat_id': str(chat_id), 'text': text}
    data_b = json.dumps(data).encode('utf-8')
    req = urllib.request.Request(TELEGRAM_URL, data=data_b, headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            r.read()
    except Exception as e:
        print('send_message failed:', e)


def main():
    positions = {}
    for f in LOG_FILES:
        try:
            positions[f] = os.path.getsize(f)
        except Exception:
            positions[f] = 0

    # Startup message
    try:
        send_message(OWNER, f"Log forwarder started. Watching: {', '.join(LOG_FILES)}")
    except Exception:
        pass

    try:
        while True:
            messages = []
            for f in LOG_FILES:
                try:
                    cur = os.path.getsize(f)
                    last = positions.get(f, 0)
                    if cur > last:
                        with open(f, 'r', errors='ignore') as fh:
                            fh.seek(last)
                            add = fh.read()
                            if add:
                                messages.append((f, add.strip()))
                        positions[f] = cur
                except FileNotFoundError:
                    continue
                except Exception:
                    continue

            for fname, text in messages:
                if not text:
                    continue
                header = f"Logs update: {os.path.basename(fname)}\n"
                payload = header + text
                while payload:
                    chunk = payload[:3000]
                    payload = payload[3000:]
                    try:
                        send_message(OWNER, chunk)
                    except Exception as e:
                        print('Failed to send chunk:', e)
                        break

            time.sleep(5)
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    main()
