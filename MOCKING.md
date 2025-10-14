# Claude Code SDK - Mocking System

The Claude Code SDK includes a comprehensive mocking system for testing without making actual API calls.

## Overview

The mocking system allows you to:
- Run tests without Claude CLI authentication
- Test your code without incurring API costs
- Create predictable test scenarios
- Speed up test execution

## How It Works

1. **Mock Server**: A GenServer that stores mock responses
2. **Mock Process**: Intercepts CLI calls and returns mock data
3. **Configuration**: Simple environment-based switching

## Basic Usage

### Enable Mocking

```elixir
# Enable mocking
Application.put_env(:claude_agent_sdk, :use_mock, true)

# Start the mock server
{:ok, _} = ClaudeAgentSDK.Mock.start_link()
```

### Set Mock Responses

```elixir
# Set a response for prompts containing "hello"
ClaudeAgentSDK.Mock.set_response("hello", [
  %{
    "type" => "assistant",
    "message" => %{"content" => "Hello from mock!"},
    "session_id" => "mock-123"
  }
])

# Now any query containing "hello" will return this response
ClaudeAgentSDK.query("say hello") |> Enum.to_list()
```

### Default Responses

The mock provides default responses for unmatched prompts:

```elixir
# This will get a default response
ClaudeAgentSDK.query("unmatched prompt") |> Enum.to_list()
```

### Custom Default Response

```elixir
ClaudeAgentSDK.Mock.set_default_response([
  %{
    "type" => "assistant",
    "message" => %{"content" => "Custom default response"}
  }
])
```

## Testing

### Running Tests with Mocks (Default)

```bash
# Tests use mocks by default
mix test
```

### Running Tests with Live API

```bash
# Run tests against real Claude API
MIX_ENV=test mix test.live

# Run specific test file with live API
MIX_ENV=test mix test.live test/specific_test.exs
```

## Environment Configuration

### Test Environment (config/test.exs)
```elixir
config :claude_agent_sdk,
  use_mock: true  # Mocks enabled by default in tests
```

### Development Environment (config/dev.exs)
```elixir
config :claude_agent_sdk,
  use_mock: false  # Real API calls in development
```

### Runtime Toggle
```elixir
# Enable mocking at runtime
Application.put_env(:claude_agent_sdk, :use_mock, true)

# Disable mocking at runtime
Application.put_env(:claude_agent_sdk, :use_mock, false)
```

## Mock Response Format

Mock responses should match the Claude CLI JSON format:

```elixir
[
  # System initialization message
  %{
    "type" => "system",
    "subtype" => "init",
    "session_id" => "mock-session-123",
    "model" => "claude-3-opus-20240229",
    "tools" => ["bash", "editor"],
    "cwd" => "/current/dir",
    "permissionMode" => "default",
    "apiKeySource" => "mock"
  },
  
  # Assistant response
  %{
    "type" => "assistant",
    "message" => %{
      "role" => "assistant",
      "content" => "Your response here"
    },
    "session_id" => "mock-session-123"
  },
  
  # Result message
  %{
    "type" => "result",
    "subtype" => "success",
    "session_id" => "mock-session-123",
    "total_cost_usd" => 0.001,
    "duration_ms" => 100,
    "num_turns" => 1,
    "is_error" => false
  }
]
```

## Example Test

```elixir
defmodule MyAppTest do
  use ExUnit.Case
  alias ClaudeAgentSDK.Mock

  setup do
    Mock.clear_responses()
    :ok
  end

  test "code analysis returns expected format" do
    # Set up mock response
    Mock.set_response("analyze", [
      %{
        "type" => "assistant",
        "message" => %{
          "content" => "Code analysis: No issues found."
        }
      }
    ])
    
    # Your code that uses ClaudeAgentSDK
    result = MyApp.analyze_code("def hello, do: :world")
    
    # Assertions
    assert result == "Code analysis: No issues found."
  end
end
```

## Demo Script

Run the included demo to see mocking in action:

```bash
mix run demo_mock.exs
```

## Benefits

1. **Fast Tests**: No network calls, instant responses
2. **Predictable**: Same response every time
3. **No Costs**: Zero API usage during testing
4. **CI/CD Friendly**: No authentication needed
5. **Offline Development**: Work without internet

## Best Practices

1. **Clear Mocks**: Always clear mocks in test setup
2. **Specific Patterns**: Use specific patterns for mock responses
3. **Test Both**: Test with mocks AND occasionally with live API
4. **Document Mocks**: Document what each mock represents
5. **Match Reality**: Keep mock responses similar to real API

## Troubleshooting

### Mock Not Working

```elixir
# Verify mock is enabled
Application.get_env(:claude_agent_sdk, :use_mock)
# Should return true

# Verify mock server is running
Process.whereis(ClaudeAgentSDK.Mock)
# Should return a PID
```

### Wrong Response

```elixir
# Check registered patterns
# The mock uses String.contains? for matching
Mock.set_response("specific phrase", [...])
```

### Mix Task Issues

```bash
# Ensure test environment for mix test.live
MIX_ENV=test mix test.live
```