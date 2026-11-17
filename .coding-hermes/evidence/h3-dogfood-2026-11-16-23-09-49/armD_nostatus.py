"""Arm D — the AGENTS.md-quickstart-shaped harness: it tracks started_at and
turn_count but writes NO 'status' key. Documented live in SDKPY-GAP-058 as the
shape where the two liveness surfaces disagree.
"""

from datetime import datetime, timezone

from fastapi import FastAPI
from h3_harness import (
    BaseHarness,
    Decision,
    DecisionType,
    End,
    TextResponse,
    create_router,
)


class NoStatusHarness(BaseHarness):
    def __init__(self):
        self._sessions: dict[str, dict] = {}

    async def on_process(self, req):
        s = self._sessions.setdefault(
            req.session_id,
            {"started_at": datetime.now(timezone.utc).isoformat(), "turn_count": 0},
        )
        s["turn_count"] += 1
        s["last_active"] = datetime.now(timezone.utc).isoformat()
        return Decision(
            decision=DecisionType.TEXT,
            text=TextResponse(content=f"Echo: {req.message.content}", finished=True),
            history=list(req.context.history),
        )

    async def on_result(self, req):
        s = self._sessions.get(req.session_id)
        if s is not None:
            s["turn_count"] += 1
        return Decision(decision=DecisionType.END, end=End(reason="task_complete"))

    def get_session_info(self, session_id: str) -> dict | None:
        return self._sessions.get(session_id)


app = FastAPI()
app.include_router(create_router(NoStatusHarness()))
