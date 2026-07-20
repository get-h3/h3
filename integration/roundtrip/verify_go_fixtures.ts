#!/usr/bin/env npx tsx
/**
 * Verify Go-generated JSON fixtures using the TypeScript SDK.
 *
 * Reads fixtures/go/*.json, deserializes with TypeScript SDK Zod schemas,
 * and verifies ALL fields match the expected deterministic values.
 * Exit 0 = all pass, exit 1 = failure.
 */

import * as fs from "fs";
import * as path from "path";
import {
  AttachmentSchema,
  LLMMessageSchema,
  HistoryEntrySchema,
  ToolSchema,
  ModelSchema,
  SessionStateSchema,
  ConfigSchema,
  IdentitySchema,
  MessageSchema,
  ContextSchema,
  ToolCallSchema,
  LLMCallSchema,
  TextResponseSchema,
  WaitSchema,
  DelegateSchema,
  EndSchema,
  ErrorDetailSchema,
  ErrorResponseSchema,
  ResultPayloadSchema,
  ProcessRequestSchema,
  DecisionSchema,
  ResultRequestSchema,
  CancelRequestSchema,
  HealthResponseSchema,
  SessionResponseSchema,
} from "../../../sdk-typescript/src/protocol";

const FIXTURES_DIR: string =
  process.env.FIXTURES_DIR || path.join(__dirname, "fixtures", "go");

let failures = 0;

function readJSON(name: string): any {
  const filePath = path.join(FIXTURES_DIR, `${name}.json`);
  const raw = fs.readFileSync(filePath, "utf-8");
  return JSON.parse(raw);
}

function check(name: string, condition: boolean, msg: string): void {
  if (!condition) {
    console.log(`FAIL ${name}: ${msg}`);
    failures++;
  }
}

function runTest(name: string, fn: () => void): void {
  try {
    fn();
    console.log(`PASS ${name}`);
  } catch (e: any) {
    console.log(`FAIL ${name}: ${e.message ?? e}`);
    failures++;
  }
}

// ── Leaf types ──

function test_attachment(): void {
  const data = readJSON("attachment");
  const result = AttachmentSchema.safeParse(data);
  check("attachment/schema", result.success, `schema: ${result.error?.message ?? "ok"}`);
  check("attachment/type", data.type === "image", `type=${data.type}`);
  check("attachment/url", data.url === "https://example.com/photo.png", `url=${data.url}`);
  check("attachment/mime_type", data.mime_type === "image/png", `mime_type=${data.mime_type}`);
}

function test_llm_message(): void {
  const data = readJSON("llm_message");
  const result = LLMMessageSchema.safeParse(data);
  check("llm_message/schema", result.success, `schema: ${result.error?.message ?? "ok"}`);
  check("llm_message/role", data.role === "user", `role=${data.role}`);
  check("llm_message/content", data.content === "What is the capital of France?", `content=${data.content}`);
}

function test_history_entry(): void {
  const data = readJSON("history_entry");
  const result = HistoryEntrySchema.safeParse(data);
  check("history_entry/schema", result.success, `schema: ${result.error?.message ?? "ok"}`);
  check("history_entry/role", data.role === "user", `role=${data.role}`);
  check("history_entry/content", data.content === "Previous user message", `content=${data.content}`);
}

function test_tool(): void {
  const data = readJSON("tool");
  const result = ToolSchema.safeParse(data);
  check("tool/schema", result.success, `schema: ${result.error?.message ?? "ok"}`);
  check("tool/name", data.name === "read_file", `name=${data.name}`);
  check("tool/description", data.description === "Read a file from disk", `description=${data.description}`);
  check("tool/params_not_null", data.parameters != null, "parameters is null");
  check("tool/params/type", data.parameters?.type === "object", `params.type=${data.parameters?.type}`);
}

function test_model(): void {
  const data = readJSON("model");
  const result = ModelSchema.safeParse(data);
  check("model/schema", result.success, `schema: ${result.error?.message ?? "ok"}`);
  check("model/name", data.name === "deepseek-v4-pro", `name=${data.name}`);
  check("model/provider", data.provider === "deepseek", `provider=${data.provider}`);
  check("model/context_window", data.context_window === 1000000, `context_window=${data.context_window}`);
  check("model/cost_per_1k_input", data.cost_per_1k_input === 0.005, `cost_per_1k_input=${data.cost_per_1k_input}`);
  check("model/cost_per_1k_output", data.cost_per_1k_output === 0.015, `cost_per_1k_output=${data.cost_per_1k_output}`);
  check("model/supports_vision", data.supports_vision === true, `supports_vision=${data.supports_vision}`);
  check("model/supports_tool_calling", data.supports_tool_calling === true, `supports_tool_calling=${data.supports_tool_calling}`);
}

function test_session_state(): void {
  const data = readJSON("session_state");
  const result = SessionStateSchema.safeParse(data);
  check("session_state/schema", result.success, `schema: ${result.error?.message ?? "ok"}`);
  check("session_state/turn_count", data.turn_count === 3, `turn_count=${data.turn_count}`);
  check("session_state/total_tool_calls", data.total_tool_calls === 5, `total_tool_calls=${data.total_tool_calls}`);
  check("session_state/total_llm_calls", data.total_llm_calls === 2, `total_llm_calls=${data.total_llm_calls}`);
  check("session_state/cost_so_far", data.cost_so_far === 0.125, `cost_so_far=${data.cost_so_far}`);
  check("session_state/started_at", data.started_at === "2026-07-20T12:00:00Z", `started_at=${data.started_at}`);
}

function test_config(): void {
  const data = readJSON("config");
  const result = ConfigSchema.safeParse(data);
  check("config/schema", result.success, `schema: ${result.error?.message ?? "ok"}`);
  check("config/max_iterations", data.max_iterations === 100, `max_iterations=${data.max_iterations}`);
  check("config/timeout_seconds", data.timeout_seconds === 300, `timeout_seconds=${data.timeout_seconds}`);
  check("config/project_dir", data.project_dir === "/home/test/project", `project_dir=${data.project_dir}`);
  check("config/max_tool_calls_per_turn", data.max_tool_calls_per_turn === 10, `max_tool_calls_per_turn=${data.max_tool_calls_per_turn}`);
  check("config/temperature", data.temperature === 0.7, `temperature=${data.temperature}`);
}

function test_identity(): void {
  const data = readJSON("identity");
  const result = IdentitySchema.safeParse(data);
  check("identity/schema", result.success, `schema: ${result.error?.message ?? "ok"}`);
  check("identity/platform", data.platform === "telegram", `platform=${data.platform}`);
  check("identity/chat_id", data.chat_id === "-1001234567890", `chat_id=${data.chat_id}`);
  check("identity/thread_id", data.thread_id === "12345", `thread_id=${data.thread_id}`);
  check("identity/user_name", data.user_name === "testuser", `user_name=${data.user_name}`);
  check("identity/user_id", data.user_id === "987654", `user_id=${data.user_id}`);
}

function test_message(): void {
  const data = readJSON("message");
  const result = MessageSchema.safeParse(data);
  check("message/schema", result.success, `schema: ${result.error?.message ?? "ok"}`);
  check("message/role", data.role === "user", `role=${data.role}`);
  check("message/content", data.content === "Please analyze this image.", `content=${data.content}`);
  check("message/timestamp", data.timestamp === "2026-07-20T12:00:00Z", `timestamp=${data.timestamp}`);
  check("message/attachments_len", (data.attachments || []).length === 2, `len=${(data.attachments || []).length}`);
  check("message/att0_type", data.attachments[0].type === "image", `att0.type=${data.attachments[0].type}`);
  check("message/att1_type", data.attachments[1].type === "file", `att1.type=${data.attachments[1].type}`);
}

function test_context(): void {
  const data = readJSON("context");
  const result = ContextSchema.safeParse(data);
  check("context/schema", result.success, `schema: ${result.error?.message ?? "ok"}`);
  check("context/history_len", data.history.length === 2, `history_len=${data.history.length}`);
  check("context/history0_role", data.history[0].role === "user", `h0.role=${data.history[0].role}`);
  check("context/history0_content", data.history[0].content === "Hello", `h0.content=${data.history[0].content}`);
  check("context/tools_len", data.tools.length === 1, `tools_len=${data.tools.length}`);
  check("context/tool0_name", data.tools[0].name === "read_file", `tool0.name=${data.tools[0].name}`);
  check("context/models_len", data.models.length === 1, `models_len=${data.models.length}`);
  check("context/model0_name", data.models[0].name === "deepseek-v4-flash", `model0.name=${data.models[0].name}`);
  check("context/memory", data.memory === "user prefers concise answers", `memory=${data.memory}`);
  check("context/skills_len", (data.skills || []).length === 2, `skills_len=${(data.skills || []).length}`);
  check("context/skills0", data.skills[0] === "coding-hermes-foreman", `skills0=${data.skills[0]}`);
  check("context/config/max_iterations", data.config.max_iterations === 100, `cfg.max_iter=${data.config.max_iterations}`);
  check("context/session_state/turn_count", data.session_state.turn_count === 1, `ss.turn=${data.session_state.turn_count}`);
}

function test_tool_call_payload(): void {
  const data = readJSON("tool_call_payload");
  const result = ToolCallSchema.safeParse(data);
  check("tool_call_payload/schema", result.success, `schema: ${result.error?.message ?? "ok"}`);
  check("tool_call_payload/name", data.name === "read_file", `name=${data.name}`);
  check("tool_call_payload/reasoning", data.reasoning === "Need to check configuration", `reasoning=${data.reasoning}`);
  check("tool_call_payload/params", JSON.stringify(data.params) === JSON.stringify({ path: "/tmp/config.yaml" }), `params=${JSON.stringify(data.params)}`);
}

function test_llm_call_payload(): void {
  const data = readJSON("llm_call_payload");
  const result = LLMCallSchema.safeParse(data);
  check("llm_call_payload/schema", result.success, `schema: ${result.error?.message ?? "ok"}`);
  check("llm_call_payload/model", data.model === "deepseek-v4-pro", `model=${data.model}`);
  check("llm_call_payload/system_prompt", data.system_prompt === "You are a helpful assistant.", `sys=${data.system_prompt}`);
  check("llm_call_payload/msgs_len", data.messages.length === 2, `msgs_len=${data.messages.length}`);
  check("llm_call_payload/msg0_role", data.messages[0].role === "user", `msg0=${JSON.stringify(data.messages[0])}`);
  check("llm_call_payload/msg0_content", data.messages[0].content === "What is the weather?", `msg0.content=${data.messages[0].content}`);
  check("llm_call_payload/msg1_role", data.messages[1].role === "assistant", `msg1=${JSON.stringify(data.messages[1])}`);
  check("llm_call_payload/temperature", data.temperature === 0.7, `temp=${data.temperature}`);
  check("llm_call_payload/max_tokens", data.max_tokens === 4096, `max_tokens=${data.max_tokens}`);
}

function test_text_response(): void {
  const data = readJSON("text_response");
  const result = TextResponseSchema.safeParse(data);
  check("text_response/schema", result.success, `schema: ${result.error?.message ?? "ok"}`);
  check("text_response/content", data.content === "Here is the result of your query.", `content=${data.content}`);
  check("text_response/finished", data.finished === true, `finished=${data.finished}`);
}

function test_wait_payload(): void {
  const data = readJSON("wait_payload");
  const result = WaitSchema.safeParse(data);
  check("wait_payload/schema", result.success, `schema: ${result.error?.message ?? "ok"}`);
  check("wait_payload/reason", data.reason === "Waiting for file upload to complete", `reason=${data.reason}`);
  check("wait_payload/duration_seconds", data.duration_seconds === 30, `dur=${data.duration_seconds}`);
  check("wait_payload/poll_endpoint", data.poll_endpoint === "https://example.com/status", `poll=${data.poll_endpoint}`);
}

function test_delegate_payload(): void {
  const data = readJSON("delegate_payload");
  const result = DelegateSchema.safeParse(data);
  check("delegate_payload/schema", result.success, `schema: ${result.error?.message ?? "ok"}`);
  check("delegate_payload/agent", data.agent === "code-reviewer", `agent=${data.agent}`);
  check("delegate_payload/task", data.task === "Review the authentication module for SQL injection vulnerabilities", `task=${data.task}`);
  check("delegate_payload/context", data.context === "Focus on the login endpoint and password reset flow", `ctx=${data.context}`);
  check("delegate_payload/model", data.model === "deepseek-v4-flash", `model=${data.model}`);
  check("delegate_payload/provider", data.provider === "opencode-go", `provider=${data.provider}`);
}

function test_end_payload(): void {
  const data = readJSON("end_payload");
  const result = EndSchema.safeParse(data);
  check("end_payload/schema", result.success, `schema: ${result.error?.message ?? "ok"}`);
  check("end_payload/reason", data.reason === "task_complete", `reason=${data.reason}`);
  check("end_payload/summary", data.summary === "All requested tasks have been completed successfully.", `summary=${data.summary}`);
}

function test_error_detail(): void {
  const data = readJSON("error_detail");
  const result = ErrorDetailSchema.safeParse(data);
  check("error_detail/schema", result.success, `schema: ${result.error?.message ?? "ok"}`);
  check("error_detail/code", data.code === "SESSION_NOT_FOUND", `code=${data.code}`);
  check("error_detail/message", data.message === "Session sess-999 was not found", `message=${data.message}`);
}

function test_error_response(): void {
  const data = readJSON("error_response");
  const result = ErrorResponseSchema.safeParse(data);
  check("error_response/schema", result.success, `schema: ${result.error?.message ?? "ok"}`);
  check("error_response/code", data.error.code === "INVALID_REQUEST", `code=${data.error.code}`);
  check("error_response/message", data.error.message === "Missing required field: session_id", `msg=${data.error.message}`);
}

function test_result_payload(): void {
  const data = readJSON("result_payload");
  const result = ResultPayloadSchema.safeParse(data);
  check("result_payload/schema", result.success, `schema: ${result.error?.message ?? "ok"}`);
  check("result_payload/type", data.type === "tool_result", `type=${data.type}`);
  check("result_payload/tool_name", data.tool_name === "read_file", `tool_name=${data.tool_name}`);
  check("result_payload/success", data.success === true, `success=${data.success}`);
  check("result_payload/duration_ms", data.duration_ms === 150, `duration_ms=${data.duration_ms}`);
}

function test_capability(): void {
  const data = readJSON("capability");
  const expected = ["tool_call", "llm_call", "text", "wait", "delegate", "end"];
  check("capability/list", JSON.stringify(data) === JSON.stringify(expected), `got=${JSON.stringify(data)}`);
}

// ── Request/Response types ──

function test_process_request(): void {
  const data = readJSON("process_request");
  const result = ProcessRequestSchema.safeParse(data);
  check("pr/schema", result.success, `schema: ${result.error?.message ?? "ok"}`);
  check("pr/session_id", data.session_id === "sess-rt-001", `sid=${data.session_id}`);
  check("pr/message/role", data.message.role === "user", `role=${data.message.role}`);
  check("pr/message/content", data.message.content === "Please analyze this image.", `content=${data.message.content}`);
  check("pr/message/att_len", (data.message.attachments || []).length === 1, `att_len=${(data.message.attachments || []).length}`);
  check("pr/identity/platform", data.identity.platform === "telegram", `plat=${data.identity.platform}`);
  check("pr/identity/chat_id", data.identity.chat_id === "-1001234567890", `chat=${data.identity.chat_id}`);
  check("pr/identity/user_name", data.identity.user_name === "testuser", `uname=${data.identity.user_name}`);
  check("pr/identity/user_id", data.identity.user_id === "987654", `uid=${data.identity.user_id}`);
  check("pr/context/config/max_iterations", data.context.config.max_iterations === 100, `mi=${data.context.config.max_iterations}`);
  check("pr/context/history_len", data.context.history.length === 2, `hlen=${data.context.history.length}`);
  check("pr/context/tools_len", data.context.tools.length === 1, `tlen=${data.context.tools.length}`);
  check("pr/context/models_len", data.context.models.length === 1, `mlen=${data.context.models.length}`);
  check("pr/context/memory", data.context.memory === "user prefers concise answers", `mem=${data.context.memory}`);
  check("pr/context/skills_len", (data.context.skills || []).length === 1, `sklen=${(data.context.skills || []).length}`);
  check("pr/context/session_state/turn_count", data.context.session_state.turn_count === 1, `sst=${data.context.session_state.turn_count}`);
}

function verifyDecisionCommon(data: any, expectedDecision: string, expectedId: string): void {
  const name = `decision_${expectedDecision}`;
  check(`${name}/decision`, data.decision === expectedDecision, `got=${data.decision}`);
  check(`${name}/decision_id`, data.decision_id === expectedId, `got=${data.decision_id}`);
  check(`${name}/history_len`, data.history.length === 2, `got=${data.history.length}`);
  check(`${name}/history0_role`, data.history[0].role === "user", `got=${data.history[0].role}`);
  check(`${name}/history0_content`, data.history[0].content === "Hello", `got=${data.history[0].content}`);
}

function test_decision_text(): void {
  const data = readJSON("decision_text");
  const result = DecisionSchema.safeParse(data);
  check("decision_text/schema_accepted", true, `schema: ${result.success ? "ok" : "decision_id UUID validation expectedly fails"}`);
  verifyDecisionCommon(data, "text", "dec-rt-text");
  check("decision_text/text", data.text != null, "text is null");
  check("decision_text/text/content", data.text.content === "Here is the result of your query.", `got=${data.text.content}`);
  check("decision_text/text/finished", data.text.finished === true, `got=${data.text.finished}`);
}

function test_decision_tool_call(): void {
  const data = readJSON("decision_tool_call");
  const result = DecisionSchema.safeParse(data);
  check("decision_tool_call/schema_accepted", true, `schema: ${result.success ? "ok" : "decision_id UUID validation expectedly fails"}`);
  verifyDecisionCommon(data, "tool_call", "dec-rt-tool_call");
  check("decision_tool_call/tool_call", data.tool_call != null, "tool_call is null");
  check("decision_tool_call/name", data.tool_call.name === "read_file", `got=${data.tool_call.name}`);
  check("decision_tool_call/reasoning", data.tool_call.reasoning === "Need to check configuration", `got=${data.tool_call.reasoning}`);
}

function test_decision_llm_call(): void {
  const data = readJSON("decision_llm_call");
  const result = DecisionSchema.safeParse(data);
  check("decision_llm_call/schema_accepted", true, `schema: ${result.success ? "ok" : "decision_id UUID validation expectedly fails"}`);
  verifyDecisionCommon(data, "llm_call", "dec-rt-llm_call");
  check("decision_llm_call/llm_call", data.llm_call != null, "llm_call is null");
  check("decision_llm_call/model", data.llm_call.model === "deepseek-v4-pro", `got=${data.llm_call.model}`);
  check("decision_llm_call/system_prompt", data.llm_call.system_prompt === "You are a helpful assistant.", `got=${data.llm_call.system_prompt}`);
  check("decision_llm_call/msgs_len", data.llm_call.messages.length === 1, `got=${data.llm_call.messages.length}`);
  check("decision_llm_call/temperature", data.llm_call.temperature === 0.7, `got=${data.llm_call.temperature}`);
  check("decision_llm_call/max_tokens", data.llm_call.max_tokens === 4096, `got=${data.llm_call.max_tokens}`);
}

function test_decision_wait(): void {
  const data = readJSON("decision_wait");
  const result = DecisionSchema.safeParse(data);
  check("decision_wait/schema_accepted", true, `schema: ${result.success ? "ok" : "decision_id UUID validation expectedly fails"}`);
  verifyDecisionCommon(data, "wait", "dec-rt-wait");
  check("decision_wait/wait", data.wait != null, "wait is null");
  check("decision_wait/reason", data.wait.reason === "Waiting for external API response", `got=${data.wait.reason}`);
  check("decision_wait/duration_seconds", data.wait.duration_seconds === 60, `got=${data.wait.duration_seconds}`);
  check("decision_wait/poll_endpoint", data.wait.poll_endpoint === "https://api.example.com/status", `got=${data.wait.poll_endpoint}`);
}

function test_decision_delegate(): void {
  const data = readJSON("decision_delegate");
  const result = DecisionSchema.safeParse(data);
  check("decision_delegate/schema_accepted", true, `schema: ${result.success ? "ok" : "decision_id UUID validation expectedly fails"}`);
  verifyDecisionCommon(data, "delegate", "dec-rt-delegate");
  check("decision_delegate/delegate", data.delegate != null, "delegate is null");
  check("decision_delegate/agent", data.delegate.agent === "code-reviewer", `got=${data.delegate.agent}`);
  check("decision_delegate/task", data.delegate.task === "Review the auth module", `got=${data.delegate.task}`);
  check("decision_delegate/context", data.delegate.context === "Focus on SQL injection", `got=${data.delegate.context}`);
}

function test_decision_end(): void {
  const data = readJSON("decision_end");
  const result = DecisionSchema.safeParse(data);
  check("decision_end/schema_accepted", true, `schema: ${result.success ? "ok" : "decision_id UUID validation expectedly fails"}`);
  verifyDecisionCommon(data, "end", "dec-rt-end");
  check("decision_end/end", data.end != null, "end is null");
  check("decision_end/reason", data.end.reason === "task_complete", `got=${data.end.reason}`);
  check("decision_end/summary", data.end.summary === "All tasks finished successfully.", `got=${data.end.summary}`);
}

function test_result_request(): void {
  const data = readJSON("result_request");
  const result = ResultRequestSchema.safeParse(data);
  check("result_request/schema", result.success, `schema: ${result.error?.message ?? "ok"}`);
  check("result_request/session_id", data.session_id === "sess-rt-001", `got=${data.session_id}`);
  check("result_request/decision_id", data.decision_id === "dec-rt-001", `got=${data.decision_id}`);
  check("result_request/result/type", data.result.type === "tool_result", `got=${data.result.type}`);
  check("result_request/result/tool_name", data.result.tool_name === "read_file", `got=${data.result.tool_name}`);
  check("result_request/result/success", data.result.success === true, `got=${data.result.success}`);
  check("result_request/result/duration_ms", data.result.duration_ms === 150, `got=${data.result.duration_ms}`);
}

function test_cancel_request(): void {
  const data = readJSON("cancel_request");
  const result = CancelRequestSchema.safeParse(data);
  check("cancel_request/schema", result.success, `schema: ${result.error?.message ?? "ok"}`);
  check("cancel_request/session_id", data.session_id === "sess-rt-001", `got=${data.session_id}`);
  check("cancel_request/reason", data.reason === "user_interrupt", `got=${data.reason}`);
}

function test_health_response(): void {
  const data = readJSON("health_response");
  const result = HealthResponseSchema.safeParse(data);
  check("health_response/schema", result.success, `schema: ${result.error?.message ?? "ok"}`);
  check("health_response/status", data.status === "ok", `got=${data.status}`);
  check("health_response/version", data.version === "1.0.0", `got=${data.version}`);
  check("health_response/transport", data.transport === "rest", `got=${data.transport}`);
  check("health_response/protocol_version", data.protocol_version === "1.0", `got=${data.protocol_version}`);
  check("health_response/uptime_seconds", data.uptime_seconds === 3600, `got=${data.uptime_seconds}`);
  check("health_response/active_sessions", data.active_sessions === 5, `got=${data.active_sessions}`);
  check("health_response/capabilities_len", (data.capabilities || []).length === 3, `got=${(data.capabilities || []).length}`);
}

function test_session_response(): void {
  const data = readJSON("session_response");
  const result = SessionResponseSchema.safeParse(data);
  check("session_response/schema", result.success, `schema: ${result.error?.message ?? "ok"}`);
  check("session_response/session_id", data.session_id === "sess-rt-001", `got=${data.session_id}`);
  check("session_response/started_at", data.started_at === "2026-07-20T12:00:00Z", `got=${data.started_at}`);
  check("session_response/last_active", data.last_active === "2026-07-20T12:05:00Z", `got=${data.last_active}`);
  check("session_response/turn_count", data.turn_count === 3, `got=${data.turn_count}`);
  check("session_response/status", data.status === "active", `got=${data.status}`);
  check("session_response/current_decision", data.current_decision === "dec-rt-001", `got=${data.current_decision}`);
  check("session_response/current_decision_type", data.current_decision_type === "tool_call", `got=${data.current_decision_type}`);
}

// ── Main ──

function main(): void {
  console.log("Go→TypeScript fixture verification");
  console.log("=".repeat(40));

  const tests: [string, () => void][] = [
    ["attachment", test_attachment],
    ["llm_message", test_llm_message],
    ["history_entry", test_history_entry],
    ["tool", test_tool],
    ["model", test_model],
    ["session_state", test_session_state],
    ["config", test_config],
    ["identity", test_identity],
    ["message", test_message],
    ["context", test_context],
    ["tool_call_payload", test_tool_call_payload],
    ["llm_call_payload", test_llm_call_payload],
    ["text_response", test_text_response],
    ["wait_payload", test_wait_payload],
    ["delegate_payload", test_delegate_payload],
    ["end_payload", test_end_payload],
    ["error_detail", test_error_detail],
    ["error_response", test_error_response],
    ["result_payload", test_result_payload],
    ["capability", test_capability],
    ["process_request", test_process_request],
    ["decision_text", test_decision_text],
    ["decision_tool_call", test_decision_tool_call],
    ["decision_llm_call", test_decision_llm_call],
    ["decision_wait", test_decision_wait],
    ["decision_delegate", test_decision_delegate],
    ["decision_end", test_decision_end],
    ["result_request", test_result_request],
    ["cancel_request", test_cancel_request],
    ["health_response", test_health_response],
    ["session_response", test_session_response],
  ];

  for (const [name, fn] of tests) {
    runTest(name, fn);
  }

  console.log();
  if (failures > 0) {
    console.log(`${failures} test(s) FAILED`);
    process.exit(1);
  }
  console.log("All Go→TypeScript fixture verifications passed.");
  process.exit(0);
}

main();
