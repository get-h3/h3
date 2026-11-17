"""Concurrency/isolation probe: N parallel turns spread over M sessions against a
single-worker uvicorn. Checks that each session's echo is its own (no cross-talk)
and records latency percentiles under concurrency.
"""

import json
import statistics
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:9191").rstrip("/")
N = int(sys.argv[2]) if len(sys.argv) > 2 else 40
SESSIONS = int(sys.argv[3]) if len(sys.argv) > 3 else 8


def turn(i):
    sid = f"cc-{i % SESSIONS}"
    payload = {
        "session_id": sid,
        "identity": {"user_id": "u", "chat_id": "c", "platform": "cli"},
        "message": {"content": f"msg-{i}"},
        "context": {"config": {}, "session_state": {}, "history": []},
    }
    req = urllib.request.Request(
        BASE + "/v1/process",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    t0 = time.perf_counter()
    with urllib.request.urlopen(req, timeout=30) as r:
        body = json.loads(r.read().decode())
    ms = (time.perf_counter() - t0) * 1000
    got = body.get("text", {}).get("content")
    return sid, f"msg-{i}", got, ms


with ThreadPoolExecutor(max_workers=SESSIONS) as pool:
    results = list(pool.map(turn, range(N)))

cross = [r for r in results if r[1] not in (r[2] or "")]
lat = sorted(r[3] for r in results)
p = lambda q: lat[min(len(lat) - 1, int(q * len(lat)))]  # noqa: E731
print(f"requests={N} sessions={SESSIONS} cross_talk={len(cross)}")
print(
    f"latency_ms p50={p(0.50):.2f} p90={p(0.90):.2f} p99={p(0.99):.2f} "
    f"max={lat[-1]:.2f} mean={statistics.mean(lat):.2f}"
)
if cross:
    print("CROSS_TALK_SAMPLES:", cross[:3])
