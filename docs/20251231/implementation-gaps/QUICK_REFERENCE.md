# Quick Reference: Implementation Gaps

## Priority Summary

| Priority | Count | Description |
|----------|-------|-------------|
| **P1** | 4 | Critical for feature parity |
| **P2** | 8 | API enhancements |
| **P3** | 5 | Optional improvements |

---

## P1 Gaps (Implement First)

### P1-001: Base Error Hierarchy
**File:** `lib/claude_agent_sdk/errors.ex`
```elixir
# Add to errors.ex
def sdk_error?(%Errors.ClaudeSDKError{}), do: true
def sdk_error?(%Errors.CLIConnectionError{}), do: true
# ... all error types
```

### P1-002: Simple Schema for MCP Tools
**File:** `lib/claude_agent_sdk/tool.ex`
```elixir
# Add map syntax support
def simple_schema(%{a: :float, b: :float})
```

### P1-003: First Result Event Pattern
**File:** `lib/claude_agent_sdk/query/cli_stream.ex`
```elixir
# Wait for result before closing stdin when SDK MCP or hooks present
if has_control_features?(options) do
  wait_for_first_result_then_close(port, timeout_ms)
end
```

### P1-004: Output.async/1 Helper
**File:** `lib/claude_agent_sdk/hooks/output.ex`
```elixir
def async(output \\ %{}), do: Map.put(output, :async, true)
def with_async_timeout(output, ms), do: Map.put(output, :asyncTimeout, ms)
```

---

## Areas Where Elixir Exceeds Python

| Feature | Elixir Advantage |
|---------|------------------|
| Transport | Dual: Port + Erlexec |
| AbortSignal | Full atomic implementation |
| Cancel Requests | Complete handling |
| Agent Switching | `set_agent/2` API |
| Session API | `resume/3`, `continue/2` |
| Streaming | `accumulated` text field |

---

## Testing Commands

```bash
# Run all tests
mix test

# Run specific gap tests
mix test test/claude_agent_sdk/errors_test.exs
mix test test/claude_agent_sdk/tool_test.exs
mix test test/claude_agent_sdk/hooks/output_test.exs
```

---

## Files to Modify

| Gap | Primary File | Test File |
|-----|--------------|-----------|
| P1-001 | `lib/claude_agent_sdk/errors.ex` | `test/claude_agent_sdk/errors_test.exs` |
| P1-002 | `lib/claude_agent_sdk/tool.ex` | `test/claude_agent_sdk/tool_test.exs` |
| P1-003 | `lib/claude_agent_sdk/query/cli_stream.ex` | `test/claude_agent_sdk/query/cli_stream_test.exs` |
| P1-004 | `lib/claude_agent_sdk/hooks/output.ex` | `test/claude_agent_sdk/hooks/output_test.exs` |
