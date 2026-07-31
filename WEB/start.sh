#!/bin/bash
cd /home/forget/LMArena/WEB
exec node server.js >> /tmp/web_server.log 2>&1
