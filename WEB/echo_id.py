#!/usr/bin/env python3
"""Simple runner to start echo-id mode using OBHOD/BOT implementation.
Usage: ./echo_id.py <BOT_TOKEN>
"""
import sys
import asyncio

if len(sys.argv) < 2:
    print("Usage: echo_id.py <BOT_TOKEN>")
    sys.exit(2)

BOT_TOKEN = sys.argv[1]

# Add OBHOD to path
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from OBHOD.BOT import core

async def main():
    try:
        await core.run_echo_id_mode(BOT_TOKEN)
    except KeyboardInterrupt:
        pass

if __name__ == '__main__':
    asyncio.run(main())
