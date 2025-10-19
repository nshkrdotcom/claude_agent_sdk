# Design Document: Runtime Control Features

## Overview

This design document describes the architecture and implementation approach for adding runtime control features to the Claude Agent SDK for Elixir. The implementation will add two major capabilities:

1. **Runtime Model Switching**: Allow changing the AI model during an active session
2. **Transport Layer Abstraction**: Provide a pluggable transport system for CLI communication

These features will bring the Elixir SDK to 100% feature parity with the Python SDK while maintaining backward compatibility and leveraging Elixir/OTP best practices.

## Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Your Application                          │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│              ClaudeAgentSDK.Client (GenServer)               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  State:                                               │   │
│  │  - transport: Transport.t()                           │   │
│  │  - current_model: String.t()                          │   │
│  │  - pending_model_change: {from, ref} | nil            │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                               │
│  Public API:                                                  │
│  - set_model(client, model) :: :ok | {:error, reason}       │
│  - get_model(client) :: {:ok, model}                         │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│         ClaudeAgentSDK.Transport (Behaviour)                 │
│                                                               │
│  Callbacks:                                                   │
│  - start_link(opts) :: {:ok, pid} | {:error, reason}        │
│  - send(transport, data) :: :ok | {:error, reason}          │
│  - subscribe(transport, pid) :: :ok                          │
│  - close(transport) :: :ok                                   │
└────────────────────┬────────────────────────────────────────┘
                     │
        ┌────────────┴────────────┐
        ▼                         ▼
┌──────────────────┐    ┌──────────────────────┐
│  Transport.Port  │    │  Transport.Custom    │
│  (Default)       │    │  (User-defined)      │
└────────┬─────────┘    └──────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│              Claude CLI Process (Port)                       │
└─────────────────────────────────────────────────────────────┘
```

### Component Interaction Flow

#### Model Switching Flow

```
User Code                Client GenServer           Transport              CLI
    │                         │                         │                   │
    │──set_model("opus")─────>│                         │                   │
    │                         │                         │                   │
    │                         │──validate_model()       │                   │
    │                         │                         │                   │
    │                         │──encode_set_model_req──>│                   │
    │                         │                         │                   │
    │                         │                         │──JSON message────>│
    │                         │                         │                   │
    │                         │                         │<──response────────│
    │                         │                         │                   │
    │                         │<──decode_response───────│                   │
    │                         │                         │                   │
    │                         │──update_state()         │                   │
    │                         │                         │                   │
    │<────:ok─────────────────│                         │                   │
```

## Components and Interfaces

### 1. ClaudeAgentSDK.Transport (Behaviour)

**Purpose**: Define a standard interface for communication with the Claude CLI.

**Module**: `lib/claude_agent_sdk/transport.ex`

```elixir
defmodule ClaudeAgentSDK.Transport do
  @moduledoc """
  Behaviour for transport implementations that communicate with Claude CLI.
  
  A transport is responsible for:
  - Starting and managing the connection to the CLI
  - Sending messages to the CLI
  - Receiving messages from the CLI
  - Notifying subscribers of incoming messages
  - Cleanup on shutdown
  """
  
  @type t :: pid()
  @type message :: binary()
  @type opts :: keyword()
  
  @doc """
  Starts the transport process.
  
  ## Options
  
  Transport-specific options are passed through from Client.
  """
  @callback start_link(opts) :: {:ok, t()} | {:error, term()}
  
  @doc """
  Sends a message to the CLI.
  
  Messages should be newline-terminated JSON strings.
  """
  @callback send(t(), message()) :: :ok | {:error, term()}
  
  @doc """
  Subscribes a process to receive messages from the CLI.
  
  The transport will send `{:transport_message, message}` to subscribers.
  """
  @callback subscribe(t(), pid()) :: :ok
  
  @doc """
  Closes the transport and cleans up resources.
  """
  @callback close(t()) :: :ok
  
  @doc """
  Returns the current status of the transport.
  """
  @callback status(t()) :: :connected | :disconnected | :error
end
```

### 2. ClaudeAgentSDK.Transport.Port (Default Implementation)

**Purpose**: Implement the Transport behaviour using Erlang Ports (current implementation).

**Module**: `lib/claude_agent_sdk/transport/port.ex`

```elixir
defmodule ClaudeAgentSDK.Transport.Port do
  @moduledoc """
  Port-based transport implementation for Claude CLI communication.
  
  This is the default transport that uses Erlang's Port mechanism
  to spawn and communicate with the Claude CLI subprocess.
  """
  
  use GenServer
  @behaviour ClaudeAgentSDK.Transport
  
  defstruct [
    :port,
    :subscribers,
    :buffer,
    :options
  ]
  
  @impl ClaudeAgentSDK.Transport
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end
  
  @impl ClaudeAgentSDK.Transport
  def send(transport, message) do
    GenServer.call(transport, {:send, message})
  end
  
  @impl ClaudeAgentSDK.Transport
  def subscribe(transport, pid) do
    GenServer.call(transport, {:subscribe, pid})
  end
  
  @impl ClaudeAgentSDK.Transport
  def close(transport) do
    GenServer.stop(transport, :normal)
  end
  
  @impl ClaudeAgentSDK.Transport
  def status(transport) do
    GenServer.call(transport, :status)
  end
  
  # GenServer callbacks handle Port communication
  # (extracted from current Client implementation)
end
```

### 3. ClaudeAgentSDK.Client (Enhanced)

**Purpose**: Add runtime model switching and transport abstraction support.

**Changes to**: `lib/claude_agent_sdk/client.ex`

**New State Fields**:
```elixir
@type state :: %{
  # Existing fields...
  port: port() | nil,  # DEPRECATED - will be removed in v1.0
  transport: Transport.t() | nil,  # NEW
  current_model: String.t() | nil,  # NEW
  pending_model_change: {GenServer.from(), reference()} | nil,  # NEW
  # ... other existing fields
}
```

**New Public Functions**:
```elixir
@spec set_model(pid(), String.t()) :: :ok | {:error, term()}
def set_model(client, model)

@spec get_model(pid()) :: {:ok, String.t()} | {:error, term()}
def get_model(client)
```

### 4. ClaudeAgentSDK.Model (New Module)

**Purpose**: Model validation and normalization.

**Module**: `lib/claude_agent_sdk/model.ex`

```elixir
defmodule ClaudeAgentSDK.Model do
  @moduledoc """
  Model validation and normalization utilities.
  """
  
  @known_models %{
    # Short forms
    "opus" => "claude-opus-4-20250514",
    "sonnet" => "claude-sonnet-4-20250514",
    "haiku" => "claude-haiku-4-20250514",
    
    # Full forms (pass through)
    "claude-opus-4-20250514" => "claude-opus-4-20250514",
    "claude-sonnet-4-20250514" => "claude-sonnet-4-20250514",
    "claude-haiku-4-20250514" => "claude-haiku-4-20250514",
    
    # Legacy versions
    "claude-opus-4" => "claude-opus-4",
    "claude-sonnet-4" => "claude-sonnet-4",
    "claude-haiku-4" => "claude-haiku-4"
  }
  
  @doc """
  Validates and normalizes a model name.
  
  ## Examples
  
      iex> Model.validate("opus")
      {:ok, "claude-opus-4-20250514"}
      
      iex> Model.validate("invalid")
      {:error, :invalid_model}
  """
  @spec validate(String.t()) :: {:ok, String.t()} | {:error, :invalid_model}
  def validate(model)
  
  @doc """
  Returns a list of all known model names.
  """
  @spec list_models() :: [String.t()]
  def list_models()
  
  @doc """
  Suggests similar model names for an invalid input.
  """
  @spec suggest(String.t()) :: [String.t()]
  def suggest(invalid_model)
end
```

### 5. ClaudeAgentSDK.ControlProtocol.Protocol (Enhanced)

**Purpose**: Add encoding/decoding for model change requests.

**Changes to**: `lib/claude_agent_sdk/control_protocol/protocol.ex`

**New Functions**:
```elixir
@doc """
Encodes a set_model control request.

Returns {request_id, json_string}
"""
@spec encode_set_model_request(String.t()) :: {String.t(), String.t()}
def encode_set_model_request(model)

@doc """
Decodes a set_model control response.
"""
@spec decode_set_model_response(map()) :: 
  {:ok, String.t()} | {:error, term()}
def decode_set_model_response(response)
```

## Data Models

### Transport Message Format

All messages between the SDK and CLI are newline-terminated JSON:

```json
{
  "type": "control_request",
  "request_id": "req_abc123",
  "request": {
    "subtype": "set_model",
    "model": "claude-opus-4-20250514"
  }
}
```

### Control Response Format

```json
{
  "type": "control_response",
  "response": {
    "request_id": "req_abc123",
    "subtype": "success",
    "result": {
      "model": "claude-opus-4-20250514",
      "previous_model": "claude-sonnet-4-20250514"
    }
  }
}
```

### Error Response Format

```json
{
  "type": "control_response",
  "response": {
    "request_id": "req_abc123",
    "subtype": "error",
    "error": {
      "code": "invalid_model",
      "message": "Model 'invalid' not found"
    }
  }
}
```

## Error Handling

### Error Types

1. **Validation Errors**
   - `:invalid_model` - Model name not recognized
   - `:invalid_transport` - Transport module not found or invalid

2. **Transport Errors**
   - `{:transport_error, :not_connected}` - Transport not initialized
   - `{:transport_error, :send_failed}` - Failed to send message
   - `{:transport_error, :closed}` - Transport connection closed

3. **CLI Errors**
   - `{:cli_error, message}` - CLI rejected the request
   - `:timeout` - Request timed out (30s)
   - `{:protocol_error, reason}` - Invalid protocol message

4. **State Errors**
   - `:model_change_in_progress` - Another model change is pending
   - `:not_initialized` - Client not fully initialized

### Error Recovery Strategy

```elixir
# Retry logic for transient errors
defp handle_model_change_error(error, state) do
  case error do
    {:transport_error, :send_failed} ->
      # Retry once after 100ms
      Process.send_after(self(), :retry_model_change, 100)
      
    {:cli_error, _} ->
      # CLI rejected - don't retry
      :permanent_failure
      
    :timeout ->
      # Timeout - don't retry
      :permanent_failure
  end
end
```

## Test-Driven Development Strategy

### TDD Workflow

This implementation follows strict **Red-Green-Refactor** cycles:

1. **🔴 RED**: Write a failing test that defines desired behavior
2. **✅ GREEN**: Write minimal code to make the test pass
3. **♻️ REFACTOR**: Improve code quality while keeping tests green
4. **📊 COVERAGE**: Verify coverage remains >95%

### TDD Principles

- **Test First**: No production code without a failing test
- **One Test, One Behavior**: Each test validates exactly one behavior
- **Descriptive Names**: Tests use `should_<behavior>_when_<condition>` pattern
- **Fast Feedback**: Tests run in <1 second (use mocks for external dependencies)
- **Coverage Driven**: Aim for >95% coverage, measure after each cycle

### Test Organization

```
test/
├── claude_agent_sdk/
│   ├── model_test.exs                    # Model validation (TDD Cycle 1)
│   ├── transport_test.exs                # Transport behaviour (TDD Cycle 2)
│   ├── transport/
│   │   └── port_test.exs                 # Port implementation (TDD Cycle 3)
│   ├── client_test.exs                   # Client enhancements (TDD Cycle 4)
│   └── control_protocol/
│       └── protocol_test.exs             # Protocol extensions (TDD Cycle 5)
├── integration/
│   ├── model_switching_live_test.exs     # End-to-end (TDD Cycle 6)
│   ├── custom_transport_test.exs         # Custom transport (TDD Cycle 7)
│   └── backward_compat_test.exs          # Compatibility (TDD Cycle 8)
└── support/
    └── mock_transport.ex                 # Test doubles
```

### TDD Cycle 1: Model Validation

**🔴 RED Phase**:
```elixir
# test/claude_agent_sdk/model_test.exs
defmodule ClaudeAgentSDK.ModelTest do
  use ExUnit.Case
  alias ClaudeAgentSDK.Model
  
  describe "validate/1" do
    test "should_return_full_model_name_when_given_short_form" do
      assert {:ok, "claude-opus-4-20250514"} = Model.validate("opus")
    end
    
    test "should_return_error_when_given_invalid_model" do
      assert {:error, :invalid_model} = Model.validate("invalid")
    end
  end
end
```

**✅ GREEN Phase**: Implement minimal Model module to pass tests

**♻️ REFACTOR Phase**: Extract model map, add documentation

**📊 COVERAGE**: Run `mix test --cover` → verify >95%

### TDD Cycle 2: Transport Behaviour

**🔴 RED Phase**:
```elixir
# test/claude_agent_sdk/transport_test.exs
defmodule ClaudeAgentSDK.TransportTest do
  use ExUnit.Case
  
  describe "behaviour callbacks" do
    test "should_define_start_link_callback" do
      assert function_exported?(ClaudeAgentSDK.Transport, :behaviour_info, 1)
      callbacks = ClaudeAgentSDK.Transport.behaviour_info(:callbacks)
      assert {:start_link, 1} in callbacks
    end
    
    test "should_define_send_callback" do
      callbacks = ClaudeAgentSDK.Transport.behaviour_info(:callbacks)
      assert {:send, 2} in callbacks
    end
  end
end
```

**✅ GREEN Phase**: Define Transport behaviour with @callback declarations

**♻️ REFACTOR Phase**: Add type specs, documentation

**📊 COVERAGE**: Verify behaviour definition coverage

### TDD Cycle 3: Port Transport Implementation

**🔴 RED Phase**:
```elixir
# test/claude_agent_sdk/transport/port_test.exs
defmodule ClaudeAgentSDK.Transport.PortTest do
  use ExUnit.Case
  alias ClaudeAgentSDK.Transport.Port, as: PortTransport
  
  describe "start_link/1" do
    test "should_start_genserver_when_given_valid_options" do
      opts = [command: "echo", args: ["test"]]
      assert {:ok, pid} = PortTransport.start_link(opts)
      assert Process.alive?(pid)
    end
    
    test "should_return_error_when_command_not_found" do
      opts = [command: "nonexistent_command_xyz"]
      assert {:error, _reason} = PortTransport.start_link(opts)
    end
  end
  
  describe "send/2" do
    setup do
      {:ok, transport} = PortTransport.start_link([command: "cat"])
      %{transport: transport}
    end
    
    test "should_send_message_to_port_when_connected", %{transport: t} do
      assert :ok = PortTransport.send(t, "test message\n")
    end
    
    test "should_return_error_when_not_connected" do
      # Stop transport first
      :ok = PortTransport.close(transport)
      assert {:error, :not_connected} = PortTransport.send(transport, "msg")
    end
  end
end
```

**✅ GREEN Phase**: Implement PortTransport GenServer with minimal logic

**♻️ REFACTOR Phase**: Extract Port handling, improve error messages

**📊 COVERAGE**: Verify >95% line coverage for Port module

### TDD Cycle 4: Client Model Switching

**🔴 RED Phase**:
```elixir
# test/claude_agent_sdk/client_test.exs (additions)
describe "set_model/2" do
  setup do
    opts = %Options{transport: MockTransport, model: "sonnet"}
    {:ok, client} = Client.start_link(opts)
    %{client: client}
  end
  
  test "should_return_ok_when_model_change_succeeds", %{client: c} do
    MockTransport.set_response(:set_model, {:ok, "opus"})
    assert :ok = Client.set_model(c, "opus")
  end
  
  test "should_return_error_when_invalid_model", %{client: c} do
    assert {:error, :invalid_model} = Client.set_model(c, "invalid")
  end
  
  test "should_update_current_model_after_successful_change", %{client: c} do
    MockTransport.set_response(:set_model, {:ok, "opus"})
    :ok = Client.set_model(c, "opus")
    assert {:ok, "claude-opus-4-20250514"} = Client.get_model(c)
  end
  
  test "should_timeout_after_30_seconds_when_no_response", %{client: c} do
    MockTransport.set_response(:set_model, :never_respond)
    assert {:error, :timeout} = Client.set_model(c, "opus")
  end
end

describe "get_model/1" do
  test "should_return_current_model_when_set", %{client: c} do
    assert {:ok, "claude-sonnet-4-20250514"} = Client.get_model(c)
  end
end
```

**✅ GREEN Phase**: Implement set_model/2 and get_model/1 in Client

**♻️ REFACTOR Phase**: Extract validation, improve state management

**📊 COVERAGE**: Verify >95% coverage for new Client functions

### TDD Cycle 5: Protocol Extensions

**🔴 RED Phase**:
```elixir
# test/claude_agent_sdk/control_protocol/protocol_test.exs (additions)
describe "encode_set_model_request/1" do
  test "should_return_tuple_with_request_id_and_json" do
    assert {request_id, json} = Protocol.encode_set_model_request("opus")
    assert is_binary(request_id)
    assert is_binary(json)
  end
  
  test "should_generate_unique_request_ids" do
    {id1, _} = Protocol.encode_set_model_request("opus")
    {id2, _} = Protocol.encode_set_model_request("opus")
    assert id1 != id2
  end
  
  test "should_encode_valid_json_with_model_name" do
    {_id, json} = Protocol.encode_set_model_request("opus")
    assert {:ok, decoded} = Jason.decode(json)
    assert decoded["type"] == "control_request"
    assert decoded["request"]["subtype"] == "set_model"
    assert decoded["request"]["model"] == "opus"
  end
end

describe "decode_set_model_response/1" do
  test "should_return_ok_tuple_when_success_response" do
    response = %{
      "response" => %{
        "subtype" => "success",
        "result" => %{"model" => "opus"}
      }
    }
    assert {:ok, "opus"} = Protocol.decode_set_model_response(response)
  end
  
  test "should_return_error_tuple_when_error_response" do
    response = %{
      "response" => %{
        "subtype" => "error",
        "error" => %{"message" => "Invalid model"}
      }
    }
    assert {:error, _} = Protocol.decode_set_model_response(response)
  end
end
```

**✅ GREEN Phase**: Implement Protocol encoding/decoding functions

**♻️ REFACTOR Phase**: Extract JSON building, add validation

**📊 COVERAGE**: Verify >95% coverage for Protocol extensions

### TDD Cycle 6: Integration Testing

**🔴 RED Phase**:
```elixir
# test/integration/model_switching_live_test.exs
defmodule ClaudeAgentSDK.Integration.ModelSwitchingLiveTest do
  use ExUnit.Case
  @moduletag :live
  
  test "should_preserve_context_when_switching_models" do
    {:ok, client} = Client.start_link(%Options{model: "sonnet"})
    
    # Initial message
    Client.send_message(client, "My name is Alice")
    messages = Client.stream_messages(client) |> Enum.take(2)
    
    # Switch model
    assert :ok = Client.set_model(client, "opus")
    
    # Verify context preserved
    Client.send_message(client, "What's my name?")
    response = Client.stream_messages(client) 
      |> Enum.find(&(&1.type == :assistant))
    
    assert response.content =~ "Alice"
  end
end
```

**✅ GREEN Phase**: Ensure all components work together

**♻️ REFACTOR Phase**: Extract test helpers, improve assertions

**📊 COVERAGE**: Integration tests don't count toward coverage but verify behavior

### Coverage Targets

| Module | Target | Measurement |
|--------|--------|-------------|
| Model | >95% | After TDD Cycle 1 |
| Transport (behaviour) | 100% | After TDD Cycle 2 |
| Transport.Port | >95% | After TDD Cycle 3 |
| Client (new code) | >95% | After TDD Cycle 4 |
| Protocol (new code) | >95% | After TDD Cycle 5 |
| **Overall** | **>95%** | **After all cycles** |

### Test Execution

```bash
# Run tests with coverage
mix test --cover

# Run only unit tests (fast feedback)
mix test --exclude integration

# Run integration tests (slower)
mix test --only integration

# Run live tests (requires CLI)
mix test --only live

# Watch mode for TDD
mix test.watch
```

### Mock Strategy

All tests use mocks by default for fast feedback:

```elixir
# test/support/mock_transport.ex
defmodule ClaudeAgentSDK.MockTransport do
  @behaviour ClaudeAgentSDK.Transport
  use GenServer
  
  # Simulates CLI responses without subprocess
  # Configurable responses for different scenarios
  # Tracks all sent messages for assertions
end
```

## Performance Considerations

### Latency Targets

- **Model switching**: < 100ms (excluding CLI processing time)
- **Transport overhead**: < 5% compared to direct Port usage
- **Message throughput**: > 1000 messages/second

### Optimization Strategies

1. **Async Model Changes**
   - Don't block on CLI response
   - Queue subsequent requests
   - Use GenServer call with timeout

2. **Transport Pooling** (Future)
   - Multiple transport processes for parallel queries
   - Load balancing across transports

3. **Message Batching** (Future)
   - Batch multiple control requests
   - Reduce protocol overhead

## Migration Path

### Phase 1: Transport Abstraction (Non-Breaking)

1. Add Transport behaviour
2. Implement Transport.Port
3. Update Client to use Transport internally
4. Keep existing Port-based API working
5. Add deprecation warnings for direct Port access

### Phase 2: Runtime Model Switching

1. Add Model validation module
2. Extend Protocol with set_model encoding
3. Add Client.set_model/2 and Client.get_model/1
4. Add tests and documentation

### Phase 3: Cleanup (v1.0)

1. Remove deprecated Port-based fields
2. Make Transport required in Options
3. Update all examples to use Transport

## Backward Compatibility

### Compatibility Matrix

| Feature | v0.4.0 (Current) | v0.5.0 (New) | v1.0 (Future) |
|---------|------------------|--------------|---------------|
| Direct Port access | ✅ Supported | ⚠️ Deprecated | ❌ Removed |
| Transport abstraction | ❌ N/A | ✅ Supported | ✅ Required |
| Runtime model switching | ❌ N/A | ✅ Supported | ✅ Supported |
| Existing Client API | ✅ Stable | ✅ Stable | ✅ Stable |

### Deprecation Warnings

```elixir
# In v0.5.0
@deprecated "Use transport option instead. Direct port access will be removed in v1.0"
def init(%Options{} = options) do
  if options.transport == nil do
    IO.warn("""
    Direct Port access is deprecated and will be removed in v1.0.
    Please use the transport option:
    
      options = %Options{
        transport: ClaudeAgentSDK.Transport.Port
      }
    """)
  end
  # ...
end
```

## Documentation Requirements

### API Documentation

1. **Transport Behaviour** (`@moduledoc` in `transport.ex`)
   - Overview of transport system
   - How to implement custom transports
   - Examples of Port transport usage

2. **Model Module** (`@moduledoc` in `model.ex`)
   - List of supported models
   - Validation rules
   - Examples

3. **Client Enhancements** (update `@moduledoc` in `client.ex`)
   - Runtime model switching examples
   - Transport configuration examples

### Guides

1. **Runtime Control Guide** (`docs/RUNTIME_CONTROL.md`)
   - When to use runtime model switching
   - Performance implications
   - Best practices

2. **Custom Transport Guide** (`docs/CUSTOM_TRANSPORTS.md`)
   - Implementing a custom transport
   - Testing custom transports
   - Example: HTTP transport

3. **Migration Guide** (`docs/MIGRATION_V0_5.md`)
   - Upgrading from v0.4.0
   - Deprecation timeline
   - Code examples

### README Updates

Add section on runtime control:

```markdown
## Runtime Control

### Model Switching

Change the AI model during an active conversation:

\`\`\`elixir
{:ok, client} = Client.start_link(%Options{model: "sonnet"})

# Start with Sonnet for quick responses
Client.send_message(client, "Summarize this document")

# Switch to Opus for complex reasoning
Client.set_model(client, "opus")
Client.send_message(client, "Analyze the architecture")

# Switch back to Sonnet
Client.set_model(client, "sonnet")
\`\`\`

### Custom Transports

Implement custom communication protocols:

\`\`\`elixir
defmodule MyApp.HTTPTransport do
  @behaviour ClaudeAgentSDK.Transport
  # ... implementation
end

options = %Options{
  transport: MyApp.HTTPTransport,
  transport_opts: [endpoint: "https://api.example.com"]
}
\`\`\`
```

## Security Considerations

### Transport Security

1. **Input Validation**
   - Validate all messages before sending to transport
   - Sanitize model names to prevent injection

2. **Transport Isolation**
   - Each transport runs in its own process
   - Failures don't crash the Client

3. **Credential Handling**
   - Transports should not log sensitive data
   - Use secure storage for API keys

### Model Switching Security

1. **Authorization**
   - Verify user has permission to use requested model
   - Log all model changes for audit

2. **Rate Limiting**
   - Limit model switch frequency (e.g., max 10/minute)
   - Prevent abuse of expensive models

## Monitoring and Observability

### Telemetry Events

```elixir
# Model change started
:telemetry.execute(
  [:claude_agent_sdk, :model, :change, :start],
  %{system_time: System.system_time()},
  %{from_model: "sonnet", to_model: "opus"}
)

# Model change completed
:telemetry.execute(
  [:claude_agent_sdk, :model, :change, :stop],
  %{duration: duration_ms},
  %{model: "opus", success: true}
)

# Transport error
:telemetry.execute(
  [:claude_agent_sdk, :transport, :error],
  %{count: 1},
  %{transport: Transport.Port, error: :send_failed}
)
```

### Logging Strategy

```elixir
# Debug level - detailed flow
Logger.debug("Sending set_model request", 
  model: model, 
  request_id: request_id
)

# Info level - important events
Logger.info("Model changed successfully",
  from: old_model,
  to: new_model,
  duration_ms: duration
)

# Error level - failures
Logger.error("Model change failed",
  model: model,
  error: error,
  request_id: request_id
)
```

## Open Questions

1. **Should we support model switching during active streaming?**
   - Option A: Queue the change until current message completes
   - Option B: Interrupt current message and switch immediately
   - **Recommendation**: Option A (safer, preserves message integrity)

2. **Should Transport be a GenServer or a behaviour with callbacks?**
   - Option A: GenServer (more flexible, easier to test)
   - Option B: Pure callbacks (less overhead, simpler)
   - **Recommendation**: Option A (GenServer) for consistency with Client

3. **Should we validate models against CLI capabilities at runtime?**
   - Option A: Static list in SDK (faster, but may be outdated)
   - Option B: Query CLI for available models (accurate, but slower)
   - **Recommendation**: Option A with periodic updates

4. **How should we handle model switching costs?**
   - Option A: Track and report cost differences
   - Option B: Let users handle cost tracking
   - **Recommendation**: Option B (keep SDK focused on functionality)

## Success Criteria

The implementation will be considered successful when:

1. ✅ All 50 acceptance criteria from requirements.md are met
2. ✅ Test coverage is > 95% for new code
3. ✅ All existing tests continue to pass
4. ✅ Documentation is complete and reviewed
5. ✅ Performance targets are met (< 100ms latency, < 5% overhead)
6. ✅ PYTHON_SDK_COMPARISON.md shows 100% feature parity
7. ✅ No breaking changes to existing API
8. ✅ Live integration tests pass with real Claude CLI

## Timeline Estimate

- **Transport Abstraction**: 3-4 days
  - Day 1: Behaviour definition and Port implementation
  - Day 2: Client integration and testing
  - Day 3: Documentation and examples
  - Day 4: Review and refinement

- **Runtime Model Switching**: 2-3 days
  - Day 1: Model validation and Protocol extensions
  - Day 2: Client.set_model implementation and testing
  - Day 3: Documentation and integration tests

- **Total**: 5-7 days for complete implementation
