# S06 — Hermes Core Integration (Shim Implementation)

**Status:** Spec  
**Version:** 1.0.0  
**Last Updated:** 2026-07-12

---

## 1. Where the Shim Lives

```
hermes_cli/agent/shims/h3/
├── __init__.py           # Plugin entry point
├── protocol.py           # Pydantic models (mirrors SDK types, Hermes-side)
├── client.py             # REST + gRPC client — calls harness
├── loader.py             # Discover harnesses, health-check, route sessions
├── native.py              # Wraps Hermes native loop as H3 harness (symmetry)
├── test_battery.py        # Compliance suite (S05)
└── cli.py                 # `hermes h3` subcommands
```

This directory is a **plugin** that ships with Hermes Core, enabled via config:

```yaml
plugins:
  h3:
    enabled: true
```

---

## 2. Protocol Types (Hermes-Side)

```python
# protocol.py — mirrors the harness-side types, Hermes ownership

from pydantic import BaseModel
from enum import Enum
from typing import Optional, Any

class DecisionType(str, Enum):
    TOOL_CALL = "tool_call"
    LLM_CALL  = "llm_call"
    TEXT      = "text"
    WAIT      = "wait"
    DELEGATE  = "delegate"
    END       = "end"

class ProcessRequest(BaseModel):
    session_id: str
    message: Message
    identity: Identity
    context: Context

class Decision(BaseModel):
    decision: DecisionType
    decision_id: str
    tool_call: Optional[ToolCall] = None
    llm_call: Optional[LLMCall] = None
    text: Optional[TextResponse] = None
    wait: Optional[Wait] = None
    delegate: Optional[Delegate] = None
    end: Optional[End] = None

class ResultRequest(BaseModel):
    session_id: str
    decision_id: str
    result: ExecutionResult

class ExecutionResult(BaseModel):
    type: str  # tool_result | llm_response | text_sent | delegate_result | wait_timeout | error
    tool_name: Optional[str] = None
    data: dict[str, Any] = {}
    duration_ms: float = 0
    success: bool = True
```

---

## 3. Client — Calling the Harness

```python
# client.py

class H3Client:
    """Hermes-side client for calling an H3 harness."""

    def __init__(self, endpoint: str, transport: str = "rest", timeout_ms: int = 30000):
        self.endpoint = endpoint.rstrip("/")
        self.transport = transport
        self.timeout = timeout_ms / 1000
        self._rest = httpx.AsyncClient(base_url=self.endpoint, timeout=self.timeout)

    async def health(self) -> HealthResponse:
        resp = await self._rest.get("/v1/health")
        resp.raise_for_status()
        return HealthResponse(**resp.json())

    async def process(self, session_id: str, message: Message, context: Context) -> Decision:
        req = ProcessRequest(
            session_id=session_id,
            message=message,
            identity=context.identity,
            context=context,
        )
        resp = await self._rest.post("/v1/process", json=req.model_dump())
        resp.raise_for_status()
        return Decision(**resp.json())

    async def result(self, session_id: str, decision_id: str, result: ExecutionResult) -> Decision:
        req = ResultRequest(
            session_id=session_id,
            decision_id=decision_id,
            result=result,
        )
        resp = await self._rest.post("/v1/result", json=req.model_dump())
        resp.raise_for_status()
        return Decision(**resp.json())

    async def cancel(self, session_id: str, reason: str = "user_interrupt") -> CancelResponse:
        resp = await self._rest.post("/v1/cancel", json={
            "session_id": session_id,
            "reason": reason,
        })
        resp.raise_for_status()
        return CancelResponse(**resp.json())

    async def close(self):
        await self._rest.aclose()
```

---

## 4. The Shim Loop — Core Logic

```python
# shim_loop.py — Hermes-side agent loop with external harness

class H3ShimLoop:
    """
    Replaces the native Hermes agent loop when using an external harness.

    Flow:
      1. Build Hermes context (tools, models, skills, memory)
      2. POST /v1/process → harness returns Decision
      3. Execute Decision (tool call / LLM / text / wait / delegate)
      4. POST /v1/result → harness returns next Decision
      5. Repeat until END
    """

    def __init__(self, client: H3Client, session: Session):
        self.client = client
        self.session = session
        self.max_iterations = session.config.get("max_iterations", 50)
        self.iteration = 0

    async def run(self, message: Message) -> str:
        """Returns the end reason string."""
        context = await self._build_context()

        decision = await self.client.process(
            self.session.id, message, context
        )

        while decision.decision != DecisionType.END:
            self.iteration += 1
            if self.iteration > self.max_iterations:
                # Force-terminate — harness didn't converge
                await self._send_text("⚠️ Max iterations reached. Terminating.")
                return "timeout"

            result = await self._execute(decision)
            decision = await self.client.result(
                self.session.id, decision.decision_id, result
            )

        return decision.end.reason

    async def _build_context(self) -> Context:
        """Gather everything the harness needs from Hermes internals."""
        return Context(
            history=await self.session.get_history(limit=20),
            tools=self.session.available_tools(),
            models=self.session.available_models(),
            memory=self.session.get_memory(),
            skills=self.session.loaded_skills,
            config=self.session.config,
            session_state=self.session.state(),
        )

    async def _execute(self, decision: Decision) -> ExecutionResult:
        """Execute the harness's decision and return the result."""
        start = time.monotonic()

        match decision.decision:
            case DecisionType.TOOL_CALL:
                return await self._execute_tool(decision.tool_call)

            case DecisionType.LLM_CALL:
                return await self._execute_llm(decision.llm_call)

            case DecisionType.TEXT:
                return await self._execute_text(decision.text)

            case DecisionType.WAIT:
                return await self._execute_wait(decision.wait)

            case DecisionType.DELEGATE:
                return await self._execute_delegate(decision.delegate)

        duration_ms = (time.monotonic() - start) * 1000
        result.duration_ms = duration_ms
        return result
```

---

## 5. Decision Executors

### 5.1 Tool Call Executor

```python
async def _execute_tool(self, tc: ToolCall) -> ExecutionResult:
    try:
        tool_fn = self.session.tool_registry.get(tc.name)
        output = await tool_fn(**tc.params)
        return ExecutionResult(
            type="tool_result",
            tool_name=tc.name,
            data=output,
            success=True,
        )
    except ToolNotFoundError:
        return ExecutionResult(
            type="error",
            tool_name=tc.name,
            data={"error": f"Unknown tool: {tc.name}"},
            success=False,
        )
    except ToolExecutionError as e:
        return ExecutionResult(
            type="error",
            tool_name=tc.name,
            data={"error": str(e), "traceback": e.traceback},
            success=False,
        )
```

### 5.2 LLM Call Executor

```python
async def _execute_llm(self, llm: LLMCall) -> ExecutionResult:
    try:
        model_config = self.session.model_registry.get(llm.model)
        response = await model_config.provider.complete(
            model=llm.model,
            system_prompt=llm.system_prompt,
            messages=llm.messages,
            temperature=llm.temperature or 0.7,
            max_tokens=llm.max_tokens,
        )
        return ExecutionResult(
            type="llm_response",
            data={
                "content": response.content,
                "model": llm.model,
                "tokens_used": response.tokens,
                "cost": response.cost,
            },
            success=True,
        )
    except Exception as e:
        return ExecutionResult(
            type="error",
            data={"error": str(e), "phase": "llm_call"},
            success=False,
        )
```

### 5.3 Text Executor

```python
async def _execute_text(self, text: TextResponse) -> ExecutionResult:
    try:
        msg_id = await self.session.gateway.send(
            platform=self.session.platform,
            chat_id=self.session.chat_id,
            thread_id=self.session.thread_id,
            content=text.content,
        )
        return ExecutionResult(
            type="text_sent",
            data={"message_id": msg_id, "platform": self.session.platform},
            success=True,
        )
    except Exception as e:
        return ExecutionResult(
            type="error",
            data={"error": str(e), "phase": "text_delivery"},
            success=False,
        )
```

---

## 6. Loader — Harness Discovery & Session Routing

```python
# loader.py

class H3Loader:
    """Discovers harnesses from config, health-checks them, routes sessions."""

    def __init__(self, config: dict):
        self.harnesses: dict[str, H3Client] = {}
        self.session_routes: dict[str, str] = {}  # session_id → harness_name
        self.default_harness = config.get("default_harness", "native")
        self._load(config)

    def _load(self, config: dict):
        for name, hconfig in config.get("harnesses", {}).items():
            if name == "native" or hconfig.get("endpoint") is None:
                continue
            self.harnesses[name] = H3Client(
                endpoint=hconfig["endpoint"],
                transport=hconfig.get("transport", "rest"),
                timeout_ms=hconfig.get("timeout_ms", 30000),
            )

    async def resolve(self, platform: str, chat_id: str, thread_id: str = None) -> str:
        """Resolve which harness handles this session."""
        routes = self.config.get("sessions", {})

        # Most specific → least specific
        for key in [
            f"{platform}:{chat_id}:{thread_id}",
            f"{platform}:{chat_id}",
            platform,
        ]:
            if key in routes:
                return routes[key]["harness"]

        return self.default_harness

    async def health_check_loop(self):
        """Background loop that health-checks all harnesses every 30s."""
        while True:
            for name, client in self.harnesses.items():
                try:
                    health = await client.health()
                    # Mark as healthy
                except Exception:
                    # Log warning, mark as unhealthy, route sessions to native
                    pass
            await asyncio.sleep(30)
```

---

## 7. Native Harness Wrapper (Symmetry)

```python
# native.py — wraps Hermes native agent loop as H3 harness
# Allows native to be treated like any other harness in config

class NativeH3Harness:
    """Adapter: Hermes native agent loop as an H3 harness."""
    endpoint = None  # signal to loader: don't make HTTP calls

    async def run(self, session, message):
        # Delegate to native Hermes agent loop
        return await native_agent_loop(session, message)
```

---

## 8. CLI Commands

```bash
hermes h3 install              # Install H3 plugin
hermes h3 uninstall            # Remove H3 plugin
hermes h3 verify               # Verify installation + compatibility
hermes h3 list                 # List configured harnesses + health status
hermes h3 test --endpoint URL  # Run compliance test battery
hermes h3 scaffold NAME --lang go|python|ts  # Generate harness template
hermes h3 route [session]      # Show which harness a session routes to

# Session-level overrides
hermes h3 use consensus        # Route current session to Consensus
hermes h3 use native           # Route current session to native Hermes
```

---

## 9. Integration Points

| Hermes Subsystem | How H3 Connects |
|---|---|
| **Gateway** | Gateway receives message → calls H3 Shim Loop → Shim calls harness → harness returns decisions → shim executes → gateway delivers |
| **Tool Registry** | Shim reads available tools → sends to harness in `context.tools` → harness requests tool → shim executes via tool registry |
| **Model Router** | Shim reads available models + pricing → sends to harness in `context.models` → harness picks model → shim routes via model router |
| **Credential Vault** | Harness NEVER sees credentials. Shim resolves tool calls through the vault automatically |
| **Cron Scheduler** | H3 harnesses CAN be used for cron jobs. Cron job config includes `harness: consensus` |
| **Skills** | Shim loads skills → passes skill names in `context.skills` → harness optionally loads skill content |
| **MCP** | Harness can request MCP tool calls. Shim routes through Hermes MCP client |
| **Delegation** | `delegate` decision → shim spawns sub-agent → result returns to harness |

---

## 10. Error Catalog

| Error Code | Trigger | Shim Behavior |
|---|---|---|
| `H3_HARNESS_UNREACHABLE` | Health check fails 3x | Route to native, log ERROR |
| `H3_TIMEOUT` | Harness doesn't respond in `timeout_ms` | Retry 3x, then end session |
| `H3_INVALID_DECISION` | Harness returns unknown decision type | Log error, end session, notify user |
| `H3_TOOL_NOT_FOUND` | Harness requests unknown tool | Return error result to harness |
| `H3_MODEL_NOT_FOUND` | Harness requests unknown model | Return error result to harness |
| `H3_MAX_ITERATIONS` | Loop exceeds `max_iterations` | Force-end with message to user |
| `H3_PROTOCOL_MISMATCH` | Harness protocol version ≠ shim version | Route to native, log CRITICAL |
| `H3_CANCEL_RECEIVED` | User sends `/stop` or new message mid-loop | Cancel in-flight, POST /v1/cancel |
