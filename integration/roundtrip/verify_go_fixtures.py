#!/usr/bin/env python3
"""Verify Go-generated JSON fixtures using the Python SDK.

Reads fixtures/go/*.json, deserializes with Python SDK types,
and verifies ALL fields match the expected deterministic values.
Exit 0 = all pass, exit 1 = failure.
"""
from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "..", "sdk-python", "src"))

from h3_harness.protocol import (  # noqa: E402
    Attachment,
    CancelRequest,
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

FIXTURES_DIR = os.environ.get("FIXTURES_DIR", os.path.join(os.path.dirname(__file__), "fixtures", "go"))

failures = 0


def read_json(name: str) -> dict:
    """Read a JSON fixture file."""
    path = os.path.join(FIXTURES_DIR, f"{name}.json")
    with open(path) as f:
        return json.load(f)


def check(name: str, condition: bool, msg: str) -> None:
    """Assert a condition, record failure if false."""
    global failures
    if not condition:
        print(f"FAIL {name}: {msg}")
        failures += 1


def run_test(name: str, fn) -> None:
    """Run a single test, catching exceptions."""
    try:
        fn()
        print(f"PASS {name}")
    except Exception as e:
        print(f"FAIL {name}: {e}")
        global failures
        failures += 1


# ── Leaf types ──

def test_attachment():
    data = read_json("attachment")
    a = Attachment.model_validate(data)
    check("attachment/type", a.type == "image", f"type={a.type}")
    check("attachment/url", a.url == "https://example.com/photo.png", f"url={a.url}")
    check("attachment/mime_type", a.mime_type == "image/png", f"mime_type={a.mime_type}")


def test_llm_message():
    data = read_json("llm_message")
    m = LLMMessage.model_validate(data)
    check("llm_message/role", m.role == "user", f"role={m.role}")
    check("llm_message/content", m.content == "What is the capital of France?", f"content={m.content}")


def test_history_entry():
    data = read_json("history_entry")
    h = HistoryEntry.model_validate(data)
    check("history_entry/role", h.role == "user", f"role={h.role}")
    check("history_entry/content", h.content == "Previous user message", f"content={h.content}")


def test_tool():
    data = read_json("tool")
    t = Tool.model_validate(data)
    check("tool/name", t.name == "read_file", f"name={t.name}")
    check("tool/description", t.description == "Read a file from disk", f"description={t.description}")
    check("tool/parameters", t.parameters is not None, "parameters is None")
    check("tool/params/type", t.parameters.get("type") == "object", f"params.type={t.parameters.get('type')}")


def test_model():
    data = read_json("model")
    m = Model.model_validate(data)
    check("model/name", m.name == "deepseek-v4-pro", f"name={m.name}")
    check("model/provider", m.provider == "deepseek", f"provider={m.provider}")
    check("model/context_window", m.context_window == 1000000, f"context_window={m.context_window}")
    check("model/cost_per_1k_input", m.cost_per_1k_input == 0.005, f"cost_per_1k_input={m.cost_per_1k_input}")
    check("model/cost_per_1k_output", m.cost_per_1k_output == 0.015, f"cost_per_1k_output={m.cost_per_1k_output}")
    check("model/supports_vision", m.supports_vision is True, f"supports_vision={m.supports_vision}")
    check("model/supports_tool_calling", m.supports_tool_calling is True, f"supports_tool_calling={m.supports_tool_calling}")


def test_session_state():
    data = read_json("session_state")
    s = SessionState.model_validate(data)
    check("session_state/turn_count", s.turn_count == 3, f"turn_count={s.turn_count}")
    check("session_state/total_tool_calls", s.total_tool_calls == 5, f"total_tool_calls={s.total_tool_calls}")
    check("session_state/total_llm_calls", s.total_llm_calls == 2, f"total_llm_calls={s.total_llm_calls}")
    check("session_state/cost_so_far", s.cost_so_far == 0.125, f"cost_so_far={s.cost_so_far}")
    check("session_state/started_at", s.started_at == "2026-07-20T12:00:00Z", f"started_at={s.started_at}")


def test_config():
    data = read_json("config")
    c = Config.model_validate(data)
    check("config/max_iterations", c.max_iterations == 100, f"max_iterations={c.max_iterations}")
    check("config/timeout_seconds", c.timeout_seconds == 300, f"timeout_seconds={c.timeout_seconds}")
    check("config/project_dir", c.project_dir == "/home/test/project", f"project_dir={c.project_dir}")
    check("config/max_tool_calls_per_turn", c.max_tool_calls_per_turn == 10, f"max_tool_calls_per_turn={c.max_tool_calls_per_turn}")
    check("config/temperature", c.temperature == 0.7, f"temperature={c.temperature}")


def test_identity():
    data = read_json("identity")
    i = Identity.model_validate(data)
    check("identity/platform", i.platform == "telegram", f"platform={i.platform}")
    check("identity/chat_id", i.chat_id == "-1001234567890", f"chat_id={i.chat_id}")
    check("identity/thread_id", i.thread_id == "12345", f"thread_id={i.thread_id}")
    check("identity/user_name", i.user_name == "testuser", f"user_name={i.user_name}")
    check("identity/user_id", i.user_id == "987654", f"user_id={i.user_id}")


def test_message():
    data = read_json("message")
    m = Message.model_validate(data)
    check("message/role", m.role == "user", f"role={m.role}")
    check("message/content", m.content == "Please analyze this image.", f"content={m.content}")
    check("message/timestamp", m.timestamp == "2026-07-20T12:00:00Z", f"timestamp={m.timestamp}")
    check("message/attachments_len", len(m.attachments or []) == 2, f"len={len(m.attachments or [])}")
    check("message/att0_type", m.attachments[0].type == "image", f"att0.type={m.attachments[0].type}")
    check("message/att1_type", m.attachments[1].type == "file", f"att1.type={m.attachments[1].type}")


def test_context():
    data = read_json("context")
    c = Context.model_validate(data)
    check("context/history_len", len(c.history) == 2, f"history_len={len(c.history)}")
    check("context/history0_role", c.history[0].role == "user", f"h0.role={c.history[0].role}")
    check("context/history0_content", c.history[0].content == "Hello", f"h0.content={c.history[0].content}")
    check("context/tools_len", len(c.tools) == 1, f"tools_len={len(c.tools)}")
    check("context/tool0_name", c.tools[0].name == "read_file", f"tool0.name={c.tools[0].name}")
    check("context/models_len", len(c.models) == 1, f"models_len={len(c.models)}")
    check("context/model0_name", c.models[0].name == "deepseek-v4-flash", f"model0.name={c.models[0].name}")
    check("context/memory", c.memory == "user prefers concise answers", f"memory={c.memory}")
    check("context/skills_len", len(c.skills or []) == 2, f"skills_len={len(c.skills or [])}")
    check("context/skills0", c.skills[0] == "coding-hermes-foreman", f"skills0={c.skills[0]}")
    check("context/config/max_iterations", c.config.max_iterations == 100, f"cfg.max_iter={c.config.max_iterations}")
    check("context/session_state/turn_count", c.session_state.turn_count == 1, f"ss.turn={c.session_state.turn_count}")


def test_tool_call_payload():
    data = read_json("tool_call_payload")
    tc = ToolCall.model_validate(data)
    check("tool_call_payload/name", tc.name == "read_file", f"name={tc.name}")
    check("tool_call_payload/reasoning", tc.reasoning == "Need to check configuration", f"reasoning={tc.reasoning}")
    check("tool_call_payload/params", tc.params == {"path": "/tmp/config.yaml"}, f"params={tc.params}")


def test_llm_call_payload():
    data = read_json("llm_call_payload")
    lc = LLMCall.model_validate(data)
    check("llm_call_payload/model", lc.model == "deepseek-v4-pro", f"model={lc.model}")
    check("llm_call_payload/system_prompt", lc.system_prompt == "You are a helpful assistant.", f"sys={lc.system_prompt}")
    check("llm_call_payload/msgs_len", len(lc.messages) == 2, f"msgs_len={len(lc.messages)}")
    check("llm_call_payload/msg0_role", lc.messages[0]["role"] == "user", f"msg0={lc.messages[0]}")
    check("llm_call_payload/msg0_content", lc.messages[0]["content"] == "What is the weather?", f"msg0.content={lc.messages[0]['content']}")
    check("llm_call_payload/msg1_role", lc.messages[1]["role"] == "assistant", f"msg1={lc.messages[1]}")
    check("llm_call_payload/temperature", lc.temperature == 0.7, f"temp={lc.temperature}")
    check("llm_call_payload/max_tokens", lc.max_tokens == 4096, f"max_tokens={lc.max_tokens}")


def test_text_response():
    data = read_json("text_response")
    tr = TextResponse.model_validate(data)
    check("text_response/content", tr.content == "Here is the result of your query.", f"content={tr.content}")
    check("text_response/finished", tr.finished is True, f"finished={tr.finished}")


def test_wait_payload():
    data = read_json("wait_payload")
    w = Wait.model_validate(data)
    check("wait_payload/reason", w.reason == "Waiting for file upload to complete", f"reason={w.reason}")
    check("wait_payload/duration_seconds", w.duration_seconds == 30, f"dur={w.duration_seconds}")
    check("wait_payload/poll_endpoint", w.poll_endpoint == "https://example.com/status", f"poll={w.poll_endpoint}")


def test_delegate_payload():
    data = read_json("delegate_payload")
    d = Delegate.model_validate(data)
    check("delegate_payload/agent", d.agent == "code-reviewer", f"agent={d.agent}")
    check("delegate_payload/task", d.task == "Review the authentication module for SQL injection vulnerabilities", f"task={d.task}")
    check("delegate_payload/context", d.context == "Focus on the login endpoint and password reset flow", f"ctx={d.context}")
    check("delegate_payload/model", d.model == "deepseek-v4-flash", f"model={d.model}")
    check("delegate_payload/provider", d.provider == "opencode-go", f"provider={d.provider}")


def test_end_payload():
    data = read_json("end_payload")
    e = End.model_validate(data)
    check("end_payload/reason", e.reason == "task_complete", f"reason={e.reason}")
    check("end_payload/summary", e.summary == "All requested tasks have been completed successfully.", f"summary={e.summary}")


def test_error_detail():
    data = read_json("error_detail")
    ed = ErrorDetail.model_validate(data)
    # Go ErrorDetail has details, Python has field — we verify what Python has
    check("error_detail/code", ed.code == "SESSION_NOT_FOUND", f"code={ed.code}")
    check("error_detail/message", ed.message == "Session sess-999 was not found", f"message={ed.message}")
    # Go's details field is ignored by Pydantic extra=ignore; Python's field is None


def test_error_response():
    data = read_json("error_response")
    er = ErrorResponse.model_validate(data)
    # error is dict[str, Any] in Python
    check("error_response/code", er.error.get("code") == "INVALID_REQUEST", f"code={er.error.get('code')}")
    check("error_response/message", er.error.get("message") == "Missing required field: session_id", f"msg={er.error.get('message')}")


def test_result_payload():
    data = read_json("result_payload")
    rp = ResultPayload.model_validate(data)
    check("result_payload/type", rp.type == "tool_result", f"type={rp.type}")
    check("result_payload/tool_name", rp.tool_name == "read_file", f"tool_name={rp.tool_name}")
    check("result_payload/success", rp.success is True, f"success={rp.success}")
    check("result_payload/duration_ms", rp.duration_ms == 150, f"duration_ms={rp.duration_ms}")


def test_capability():
    data = read_json("capability")
    expected = ["tool_call", "llm_call", "text", "wait", "delegate", "end"]
    check("capability/list", data == expected, f"got={data}")


# ── Request/Response types ──

def test_process_request():
    data = read_json("process_request")
    pr = ProcessRequest.model_validate(data)
    check("pr/session_id", pr.session_id == "sess-rt-001", f"sid={pr.session_id}")
    check("pr/message/role", pr.message.role == "user", f"role={pr.message.role}")
    check("pr/message/content", pr.message.content == "Please analyze this image.", f"content={pr.message.content}")
    check("pr/message/att_len", len(pr.message.attachments or []) == 1, f"att_len={len(pr.message.attachments or [])}")
    check("pr/identity/platform", pr.identity.platform == "telegram", f"plat={pr.identity.platform}")
    check("pr/identity/chat_id", pr.identity.chat_id == "-1001234567890", f"chat={pr.identity.chat_id}")
    check("pr/identity/user_name", pr.identity.user_name == "testuser", f"uname={pr.identity.user_name}")
    check("pr/identity/user_id", pr.identity.user_id == "987654", f"uid={pr.identity.user_id}")
    check("pr/context/config/max_iterations", pr.context.config.max_iterations == 100, f"mi={pr.context.config.max_iterations}")
    check("pr/context/history_len", len(pr.context.history) == 2, f"hlen={len(pr.context.history)}")
    check("pr/context/tools_len", len(pr.context.tools) == 1, f"tlen={len(pr.context.tools)}")
    check("pr/context/models_len", len(pr.context.models) == 1, f"mlen={len(pr.context.models)}")
    check("pr/context/memory", pr.context.memory == "user prefers concise answers", f"mem={pr.context.memory}")
    check("pr/context/skills_len", len(pr.context.skills or []) == 1, f"sklen={len(pr.context.skills or [])}")
    check("pr/context/session_state/turn_count", pr.context.session_state.turn_count == 1, f"sst={pr.context.session_state.turn_count}")


def _verify_decision_common(d: Decision, expected_decision: DecisionType, expected_id: str) -> None:
    """Verify common Decision fields."""
    name = f"decision_{expected_decision.value}"
    check(f"{name}/decision", d.decision == expected_decision, f"got={d.decision}")
    check(f"{name}/decision_id", d.decision_id == expected_id, f"got={d.decision_id}")
    check(f"{name}/history_len", len(d.history) == 2, f"got={len(d.history)}")
    check(f"{name}/history0_role", d.history[0].role == "user", f"got={d.history[0].role}")
    check(f"{name}/history0_content", d.history[0].content == "Hello", f"got={d.history[0].content}")


def test_decision_text():
    data = read_json("decision_text")
    d = Decision.model_validate(data)
    _verify_decision_common(d, DecisionType.TEXT, "dec-rt-text")
    check("decision_text/text", d.text is not None, "text is None")
    check("decision_text/text/content", d.text.content == "Here is the result of your query.", f"got={d.text.content}")
    check("decision_text/text/finished", d.text.finished is True, f"got={d.text.finished}")


def test_decision_tool_call():
    data = read_json("decision_tool_call")
    d = Decision.model_validate(data)
    _verify_decision_common(d, DecisionType.TOOL_CALL, "dec-rt-tool_call")
    check("decision_tool_call/tool_call", d.tool_call is not None, "tool_call is None")
    check("decision_tool_call/name", d.tool_call.name == "read_file", f"got={d.tool_call.name}")
    check("decision_tool_call/reasoning", d.tool_call.reasoning == "Need to check configuration", f"got={d.tool_call.reasoning}")


def test_decision_llm_call():
    data = read_json("decision_llm_call")
    d = Decision.model_validate(data)
    _verify_decision_common(d, DecisionType.LLM_CALL, "dec-rt-llm_call")
    check("decision_llm_call/llm_call", d.llm_call is not None, "llm_call is None")
    check("decision_llm_call/model", d.llm_call.model == "deepseek-v4-pro", f"got={d.llm_call.model}")
    check("decision_llm_call/system_prompt", d.llm_call.system_prompt == "You are a helpful assistant.", f"got={d.llm_call.system_prompt}")
    check("decision_llm_call/msgs_len", len(d.llm_call.messages) == 1, f"got={len(d.llm_call.messages)}")
    check("decision_llm_call/temperature", d.llm_call.temperature == 0.7, f"got={d.llm_call.temperature}")
    check("decision_llm_call/max_tokens", d.llm_call.max_tokens == 4096, f"got={d.llm_call.max_tokens}")


def test_decision_wait():
    data = read_json("decision_wait")
    d = Decision.model_validate(data)
    _verify_decision_common(d, DecisionType.WAIT, "dec-rt-wait")
    check("decision_wait/wait", d.wait is not None, "wait is None")
    check("decision_wait/reason", d.wait.reason == "Waiting for external API response", f"got={d.wait.reason}")
    check("decision_wait/duration_seconds", d.wait.duration_seconds == 60, f"got={d.wait.duration_seconds}")
    check("decision_wait/poll_endpoint", d.wait.poll_endpoint == "https://api.example.com/status", f"got={d.wait.poll_endpoint}")


def test_decision_delegate():
    data = read_json("decision_delegate")
    d = Decision.model_validate(data)
    _verify_decision_common(d, DecisionType.DELEGATE, "dec-rt-delegate")
    check("decision_delegate/delegate", d.delegate is not None, "delegate is None")
    check("decision_delegate/agent", d.delegate.agent == "code-reviewer", f"got={d.delegate.agent}")
    check("decision_delegate/task", d.delegate.task == "Review the auth module", f"got={d.delegate.task}")
    check("decision_delegate/context", d.delegate.context == "Focus on SQL injection", f"got={d.delegate.context}")


def test_decision_end():
    data = read_json("decision_end")
    d = Decision.model_validate(data)
    _verify_decision_common(d, DecisionType.END, "dec-rt-end")
    check("decision_end/end", d.end is not None, "end is None")
    check("decision_end/reason", d.end.reason == "task_complete", f"got={d.end.reason}")
    check("decision_end/summary", d.end.summary == "All tasks finished successfully.", f"got={d.end.summary}")


def test_result_request():
    data = read_json("result_request")
    rr = ResultRequest.model_validate(data)
    check("result_request/session_id", rr.session_id == "sess-rt-001", f"got={rr.session_id}")
    check("result_request/decision_id", rr.decision_id == "dec-rt-001", f"got={rr.decision_id}")
    # result is dict[str, Any] in Python
    check("result_request/result/type", rr.result.get("type") == "tool_result", f"got={rr.result.get('type')}")
    check("result_request/result/tool_name", rr.result.get("tool_name") == "read_file", f"got={rr.result.get('tool_name')}")
    check("result_request/result/success", rr.result.get("success") is True, f"got={rr.result.get('success')}")
    check("result_request/result/duration_ms", rr.result.get("duration_ms") == 150, f"got={rr.result.get('duration_ms')}")


def test_cancel_request():
    data = read_json("cancel_request")
    cr = CancelRequest.model_validate(data)
    check("cancel_request/session_id", cr.session_id == "sess-rt-001", f"got={cr.session_id}")
    check("cancel_request/reason", cr.reason == "user_interrupt", f"got={cr.reason}")


def test_health_response():
    data = read_json("health_response")
    hr = HealthResponse.model_validate(data)
    check("health_response/status", hr.status == "ok", f"got={hr.status}")
    check("health_response/version", hr.version == "1.0.0", f"got={hr.version}")
    check("health_response/transport", hr.transport == "rest", f"got={hr.transport}")
    check("health_response/protocol_version", hr.protocol_version == "1.0", f"got={hr.protocol_version}")
    check("health_response/uptime_seconds", hr.uptime_seconds == 3600, f"got={hr.uptime_seconds}")
    check("health_response/active_sessions", hr.active_sessions == 5, f"got={hr.active_sessions}")
    check("health_response/capabilities_len", len(hr.capabilities or []) == 3, f"got={len(hr.capabilities or [])}")


def test_session_response():
    data = read_json("session_response")
    sr = SessionResponse.model_validate(data)
    check("session_response/session_id", sr.session_id == "sess-rt-001", f"got={sr.session_id}")
    check("session_response/started_at", sr.started_at == "2026-07-20T12:00:00Z", f"got={sr.started_at}")
    check("session_response/last_active", sr.last_active == "2026-07-20T12:05:00Z", f"got={sr.last_active}")
    check("session_response/turn_count", sr.turn_count == 3, f"got={sr.turn_count}")
    check("session_response/status", sr.status == "active", f"got={sr.status}")
    check("session_response/current_decision", sr.current_decision == "dec-rt-001", f"got={sr.current_decision}")
    check("session_response/current_decision_type", sr.current_decision_type == "tool_call", f"got={sr.current_decision_type}")


# ── Main ──

def main():
    print("Go→Python fixture verification")
    print("=" * 40)

    tests = [
        ("attachment", test_attachment),
        ("llm_message", test_llm_message),
        ("history_entry", test_history_entry),
        ("tool", test_tool),
        ("model", test_model),
        ("session_state", test_session_state),
        ("config", test_config),
        ("identity", test_identity),
        ("message", test_message),
        ("context", test_context),
        ("tool_call_payload", test_tool_call_payload),
        ("llm_call_payload", test_llm_call_payload),
        ("text_response", test_text_response),
        ("wait_payload", test_wait_payload),
        ("delegate_payload", test_delegate_payload),
        ("end_payload", test_end_payload),
        ("error_detail", test_error_detail),
        ("error_response", test_error_response),
        ("result_payload", test_result_payload),
        ("capability", test_capability),
        ("process_request", test_process_request),
        ("decision_text", test_decision_text),
        ("decision_tool_call", test_decision_tool_call),
        ("decision_llm_call", test_decision_llm_call),
        ("decision_wait", test_decision_wait),
        ("decision_delegate", test_decision_delegate),
        ("decision_end", test_decision_end),
        ("result_request", test_result_request),
        ("cancel_request", test_cancel_request),
        ("health_response", test_health_response),
        ("session_response", test_session_response),
    ]

    for name, fn in tests:
        run_test(name, fn)

    print()
    if failures > 0:
        print(f"{failures} test(s) FAILED")
        sys.exit(1)
    print("All Go→Python fixture verifications passed.")
    sys.exit(0)


if __name__ == "__main__":
    main()
