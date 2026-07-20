// verify-python-fixtures reads Python-generated JSON fixtures and verifies
// the Go SDK deserializes them correctly with all field values matching.
// Exit 0 = all pass, exit 1 = failure.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"reflect"

	"github.com/get-h3/sdk-go/protocol"
)

var fixturesDir = ""

func init() {
	// Allow override via env, default to relative from cmd/verify-python-fixtures/
	if d := os.Getenv("FIXTURES_DIR"); d != "" {
		fixturesDir = d
	} else {
		// Running from integration/roundtrip/
		fixturesDir = "fixtures/python"
	}
}

func main() {
	failures := 0
	run := func(name string, fn func() error) {
		if err := fn(); err != nil {
			fmt.Fprintf(os.Stderr, "FAIL %s: %v\n", name, err)
			failures++
		} else {
			fmt.Printf("PASS %s\n", name)
		}
	}

	// ── Leaf types ──
	run("attachment", verifyAttachment)
	run("llm_message", verifyLLMMessage)
	run("history_entry", verifyHistoryEntry)
	run("tool", verifyTool)
	run("model", verifyModel)
	run("session_state", verifySessionState)
	run("config", verifyConfig)
	run("identity", verifyIdentity)
	run("message", verifyMessage)
	run("context", verifyContext)
	run("tool_call_payload", verifyToolCallPayload)
	run("llm_call_payload", verifyLLMCallPayload)
	run("text_response", verifyTextResponse)
	run("wait_payload", verifyWaitPayload)
	run("delegate_payload", verifyDelegatePayload)
	run("end_payload", verifyEndPayload)
	run("error_detail", verifyErrorDetail)
	run("error_response", verifyErrorResponse)
	run("result_payload", verifyResultPayload)
	run("capability", verifyCapability)

	// ── Request/Response types ──
	run("process_request", verifyProcessRequest)
	run("decision_text", verifyDecisionText)
	run("decision_tool_call", verifyDecisionToolCall)
	run("decision_llm_call", verifyDecisionLLMCall)
	run("decision_wait", verifyDecisionWait)
	run("decision_delegate", verifyDecisionDelegate)
	run("decision_end", verifyDecisionEnd)
	run("result_request", verifyResultRequest)
	run("cancel_request", verifyCancelRequest)
	run("health_response", verifyHealthResponse)
	run("session_response", verifySessionResponse)

	if failures > 0 {
		fmt.Fprintf(os.Stderr, "\n%d test(s) FAILED\n", failures)
		os.Exit(1)
	}
	fmt.Println("\nAll Python→Go fixture verifications passed.")
}

func readJSON(name string, v any) error {
	path := filepath.Join(fixturesDir, name+".json")
	data, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("read %s: %w", path, err)
	}
	if err := json.Unmarshal(data, v); err != nil {
		return fmt.Errorf("unmarshal %s: %w", name, err)
	}
	return nil
}

// ── Verifiers ──

func verifyAttachment() error {
	var a protocol.Attachment
	if err := readJSON("attachment", &a); err != nil {
		return err
	}
	if a.Type != "image" {
		return fmt.Errorf("type: got %q, want %q", a.Type, "image")
	}
	if a.URL != "https://example.com/photo.png" {
		return fmt.Errorf("url: got %q", a.URL)
	}
	if a.MimeType != "image/png" {
		return fmt.Errorf("mime_type: got %q", a.MimeType)
	}
	return nil
}

func verifyLLMMessage() error {
	var m protocol.LLMMessage
	if err := readJSON("llm_message", &m); err != nil {
		return err
	}
	if m.Role != "user" {
		return fmt.Errorf("role: got %q, want %q", m.Role, "user")
	}
	if m.Content != "What is the capital of France?" {
		return fmt.Errorf("content: got %q", m.Content)
	}
	return nil
}

func verifyHistoryEntry() error {
	var h protocol.HistoryEntry
	if err := readJSON("history_entry", &h); err != nil {
		return err
	}
	if h.Role != "user" {
		return fmt.Errorf("role: got %q, want %q", h.Role, "user")
	}
	if h.Content != "Previous user message" {
		return fmt.Errorf("content: got %q", h.Content)
	}
	return nil
}

func verifyTool() error {
	var t protocol.Tool
	if err := readJSON("tool", &t); err != nil {
		return err
	}
	if t.Name != "read_file" {
		return fmt.Errorf("name: got %q", t.Name)
	}
	if t.Description != "Read a file from disk" {
		return fmt.Errorf("description: got %q", t.Description)
	}
	if t.Parameters == nil {
		return fmt.Errorf("parameters is nil")
	}
	return nil
}

func verifyModel() error {
	var m protocol.Model
	if err := readJSON("model", &m); err != nil {
		return err
	}
	if m.Name != "deepseek-v4-pro" {
		return fmt.Errorf("name: got %q", m.Name)
	}
	if m.Provider != "deepseek" {
		return fmt.Errorf("provider: got %q", m.Provider)
	}
	if m.ContextWindow != 1000000 {
		return fmt.Errorf("context_window: got %d", m.ContextWindow)
	}
	if m.CostPer1kInput != 0.005 {
		return fmt.Errorf("cost_per_1k_input: got %f", m.CostPer1kInput)
	}
	if m.CostPer1kOutput != 0.015 {
		return fmt.Errorf("cost_per_1k_output: got %f", m.CostPer1kOutput)
	}
	if !m.SupportsVision {
		return fmt.Errorf("supports_vision: got false, want true")
	}
	if !m.SupportsToolCalling {
		return fmt.Errorf("supports_tool_calling: got false, want true")
	}
	return nil
}

func verifySessionState() error {
	var s protocol.SessionState
	if err := readJSON("session_state", &s); err != nil {
		return err
	}
	if s.TurnCount != 3 {
		return fmt.Errorf("turn_count: got %d", s.TurnCount)
	}
	if s.TotalToolCalls != 5 {
		return fmt.Errorf("total_tool_calls: got %d", s.TotalToolCalls)
	}
	if s.TotalLLMCalls != 2 {
		return fmt.Errorf("total_llm_calls: got %d", s.TotalLLMCalls)
	}
	if s.CostSoFar != 0.125 {
		return fmt.Errorf("cost_so_far: got %f", s.CostSoFar)
	}
	if s.StartedAt != "2026-07-20T12:00:00Z" {
		return fmt.Errorf("started_at: got %q", s.StartedAt)
	}
	return nil
}

func verifyConfig() error {
	var c protocol.Config
	if err := readJSON("config", &c); err != nil {
		return err
	}
	if c.MaxIterations != 100 {
		return fmt.Errorf("max_iterations: got %d", c.MaxIterations)
	}
	if c.TimeoutSeconds != 300 {
		return fmt.Errorf("timeout_seconds: got %d", c.TimeoutSeconds)
	}
	if c.ProjectDir != "/home/test/project" {
		return fmt.Errorf("project_dir: got %q", c.ProjectDir)
	}
	if c.MaxToolCallsPerTurn != 10 {
		return fmt.Errorf("max_tool_calls_per_turn: got %d", c.MaxToolCallsPerTurn)
	}
	if c.Temperature == nil || *c.Temperature != 0.7 {
		return fmt.Errorf("temperature: got %v", c.Temperature)
	}
	return nil
}

func verifyIdentity() error {
	var id protocol.Identity
	if err := readJSON("identity", &id); err != nil {
		return err
	}
	if id.Platform != "telegram" {
		return fmt.Errorf("platform: got %q", id.Platform)
	}
	if id.ChatID != "-1001234567890" {
		return fmt.Errorf("chat_id: got %q", id.ChatID)
	}
	if id.ThreadID != "12345" {
		return fmt.Errorf("thread_id: got %q", id.ThreadID)
	}
	if id.UserName != "testuser" {
		return fmt.Errorf("user_name: got %q", id.UserName)
	}
	if id.UserID != "987654" {
		return fmt.Errorf("user_id: got %q", id.UserID)
	}
	return nil
}

func verifyMessage() error {
	var m protocol.Message
	if err := readJSON("message", &m); err != nil {
		return err
	}
	if m.Role != "user" {
		return fmt.Errorf("role: got %q", m.Role)
	}
	if m.Content != "Please analyze this image." {
		return fmt.Errorf("content: got %q", m.Content)
	}
	if m.Timestamp != "2026-07-20T12:00:00Z" {
		return fmt.Errorf("timestamp: got %q", m.Timestamp)
	}
	if len(m.Attachments) != 2 {
		return fmt.Errorf("attachments len: got %d, want 2", len(m.Attachments))
	}
	if m.Attachments[0].Type != "image" {
		return fmt.Errorf("attachments[0].type: got %q", m.Attachments[0].Type)
	}
	if m.Attachments[1].Type != "file" {
		return fmt.Errorf("attachments[1].type: got %q", m.Attachments[1].Type)
	}
	return nil
}

func verifyContext() error {
	var c protocol.Context
	if err := readJSON("context", &c); err != nil {
		return err
	}
	if len(c.History) != 2 {
		return fmt.Errorf("history len: got %d, want 2", len(c.History))
	}
	if c.History[0].Role != "user" || c.History[0].Content != "Hello" {
		return fmt.Errorf("history[0]: got role=%q content=%q", c.History[0].Role, c.History[0].Content)
	}
	if len(c.Tools) != 1 {
		return fmt.Errorf("tools len: got %d, want 1", len(c.Tools))
	}
	if c.Tools[0].Name != "read_file" {
		return fmt.Errorf("tools[0].name: got %q", c.Tools[0].Name)
	}
	if len(c.Models) != 1 {
		return fmt.Errorf("models len: got %d, want 1", len(c.Models))
	}
	if c.Models[0].Name != "deepseek-v4-flash" {
		return fmt.Errorf("models[0].name: got %q", c.Models[0].Name)
	}
	if c.Memory != "user prefers concise answers" {
		return fmt.Errorf("memory: got %q", c.Memory)
	}
	if len(c.Skills) != 2 {
		return fmt.Errorf("skills len: got %d, want 2", len(c.Skills))
	}
	if c.Skills[0] != "coding-hermes-foreman" {
		return fmt.Errorf("skills[0]: got %q", c.Skills[0])
	}
	if c.Config.MaxIterations != 100 {
		return fmt.Errorf("config.max_iterations: got %d", c.Config.MaxIterations)
	}
	if c.SessionState.TurnCount != 1 {
		return fmt.Errorf("session_state.turn_count: got %d", c.SessionState.TurnCount)
	}
	return nil
}

func verifyToolCallPayload() error {
	var tc protocol.ToolCall
	if err := readJSON("tool_call_payload", &tc); err != nil {
		return err
	}
	if tc.Name != "read_file" {
		return fmt.Errorf("name: got %q", tc.Name)
	}
	if tc.Reasoning != "Need to check configuration" {
		return fmt.Errorf("reasoning: got %q", tc.Reasoning)
	}
	// Params is any, check it's a map with expected key
	params, ok := tc.Params.(map[string]any)
	if !ok {
		return fmt.Errorf("params: not a map, got %T", tc.Params)
	}
	if params["path"] != "/tmp/config.yaml" {
		return fmt.Errorf("params.path: got %v", params["path"])
	}
	return nil
}

func verifyLLMCallPayload() error {
	var lc protocol.LLMCall
	if err := readJSON("llm_call_payload", &lc); err != nil {
		return err
	}
	if lc.Model != "deepseek-v4-pro" {
		return fmt.Errorf("model: got %q", lc.Model)
	}
	if lc.SystemPrompt != "You are a helpful assistant." {
		return fmt.Errorf("system_prompt: got %q", lc.SystemPrompt)
	}
	if len(lc.Messages) != 2 {
		return fmt.Errorf("messages len: got %d, want 2", len(lc.Messages))
	}
	if lc.Messages[0].Role != "user" || lc.Messages[0].Content != "What is the weather?" {
		return fmt.Errorf("messages[0]: role=%q content=%q", lc.Messages[0].Role, lc.Messages[0].Content)
	}
	if lc.Temperature == nil || *lc.Temperature != 0.7 {
		return fmt.Errorf("temperature: got %v", lc.Temperature)
	}
	if lc.MaxTokens == nil || *lc.MaxTokens != 4096 {
		return fmt.Errorf("max_tokens: got %v", lc.MaxTokens)
	}
	return nil
}

func verifyTextResponse() error {
	var tr protocol.TextResp
	if err := readJSON("text_response", &tr); err != nil {
		return err
	}
	if tr.Content != "Here is the result of your query." {
		return fmt.Errorf("content: got %q", tr.Content)
	}
	if !tr.Finished {
		return fmt.Errorf("finished: got false, want true")
	}
	return nil
}

func verifyWaitPayload() error {
	var w protocol.Wait
	if err := readJSON("wait_payload", &w); err != nil {
		return err
	}
	if w.Reason != "Waiting for file upload to complete" {
		return fmt.Errorf("reason: got %q", w.Reason)
	}
	if w.DurationSeconds == nil || *w.DurationSeconds != 30 {
		return fmt.Errorf("duration_seconds: got %v", w.DurationSeconds)
	}
	if w.PollEndpoint != "https://example.com/status" {
		return fmt.Errorf("poll_endpoint: got %q", w.PollEndpoint)
	}
	return nil
}

func verifyDelegatePayload() error {
	var d protocol.Delegate
	if err := readJSON("delegate_payload", &d); err != nil {
		return err
	}
	if d.Agent != "code-reviewer" {
		return fmt.Errorf("agent: got %q", d.Agent)
	}
	if d.Task != "Review the authentication module for SQL injection vulnerabilities" {
		return fmt.Errorf("task: got %q", d.Task)
	}
	if d.Context != "Focus on the login endpoint and password reset flow" {
		return fmt.Errorf("context: got %q", d.Context)
	}
	if d.Model != "deepseek-v4-flash" {
		return fmt.Errorf("model: got %q", d.Model)
	}
	if d.Provider != "opencode-go" {
		return fmt.Errorf("provider: got %q", d.Provider)
	}
	return nil
}

func verifyEndPayload() error {
	var e protocol.End
	if err := readJSON("end_payload", &e); err != nil {
		return err
	}
	if e.Reason != "task_complete" {
		return fmt.Errorf("reason: got %q", e.Reason)
	}
	if e.Summary != "All requested tasks have been completed successfully." {
		return fmt.Errorf("summary: got %q", e.Summary)
	}
	return nil
}

func verifyErrorDetail() error {
	var ed protocol.ErrorDetail
	if err := readJSON("error_detail", &ed); err != nil {
		return err
	}
	if ed.Code != "SESSION_NOT_FOUND" {
		return fmt.Errorf("code: got %q", ed.Code)
	}
	if ed.Message != "Session sess-999 was not found" {
		return fmt.Errorf("message: got %q", ed.Message)
	}
	// Python ErrorDetail has field instead of details; we don't test what we don't have
	return nil
}

func verifyErrorResponse() error {
	var er protocol.ErrorResponse
	if err := readJSON("error_response", &er); err != nil {
		return err
	}
	if er.Error.Code != "INVALID_REQUEST" {
		return fmt.Errorf("error.code: got %q", er.Error.Code)
	}
	if er.Error.Message != "Missing required field: session_id" {
		return fmt.Errorf("error.message: got %q", er.Error.Message)
	}
	return nil
}

func verifyResultPayload() error {
	var r protocol.Result
	if err := readJSON("result_payload", &r); err != nil {
		return err
	}
	if r.Type != "tool_result" {
		return fmt.Errorf("type: got %q", r.Type)
	}
	if r.ToolName != "read_file" {
		return fmt.Errorf("tool_name: got %q", r.ToolName)
	}
	if !r.Success {
		return fmt.Errorf("success: got false, want true")
	}
	if r.DurationMs != 150 {
		return fmt.Errorf("duration_ms: got %f", r.DurationMs)
	}
	return nil
}

func verifyCapability() error {
	path := filepath.Join(fixturesDir, "capability.json")
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	var caps []string
	if err := json.Unmarshal(data, &caps); err != nil {
		return err
	}
	expected := []string{"tool_call", "llm_call", "text", "wait", "delegate", "end"}
	if !reflect.DeepEqual(caps, expected) {
		return fmt.Errorf("capabilities: got %v, want %v", caps, expected)
	}
	return nil
}

// ── Request/Response verifiers ──

func verifyProcessRequest() error {
	var pr protocol.ProcessRequest
	if err := readJSON("process_request", &pr); err != nil {
		return err
	}
	if pr.SessionID != "sess-rt-001" {
		return fmt.Errorf("session_id: got %q", pr.SessionID)
	}
	if pr.Message.Role != "user" {
		return fmt.Errorf("message.role: got %q", pr.Message.Role)
	}
	if pr.Message.Content != "Please analyze this image." {
		return fmt.Errorf("message.content: got %q", pr.Message.Content)
	}
	if len(pr.Message.Attachments) != 1 {
		return fmt.Errorf("message.attachments len: got %d", len(pr.Message.Attachments))
	}
	if pr.Identity.Platform != "telegram" {
		return fmt.Errorf("identity.platform: got %q", pr.Identity.Platform)
	}
	if pr.Identity.ChatID != "-1001234567890" {
		return fmt.Errorf("identity.chat_id: got %q", pr.Identity.ChatID)
	}
	if pr.Identity.UserName != "testuser" {
		return fmt.Errorf("identity.user_name: got %q", pr.Identity.UserName)
	}
	if pr.Identity.UserID != "987654" {
		return fmt.Errorf("identity.user_id: got %q", pr.Identity.UserID)
	}
	if pr.Context.Config.MaxIterations != 100 {
		return fmt.Errorf("context.config.max_iterations: got %d", pr.Context.Config.MaxIterations)
	}
	if len(pr.Context.History) != 2 {
		return fmt.Errorf("context.history len: got %d", len(pr.Context.History))
	}
	if len(pr.Context.Tools) != 1 {
		return fmt.Errorf("context.tools len: got %d", len(pr.Context.Tools))
	}
	if len(pr.Context.Models) != 1 {
		return fmt.Errorf("context.models len: got %d", len(pr.Context.Models))
	}
	if pr.Context.Memory != "user prefers concise answers" {
		return fmt.Errorf("context.memory: got %q", pr.Context.Memory)
	}
	if len(pr.Context.Skills) != 1 || pr.Context.Skills[0] != "coding-hermes-foreman" {
		return fmt.Errorf("context.skills: got %v", pr.Context.Skills)
	}
	if pr.Context.SessionState.TurnCount != 1 {
		return fmt.Errorf("context.session_state.turn_count: got %d", pr.Context.SessionState.TurnCount)
	}
	return nil
}

func verifyDecisionText() error {
	var d protocol.Decision
	if err := readJSON("decision_text", &d); err != nil {
		return err
	}
	if d.Decision != protocol.DecisionText {
		return fmt.Errorf("decision: got %q", d.Decision)
	}
	if d.DecisionID != "dec-rt-text" {
		return fmt.Errorf("decision_id: got %q", d.DecisionID)
	}
	if d.Text == nil {
		return fmt.Errorf("text is nil")
	}
	if d.Text.Content != "Here is the result of your query." {
		return fmt.Errorf("text.content: got %q", d.Text.Content)
	}
	if !d.Text.Finished {
		return fmt.Errorf("text.finished: got false")
	}
	if len(d.History) != 2 {
		return fmt.Errorf("history len: got %d", len(d.History))
	}
	// Verify unused variants are nil
	if d.ToolCall != nil || d.LLMCall != nil || d.Wait != nil || d.Delegate != nil || d.End != nil {
		return fmt.Errorf("unused decision variants should be nil")
	}
	return nil
}

func verifyDecisionToolCall() error {
	var d protocol.Decision
	if err := readJSON("decision_tool_call", &d); err != nil {
		return err
	}
	if d.Decision != protocol.DecisionToolCall {
		return fmt.Errorf("decision: got %q", d.Decision)
	}
	if d.DecisionID != "dec-rt-tool_call" {
		return fmt.Errorf("decision_id: got %q", d.DecisionID)
	}
	if d.ToolCall == nil {
		return fmt.Errorf("tool_call is nil")
	}
	if d.ToolCall.Name != "read_file" {
		return fmt.Errorf("tool_call.name: got %q", d.ToolCall.Name)
	}
	if d.ToolCall.Reasoning != "Need to check configuration" {
		return fmt.Errorf("tool_call.reasoning: got %q", d.ToolCall.Reasoning)
	}
	if len(d.History) != 2 {
		return fmt.Errorf("history len: got %d", len(d.History))
	}
	return nil
}

func verifyDecisionLLMCall() error {
	var d protocol.Decision
	if err := readJSON("decision_llm_call", &d); err != nil {
		return err
	}
	if d.Decision != protocol.DecisionLLMCall {
		return fmt.Errorf("decision: got %q", d.Decision)
	}
	if d.DecisionID != "dec-rt-llm_call" {
		return fmt.Errorf("decision_id: got %q", d.DecisionID)
	}
	if d.LLMCall == nil {
		return fmt.Errorf("llm_call is nil")
	}
	if d.LLMCall.Model != "deepseek-v4-pro" {
		return fmt.Errorf("llm_call.model: got %q", d.LLMCall.Model)
	}
	if d.LLMCall.SystemPrompt != "You are a helpful assistant." {
		return fmt.Errorf("llm_call.system_prompt: got %q", d.LLMCall.SystemPrompt)
	}
	if len(d.LLMCall.Messages) != 1 {
		return fmt.Errorf("llm_call.messages len: got %d", len(d.LLMCall.Messages))
	}
	if d.LLMCall.Temperature == nil || *d.LLMCall.Temperature != 0.7 {
		return fmt.Errorf("llm_call.temperature: got %v", d.LLMCall.Temperature)
	}
	if d.LLMCall.MaxTokens == nil || *d.LLMCall.MaxTokens != 4096 {
		return fmt.Errorf("llm_call.max_tokens: got %v", d.LLMCall.MaxTokens)
	}
	return nil
}

func verifyDecisionWait() error {
	var d protocol.Decision
	if err := readJSON("decision_wait", &d); err != nil {
		return err
	}
	if d.Decision != protocol.DecisionWait {
		return fmt.Errorf("decision: got %q", d.Decision)
	}
	if d.DecisionID != "dec-rt-wait" {
		return fmt.Errorf("decision_id: got %q", d.DecisionID)
	}
	if d.Wait == nil {
		return fmt.Errorf("wait is nil")
	}
	if d.Wait.Reason != "Waiting for external API response" {
		return fmt.Errorf("wait.reason: got %q", d.Wait.Reason)
	}
	if d.Wait.DurationSeconds == nil || *d.Wait.DurationSeconds != 60 {
		return fmt.Errorf("wait.duration_seconds: got %v", d.Wait.DurationSeconds)
	}
	if d.Wait.PollEndpoint != "https://api.example.com/status" {
		return fmt.Errorf("wait.poll_endpoint: got %q", d.Wait.PollEndpoint)
	}
	return nil
}

func verifyDecisionDelegate() error {
	var d protocol.Decision
	if err := readJSON("decision_delegate", &d); err != nil {
		return err
	}
	if d.Decision != protocol.DecisionDelegate {
		return fmt.Errorf("decision: got %q", d.Decision)
	}
	if d.DecisionID != "dec-rt-delegate" {
		return fmt.Errorf("decision_id: got %q", d.DecisionID)
	}
	if d.Delegate == nil {
		return fmt.Errorf("delegate is nil")
	}
	if d.Delegate.Agent != "code-reviewer" {
		return fmt.Errorf("delegate.agent: got %q", d.Delegate.Agent)
	}
	if d.Delegate.Task != "Review the auth module" {
		return fmt.Errorf("delegate.task: got %q", d.Delegate.Task)
	}
	if d.Delegate.Context != "Focus on SQL injection" {
		return fmt.Errorf("delegate.context: got %q", d.Delegate.Context)
	}
	return nil
}

func verifyDecisionEnd() error {
	var d protocol.Decision
	if err := readJSON("decision_end", &d); err != nil {
		return err
	}
	if d.Decision != protocol.DecisionEnd {
		return fmt.Errorf("decision: got %q", d.Decision)
	}
	if d.DecisionID != "dec-rt-end" {
		return fmt.Errorf("decision_id: got %q", d.DecisionID)
	}
	if d.End == nil {
		return fmt.Errorf("end is nil")
	}
	if d.End.Reason != "task_complete" {
		return fmt.Errorf("end.reason: got %q", d.End.Reason)
	}
	if d.End.Summary != "All tasks finished successfully." {
		return fmt.Errorf("end.summary: got %q", d.End.Summary)
	}
	return nil
}

func verifyResultRequest() error {
	var rr protocol.ResultRequest
	if err := readJSON("result_request", &rr); err != nil {
		return err
	}
	if rr.SessionID != "sess-rt-001" {
		return fmt.Errorf("session_id: got %q", rr.SessionID)
	}
	if rr.DecisionID != "dec-rt-001" {
		return fmt.Errorf("decision_id: got %q", rr.DecisionID)
	}
	if rr.Result.Type != "tool_result" {
		return fmt.Errorf("result.type: got %q", rr.Result.Type)
	}
	if rr.Result.ToolName != "read_file" {
		return fmt.Errorf("result.tool_name: got %q", rr.Result.ToolName)
	}
	if !rr.Result.Success {
		return fmt.Errorf("result.success: got false")
	}
	if rr.Result.DurationMs != 150 {
		return fmt.Errorf("result.duration_ms: got %f", rr.Result.DurationMs)
	}
	return nil
}

func verifyCancelRequest() error {
	var cr protocol.CancelRequest
	if err := readJSON("cancel_request", &cr); err != nil {
		return err
	}
	if cr.SessionID != "sess-rt-001" {
		return fmt.Errorf("session_id: got %q", cr.SessionID)
	}
	if cr.Reason != "user_interrupt" {
		return fmt.Errorf("reason: got %q", cr.Reason)
	}
	return nil
}

func verifyHealthResponse() error {
	var hr protocol.HealthResponse
	if err := readJSON("health_response", &hr); err != nil {
		return err
	}
	if hr.Status != "ok" {
		return fmt.Errorf("status: got %q", hr.Status)
	}
	if hr.Version != "1.0.0" {
		return fmt.Errorf("version: got %q", hr.Version)
	}
	if hr.Transport != "rest" {
		return fmt.Errorf("transport: got %q", hr.Transport)
	}
	if hr.ProtocolVersion != "1.0" {
		return fmt.Errorf("protocol_version: got %q", hr.ProtocolVersion)
	}
	if hr.UptimeSeconds != 3600 {
		return fmt.Errorf("uptime_seconds: got %d", hr.UptimeSeconds)
	}
	if hr.ActiveSessions != 5 {
		return fmt.Errorf("active_sessions: got %d", hr.ActiveSessions)
	}
	if len(hr.Capabilities) != 3 {
		return fmt.Errorf("capabilities len: got %d, want 3", len(hr.Capabilities))
	}
	return nil
}

func verifySessionResponse() error {
	var sr protocol.SessionResponse
	if err := readJSON("session_response", &sr); err != nil {
		return err
	}
	if sr.SessionID != "sess-rt-001" {
		return fmt.Errorf("session_id: got %q", sr.SessionID)
	}
	if sr.StartedAt != "2026-07-20T12:00:00Z" {
		return fmt.Errorf("started_at: got %q", sr.StartedAt)
	}
	if sr.LastActive != "2026-07-20T12:05:00Z" {
		return fmt.Errorf("last_active: got %q", sr.LastActive)
	}
	if sr.TurnCount != 3 {
		return fmt.Errorf("turn_count: got %d", sr.TurnCount)
	}
	if sr.Status != "active" {
		return fmt.Errorf("status: got %q", sr.Status)
	}
	if sr.CurrentDecision != "dec-rt-001" {
		return fmt.Errorf("current_decision: got %q", sr.CurrentDecision)
	}
	if sr.CurrentDecisionType != "tool_call" {
		return fmt.Errorf("current_decision_type: got %q", sr.CurrentDecisionType)
	}
	return nil
}
