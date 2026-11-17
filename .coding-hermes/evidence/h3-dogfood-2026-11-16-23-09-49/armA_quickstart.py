from datetime import datetime, timezone

from h3_harness import (
    BaseHarness,
    Decision,
    DecisionType,
    End,
    TextResponse,
    create_router,
)
from fastapi import FastAPI


class MyHarness(BaseHarness):
    def __init__(self):
        # Track sessions so cancel/session lookups 404 on unknown ids
        # (battery: test_5_9b cancel_unknown_session, test_5_10 session_not_found).
        self._sessions: dict[str, dict] = {}

    async def on_process(self, req):
        # Echo conversation history from context (battery: history preserved).
        history = list(req.context.history)
        # Streaming: "do not finish" in message -> unfinished text.
        streaming = "do not finish" in req.message.content
        finished = not streaming
        self._sessions[req.session_id] = {
            "started_at": datetime.now(timezone.utc).isoformat(),
            "turn_count": (
                self._sessions.get(req.session_id, {}).get("turn_count", 0) + 1
            ),
            # Battery: sessions start active; on_result flips them to
            # "completed" (test_5_11 session_status_completed).
            "status": "active",
        }
        return Decision(
            decision=DecisionType.TEXT,
            text=TextResponse(
                content=f"Echo: {req.message.content}",
                finished=finished,
            ),
            history=history,
        )

    async def on_result(self, req):
        # Battery: a session that has ended must report status="completed"
        # (test_5_11 session_status_completed) — flip it before returning END.
        session = self._sessions.get(req.session_id)
        if session is not None:
            session["status"] = "completed"
        return Decision(decision=DecisionType.END, end=End(reason="task_complete"))

    def get_session_info(self, session_id: str) -> dict | None:
        return self._sessions.get(session_id)

    async def on_session_terminate(self, session_id: str) -> None:
        # DELETE /v1/sessions/{id} -> forget the session so a later GET 404s.
        self._sessions.pop(session_id, None)


app = FastAPI()
app.include_router(create_router(MyHarness()))
# Run with: uvicorn my_harness:app --port 9191
