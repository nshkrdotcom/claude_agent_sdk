# Claude Agent SDK Test Patterns Research

**Research Date:** 2025-12-29

This document provides a comprehensive analysis of all test files in the Claude Agent SDK test suite, documenting APIs tested, usage patterns, edge cases, and real-world usage examples.

---

## Table of Contents

1. [Test File Inventory](#test-file-inventory)
2. [Core API Testing](#core-api-testing)
3. [Tool System Testing](#tool-system-testing)
4. [Hooks System Testing](#hooks-system-testing)
5. [Permission System Testing](#permission-system-testing)
6. [Transport Layer Testing](#transport-layer-testing)
7. [Streaming Testing](#streaming-testing)
8. [SDK MCP Server Testing](#sdk-mcp-server-testing)
9. [Agent System Testing](#agent-system-testing)
10. [Message Handling Testing](#message-handling-testing)
11. [Debug and Diagnostics Testing](#debug-and-diagnostics-testing)
12. [Authentication Testing](#authentication-testing)
13. [Integration Testing](#integration-testing)
14. [Test Support Infrastructure](#test-support-infrastructure)
15. [Edge Cases and Important Behaviors](#edge-cases-and-important-behaviors)
16. [Real-World Usage Examples](#real-world-usage-examples)

---

## Test File Inventory

The test suite contains **63 test files** organized as follows:

### Core Tests (`test/claude_agent_sdk/`)
- `client_test.exs` - Core client functionality
- `client_streaming_test.exs` - Client streaming operations
- `client_agents_test.exs` - Client agent support
- `client_cancel_test.exs` - Request cancellation
- `client_query_test.exs` - Query operations
- `client_permission_test.exs` - Permission callback testing
- `client_hook_timeout_test.exs` - Hook timeout handling
- `client_init_timeout_env_test.exs` - Initialization timeout
- `client_control_request_timeout_test.exs` - Control request timeouts

### Options Tests
- `option_builder_test.exs` - Options builder pattern
- `options_streaming_test.exs` - Streaming-related options
- `options_agents_test.exs` - Agent-related options
- `options_extended_test.exs` - Extended options

### Tool System Tests
- `tool_test.exs` - Tool macro and registration
- `tool/registry_test.exs` - Tool registry GenServer
- `tool/edge_cases_test.exs` - Edge cases for tools

### Hooks Tests (`hooks/`)
- `hooks_test.exs` - Hook event system
- `matcher_test.exs` - Hook matchers
- `registry_test.exs` - Hook callback registry
- `output_test.exs` - Hook output generation

### Transport Tests (`transport/`)
- `transport_test.exs` - Transport abstraction
- `port_test.exs` - Port transport
- `erlexec_transport_test.exs` - Erlexec transport
- `streaming_router_test.exs` - Transport routing decisions
- `stderr_callback_test.exs` - stderr handling
- `env_parity_test.exs` - Environment parity
- `agents_file_test.exs` - Agent file handling

### Streaming Tests (`streaming/`)
- `event_parser_test.exs` - SSE event parsing
- `event_adapter_test.exs` - Event adaptation
- `session_cwd_semantics_test.exs` - CWD semantics

### MCP Tests
- `sdk_mcp_server_test.exs` - SDK MCP server creation
- `sdk_mcp_integration_test.exs` - MCP integration
- `sdk_mcp_routing_test.exs` - MCP request routing

### Integration Tests (`test/integration/`)
- `live_smoke_test.exs` - End-to-end smoke tests
- `backward_compat_test.exs` - Backward compatibility
- `custom_transport_test.exs` - Custom transport usage
- `model_switching_live_test.exs` - Live model switching
- `filesystem_agents_test.exs` - Filesystem agent tests

### Examples Tests (`test/examples/`)
- `runtime_control_examples_test.exs` - Example scripts validation

---

## Core API Testing

### ClaudeAgentSDK Module (`claude_agent_sdk_test.exs`)

**APIs Tested:**
- `ClaudeAgentSDK.query/2` - Primary query interface
- `ClaudeAgentSDK.continue/2` - Continue conversation
- `ClaudeAgentSDK.resume/3` - Resume with session ID

**Usage Patterns:**

```elixir
# Basic query with mocked responses
messages = ClaudeAgentSDK.query("test prompt") |> Enum.to_list()

# Query with options
opts = %Options{max_turns: 3, output_format: :json}
messages = ClaudeAgentSDK.query("test prompt", opts) |> Enum.to_list()

# Continue without prompt
result = ClaudeAgentSDK.continue()

# Continue with additional prompt
result = ClaudeAgentSDK.continue("additional prompt")

# Resume with session ID
result = ClaudeAgentSDK.resume("test-session-id", "additional prompt")
```

### Client Module (`client_test.exs`)

**APIs Tested:**
- `Client.start_link/2` - Start client with options and transport
- `Client.stop/1` - Stop client
- `Client.set_model/2` - Runtime model switching
- `Client.get_model/1` - Get current model
- `Client.interrupt/1` - Interrupt execution
- `Client.get_server_info/1` - Get server info
- `Client.receive_response/1` - Collect messages
- `Client.rewind_files/2` - File checkpointing
- `Client.query/3` - Send query with session

**Usage Patterns:**

```elixir
# Start with mock transport for testing
{:ok, client} = Client.start_link(%Options{},
  transport: MockTransport,
  transport_opts: [test_pid: self()]
)

# Start with hooks configuration
callback = fn _, _, _ -> Output.allow() end
options = %Options{
  hooks: %{
    pre_tool_use: [Matcher.new("Bash", [callback])]
  }
}
{:ok, client} = Client.start_link(options)

# Model switching at runtime
:ok = Client.set_model(client, "opus")
{:ok, model} = Client.get_model(client)

# Interrupt execution
:ok = Client.interrupt(client)

# Get server info (after initialization)
{:ok, info} = Client.get_server_info(client)

# Collect response messages
{:ok, messages} = Client.receive_response(client)

# File checkpointing (requires option)
options = %Options{enable_file_checkpointing: true}
{:ok, client} = Client.start_link(options, transport: MockTransport)
:ok = Client.rewind_files(client, "user_msg_123")
```

---

## Tool System Testing

### Tool Macro (`tool_test.exs`)

**APIs Tested:**
- `deftool/3` macro - Define tools
- `Tool.list_tools/1` - List tools in module
- `Tool.valid_schema?/1` - Validate schemas

**Usage Patterns:**

```elixir
# Define tools with deftool macro
defmodule MyTools do
  use ClaudeAgentSDK.Tool

  deftool :add,
          "Add two numbers",
          %{
            type: "object",
            properties: %{
              a: %{type: "number"},
              b: %{type: "number"}
            },
            required: ["a", "b"]
          } do
    def execute(%{"a" => a, "b" => b}) do
      {:ok, %{"content" => [%{"type" => "text", "text" => "#{a + b}"}]}}
    end
  end

  deftool :error_tool,
          "Always fails",
          %{type: "object"} do
    def execute(_args) do
      {:error, "Expected error"}
    end
  end
end

# Execute tool
{:ok, result} = MyTools.Add.execute(%{"a" => 5, "b" => 3})

# List tools in module
tools = Tool.list_tools(MyTools)

# Validate schema
assert Tool.valid_schema?(%{type: "object"})
```

### Tool Registry (`tool/registry_test.exs`)

**APIs Tested:**
- `Registry.start_link/1` - Start registry
- `Registry.register_tool/2` - Register tool
- `Registry.get_tool/2` - Lookup tool
- `Registry.list_tools/1` - List all tools
- `Registry.execute_tool/3` - Execute tool

**Usage Patterns:**

```elixir
# Start registry
{:ok, registry} = Registry.start_link([])

# Register tool
tool = %{
  name: :add,
  description: "Add two numbers",
  input_schema: %{type: "object"},
  module: MyModule.Add
}
:ok = Registry.register_tool(registry, tool)

# Lookup tool
{:ok, found} = Registry.get_tool(registry, :add)

# List all tools
{:ok, tools} = Registry.list_tools(registry)

# Execute tool
{:ok, result} = Registry.execute_tool(registry, :add, %{"a" => 5, "b" => 3})
```

### Tool Edge Cases (`tool/edge_cases_test.exs`)

**Edge Cases Documented:**
- Minimal schema: `%{type: "object"}`
- Optional fields (no required fields)
- Nested object schemas
- Array schemas
- Large inputs (10,000+ bytes)
- Large outputs (30,000+ bytes)
- Concurrent execution
- Malformed input handling
- Execution timeouts
- Numeric suffixes in tool names
- Single character tool names
- Complex JSON schema features (oneOf, anyOf, allOf)

---

## Hooks System Testing

### Hooks Module (`hooks/hooks_test.exs`)

**APIs Tested:**
- `Hooks.event_to_string/1` - Convert atom to string
- `Hooks.string_to_event/1` - Convert string to atom
- `Hooks.validate_config/1` - Validate configuration
- `Hooks.all_valid_events/0` - List valid events

**Valid Hook Events:**
- `:pre_tool_use` / "PreToolUse"
- `:post_tool_use` / "PostToolUse"
- `:session_start` / "SessionStart"
- `:session_end` / "SessionEnd"
- `:notification` / "Notification"
- `:user_prompt_submit` / "UserPromptSubmit"
- `:stop` / "Stop"
- `:subagent_stop` / "SubagentStop"
- `:pre_compact` / "PreCompact"

**Usage Patterns:**

```elixir
# Event conversion
assert Hooks.event_to_string(:pre_tool_use) == "PreToolUse"
assert Hooks.string_to_event("PreToolUse") == :pre_tool_use

# Validate hook configuration
matcher = %Matcher{
  matcher: "Bash",
  hooks: [fn _, _, _ -> %{} end]
}
:ok = Hooks.validate_config(%{pre_tool_use: [matcher]})

# Get all valid events
events = Hooks.all_valid_events()
```

### Hook Matchers (`hooks/matcher_test.exs`)

**APIs Tested:**
- `Matcher.new/3` - Create matcher
- `Matcher.matches?/2` - Check if tool matches

**Usage Patterns:**

```elixir
# Create matcher for specific tool
matcher = Matcher.new("Bash", [callback])

# Create wildcard matcher
wildcard = Matcher.new("*", [callback])

# Create matcher with timeout
timed = Matcher.new("Bash", [callback], timeout_ms: 1500)

# Check if matcher applies to tool
assert Matcher.matches?(matcher, "Bash")
assert Matcher.matches?(wildcard, "AnyTool")
```

### Hook Registry (`hooks/registry_test.exs`)

**APIs Tested:**
- `Registry.new/0` - Create new registry
- `Registry.register/2` - Register callback
- `Registry.get_id/2` - Get callback ID
- `Registry.get_callback/2` - Get callback by ID
- `Registry.count/1` - Count registered callbacks

**Usage Patterns:**

```elixir
# Create and populate registry
registry = Hooks.Registry.new()
registry = Hooks.Registry.register(registry, callback1)
registry = Hooks.Registry.register(registry, callback2)

# Get callback IDs
assert Hooks.Registry.get_id(registry, callback1) == "hook_0"
assert Hooks.Registry.get_id(registry, callback2) == "hook_1"

# Count callbacks
assert Hooks.Registry.count(registry) == 2
```

### Hook Output (`hooks/output_test.exs`)

**APIs Tested:**
- `Output.allow/0` - Allow tool execution
- `Output.allow/1` - Allow with options
- `Output.deny/1` - Deny with reason
- `Output.deny/2` - Deny with options

**Usage Patterns:**

```elixir
# Simple allow
result = Output.allow()
assert result.hookSpecificOutput.permissionDecision == "allow"

# Allow with message
result = Output.allow("Approved by hook")

# Deny with reason
result = Output.deny("Not allowed")
assert result.hookSpecificOutput.permissionDecision == "deny"

# Deny with interrupt
result = Output.deny("Critical", interrupt: true)
```

---

## Permission System Testing

### Permission Module (`permission_test.exs`)

**APIs Tested:**
- `Permission.Result.allow/0` - Allow result
- `Permission.Result.allow/1` - Allow with options
- `Permission.Result.deny/1` - Deny result
- `Permission.Result.deny/2` - Deny with options
- `Permission.Result.to_json_map/1` - Convert to JSON
- `Permission.Context.new/1` - Create context

**Permission Modes:**
- `:default` - Normal permission checking
- `:accept_edits` - Auto-allow edit operations
- `:plan` - Show plan before execution
- `:bypass_permissions` - Skip all permission checks

**Usage Patterns:**

```elixir
# Create permission callback
callback = fn context ->
  if context.tool_name == "Bash" do
    command = context.tool_input["command"] || ""
    if String.contains?(command, "rm -rf") do
      Permission.Result.deny("Dangerous command")
    else
      Permission.Result.allow()
    end
  else
    Permission.Result.allow()
  end
end

# Use in options
options = %Options{
  can_use_tool: callback,
  permission_mode: :default
}

# Create context
context = Permission.Context.new(
  tool_name: "Bash",
  tool_input: %{"command" => "ls -la"},
  session_id: "test-session",
  suggestions: []
)

# Allow with input modification
Permission.Result.allow(updated_input: %{"file_path" => "/safe/path"})

# Deny with interrupt
Permission.Result.deny("Critical error", interrupt: true)

# Allow with permission updates
Permission.Result.allow(updated_permissions: [
  %{"type" => "setMode", "mode" => "plan", "destination" => "session"}
])
```

---

## Transport Layer Testing

### Transport Abstraction (`transport_test.exs`)

**Transport Behaviour:**
- `start_link/1` - Start transport
- `send/2` - Send message
- `subscribe/2` - Subscribe to messages
- `close/1` - Close transport
- `status/1` - Get status

### Streaming Router (`transport/streaming_router_test.exs`)

**APIs Tested:**
- `StreamingRouter.select_transport/1` - Select transport mode
- `StreamingRouter.requires_control_protocol?/1` - Check if control needed
- `StreamingRouter.explain/1` - Explain routing decision

**Transport Selection Rules:**
- Empty options -> `:streaming_session` (CLI-only)
- Hooks configured -> `:control_client`
- SDK MCP servers -> `:control_client`
- Permission callback -> `:control_client`
- Agents configured -> `:control_client`
- Non-default permission mode -> `:control_client`
- `preferred_transport: :cli` -> Override to `:streaming_session`
- `preferred_transport: :control` -> Override to `:control_client`

**Usage Patterns:**

```elixir
# Check transport selection
opts = %Options{}
assert :streaming_session = StreamingRouter.select_transport(opts)

# With hooks -> control client
callback = fn _, _, _ -> %{behavior: :allow} end
opts = %Options{hooks: %{pre_tool_use: [Matcher.new("Bash", [callback])]}}
assert :control_client = StreamingRouter.select_transport(opts)

# Check if control protocol needed
assert StreamingRouter.requires_control_protocol?(opts_with_hooks)

# Get explanation
explanation = StreamingRouter.explain(opts)
```

### Erlexec Transport (`transport/erlexec_transport_test.exs`)

**Usage Patterns:**

```elixir
# Start transport with stderr callback
stderr_cb = fn line -> send(test_pid, {:stderr_line, line}) end
options = %Options{stderr: stderr_cb}

{:ok, transport} = ErlexecTransport.start_link(
  command: script,
  args: [],
  options: options
)

# Subscribe to stdout
:ok = ErlexecTransport.subscribe(transport, self())

# Send message
:ok = ErlexecTransport.send(transport, "PING\n")

# Close transport
ErlexecTransport.close(transport)
```

---

## Streaming Testing

### Event Parser (`streaming/event_parser_test.exs`)

**APIs Tested:**
- SSE event parsing
- Multiline data handling
- Partial message assembly

### Options Streaming (`options_streaming_test.exs`)

**New Fields (v0.6.0):**
- `include_partial_messages` - Include partial messages in stream
- `preferred_transport` - Override transport selection (`:cli`, `:control`, `:auto`)

**Usage Patterns:**

```elixir
# Enable partial messages
options = Options.new(include_partial_messages: true)
args = Options.to_args(options)
assert "--include-partial-messages" in args

# Set preferred transport
options = Options.new(preferred_transport: :control)

# Combined
options = Options.new(
  model: "sonnet",
  include_partial_messages: true,
  preferred_transport: :auto
)
```

---

## SDK MCP Server Testing

### Server Creation (`sdk_mcp_server_test.exs`)

**APIs Tested:**
- `ClaudeAgentSDK.create_sdk_mcp_server/1` - Create SDK MCP server

**Usage Patterns:**

```elixir
# Create SDK MCP server with tools
server = ClaudeAgentSDK.create_sdk_mcp_server(
  name: "calc-server",
  version: "1.0.0",
  tools: [CalculatorTools.Add, CalculatorTools.GreetUser]
)

assert server.type == :sdk
assert server.name == "calc-server"
assert is_pid(server.registry_pid)

# Execute tool through server
{:ok, result} = Tool.Registry.execute_tool(
  server.registry_pid,
  :add,
  %{"a" => 5, "b" => 3}
)

# Multiple servers can coexist
server1 = ClaudeAgentSDK.create_sdk_mcp_server(name: "s1", tools: [Tool1])
server2 = ClaudeAgentSDK.create_sdk_mcp_server(name: "s2", tools: [Tool2])
assert server1.registry_pid != server2.registry_pid
```

### MCP Integration (`sdk_mcp_integration_test.exs`)

**Usage Patterns:**

```elixir
# SDK MCP server in Options
server = ClaudeAgentSDK.create_sdk_mcp_server(
  name: "calc",
  version: "1.0.0",
  tools: [CalculatorTools.Add]
)
options = Options.new(mcp_servers: %{"calc" => server})

# Mixed SDK and external servers
sdk_server = ClaudeAgentSDK.create_sdk_mcp_server(name: "sdk", tools: [])
external_server = %{type: :stdio, command: "uvx", args: ["mcp-server-time"]}

options = Options.new(mcp_servers: %{
  "sdk" => sdk_server,
  "external" => external_server
})
```

---

## Agent System Testing

### Agent Module (`agent_test.exs`)

**Agent Struct:**
- `description` - Agent description
- `prompt` - System prompt
- `allowed_tools` - List of allowed tools

**Usage Patterns:**

```elixir
# Define agent
agent = %ClaudeAgentSDK.Agent{
  description: "Test agent",
  prompt: "You are a test agent",
  allowed_tools: []
}

# Use in options
options = %Options{
  agents: %{test: agent},
  agent: :test
}
```

---

## Message Handling Testing

### Content Extractor (`content_extractor_test.exs`)

**APIs Tested:**
- `ContentExtractor.extract_text/1` - Extract text from message
- `ContentExtractor.has_text?/1` - Check if message has text
- `ContentExtractor.extract_all_text/2` - Extract from multiple messages
- `ContentExtractor.summarize/2` - Summarize message
- `ContentExtractor.extract_content_text/1` - Extract from content array

**Usage Patterns:**

```elixir
# Extract text from assistant message
message = %Message{
  type: :assistant,
  data: %{message: %{"content" => "Hello, world!"}}
}
assert ContentExtractor.extract_text(message) == "Hello, world!"

# Handle array-based content
message = %Message{
  type: :assistant,
  data: %{message: %{"content" => [
    %{"type" => "text", "text" => "Part 1"},
    %{"type" => "tool_use", "name" => "calculator"},
    %{"type" => "text", "text" => "Part 2"}
  ]}}
}
result = ContentExtractor.extract_text(message)
# Returns: "Part 1 [Tool: calculator] Part 2"

# Extract from multiple messages
messages = [msg1, msg2, msg3]
combined = ContentExtractor.extract_all_text(messages, "\n")

# Summarize with truncation
summary = ContentExtractor.summarize(message, 100)
```

### Message Error Handling (`message_error_test.exs`)

**Error Types:**
- `:rate_limit`
- `:unknown` (for unrecognized errors)

### Message Structured Output (`message_structured_output_test.exs`)

**Usage Patterns:**

```elixir
# Result with structured output
json = ~s({"type":"result","structured_output":{"status":"ok"}})
{:ok, message} = Message.from_json(json)
assert message.data.structured_output == %{"status" => "ok"}
```

---

## Debug and Diagnostics Testing

### Debug Mode (`debug_mode_test.exs`)

**APIs Tested:**
- `DebugMode.debug_query/2` - Query with debug output
- `DebugMode.analyze_messages/1` - Analyze message statistics
- `DebugMode.run_diagnostics/0` - System diagnostics
- `DebugMode.inspect_message/1` - Inspect single message
- `DebugMode.benchmark/3` - Performance benchmarking
- `DebugMode.profile_query/2` - Performance profiling

**Usage Patterns:**

```elixir
# Analyze messages
stats = DebugMode.analyze_messages(messages)
# Returns: %{
#   total_messages: 4,
#   message_types: %{system: 1, assistant: 2, result: 1},
#   total_cost_usd: 0.025,
#   duration_ms: 1500,
#   session_id: "123",
#   tools_used: ["Read", "Grep"],
#   errors: []
# }

# Inspect message format
result = DebugMode.inspect_message(message)
# Returns: "Message[assistant]: \"Hello...\" (29 chars)"

# Benchmark queries
results = DebugMode.benchmark("test prompt", nil, 3)
# Returns: %{
#   runs: 3,
#   avg_duration_ms: 150,
#   min_duration_ms: 100,
#   max_duration_ms: 200,
#   avg_cost_usd: 0.002
# }

# Profile query
{messages, profile} = DebugMode.profile_query("test query")
# profile contains: execution_time_ms, memory_delta_bytes, peak_memory_mb
```

---

## Authentication Testing

### Auth Manager (`auth_manager_test.exs`)

**APIs Tested:**
- `AuthManager.ensure_authenticated/0` - Ensure authentication
- `AuthManager.get_token/0` - Get current token
- `AuthManager.clear_auth/0` - Clear authentication
- `AuthManager.status/0` - Get auth status
- `AuthManager.setup_token/0` - Acquire token via CLI

**Token Sources (in priority order):**
1. `CLAUDE_AGENT_OAUTH_TOKEN` environment variable
2. `ANTHROPIC_API_KEY` environment variable
3. Stored token (with expiry checking)

**Usage Patterns:**

```elixir
# Check authentication
:ok = AuthManager.ensure_authenticated()

# Get token
{:ok, token} = AuthManager.get_token()

# Get status
status = AuthManager.status()
# Returns: %{
#   authenticated: true,
#   token_present: true,
#   expires_at: ~U[2025-01-05 12:00:00Z],
#   time_until_expiry_hours: 168.0
# }

# Clear authentication
:ok = AuthManager.clear_auth()
```

---

## Integration Testing

### Live Smoke Test (`integration/live_smoke_test.exs`)

```elixir
# End-to-end test
messages = ClaudeAgentSDK.query(
  "Say exactly: live smoke ok",
  %Options{max_turns: 1, output_format: :stream_json}
) |> Enum.to_list()

assert Enum.any?(messages, &(&1.type == :assistant))
assert Enum.any?(messages, &match?(%{type: :result, subtype: :success}, &1))
```

### Examples Smoke Test (`examples/runtime_control_examples_test.exs`)

```elixir
# Verify examples run without errors
@scripts [
  {"control client demo", "examples/archive/mock_demos/control_client_demo.exs", "Control Client Demo"},
  {"streaming demo", "examples/archive/mock_demos/streaming_demo.exs", "Streaming Demo"},
  {"sdk mcp demo", "examples/archive/mock_demos/sdk_mcp_demo.exs", "SDK MCP Demo"}
]

for {label, script, expected} <- @scripts do
  test "#{label} example runs successfully" do
    {output, status} = System.cmd("mix", ["run", script])
    assert status == 0
    assert output =~ expected
  end
end
```

---

## Test Support Infrastructure

### Test Helper (`test_helper.exs`)

```elixir
# Enable mock mode for tests
live_tests? = System.get_env("LIVE_TESTS") == "true"
Application.put_env(:claude_agent_sdk, :use_mock, !live_tests?)

# Start mock server
unless live_tests? do
  {:ok, _} = ClaudeAgentSDK.Mock.start_link()
end

# Exclude integration tests by default
ExUnit.start(exclude: [:integration, :live], capture_log: true)
```

### SupertesterCase (`support/supertester_case.ex`)

```elixir
use ClaudeAgentSDK.SupertesterCase

# Provides:
# - Supertester OTP helpers
# - GenServer helpers
# - Assertions
# - Supervisor helpers
# - Performance helpers
# - Chaos helpers

# Eventually helper for polling
SupertesterCase.eventually(fn ->
  receive do
    {:expected, value} -> value
  after
    0 -> nil
  end
end, timeout: 1_000)
```

### Mock Transport (`support/mock_transport.ex`)

```elixir
# Start mock transport in test
{:ok, client} = Client.start_link(%Options{},
  transport: MockTransport,
  transport_opts: [test_pid: self()]
)

# Receive notifications
assert_receive {:mock_transport_started, transport_pid}
assert_receive {:mock_transport_send, json}

# Push messages to client
MockTransport.push_message(transport_pid, Jason.encode!(response))

# Get recorded messages
messages = MockTransport.recorded_messages(transport_pid)
```

### Test Tools (`support/test_tools.ex`)

```elixir
defmodule ClaudeAgentSDK.TestSupport.CalculatorTools do
  use ClaudeAgentSDK.Tool

  deftool :add, "Add two numbers", %{...} do
    def execute(%{"a" => a, "b" => b}) do
      {:ok, %{"content" => [%{"type" => "text", "text" => "#{a + b}"}]}}
    end
  end
end

defmodule ClaudeAgentSDK.TestSupport.ErrorTools do
  deftool :fail_tool, "Always fails", %{type: "object"} do
    def execute(_input) do
      {:error, "Expected error"}
    end
  end

  deftool :raise_tool, "Raises exception", %{type: "object"} do
    def execute(_input) do
      raise "Intentional error"
    end
  end
end

defmodule ClaudeAgentSDK.TestSupport.ImageTools do
  deftool :generate_chart, "Generates chart image", %{...} do
    def execute(%{"title" => title}) do
      {:ok, %{
        "content" => [
          %{"type" => "text", "text" => "Generated: #{title}"},
          %{"type" => "image", "data" => png_base64, "mimeType" => "image/png"}
        ]
      }}
    end
  end
end
```

### Test Fixtures (`support/test_fixtures.ex`)

```elixir
alias ClaudeAgentSDK.TestSupport.TestFixtures

# Hooks
hook = TestFixtures.allow_all_hook()
hook = TestFixtures.deny_all_hook()
hook = TestFixtures.allow_tool_hook("Bash")
hook = TestFixtures.recording_hook(test_pid)

# Permissions
callback = TestFixtures.allow_all_permission()
callback = TestFixtures.deny_all_permission()
callback = TestFixtures.recording_permission(test_pid)

# Options
options = TestFixtures.basic_options()
options = TestFixtures.options_with_hooks(hook)
options = TestFixtures.options_with_mcp(server)
options = TestFixtures.options_with_permissions(callback)

# Agents
agent = TestFixtures.test_agent(description: "Test", prompt: "You are...")
```

---

## Edge Cases and Important Behaviors

### Tool System Edge Cases

1. **Minimal schema accepted:** `%{type: "object"}`
2. **Duplicate registration prevented:** Returns `{:error, :already_registered}`
3. **Missing tool returns:** `{:error, :not_found}`
4. **Concurrent registrations handled safely**
5. **Large inputs (10KB+) supported**
6. **Large outputs (30KB+) supported**
7. **Execution timeouts handled gracefully**
8. **Exceptions in tools converted to error tuples**

### Hooks Edge Cases

1. **Empty hooks map is valid:** Results in CLI-only transport
2. **Hooks with empty matchers is valid**
3. **Invalid event names rejected during validation**
4. **Non-map config rejected**
5. **Non-atom event keys rejected**
6. **Callback exceptions handled and converted to errors**
7. **Callback timeouts handled via Task.yield**

### Transport Router Edge Cases

1. **Invalid permission mode gracefully defaults to CLI-only**
2. **External MCP only does not require control protocol**
3. **Mixed SDK + external MCP requires control protocol**
4. **`preferred_transport` override takes precedence**

### Permission Edge Cases

1. **Callback exceptions converted to deny results**
2. **Input modification preserves unmodified fields**
3. **Interrupt flag stops entire session**
4. **Permission suggestions from CLI available in context**

### Message Edge Cases

1. **Unknown error values mapped to `:unknown`**
2. **Missing content field handled gracefully**
3. **Malformed content inspected as string**
4. **Array content with mixed types handled**
5. **Tool use without name shows "unknown"**
6. **Tool result without content shows ID only**

### Authentication Edge Cases

1. **Expired tokens return `:not_authenticated`**
2. **CI environment returns `:authentication_required`**
3. **OAuth token takes precedence over API key**
4. **Storage cleared on `clear_auth/0`**

---

## Real-World Usage Examples

### Example 1: Custom Permission Policy

```elixir
# Deny dangerous bash commands
callback = fn context ->
  if context.tool_name == "Bash" do
    command = context.tool_input["command"] || ""

    dangerous? = Enum.any?(
      ["rm -rf", "sudo", "chmod 777", "dd if=", "mkfs"],
      &String.contains?(command, &1)
    )

    if dangerous? do
      Permission.Result.deny("Dangerous command pattern detected")
    else
      Permission.Result.allow()
    end
  else
    Permission.Result.allow()
  end
end

options = %Options{
  can_use_tool: callback,
  permission_mode: :default
}

messages = ClaudeAgentSDK.query("Run rm -rf /", options) |> Enum.to_list()
```

### Example 2: Path Restriction Policy

```elixir
allowed_dirs = ["/tmp", "/home/user/project", "./"]

callback = fn context ->
  if context.tool_name in ["Read", "Write"] do
    file_path = context.tool_input["file_path"] || ""

    allowed? = Enum.any?(allowed_dirs, &String.starts_with?(file_path, &1))

    if allowed? do
      Permission.Result.allow()
    else
      Permission.Result.deny("File path outside allowed directories")
    end
  else
    Permission.Result.allow()
  end
end
```

### Example 3: Redirect System File Writes

```elixir
callback = fn context ->
  if context.tool_name == "Write" do
    file_path = context.tool_input["file_path"]

    if String.starts_with?(file_path, "/etc/") or String.starts_with?(file_path, "/usr/") do
      safe_path = "/tmp/safe_output/#{Path.basename(file_path)}"
      Permission.Result.allow(
        updated_input: Map.put(context.tool_input, "file_path", safe_path)
      )
    else
      Permission.Result.allow()
    end
  else
    Permission.Result.allow()
  end
end
```

### Example 4: SDK MCP Server with Tools

```elixir
defmodule MyCalculator do
  use ClaudeAgentSDK.Tool

  deftool :add, "Add two numbers", %{
    type: "object",
    properties: %{a: %{type: "number"}, b: %{type: "number"}},
    required: ["a", "b"]
  } do
    def execute(%{"a" => a, "b" => b}) do
      {:ok, %{"content" => [%{"type" => "text", "text" => "#{a + b}"}]}}
    end
  end
end

server = ClaudeAgentSDK.create_sdk_mcp_server(
  name: "calculator",
  version: "1.0.0",
  tools: [MyCalculator.Add]
)

options = %Options{mcp_servers: %{"calc" => server}}
messages = ClaudeAgentSDK.query("What is 5 + 3?", options) |> Enum.to_list()
```

### Example 5: Hook-Based Tool Logging

```elixir
test_pid = self()

callback = fn tool_name, input, _context ->
  send(test_pid, {:tool_use, tool_name, input})
  Output.allow()
end

options = %Options{
  hooks: %{
    pre_tool_use: [Matcher.new("*", [callback])]
  }
}

messages = ClaudeAgentSDK.query("List files", options) |> Enum.to_list()

# Receive tool use notifications
receive do
  {:tool_use, "Bash", %{"command" => cmd}} ->
    IO.puts("Bash command: #{cmd}")
after
  1000 -> :timeout
end
```

### Example 6: Model Switching at Runtime

```elixir
{:ok, client} = Client.start_link(%Options{}, transport: MockTransport)

# Switch to Opus for complex task
:ok = Client.set_model(client, "opus")

# Execute complex query
:ok = Client.query(client, "Analyze this codebase", "session-1")
{:ok, messages} = Client.receive_response(client)

# Switch back to Sonnet for simpler tasks
:ok = Client.set_model(client, "sonnet")
```

### Example 7: Abort Signal Handling

```elixir
callback = fn _input, _tool_use_id, %{signal: signal} ->
  # Check if cancelled before expensive operation
  if AbortSignal.cancelled?(signal) do
    Output.deny("Operation cancelled")
  else
    # Perform operation
    Output.allow()
  end
end

options = %Options{
  hooks: %{
    pre_tool_use: [Matcher.new("*", [callback])]
  }
}

{:ok, client} = Client.start_link(options)

# Later, cancel in-progress request
Client.interrupt(client)
```

---

## Summary

The Claude Agent SDK test suite provides comprehensive coverage of:

1. **Core API** - Query, continue, resume operations
2. **Client lifecycle** - Start, stop, model switching, interruption
3. **Tool system** - Definition, registration, execution
4. **Hooks system** - Event handling, matchers, callbacks
5. **Permission system** - Allow/deny, input modification, modes
6. **Transport layer** - Routing, protocols, stderr handling
7. **Streaming** - Partial messages, event parsing
8. **MCP servers** - SDK and external server integration
9. **Agents** - Multi-agent configuration
10. **Authentication** - Token management, storage
11. **Debug/diagnostics** - Profiling, benchmarking, analysis

The tests demonstrate real-world patterns for:
- Security policies (command filtering, path restrictions)
- Input modification (path redirection)
- Logging and monitoring (tool use tracking)
- Runtime control (model switching, interruption)
- Error handling (exceptions, timeouts, cancellation)

Key testing infrastructure includes:
- Mock transport for isolated testing
- Test tool definitions
- Test fixtures for common patterns
- SupertesterCase for OTP testing utilities
- Eventually helper for async assertions
