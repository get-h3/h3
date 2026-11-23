#!/bin/sh
# DF-H3-49 smoke, run 2: start echo on 9191, health must be HTTP 200.
# Server intentionally LEFT RUNNING — teardown is a separate exec (run-1 lesson:
# killing the nohup child from inside the same exec session surfaced exit 255).
set -eu
cd "$HOME/sdk-python"
nohup .venv/bin/python src/h3_harness/examples/echo.py > /tmp/echo.log 2>&1 &
SERVER_PID=$!
echo "SERVER_PID=$SERVER_PID"
sleep 5
echo "== echo.log head =="
head -5 /tmp/echo.log
echo "== health body =="
curl -sf http://127.0.0.1:9191/v1/health
echo
echo "HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9191/v1/health)"
echo "== installed version =="
.venv/bin/python -c "import h3_harness; print(h3_harness.__version__)"
echo "SMOKE2_COMPLETE"
