"""Arm C — the most common beginner mistake per the docs themselves: health at
/health instead of /v1/health, and a bare /v1/process that returns text.
No SDK: hand-rolled FastAPI, as a user coming from the OpenAPI spec would write.
"""

from fastapi import FastAPI

app = FastAPI()


@app.get("/health")
async def health():
    return {
        "status": "ok",
        "version": "0.0.1",
        "uptime_seconds": 1.0,
        "active_sessions": 0,
    }


@app.post("/v1/process")
async def process(body: dict):
    return {
        "decision": "text",
        "decision_id": "d-1",
        "history": [],
        "text": {
            "content": "Echo: " + str(body.get("message", {}).get("content", "")),
            "finished": True,
        },
    }
