#!/bin/bash
cd "$(dirname "$0")"
DIVE_HEADLESS=1 npx electron smoke-app.js > /tmp/dive-app-smoke.log 2>&1 &
pid=$!
for i in $(seq 1 45); do sleep 1; grep -q "photos=\|ERR " /tmp/dive-app-smoke.log && break; done
sleep 1; kill $pid 2>/dev/null; pkill -f "electron smoke-app" 2>/dev/null
grep -vE "^\[|CVDisplay|^$|Security Warning|Policy|security|electronjs|warning will|unsafe-eval|renderer process|^  " /tmp/dive-app-smoke.log | head -20
