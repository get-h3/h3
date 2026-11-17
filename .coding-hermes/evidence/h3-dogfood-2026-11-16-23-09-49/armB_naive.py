"""Arm B — a plausible first harness written from the integration docs WITHOUT
copying the battery-aware quickstart comments: no session tracking, no history
echo, no on_result, no streaming semantics. This is what a user who wired the
protocol endpoints and their own brain would ship first.
"""

from h3_harness import (
    BaseHarness,
    Decision,
    DecisionType,
    End,
    TextResponse,
    create_router,
)
from fastapi import FastAPI


class NaiveHarness(BaseHarness):
    async def on_process(self, req):
        # A real harness would call its LLM here; the shape is what matters.
        return Decision(
            decision=DecisionType.TEXT,
            text=TextResponse(content=f"Echo: {req.message.content}", finished=True),
        )

    async def on_result(self, req):
        return Decision(decision=DecisionType.END, end=End(reason="task_complete"))


app = FastAPI()
app.include_router(create_router(NaiveHarness()))
