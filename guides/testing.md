# Testing Guide for Claude Agent SDK

This guide provides comprehensive documentation for testing applications built with the Claude Agent SDK for Elixir. It covers the mock system, test fixtures, hooks testing, permission callbacks, integration testing patterns, and best practices.

## Table of Contents

1. [Mock System Overview](#mock-system-overview)
2. [Enabling Mock Mode](#enabling-mock-mode)
3. [Setting Mock Responses](#setting-mock-responses)
4. [Mock Response Format](#mock-response-format)
5. [Testing Hooks](#testing-hooks)
6. [Testing Permission Callbacks](#testing-permission-callbacks)
7. [Testing with SupertesterCase](#testing-with-supertestercase)
8. [Integration Testing Patterns](#integration-testing-patterns)
9. [Environment Configuration for Tests](#environment-configuration-for-tests)
10. [Best Practices](#best-practices)

---

## Mock System Overview

The Claude Agent SDK includes a comprehensive mocking system that enables testing without making actual API calls to the Claude service. The mock system consists of three main components:

### Components

1. **Mock Server (`ClaudeAgentSDK.Mock`)**: A GenServer that stores and retrieves mock responses based on prompt patterns.

2. **Mock Process (`ClaudeAgentSDK.Mock.Process`)**: Intercepts CLI calls when mock mode is enabled and returns stored responses.

3. **Mock Transport (`ClaudeAgentSDK.TestSupport.MockTransport`)**: A test transport that records outbound messages and allows pushing inbound frames for testing the control protocol client.

### Benefits

- **Fast Tests**: No network calls, instant responses
- **Predictable**: Deterministic responses for consistent test results
- **No API Costs**: Zero usage charges during testing
- **CI/CD Friendly**: No authentication required
- **Offline Development**: Work without internet connectivity

---

## Enabling Mock Mode

There are multiple ways to enable mock mode depending on your use case.

### Configuration-Based (Recommended for Tests)

Configure mock mode in your `config/test.exs`:

```elixir
# config/test.exs
config :claude_agent_sdk,
  use_mock: true
```

### Runtime Toggle

Enable or disable mocking at runtime:

```elixir
# Enable mocking
Application.put_env(:claude_agent_sdk, :use_mock, true)

# Start the mock server (required)
{:ok, _pid} = ClaudeAgentSDK.Mock.start_link()

# Disable mocking
Application.put_env(:claude_agent_sdk, :use_mock, false)
```

### Test Helper Setup

The SDK's `test_helper.exs` automatically configures mock mode:

```elixir
# test/test_helper.exs
live_tests? = System.get_env("LIVE_TESTS") == "true"

# Enable mocking for tests unless running in live mode
Application.put_env(:claude_agent_sdk, :use_mock, !live_tests?)

# Start the mock server only when mock mode is enabled
unless live_tests? do
  {:ok, _} = ClaudeAgentSDK.Mock.start_link()
end

ExUnit.start(exclude: [:integration, :live], capture_log: true)
```

### Verifying Mock Mode

```elixir
# Check if mock mode is enabled
Application.get_env(:claude_agent_sdk, :use_mock)
# => true or false

# Verify mock server is running
Process.whereis(ClaudeAgentSDK.Mock)
# => PID or nil
```

---

## Setting Mock Responses

### Basic Pattern Matching

Set responses that match prompts containing a specific pattern:

```elixir
alias ClaudeAgentSDK.Mock

# Set a response for prompts containing "hello"
Mock.set_response("hello", [
  %{
    "type" => "assistant",
    "message" => %{"content" => "Hello from mock!"},
    "session_id" => "mock-123"
  }
])

# Any query containing "hello" returns this response
ClaudeAgentSDK.query("say hello") |> Enum.to_list()
```

### Setting Default Responses

Configure a fallback response for unmatched prompts:

```elixir
Mock.set_default_response([
  %{
    "type" => "assistant",
    "message" => %{"content" => "Custom default response"}
  }
])
```

### Clearing Responses

Reset all mock responses between tests:

```elixir
Mock.clear_responses()
```

### Getting Responses Programmatically

Retrieve the response that would be returned for a prompt:

```elixir
response = Mock.get_response("test prompt")
```

---

## Mock Response Format

Mock responses should match the Claude CLI JSON format. A complete response typically includes three message types.

### Complete Response Structure

```elixir
[
  # 1. System initialization message
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

  # 2. Assistant response
  %{
    "type" => "assistant",
    "message" => %{
      "role" => "assistant",
      "content" => "Your response here"
    },
    "session_id" => "mock-session-123"
  },

  # 3. Result message
  %{
    "type" => "result",
    "subtype" => "success",
    "session_id" => "mock-session-123",
    "total_cost_usd" => 0.001,
    "duration_ms" => 100,
    "duration_api_ms" => 50,
    "num_turns" => 1,
    "is_error" => false
  }
]
```

### Message Types Reference

| Type | Description | Key Fields |
|------|-------------|------------|
| `system` | Session initialization | `session_id`, `model`, `cwd`, `tools` |
| `user` | User input | `message`, `session_id` |
| `assistant` | Claude response | `message`, `session_id` |
| `result` | Final result | `total_cost_usd`, `duration_ms`, `num_turns` |

### Result Subtypes

- `success` - Successful completion
- `error_max_turns` - Max turns limit reached
- `error_during_execution` - Error during execution

### Tool Use in Responses

Mock responses can include tool use:

```elixir
%{
  "type" => "assistant",
  "message" => %{
    "role" => "assistant",
    "content" => [
      %{
        "type" => "tool_use",
        "id" => "tool_123",
        "name" => "Bash",
        "input" => %{"command" => "ls -la"}
      }
    ]
  }
}
```

---

## Testing Hooks

The hooks system provides lifecycle event interception for testing security policies, logging, and custom behavior.

### Hook Events

| Event | When Triggered | Use Case |
|-------|----------------|----------|
| `pre_tool_use` | Before tool executes | Security validation, logging |
| `post_tool_use` | After tool executes | Audit trails, monitoring |
| `user_prompt_submit` | When user submits prompt | Context injection |
| `stop` | When agent finishes | Final logging |
| `subagent_stop` | When subagent finishes | Subagent result handling |
| `pre_compact` | Before context compaction | Preserve context |

Note: `session_start`, `session_end`, and `notification` hooks are not supported by the Python SDK and are rejected.

### Creating Test Hooks

```elixir
alias ClaudeAgentSDK.Hooks.{Matcher, Output}

# Hook that allows all tools
allow_all_hook = fn _input, _tool_use_id, _context ->
  Output.allow()
end

# Hook that denies specific tools
deny_dangerous = fn input, _tool_use_id, _context ->
  case input do
    %{"tool_name" => "Bash", "tool_input" => %{"command" => cmd}} ->
      if String.contains?(cmd, "rm -rf") do
        Output.deny("Dangerous command blocked")
      else
        Output.allow()
      end
    _ -> Output.allow()
  end
end

# Hook that records invocations for testing
test_pid = self()
recording_hook = fn input, tool_use_id, context ->
  send(test_pid, {:hook_called, input["tool_name"], input, tool_use_id})
  Output.allow()
end
```

### Configuring Hooks in Options

```elixir
alias ClaudeAgentSDK.{Options, Hooks.Matcher}

options = %Options{
  hooks: %{
    pre_tool_use: [
      Matcher.new("*", [&audit_log/3]),           # Match all tools
      Matcher.new("Bash", [&security_check/3])    # Match specific tool
    ],
    post_tool_use: [
      Matcher.new("*", [&record_result/3])
    ]
  }
}
```

### Testing Hook Behavior

```elixir
defmodule MyApp.HooksTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Mock, Options}
  alias ClaudeAgentSDK.Hooks.{Matcher, Output}

  setup do
    Mock.clear_responses()
    :ok
  end

  test "pre_tool_use hook can deny dangerous commands" do
    test_pid = self()

    deny_dangerous = fn input, _tool_use_id, _context ->
      send(test_pid, {:hook_check, input})

      case input do
        %{"tool_name" => "Bash", "tool_input" => %{"command" => cmd}} ->
          if String.contains?(cmd, "rm -rf") do
            Output.deny("Dangerous command blocked")
          else
            Output.allow()
          end
        _ -> Output.allow()
      end
    end

    options = %Options{
      hooks: %{
        pre_tool_use: [Matcher.new("Bash", [deny_dangerous])]
      }
    }

    # Set up mock response with tool use
    Mock.set_response("delete files", [
      %{
        "type" => "assistant",
        "message" => %{
          "content" => [
            %{
              "type" => "tool_use",
              "name" => "Bash",
              "input" => %{"command" => "rm -rf /"}
            }
          ]
        }
      }
    ])

    _messages = ClaudeAgentSDK.query("delete files", options) |> Enum.to_list()

    # Verify hook was called
    assert_receive {:hook_check, %{"tool_name" => "Bash"}}
  end

  test "recording hook tracks all tool invocations" do
    test_pid = self()
    invocations = :ets.new(:invocations, [:set, :public])

    recording_hook = fn input, tool_use_id, _context ->
      :ets.insert(invocations, {tool_use_id, input["tool_name"]})
      send(test_pid, {:tool_used, input["tool_name"]})
      Output.allow()
    end

    options = %Options{
      hooks: %{
        pre_tool_use: [Matcher.new("*", [recording_hook])]
      }
    }

    # Execute query and verify recording
    _messages = ClaudeAgentSDK.query("list files", options) |> Enum.to_list()

    # Check recorded tools
    recorded = :ets.tab2list(invocations)
    assert length(recorded) > 0
  end
end
```

### Hook Output Types

```elixir
alias ClaudeAgentSDK.Hooks.Output

# Allow execution
Output.allow()
Output.allow("Approved")

# Allow with input modification
Output.allow(updated_input: %{...})

# Deny execution
Output.deny("Reason")
Output.deny("Reason", interrupt: true)  # Stop entire session

# Add context to prompt
Output.add_context("UserPromptSubmit", "Additional context here")

# Add system message
output = Output.allow() |> Output.with_system_message("Logged")
```

---

## Testing Permission Callbacks

Permission callbacks provide fine-grained control over tool execution.

### Permission Context

```elixir
alias ClaudeAgentSDK.Permission.Context

# Context struct contains:
%Context{
  tool_name: "Write",
  tool_input: %{"file_path" => "/etc/hosts", "content" => "..."},
  session_id: "session-123",
  cwd: "/project"
}
```

### Permission Results

```elixir
alias ClaudeAgentSDK.Permission.Result

# Allow
Result.allow()

# Allow with modified input
Result.allow(updated_input: %{"file_path" => "/safe/path"})

# Deny
Result.deny("Reason")

# Deny with interrupt (stops session)
Result.deny("Critical error", interrupt: true)

# Allow with permission updates
Result.allow(updated_permissions: [
  %{"type" => "setMode", "mode" => "plan", "destination" => "session"}
])
```

### Creating Test Permission Callbacks

```elixir
alias ClaudeAgentSDK.Permission.Result

# Allow all
allow_all = fn _context -> Result.allow() end

# Deny all
deny_all = fn _context -> Result.deny("All denied") end

# Recording callback for testing
test_pid = self()
recording_callback = fn context ->
  send(test_pid, {:permission_check, context})
  Result.allow()
end

# Path restriction callback
path_restriction = fn context ->
  allowed_dirs = ["/tmp", "/home/user/project"]

  if context.tool_name in ["Read", "Write"] do
    file_path = context.tool_input["file_path"] || ""

    if Enum.any?(allowed_dirs, &String.starts_with?(file_path, &1)) do
      Result.allow()
    else
      Result.deny("File path outside allowed directories")
    end
  else
    Result.allow()
  end
end
```

### Testing Permission Callbacks

```elixir
defmodule MyApp.PermissionsTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Mock, Options}
  alias ClaudeAgentSDK.Permission.{Context, Result}

  setup do
    Mock.clear_responses()
    :ok
  end

  test "permission callback can redirect file writes" do
    redirect_callback = fn context ->
      if context.tool_name == "Write" do
        file_path = context.tool_input["file_path"]

        if String.starts_with?(file_path, "/etc/") do
          safe_path = "/tmp/safe/" <> Path.basename(file_path)
          Result.allow(
            updated_input: Map.put(context.tool_input, "file_path", safe_path)
          )
        else
          Result.allow()
        end
      else
        Result.allow()
      end
    end

    options = %Options{
      can_use_tool: redirect_callback,
      permission_mode: :default
    }

    # Test that writes to /etc/ are redirected
    # ...
  end

  test "permission callback receives correct context" do
    test_pid = self()

    recording_callback = fn context ->
      send(test_pid, {:context_received, context})
      Result.allow()
    end

    options = %Options{
      can_use_tool: recording_callback,
      permission_mode: :default
    }

    # can_use_tool with query uses the control client (string or streaming prompts)
    prompts = [
      %{"type" => "user", "message" => %{"role" => "user", "content" => "write a file"}}
    ]

    _messages = ClaudeAgentSDK.query(prompts, options) |> Enum.to_list()

    assert_receive {:context_received, context}
    assert is_binary(context.tool_name)
    assert is_map(context.tool_input)
  end
end
```

### Permission Modes

```elixir
%Options{
  permission_mode: :default          # CLI default permission flow
}

%Options{
  permission_mode: :delegate         # Delegate decisions to SDK callback
}

%Options{
  permission_mode: :accept_edits     # Edit operations auto-allowed
}

%Options{
  permission_mode: :plan             # Show plan, execute after approval
}

%Options{
  permission_mode: :bypass_permissions  # All tools allowed (use with caution)
}

%Options{
  permission_mode: :dont_ask         # No permission prompts
}
```

---

## Testing with SupertesterCase

The SDK provides `SupertesterCase` for advanced OTP testing with deterministic behavior.

### Basic Usage

```elixir
defmodule MyApp.SDKTest do
  use ClaudeAgentSDK.SupertesterCase

  # Imports available:
  # - Supertester.OTPHelpers
  # - Supertester.GenServerHelpers
  # - Supertester.Assertions
  # - Supertester.SupervisorHelpers
  # - Supertester.PerformanceHelpers
  # - Supertester.ChaosHelpers

  test "basic SDK operation" do
    # Your test code
  end
end
```

### Eventually Helper

For async assertions that require polling:

```elixir
test "eventually receives expected message" do
  # Start some async operation
  spawn(fn ->
    Process.sleep(50)
    send(self(), {:completed, :value})
  end)

  # Wait for the result
  result = SupertesterCase.eventually(fn ->
    receive do
      {:completed, value} -> value
    after
      0 -> nil
    end
  end, timeout: 1_000, interval: 25)

  assert result == :value
end
```

### Using Mock Transport

For testing the control protocol client:

```elixir
alias ClaudeAgentSDK.Client
alias ClaudeAgentSDK.TestSupport.MockTransport

test "client handles messages correctly" do
  test_pid = self()

  # Start client with mock transport
  {:ok, client} = Client.start_link(%Options{},
    transport: MockTransport,
    transport_opts: [test_pid: test_pid]
  )

  # Receive transport start notification
  assert_receive {:mock_transport_started, transport_pid}

  # Subscribe to get messages
  assert_receive {:mock_transport_subscribed, _pid}

  # Push a message to the client
  response = %{
    "type" => "assistant",
    "message" => %{"content" => "Hello"}
  }
  MockTransport.push_message(transport_pid, Jason.encode!(response))

  # Verify message was processed
  # ...

  # Get recorded outbound messages
  messages = MockTransport.recorded_messages(transport_pid)
  assert length(messages) > 0

  Client.stop(client)
end
```

---

## Integration Testing Patterns

### Live Smoke Test Pattern

For end-to-end testing with real API:

```elixir
defmodule MyApp.LiveSmokeTest do
  use ClaudeAgentSDK.SupertesterCase

  @moduletag :live  # Tag for live tests

  test "basic query works end-to-end" do
    messages = ClaudeAgentSDK.query(
      "Say exactly: live smoke ok",
      %Options{max_turns: 1, output_format: :stream_json}
    ) |> Enum.to_list()

    assert Enum.any?(messages, &(&1.type == :assistant))
    assert Enum.any?(messages, &match?(%{type: :result, subtype: :success}, &1))
  end
end
```

### Running Integration Tests

```bash
# Run all tests (mocks enabled)
mix test

# Run only live tests against real API
LIVE_TESTS=true mix test --only live

# Run integration tests
mix test --only integration

# Run with verbose output
mix test --trace
```

### Testing SDK MCP Tools

```elixir
defmodule MyApp.MCPToolsTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Mock, Options}
  alias ClaudeAgentSDK.Tool.Registry

  setup do
    Mock.clear_responses()
    :ok
  end

  test "SDK MCP server executes tools correctly" do
    # Create server with test tools
    server = ClaudeAgentSDK.create_sdk_mcp_server(
      name: "calc",
      version: "1.0.0",
      tools: [
        ClaudeAgentSDK.TestSupport.CalculatorTools.Add,
        ClaudeAgentSDK.TestSupport.CalculatorTools.GreetUser
      ]
    )

    assert server.type == :sdk
    assert server.name == "calc"
    assert is_pid(server.registry_pid)

    # Execute tool directly
    {:ok, result} = Registry.execute_tool(
      server.registry_pid,
      "add",
      %{"a" => 5, "b" => 3}
    )

    assert result["content"] |> hd() |> Map.get("text") =~ "8"
  end

  test "SDK MCP tools work in query" do
    server = ClaudeAgentSDK.create_sdk_mcp_server(
      name: "math",
      version: "1.0.0",
      tools: [ClaudeAgentSDK.TestSupport.CalculatorTools.Add]
    )

    options = %Options{
      mcp_servers: %{"math" => server},
      allowed_tools: ["mcp__math__add"]
    }

    # Set mock to trigger tool use
    Mock.set_response("calculate", [
      %{
        "type" => "assistant",
        "message" => %{
          "content" => [
            %{
              "type" => "tool_use",
              "name" => "mcp__math__add",
              "input" => %{"a" => 10, "b" => 20}
            }
          ]
        }
      },
      %{
        "type" => "result",
        "subtype" => "success"
      }
    ])

    messages = ClaudeAgentSDK.query("calculate 10 + 20", options) |> Enum.to_list()
    assert Enum.any?(messages, &(&1.type == :result))
  end
end
```

### Testing Streaming

```elixir
defmodule MyApp.StreamingTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Options, Streaming}

  @moduletag :live

  test "streaming session works" do
    options = %Options{model: "haiku", max_turns: 1, allowed_tools: []}

    {:ok, session} = Streaming.start_session(options)

    try do
      result = Streaming.send_message(session, "Say hello in five words.")
      |> Enum.reduce_while(%{chunks: 0, stopped?: false}, fn
        %{type: :text_delta, text: _chunk}, acc ->
          {:cont, %{acc | chunks: acc.chunks + 1}}

        %{type: :message_stop}, acc ->
          {:halt, %{acc | stopped?: true}}

        %{type: :error, error: reason}, _acc ->
          {:halt, %{error: reason}}

        _event, acc -> {:cont, acc}
      end)

      assert result.stopped? == true
      assert result.chunks > 0
    after
      Streaming.close_session(session)
    end
  end
end
```

---

## Environment Configuration for Tests

### Test Configuration (config/test.exs)

```elixir
import Config

config :claude_agent_sdk,
  use_mock: true,
  cli_command: "claude"

# Optional: Customize timeouts for tests
config :claude_agent_sdk,
  timeout_ms: 30_000
```

### Development Configuration (config/dev.exs)

```elixir
import Config

config :claude_agent_sdk,
  use_mock: true,  # Use mocks by default in dev
  cli_command: "claude"
```

### Production Configuration (config/prod.exs)

```elixir
import Config

config :claude_agent_sdk,
  use_mock: false,
  cli_command: "claude"
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `LIVE_TESTS` | Enable live API tests | `false` |
| `ANTHROPIC_API_KEY` | API key for live tests | - |
| `CLAUDE_AGENT_OAUTH_TOKEN` | OAuth token (alternative auth) | - |

---

## Best Practices

### 1. Always Clear Mocks in Setup

```elixir
setup do
  ClaudeAgentSDK.Mock.clear_responses()
  :ok
end
```

### 2. Use Specific Patterns for Mock Responses

```elixir
# Good: Specific pattern
Mock.set_response("analyze security", security_analysis_response)

# Avoid: Too generic
Mock.set_response("a", generic_response)
```

### 3. Test Both Mock and Live Paths

```elixir
# Unit tests with mocks (fast, predictable)
describe "with mocks" do
  test "handles response correctly" do
    Mock.set_response("test", expected_response)
    # ...
  end
end

# Integration tests with live API (periodic validation)
@tag :live
describe "live integration" do
  test "works with real API" do
    # ...
  end
end
```

### 4. Keep Mock Responses Realistic

```elixir
# Good: Complete, realistic response
Mock.set_response("hello", [
  %{"type" => "system", "subtype" => "init", "session_id" => "mock-123"},
  %{"type" => "assistant", "message" => %{"content" => "Hello!"}},
  %{"type" => "result", "subtype" => "success", "total_cost_usd" => 0.001}
])

# Avoid: Minimal response that may not test all code paths
Mock.set_response("hello", [%{"type" => "assistant"}])
```

### 5. Use Test Fixtures for Common Patterns

```elixir
alias ClaudeAgentSDK.TestSupport.TestFixtures

test "with standard fixtures" do
  hook = TestFixtures.allow_all_hook()
  options = TestFixtures.options_with_hooks(hook)
  # ...
end
```

### 6. Test Error Handling

```elixir
test "handles API errors gracefully" do
  Mock.set_response("error case", [
    %{
      "type" => "assistant",
      "message" => %{"content" => "Error"},
      "error" => %{"code" => "rate_limit"}
    },
    %{
      "type" => "result",
      "subtype" => "error_during_execution",
      "is_error" => true
    }
  ])

  messages = ClaudeAgentSDK.query("error case") |> Enum.to_list()
  assert Enum.any?(messages, &(&1.type == :result and &1.subtype == :error_during_execution))
end
```

### 7. Use Eventually for Async Operations

```elixir
test "async operation completes" do
  start_async_operation()

  result = SupertesterCase.eventually(fn ->
    check_completion_status()
  end, timeout: 5_000)

  assert result == :completed
end
```

### 8. Document Test Purposes

```elixir
@moduledoc """
Tests for the permission callback system.

These tests verify that:
- Permission callbacks receive correct context
- Allow/deny decisions are respected
- Input modifications are applied
- Interrupt flags stop execution
"""

@doc """
Verifies that dangerous bash commands are blocked
by the permission callback.
"""
test "blocks rm -rf commands" do
  # ...
end
```

### 9. Isolate Test State

```elixir
setup do
  # Clear global state
  Mock.clear_responses()

  # Create isolated resources
  {:ok, registry} = Tool.Registry.start_link([])

  on_exit(fn ->
    GenServer.stop(registry)
  end)

  {:ok, registry: registry}
end
```

### 10. Run Live Tests Periodically

```bash
# In CI, run live tests on a schedule (e.g., nightly)
LIVE_TESTS=true mix test --only live

# Locally, verify before major releases
LIVE_TESTS=true mix test --only live --trace
```

---

## Test Support Files Reference

| File | Purpose |
|------|---------|
| `test/test_helper.exs` | Test initialization, mock setup |
| `test/support/supertester_case.ex` | OTP testing foundation |
| `test/support/mock_transport.ex` | Transport mock for client tests |
| `test/support/test_tools.ex` | Reusable tool definitions |
| `test/support/test_fixtures.ex` | Common test fixtures |

---

## Troubleshooting

### Mock Not Working

```elixir
# Verify mock is enabled
IO.inspect(Application.get_env(:claude_agent_sdk, :use_mock))
# Should be: true

# Verify mock server is running
IO.inspect(Process.whereis(ClaudeAgentSDK.Mock))
# Should be: a PID
```

### Wrong Response Returned

```elixir
# Check if pattern matches
# Mock uses String.contains? for matching
Mock.get_response("your actual prompt")
# Compare with expected response
```

### Tests Timing Out

```elixir
# Increase timeout for slow operations
options = %Options{timeout_ms: 60_000}

# Or use eventually with longer timeout
SupertesterCase.eventually(fn -> ... end, timeout: 10_000)
```

### Live Tests Failing

```bash
# Verify authentication
claude --version
claude auth status

# Check environment variables
echo $ANTHROPIC_API_KEY

# Run with verbose output
LIVE_TESTS=true mix test --only live --trace
```
