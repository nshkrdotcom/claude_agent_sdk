# Claude Code SDK - Mocking System Summary

## Overview

A comprehensive mocking system has been implemented for the Claude Code SDK that allows testing without making actual API calls.

## Components

### 1. Mock Server (ClaudeCodeSDK.Mock)
- GenServer that stores mock responses
- Pattern matching for prompts using `String.contains?`
- Default response handling
- Full state reset with `clear_responses/0`

### 2. Mock Process (ClaudeCodeSDK.Mock.Process)
- Intercepts CLI calls when mocking is enabled
- Converts mock data to proper Message structs
- Maintains stream interface compatibility

### 3. Configuration
- Environment-based configuration (`use_mock`)
- Test environment uses mocks by default
- Development/production use real API
- Runtime toggle available

### 4. Mix Tasks
- `mix test` - Uses mocks by default
- `mix test.live` - Forces real API calls

## Usage Example

```elixir
# Enable mocking
Application.put_env(:claude_code_sdk, :use_mock, true)

# Start mock server
{:ok, _} = ClaudeCodeSDK.Mock.start_link()

# Set a mock response
ClaudeCodeSDK.Mock.set_response("hello", [
  %{"type" => "assistant", "message" => %{"content" => "Hello!"}}
])

# Query will return mock response
ClaudeCodeSDK.query("say hello") |> Enum.to_list()
```

## Benefits

1. **Fast Tests**: No network calls
2. **Predictable**: Consistent responses
3. **Zero Cost**: No API usage
4. **CI/CD Ready**: No authentication needed
5. **Offline Development**: Works without internet

## Files Added/Modified

- `lib/claude_code_sdk/mock.ex` - Mock server
- `lib/claude_code_sdk/mock/process.ex` - Mock process handler
- `lib/claude_code_sdk/process.ex` - Added mock support
- `lib/mix/tasks/test.live.ex` - Mix task for live testing
- `config/*.exs` - Environment configurations
- `test/test_helper.exs` - Mock initialization
- `demo_mock.exs` - Demo script
- `MOCKING.md` - Full documentation