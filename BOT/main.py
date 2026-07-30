#!/usr/bin/env python3
"""Minimal Telegram bot for echo mode and log forwarding.
Usage:
  python3 BOT/main.py --mode echo --token <BOT_TOKEN>
  python3 BOT/main.py --mode forward --token <BOT_TOKEN> --owner <OWNER_ID>

This implements long-poll getUpdates (no external deps) and two modes:
 - echo: replies to incoming messages with the sender id
 - forward: tails logs and forwards new lines to owner chat

Note: This is intentionally small and avoids adding async/http libs.
"""
import sys
import time
import json
import argparse
import urllib.request
import urllib.parse
import os

API_BASE = None


def send_message(token, chat_id, text):
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    data = {"chat_id": str(chat_id), "text": text}
    body = json.dumps(data).encode('utf-8')
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return json.load(r)
    except Exception as e:
        print("send_message error:", e)
        return None


def get_updates(token, offset=None, timeout=20):
    url = f"https://api.telegram.org/bot{token}/getUpdates"
    params = {}
    if offset is not None:
        params['offset'] = offset
    if timeout is not None:
        params['timeout'] = timeout
    if params:
        url = url + '?' + urllib.parse.urlencode(params)
    try:
        with urllib.request.urlopen(url, timeout=timeout+10) as r:
            return json.load(r).get('result', [])
    except Exception as e:
        print('get_updates error:', e)
        return []


def run_echo_mode(token):
    print('Starting echo mode...')
    offset = None
    while True:
        updates = get_updates(token, offset=offset, timeout=25)
        for u in updates:
            offset = u['update_id'] + 1
            msg = u.get('message')
            if not msg:
                continue
            chat_id = msg.get('chat', {}).get('id')
            sender = msg.get('from') or {}
            sender_id = sender.get('id')
            text = f"Your id: {sender_id}"
            print(f"Echo -> chat {chat_id}: {text}")
            try:
                send_message(token, chat_id, text)
            except Exception as e:
                print('send_message failed:', e)
        time.sleep(0.1)


def tail_and_forward(token, owner_id, log_files, interval=5):
    print('Starting log forwarder...')
    positions = {}
    for f in log_files:
        try:
            positions[f] = os.path.getsize(f)
        except Exception:
            positions[f] = 0
    send_message(token, owner_id, f'Log forwarder started. Watching: {", ".join(log_files)}')
    try:
        while True:
            for f in log_files:
                try:
                    cur = os.path.getsize(f)
                    last = positions.get(f, 0)
                    if cur > last:
                        with open(f, 'r', errors='ignore') as fh:
                            fh.seek(last)
                            chunk = fh.read()
                            if chunk:
                                # split into 3000-char chunks
                                while chunk:
                                    part = chunk[:3000]
                                    chunk = chunk[3000:]
                                    send_message(token, owner_id, f"Logs update ({os.path.basename(f)}):\n" + part)
                        positions[f] = cur
                except FileNotFoundError:
                    continue
                except Exception as e:
                    print('tail error for', f, e)
            time.sleep(interval)
    except KeyboardInterrupt:
        print('Log forwarder stopped')


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--mode', choices=['echo', 'forward'], required=True)
    p.add_argument('--token', required=True)
    p.add_argument('--owner')
    p.add_argument('--logs', nargs='*')
    args = p.parse_args()

    if args.mode == 'echo':
        run_echo_mode(args.token)
    else:
        owner = args.owner or os.environ.get('OWNER_ID')
        if not owner:
            print('owner id required for forward mode')
            sys.exit(2)
        logs = args.logs or ['/tmp/web_server.log', '/tmp/client_errors.log', '/tmp/auth_times.log', '/home/forget/OBHOD/BOT/obhod.log']
        tail_and_forward(args.token, owner, logs)
