#!/usr/bin/env python3
"""Simple log forwarder: tails selected log files and forwards new lines to OWNER via Telegram bot.
Usage: TELEGRAM_BOT_TOKEN=... OWNER_ID=... python3 telegram_log_bot.py
"""
import os
import sys
import time
import asyncio
from pathlib import Path

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

# Use OBHOD BotAPI if available, else fallback to simple HTTP sender
try:
    from OBHOD.BOT.core import BotAPI
    use_botapi = True
except Exception:
    use_botapi = False

import aiohttp

async def send_message_simple(token, chat_id, text):
    url = f'https://api.telegram.org/bot{token}/sendMessage'
    async with aiohttp.ClientSession() as s:
        await s.post(url, json={'chat_id': chat_id, 'text': text})

async def forwarder():
    if use_botapi:
        api = BotAPI(TOKEN)
        await api.start()
        send = api.send_message
    else:
        async def send(chat_id, text, **kw):
            await send_message_simple(TOKEN, chat_id, text)
        send = send

    # Track file positions
    positions = {}
    for f in LOG_FILES:
        try:
            positions[f] = os.path.getsize(f)
        except Exception:
            positions[f] = 0

    # Send startup message
    try:
        await (send(OWNER, f"Log forwarder started. Watching: {', '.join(LOG_FILES)}"))
    except Exception:
        pass

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

        # Send aggregated messages, but limit size to 3000 chars per message
        for fname, text in messages:
            if not text:
                continue
            header = f"Logs update: {os.path.basename(fname)}\n"
            payload = header + text
            # split into chunks
            while payload:
                chunk = payload[:3000]
                payload = payload[3000:]
                try:
                    await (send(OWNER, f"{chunk}"))
                except Exception as e:
                    # swallow errors but log
                    print('Failed to send log chunk:', e)
                    break
        await asyncio.sleep(5)

if __name__ == '__main__':
    try:
        asyncio.run(forwarder())
    except KeyboardInterrupt:
        pass
