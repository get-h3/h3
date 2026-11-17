"""Lifecycle probe: drives process -> result(END) -> cancel and compares the two
liveness surfaces (/v1/sessions/{id}.status vs /v1/health.active_sessions), and
prints the raw cancel body to check the documented cancel-response contract.
"""

import json
import sys
import urllib.error
import urllib.request

BASE = sys.argv[1].rstrip("/") if len(sys.argv) > 1 else "http://127.0.0.1:9194"
SID = sys.argv[2] if len(sys.argv) > 2 else "life-1"


def call(method, path, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(
        BASE + path,
        data=data,
        headers={"Content-Type": "application/json"} if data else {},
        method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode()


PROC = {
    "session_id": SID,
    "identity": {"user_id": "u1", "chat_id": "c1", "platform": "cli"},
    "message": {"content": "hello lifecycle"},
    "context": {"config": {}, "session_state": {}, "history": []},
}

print("process      ->", *call("POST", "/v1/process", PROC))
print("session GET  ->", *call("GET", f"/v1/sessions/{SID}"))
print("health       ->", *call("GET", "/v1/health"))
res = call("POST", "/v1/process", PROC)
print("process#2    ->", res[0], res[1][:300])
try:
    dec = json.loads(res[1])
except Exception:  # noqa: BLE001
    dec = {}
did = dec.get("decision_id")
print("decision_id  =", did)
RESULT = {
    "session_id": SID,
    "decision_id": did,
    "result": {"type": "text_sent", "content": "delivered"},
}
print("result(END)  ->", *call("POST", "/v1/result", RESULT))
print("session GET  ->", *call("GET", f"/v1/sessions/{SID}"))
print("health       ->", *call("GET", "/v1/health"))
print(
    "cancel       ->",
    *call("POST", "/v1/cancel", {"session_id": SID, "reason": "user_abort"}),
)
print("session GET  ->", *call("GET", f"/v1/sessions/{SID}"))
print("health       ->", *call("GET", "/v1/health"))
print("delete       ->", *call("DELETE", f"/v1/sessions/{SID}"))
print("session GET  ->", *call("GET", f"/v1/sessions/{SID}"))
print("health       ->", *call("GET", "/v1/health"))
