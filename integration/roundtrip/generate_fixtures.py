#!/usr/bin/env python3
"""Generate H3 protocol JSON fixtures using the Python SDK.

Creates ONE instance of EVERY protocol type with ALL fields populated.
Output: fixtures/python/*.json
"""

import json
import os
import sys

# Ensure the Python SDK is importable
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "..", "sdk-python", "src"))

from h3_harness.protocol import (  # noqa: E402
    Attachment,
    CancelRequest,
    Capability,
    Config,
    Context,
    Decision,
    DecisionType,
    Delegate,
    End,
    ErrorDetail,
    ErrorResponse,
    HealthResponse,
    HistoryEntry,
    Identity,
    LLMCall,
    LLMMessage,
    Message,
    Model,
    ProcessRequest,
    ResultPayload,
    ResultRequest,
    SessionResponse,
    SessionState,
    TextResponse,
    Tool,
    ToolCall,
    Wait,
)

OUT_DIR = os.path.join(os.path.dirname(__file__), "fixtures", "python")
os.makedirs(OUT_DIR, exist_ok=True)

# ── Deterministic test values ────────────────────────────────────────

SID = "sess-rt-001"
DID = "dec-rt-001"
TS = "2026-07-20T12:00:00Z"
TS2 = "2026-07-20T12:05:00Z"


def dump(obj, name: str) -> None:
    """Serialize obj to JSON with indent=2 and write to fixtures/python/<name>.json."""
    path = os.path.join(OUT_DIR, f"{name}.json")
    data = obj.model_dump(mode="json")
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
    print(f"  Wrote {path}")


# ── Leaf types ───────────────────────────────────────────────────────

print("Generating Python fixtures → fixtures/python/")

# Attachment
dump(
    Attachment(type="image", url="https://example.com/photo.png", mime_type="image/png"),
    "attachment",
)

# LLMMessage
dump(LLMMessage(role="user", content="What is the capital of France?"), "llm_message")

# HistoryEntry
dump(HistoryEntry(role="user", content="Previous user message"), "history_entry")

# Tool
dump(
    Tool(
        name="read_file",
        description="Read a file from disk",
        parameters={"type": "object", "properties": {"path": {"type": "string"}}},
    ),
    "tool",
)

# Model
dump(
    Model(
        name="deepseek-v4-pro",
        provider="deepseek",
        context_window=1000000,
        cost_per_1k_input=0.005,
        cost_per_1k_output=0.015,
        supports_vision=True,
        supports_tool_calling=True,
    ),
    "model",
)

# SessionState
dump(
    SessionState(turn_count=3, total_tool_calls=5, total_llm_calls=2, cost_so_far=0.125, started_at=TS),
    "session_state",
)

# Config
dump(
    Config(
        max_iterations=100,
        timeout_seconds=300,
        project_dir="/home/test/project",
        max_tool_calls_per_turn=10,
        temperature=0.7,
    ),
    "config",
)

# Identity
dump(
    Identity(platform="telegram", chat_id="-1001234567890", thread_id="12345", user_name="testuser", user_id="987654"),
    "identity",
)

# Message
dump(
    Message(
        role="user",
        content="Please analyze this image.",
        timestamp=TS,
        attachments=[
            Attachment(type="image", url="https://example.com/img.png", mime_type="image/png"),
            Attachment(type="file", url="https://example.com/doc.pdf", mime_type="application/pdf"),
        ],
    ),
    "message",
)

# Context
dump(
    Context(
        history=[
            HistoryEntry(role="user", content="Hello"),
            HistoryEntry(role="assistant", content="Hi! How can I help?"),
        ],
        tools=[
            Tool(
                name="read_file",
                description="Read a file",
                parameters={"type": "object", "properties": {"path": {"type": "string"}}},
            ),
        ],
        models=[
            Model(
                name="deepseek-v4-flash",
                provider="deepseek",
                context_window=1000000,
                cost_per_1k_input=0.001,
                cost_per_1k_output=0.005,
                supports_vision=False,
                supports_tool_calling=True,
            ),
        ],
        memory="user prefers concise answers",
        skills=["coding-hermes-foreman", "python-debugging"],
        config=Config(
            max_iterations=100,
            timeout_seconds=300,
            project_dir="/home/test/project",
            max_tool_calls_per_turn=10,
            temperature=0.7,
        ),
        session_state=SessionState(turn_count=1, total_tool_calls=0, total_llm_calls=0, cost_so_far=0.0, started_at=TS),
    ),
    "context",
)

# ToolCall (decision payload)
dump(
    ToolCall(name="read_file", params={"path": "/tmp/config.yaml"}, reasoning="Need to check configuration"),
    "tool_call_payload",
)

# LLMCall (decision payload)
dump(
    LLMCall(
        model="deepseek-v4-pro",
        system_prompt="You are a helpful assistant.",
        messages=[
            LLMMessage(role="user", content="What is the weather?").model_dump(),
            LLMMessage(role="assistant", content="Let me check that for you.").model_dump(),
        ],
        temperature=0.7,
        max_tokens=4096,
    ),
    "llm_call_payload",
)

# TextResponse
dump(TextResponse(content="Here is the result of your query.", finished=True), "text_response")

# Wait (decision payload)
dump(Wait(reason="Waiting for file upload to complete", duration_seconds=30, poll_endpoint="https://example.com/status"), "wait_payload")

# Delegate (decision payload)
dump(
    Delegate(
        agent="code-reviewer",
        task="Review the authentication module for SQL injection vulnerabilities",
        context="Focus on the login endpoint and password reset flow",
        model="deepseek-v4-flash",
        provider="opencode-go",
    ),
    "delegate_payload",
)

# End (decision payload)
dump(End(reason="task_complete", summary="All requested tasks have been completed successfully."), "end_payload")

# ErrorDetail
dump(ErrorDetail(code="SESSION_NOT_FOUND", message="Session sess-999 was not found", field="session_id"), "error_detail")

# ErrorResponse
dump(
    ErrorResponse(
        error=ErrorDetail(code="INVALID_REQUEST", message="Missing required field: session_id", field="session_id").model_dump()
    ),
    "error_response",
)

# ResultPayload
dump(
    ResultPayload(
        type="tool_result", tool_name="read_file", data={"content": "file contents\nline 2\nline 3"}, duration_ms=150, success=True
    ),
    "result_payload",
)

# Capability (list of DecisionType string values)
cap_path = os.path.join(OUT_DIR, "capability.json")
caps = [c.value for c in Capability]
with open(cap_path, "w") as f:
    json.dump(caps, f, indent=2)
print(f"  Wrote {cap_path}")

# ── Request / Response types ─────────────────────────────────────────

# ProcessRequest
dump(
    ProcessRequest(
        session_id=SID,
        message=Message(
            role="user",
            content="Please analyze this image.",
            timestamp=TS,
            attachments=[
                Attachment(type="image", url="https://example.com/img.png", mime_type="image/png"),
            ],
        ),
        identity=Identity(platform="telegram", chat_id="-1001234567890", thread_id="12345", user_name="testuser", user_id="987654"),
        context=Context(
            history=[
                HistoryEntry(role="user", content="Hello"),
                HistoryEntry(role="assistant", content="Hi! How can I help?"),
            ],
            tools=[
                Tool(
                    name="read_file",
                    description="Read a file",
                    parameters={"type": "object", "properties": {"path": {"type": "string"}}},
                ),
            ],
            models=[
                Model(
                    name="deepseek-v4-pro",
                    provider="deepseek",
                    context_window=1000000,
                    cost_per_1k_input=0.005,
                    cost_per_1k_output=0.015,
                    supports_vision=True,
                    supports_tool_calling=True,
                ),
            ],
            memory="user prefers concise answers",
            skills=["coding-hermes-foreman"],
            config=Config(
                max_iterations=100,
                timeout_seconds=300,
                project_dir="/home/test/project",
                max_tool_calls_per_turn=10,
                temperature=0.7,
            ),
            session_state=SessionState(turn_count=1, total_tool_calls=0, total_llm_calls=0, cost_so_far=0.0, started_at=TS),
        ),
    ),
    "process_request",
)

# Decision — all 6 variants
for dtype, payload_name, payload_obj in [
    (
        DecisionType.TEXT,
        "text",
        TextResponse(content="Here is the result of your query.", finished=True),
    ),
    (
        DecisionType.TOOL_CALL,
        "tool_call",
        ToolCall(name="read_file", params={"path": "/tmp/config.yaml"}, reasoning="Need to check configuration"),
    ),
    (
        DecisionType.LLM_CALL,
        "llm_call",
        LLMCall(
            model="deepseek-v4-pro",
            system_prompt="You are a helpful assistant.",
            messages=[
                LLMMessage(role="user", content="What is the weather?").model_dump(),
            ],
            temperature=0.7,
            max_tokens=4096,
        ),
    ),
    (
        DecisionType.WAIT,
        "wait",
        Wait(reason="Waiting for external API response", duration_seconds=60, poll_endpoint="https://api.example.com/status"),
    ),
    (
        DecisionType.DELEGATE,
        "delegate",
        Delegate(
            agent="code-reviewer",
            task="Review the auth module",
            context="Focus on SQL injection",
            model="deepseek-v4-flash",
            provider="opencode-go",
        ),
    ),
    (
        DecisionType.END,
        "end",
        End(reason="task_complete", summary="All tasks finished successfully."),
    ),
]:
    d = Decision(
        decision=dtype,
        decision_id=f"dec-rt-{dtype.value}",
        history=[
            HistoryEntry(role="user", content="Hello"),
            HistoryEntry(role="assistant", content="Hi! How can I help?"),
        ],
        **{payload_name: payload_obj},  # type: ignore[arg-type]
    )
    dump(d, f"decision_{dtype.value}")

# ResultRequest
dump(
    ResultRequest(
        session_id=SID,
        decision_id=DID,
        result=ResultPayload(
            type="tool_result",
            tool_name="read_file",
            data={"content": "file contents here"},
            duration_ms=150,
            success=True,
        ).model_dump(),
    ),
    "result_request",
)

# CancelRequest
dump(CancelRequest(session_id=SID, reason="user_interrupt"), "cancel_request")

# HealthResponse
dump(
    HealthResponse(
        status="ok",
        version="1.0.0",
        transport="rest",
        protocol_version="1.0",
        uptime_seconds=3600,
        active_sessions=5,
        capabilities=["text", "tool_call", "end"],
        degraded_reason=None,
        error=None,
    ),
    "health_response",
)

# SessionResponse
dump(
    SessionResponse(
        session_id=SID,
        started_at=TS,
        last_active=TS2,
        turn_count=3,
        status="active",
        current_decision=DID,
        current_decision_type="tool_call",
    ),
    "session_response",
)

print("\nAll fixtures generated successfully.")
