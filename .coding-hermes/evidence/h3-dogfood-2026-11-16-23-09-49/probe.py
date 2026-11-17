"""Timing probe for one H3 harness endpoint.

Usage: python probe.py <base_url> [n_requests]
Prints: cold_start_ms (time from script start until /v1/health answers 200),
        health_ms, process_ms list summary.
"""

import json
import statistics
import sys
import time
import urllib.request


def get(url, timeout=10.0):
    t0 = time.monotonic()
    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            body = r.read()
            return r.status, body, (time.monotonic() - t0) * 1000.0
    except Exception as exc:  # noqa: BLE001
        return None, repr(exc).encode(), (time.monotonic() - t0) * 1000.0


def post(url, payload, timeout=30.0):
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        url, data=data, headers={"Content-Type": "application/json"}, method="POST"
    )
    t0 = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            body = r.read()
            return r.status, body, (time.monotonic() - t0) * 1000.0
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read(), (time.monotonic() - t0) * 1000.0
    except Exception as exc:  # noqa: BLE001
        return None, repr(exc).encode(), (time.monotonic() - t0) * 1000.0


def main():
    base = sys.argv[1].rstrip("/")
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 10

    t_start = time.monotonic()
    deadline = t_start + 30.0
    cold_ms = None
    while time.monotonic() < deadline:
        status, body, _ = get(f"{base}/v1/health", timeout=2.0)
        if status == 200:
            cold_ms = (time.monotonic() - t_start) * 1000.0
            break
        time.sleep(0.02)
    print(f"cold_start_ms={cold_ms:.1f}" if cold_ms else "cold_start_ms=TIMEOUT")
    if cold_ms is None:
        return 1

    status, body, ms = get(f"{base}/v1/health")
    print(f"health_status={status} health_ms={ms:.2f} bytes={len(body)}")

    payload = {
        "session_id": "probe-sess",
        "identity": {"chat_id": "chat-1", "platform": "cli"},
        "message": {"content": "probe turn"},
        "context": {"config": {}, "session_state": {}, "history": []},
    }
    lat = []
    first_body = None
    for i in range(n):
        payload["session_id"] = f"probe-sess-{i}"
        status, body, ms = post(f"{base}/v1/process", payload)
        if first_body is None:
            first_body = body
        lat.append(ms)
        if status != 200:
            print(f"process_rc={status} body={body[:200]!r} ms={ms:.2f}")
    print(
        f"process_n={len(lat)} first_ms={lat[0]:.2f} cold_first_body={first_body[:160]!r}"
    )
    print(
        "process_ms min=%.2f p50=%.2f mean=%.2f max=%.2f"
        % (
            min(lat),
            statistics.median(lat),
            statistics.fmean(lat),
            max(lat),
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
