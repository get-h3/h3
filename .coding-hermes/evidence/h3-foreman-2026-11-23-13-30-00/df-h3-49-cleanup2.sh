#!/bin/sh
# DF-H3-49 cleanup, run 2: stop the echo server left by smoke2.
set -u
pkill -f examples/echo.py
sleep 1
if curl -s -o /dev/null --max-time 3 http://127.0.0.1:9191/v1/health; then
  echo "PORT_STILL_SERVING"
  exit 1
else
  echo "PORT_CLOSED"
fi
echo "CLEANUP2_COMPLETE"
