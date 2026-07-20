// generate-go-fixtures creates JSON fixtures using the Go SDK types.
// Output: fixtures/go/*.json
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/get-h3/sdk-go/protocol"
)

var outDir string

func init() {
	if d := os.Getenv("FIXTURES_OUT_DIR"); d != "" {
		outDir = d
	} else {
		outDir = "fixtures/go"
	}
}

func main() {
	if err := os.MkdirAll(outDir, 0755); err != nil {
		fmt.Fprintf(os.Stderr, "mkdir: %v\n", err)
		os.Exit(1)
	}

	fmt.Println("Generating Go fixtures → fixtures/go/")

	dump := func(name string, v any) {
		path := filepath.Join(outDir, name+".json")
		data, err := json.MarshalIndent(v, "", "  ")
		if err != nil {
			fmt.Fprintf(os.Stderr, "marshal %s: %v\n", name, err)
			os.Exit(1)
		}
		if err := os.WriteFile(path, data, 0644); err != nil {
			fmt.Fprintf(os.Stderr, "write %s: %v\n", name, err)
			os.Exit(1)
		}
		fmt.Printf("  Wrote %s\n", path)
	}

	const sid = "sess-rt-001"
	const did = "dec-rt-001"
	const ts = "2026-07-20T12:00:00Z"
	const ts2 = "2026-07-20T12:05:00Z"

	tmp0_7 := 0.7
	tmp4096 := 4096
	dur30 := 30
	dur60 := 60

	// ── Leaf types ──

	dump("attachment", protocol.Attachment{
		Type:     "image",
		URL:      "https://example.com/photo.png",
		MimeType: "image/png",
	})

	dump("llm_message", protocol.LLMMessage{
		Role:    "user",
		Content: "What is the capital of France?",
	})

	dump("history_entry", protocol.HistoryEntry{
		Role:    "user",
		Content: "Previous user message",
	})

	dump("tool", protocol.Tool{
		Name:        "read_file",
		Description: "Read a file from disk",
		Parameters: map[string]any{
			"type": "object",
			"properties": map[string]any{
				"path": map[string]any{"type": "string"},
			},
		},
	})

	dump("model", protocol.Model{
		Name:               "deepseek-v4-pro",
		Provider:           "deepseek",
		ContextWindow:      1000000,
		CostPer1kInput:     0.005,
		CostPer1kOutput:    0.015,
		SupportsVision:     true,
		SupportsToolCalling: true,
	})

	dump("session_state", protocol.SessionState{
		TurnCount:      3,
		TotalToolCalls: 5,
		TotalLLMCalls:  2,
		CostSoFar:      0.125,
		StartedAt:      ts,
	})

	dump("config", protocol.Config{
		MaxIterations:       100,
		TimeoutSeconds:      300,
		ProjectDir:          "/home/test/project",
		MaxToolCallsPerTurn: 10,
		Temperature:         &tmp0_7,
	})

	dump("identity", protocol.Identity{
		Platform: "telegram",
		ChatID:   "-1001234567890",
		ThreadID: "12345",
		UserName: "testuser",
		UserID:   "987654",
	})

	dump("message", protocol.Message{
		Role:    "user",
		Content: "Please analyze this image.",
		Attachments: []protocol.Attachment{
			{Type: "image", URL: "https://example.com/img.png", MimeType: "image/png"},
			{Type: "file", URL: "https://example.com/doc.pdf", MimeType: "application/pdf"},
		},
		Timestamp: ts,
	})

	dump("context", protocol.Context{
		History: []protocol.HistoryEntry{
			{Role: "user", Content: "Hello"},
			{Role: "assistant", Content: "Hi! How can I help?"},
		},
		Tools: []protocol.Tool{
			{
				Name:        "read_file",
				Description: "Read a file",
				Parameters: map[string]any{
					"type": "object",
					"properties": map[string]any{
						"path": map[string]any{"type": "string"},
					},
				},
			},
		},
		Models: []protocol.Model{
			{
				Name:               "deepseek-v4-flash",
				Provider:           "deepseek",
				ContextWindow:      1000000,
				CostPer1kInput:     0.001,
				CostPer1kOutput:    0.005,
				SupportsVision:     false,
				SupportsToolCalling: true,
			},
		},
		Memory: "user prefers concise answers",
		Skills: []string{"coding-hermes-foreman", "python-debugging"},
		Config: protocol.Config{
			MaxIterations:       100,
			TimeoutSeconds:      300,
			ProjectDir:          "/home/test/project",
			MaxToolCallsPerTurn: 10,
			Temperature:         &tmp0_7,
		},
		SessionState: protocol.SessionState{
			TurnCount:      1,
			TotalToolCalls: 0,
			TotalLLMCalls:  0,
			CostSoFar:      0.0,
			StartedAt:      ts,
		},
	})

	dump("tool_call_payload", protocol.ToolCall{
		Name:      "read_file",
		Params:    map[string]any{"path": "/tmp/config.yaml"},
		Reasoning: "Need to check configuration",
	})

	dump("llm_call_payload", protocol.LLMCall{
		Model:        "deepseek-v4-pro",
		SystemPrompt: "You are a helpful assistant.",
		Messages: []protocol.LLMMessage{
			{Role: "user", Content: "What is the weather?"},
			{Role: "assistant", Content: "Let me check that for you."},
		},
		Temperature: &tmp0_7,
		MaxTokens:   &tmp4096,
	})

	dump("text_response", protocol.TextResp{
		Content:  "Here is the result of your query.",
		Finished: true,
	})

	dump("wait_payload", protocol.Wait{
		Reason:          "Waiting for file upload to complete",
		DurationSeconds: &dur30,
		PollEndpoint:    "https://example.com/status",
	})

	dump("delegate_payload", protocol.Delegate{
		Agent:    "code-reviewer",
		Task:     "Review the authentication module for SQL injection vulnerabilities",
		Context:  "Focus on the login endpoint and password reset flow",
		Model:    "deepseek-v4-flash",
		Provider: "opencode-go",
	})

	dump("end_payload", protocol.End{
		Reason:  "task_complete",
		Summary: "All requested tasks have been completed successfully.",
	})

	dump("error_detail", protocol.ErrorDetail{
		Code:    "SESSION_NOT_FOUND",
		Message: "Session sess-999 was not found",
		Details: map[string]any{"session_id": "sess-999"},
	})

	dump("error_response", protocol.ErrorResponse{
		Error: protocol.ErrorDetail{
			Code:    "INVALID_REQUEST",
			Message: "Missing required field: session_id",
			Details: map[string]any{"field": "session_id"},
		},
	})

	dump("result_payload", protocol.Result{
		Type:       "tool_result",
		ToolName:   "read_file",
		Data:       map[string]any{"content": "file contents\nline 2\nline 3"},
		DurationMs: 150,
		Success:    true,
	})

	// Capability — list of DecisionType string values
	dump("capability", []string{"tool_call", "llm_call", "text", "wait", "delegate", "end"})

	// ── Request/Response types ──

	dump("process_request", protocol.ProcessRequest{
		SessionID: sid,
		Message: protocol.Message{
			Role:    "user",
			Content: "Please analyze this image.",
			Attachments: []protocol.Attachment{
				{Type: "image", URL: "https://example.com/img.png", MimeType: "image/png"},
			},
			Timestamp: ts,
		},
		Identity: protocol.Identity{
			Platform: "telegram",
			ChatID:   "-1001234567890",
			ThreadID: "12345",
			UserName: "testuser",
			UserID:   "987654",
		},
		Context: protocol.Context{
			History: []protocol.HistoryEntry{
				{Role: "user", Content: "Hello"},
				{Role: "assistant", Content: "Hi! How can I help?"},
			},
			Tools: []protocol.Tool{
				{
					Name:        "read_file",
					Description: "Read a file",
					Parameters: map[string]any{
						"type": "object",
						"properties": map[string]any{
							"path": map[string]any{"type": "string"},
						},
					},
				},
			},
			Models: []protocol.Model{
				{
					Name:               "deepseek-v4-pro",
					Provider:           "deepseek",
					ContextWindow:      1000000,
					CostPer1kInput:     0.005,
					CostPer1kOutput:    0.015,
					SupportsVision:     true,
					SupportsToolCalling: true,
				},
			},
			Memory: "user prefers concise answers",
			Skills: []string{"coding-hermes-foreman"},
			Config: protocol.Config{
				MaxIterations:       100,
				TimeoutSeconds:      300,
				ProjectDir:          "/home/test/project",
				MaxToolCallsPerTurn: 10,
				Temperature:         &tmp0_7,
			},
			SessionState: protocol.SessionState{
				TurnCount:      1,
				TotalToolCalls: 0,
				TotalLLMCalls:  0,
				CostSoFar:      0.0,
				StartedAt:      ts,
			},
		},
	})

	// Decision — all 6 variants
	dump("decision_text", protocol.Decision{
		Decision:   protocol.DecisionText,
		DecisionID: "dec-rt-text",
		History: []protocol.HistoryEntry{
			{Role: "user", Content: "Hello"},
			{Role: "assistant", Content: "Hi! How can I help?"},
		},
		Text: &protocol.TextResp{
			Content:  "Here is the result of your query.",
			Finished: true,
		},
	})

	dump("decision_tool_call", protocol.Decision{
		Decision:   protocol.DecisionToolCall,
		DecisionID: "dec-rt-tool_call",
		History: []protocol.HistoryEntry{
			{Role: "user", Content: "Hello"},
			{Role: "assistant", Content: "Hi! How can I help?"},
		},
		ToolCall: &protocol.ToolCall{
			Name:      "read_file",
			Params:    map[string]any{"path": "/tmp/config.yaml"},
			Reasoning: "Need to check configuration",
		},
	})

	dump("decision_llm_call", protocol.Decision{
		Decision:   protocol.DecisionLLMCall,
		DecisionID: "dec-rt-llm_call",
		History: []protocol.HistoryEntry{
			{Role: "user", Content: "Hello"},
			{Role: "assistant", Content: "Hi! How can I help?"},
		},
		LLMCall: &protocol.LLMCall{
			Model:        "deepseek-v4-pro",
			SystemPrompt: "You are a helpful assistant.",
			Messages: []protocol.LLMMessage{
				{Role: "user", Content: "What is the weather?"},
			},
			Temperature: &tmp0_7,
			MaxTokens:   &tmp4096,
		},
	})

	dump("decision_wait", protocol.Decision{
		Decision:   protocol.DecisionWait,
		DecisionID: "dec-rt-wait",
		History: []protocol.HistoryEntry{
			{Role: "user", Content: "Hello"},
			{Role: "assistant", Content: "Hi! How can I help?"},
		},
		Wait: &protocol.Wait{
			Reason:          "Waiting for external API response",
			DurationSeconds: &dur60,
			PollEndpoint:    "https://api.example.com/status",
		},
	})

	dump("decision_delegate", protocol.Decision{
		Decision:   protocol.DecisionDelegate,
		DecisionID: "dec-rt-delegate",
		History: []protocol.HistoryEntry{
			{Role: "user", Content: "Hello"},
			{Role: "assistant", Content: "Hi! How can I help?"},
		},
		Delegate: &protocol.Delegate{
			Agent:    "code-reviewer",
			Task:     "Review the auth module",
			Context:  "Focus on SQL injection",
			Model:    "deepseek-v4-flash",
			Provider: "opencode-go",
		},
	})

	dump("decision_end", protocol.Decision{
		Decision:   protocol.DecisionEnd,
		DecisionID: "dec-rt-end",
		History: []protocol.HistoryEntry{
			{Role: "user", Content: "Hello"},
			{Role: "assistant", Content: "Hi! How can I help?"},
		},
		End: &protocol.End{
			Reason:  "task_complete",
			Summary: "All tasks finished successfully.",
		},
	})

	dump("result_request", protocol.ResultRequest{
		SessionID:  sid,
		DecisionID: did,
		Result: protocol.Result{
			Type:       "tool_result",
			ToolName:   "read_file",
			Data:       map[string]any{"content": "file contents here"},
			DurationMs: 150,
			Success:    true,
		},
	})

	dump("cancel_request", protocol.CancelRequest{
		SessionID: sid,
		Reason:    "user_interrupt",
	})

	dump("health_response", protocol.HealthResponse{
		Status:          "ok",
		Version:         "1.0.0",
		Transport:       "rest",
		ProtocolVersion: "1.0",
		UptimeSeconds:   3600,
		ActiveSessions:  5,
		Capabilities:    []protocol.DecisionType{"text", "tool_call", "end"},
	})

	dump("session_response", protocol.SessionResponse{
		SessionID:           sid,
		StartedAt:           ts,
		LastActive:          ts2,
		TurnCount:           3,
		Status:              "active",
		CurrentDecision:     did,
		CurrentDecisionType: "tool_call",
	})

	fmt.Println("\nAll Go fixtures generated successfully.")
}
