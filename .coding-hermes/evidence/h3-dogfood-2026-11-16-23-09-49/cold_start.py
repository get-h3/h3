"""Cold-start probe: time from spawning `uvicorn <app>` to the first 200 on
/v1/health, repeated R times. This is the number a user feels when they restart
their harness; warm latency is measured separately.
"""

import json
import statistics
import subprocess
import sys
import time
import urllib.error
import urllib.request

APP = sys.argv[1] if len(sys.argv) > 1 else "armA_quickstart:app"
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 9188
REPS = int(sys.argv[3]) if len(sys.argv) > 3 else 5
UVICORN = ".venv/bin/uvicorn"

starts = []
for i in range(REPS):
    t0 = time.perf_counter()
    proc = subprocess.Popen(
        [UVICORN, APP, "--port", str(PORT), "--log-level", "warning"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    ok = False
    deadline = time.time() + 30
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(
                f"http://127.0.0.1:{PORT}/v1/health", timeout=2
            ) as r:
                if r.status == 200:
                    json.loads(r.read().decode())
                    ok = True
                    break
        except (urllib.error.URLError, OSError, ValueError):
            time.sleep(0.005)
    cold = (time.perf_counter() - t0) * 1000
    proc.terminate()
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=10)
    time.sleep(0.2)
    starts.append(cold)
    print(f"boot {i + 1}: cold_start_ms={cold:.0f} ok={ok}")

print(
    f"cold_start_ms n={len(starts)} median={statistics.median(starts):.0f} "
    f"min={min(starts):.0f} max={max(starts):.0f}"
)
