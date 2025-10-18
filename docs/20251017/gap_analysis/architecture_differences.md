# Architecture Differences: Python vs Elixir

**Date:** 2025-10-17

This document analyzes the architectural differences between the Python SDK and Elixir port, examining design patterns, concurrency models, and structural choices.

---

## 1. Concurrency Model

### Python: Async/Await
```python
# Async generators for streaming
async def query(prompt: str, options: ClaudeAgentOptions) -> AsyncIterator[Message]:
    async with transport:
        await transport.send(prompt)
        async for message in transport.receive():
            yield message

# Async context managers for client
async with ClaudeSDKClient(options) as client:
    await client.query("Hello")
    async for message in client.receive_messages():
        print(message)
```

**Characteristics:**
- Single-threaded event loop (asyncio)
- Cooperative multitasking
- async/await syntax
- AsyncIterator for streaming
- Context managers for resource cleanup

**Advantages:**
- Familiar to Python developers
- Good for I/O-bound operations
- Lower overhead than threading

**Limitations:**
- GIL prevents true parallelism
- Complexity with mixing sync/async code
- Requires event loop management

---

### Elixir: Actor Model (GenServer)
```elixir
# Streams for lazy evaluation
def query(prompt, options) do
  Stream.resource(
    fn -> start_process(prompt, options) end,
    fn state -> {messages, new_state} end,
    fn state -> cleanup(state) end
  )
end

# GenServer for bidirectional client
{:ok, client} = ClaudeAgentSDK.Client.start_link(options)
ClaudeAgentSDK.Client.send_message(client, "Hello")

ClaudeAgentSDK.Client.stream_messages(client)
|> Stream.each(&IO.inspect/1)
|> Stream.run()
```

**Characteristics:**
- Process-based concurrency (Erlang VM)
- Actor model with message passing
- Lightweight processes (thousands per core)
- Supervision trees for fault tolerance
- Stream abstraction for lazy evaluation

**Advantages:**
- True parallelism (no GIL)
- Fault isolation (process crashes isolated)
- Built-in supervision and restart
- Scalable to distributed systems

**Limitations:**
- Message passing overhead for small operations
- Process spawning for each client
- Learning curve for GenServer patterns

---

### Architectural Impact

| Aspect | Python | Elixir | Winner |
|--------|--------|--------|--------|
| **Parallelism** | Cooperative (event loop) | Preemptive (scheduler) | ✅ Elixir |
| **Fault Tolerance** | Exception handling | Supervision trees | ✅ Elixir |
| **Scalability** | Limited by GIL | Scales to millions of processes | ✅ Elixir |
| **Resource Usage** | Lower for single tasks | Higher per-process overhead | ✅ Python (single task) |
| **Concurrency Safety** | Manual synchronization | Message passing (safe by default) | ✅ Elixir |
| **Learning Curve** | Easier (familiar syntax) | Steeper (functional + actor model) | ✅ Python |

**Conclusion:** Elixir's architecture is superior for **concurrent, fault-tolerant, scalable** applications. Python's is simpler for **single-task, I/O-bound** operations.

---

## 2. State Management

### Python: Async Context Managers
```python
class ClaudeSDKClient:
    def __init__(self, options: ClaudeAgentOptions, transport: Transport):
        self._options = options
        self._transport = transport
        self._connected = False

    async def connect(self) -> None:
        self._connected = True
        await self._transport.connect()

    async def __aenter__(self) -> "ClaudeSDKClient":
        await self.connect()
        return self

    async def __aexit__(self, *args) -> None:
        await self.disconnect()
```

**Characteristics:**
- Instance variables for mutable state
- Manual state management
- Context managers for lifecycle
- No built-in concurrency safety

**Challenges:**
- Shared mutable state (requires locks for thread safety)
- No automatic cleanup on crash
- Manual resource management

---

### Elixir: GenServer State
```elixir
defmodule ClaudeAgentSDK.Client do
  use GenServer

  defstruct [:options, :process, :messages, :session_id]

  @impl true
  def init(options) do
    state = %__MODULE__{
      options: options,
      process: nil,
      messages: [],
      session_id: nil
    }
    {:ok, state}
  end

  @impl true
  def handle_call({:send_message, prompt}, _from, state) do
    # State transformation
    new_state = %{state | messages: [prompt | state.messages]}
    {:reply, :ok, new_state}
  end

  @impl true
  def terminate(_reason, state) do
    # Automatic cleanup
    cleanup_process(state.process)
    :ok
  end
end
```

**Characteristics:**
- Immutable state updates
- GenServer encapsulates state
- Automatic lifecycle management
- Concurrency-safe by default (single process handles state)

**Advantages:**
- No race conditions (single process per client)
- Automatic cleanup on crash
- Supervised restart possible
- State transformations are pure functions

---

## 3. Transport Layer

### Python: Abstract Base Class
```python
from abc import ABC, abstractmethod

class Transport(ABC):
    @abstractmethod
    async def send(self, message: str) -> None:
        """Send a message"""
        pass

    @abstractmethod
    async def receive(self) -> AsyncIterator[str]:
        """Receive messages"""
        pass

    @abstractmethod
    async def close(self) -> None:
        """Close transport"""
        pass

class SubprocessCliTransport(Transport):
    async def send(self, message: str) -> None:
        self._process.stdin.write(message.encode())

    async def receive(self) -> AsyncIterator[str]:
        async for line in self._process.stdout:
            yield line.decode()
```

**Characteristics:**
- Interface via ABC
- Pluggable implementations
- Async methods

---

### Elixir: Hardcoded Process Execution (Current)
```elixir
defmodule ClaudeAgentSDK.Process do
  def stream(prompt, options, callback) do
    port = Port.open({:spawn, build_command(options)}, [
      :binary,
      :exit_status,
      {:line, 1024}
    ])

    Port.command(port, prompt)

    Stream.resource(
      fn -> port end,
      fn port -> receive_messages(port) end,
      fn port -> Port.close(port) end
    )
  end
end
```

**Characteristics:**
- No abstraction layer
- Direct port communication
- Hardcoded to CLI subprocess

**Gap:** Need behavior-based abstraction

```elixir
# Proposed
defmodule ClaudeAgentSDK.Transport do
  @callback init(opts :: keyword()) :: {:ok, state :: any()}
  @callback send(state, message :: String.t()) :: {:ok, state}
  @callback receive(state) :: {:ok, Stream.t(), state}
  @callback close(state) :: :ok
end

defmodule ClaudeAgentSDK.Transport.CLI do
  @behaviour ClaudeAgentSDK.Transport
  # Implementation
end
```

---

## 4. Error Handling

### Python: Exception Hierarchy
```python
class ClaudeSDKError(Exception):
    """Base exception"""
    pass

class CLIConnectionError(ClaudeSDKError):
    """CLI connection failed"""
    pass

class ProcessError(ClaudeSDKError):
    """Process exited with error"""
    def __init__(self, exit_code: int, stderr: str):
        self.exit_code = exit_code
        self.stderr = stderr
        super().__init__(f"Process exited {exit_code}: {stderr}")

# Usage
try:
    async for message in query(prompt, options):
        print(message)
except CLINotFoundError:
    print("Install Claude CLI")
except ProcessError as e:
    print(f"Exit code: {e.exit_code}")
```

**Characteristics:**
- Exception hierarchy
- Typed exceptions with attributes
- Try/except for control flow
- Stack traces for debugging

---

### Elixir: Error Tuples + Pattern Matching
```elixir
# Tagged tuples
case ClaudeAgentSDK.query(prompt, options) do
  {:ok, stream} ->
    Stream.run(stream)

  {:error, :cli_not_found} ->
    IO.puts("Install Claude CLI")

  {:error, {:process_error, exit_code, stderr}} ->
    IO.puts("Exit code: #{exit_code}")

  {:error, reason} ->
    IO.inspect(reason)
end

# Or with bang version
try do
  ClaudeAgentSDK.query!(prompt, options)
rescue
  e in RuntimeError -> IO.inspect(e)
end
```

**Characteristics:**
- `{:ok, result}` / `{:error, reason}` tuples
- Pattern matching for error handling
- Explicit error propagation
- "Let it crash" philosophy

**Advantages:**
- Errors are values (easier to compose)
- Explicit error handling in type signatures
- No hidden control flow
- Supervision handles crashes gracefully

---

## 5. Type System

### Python: Gradual Typing (Type Hints)
```python
from typing import AsyncIterator, Optional, List, Union

class ClaudeAgentOptions:
    def __init__(
        self,
        system: Optional[str] = None,
        max_turns: Optional[int] = None,
        mcp_servers: Optional[List[McpServerConfig]] = None,
        # ...
    ) -> None:
        self.system = system
        self.max_turns = max_turns
        self.mcp_servers = mcp_servers or []

Message = Union[UserMessage, AssistantMessage, SystemMessage, ResultMessage]

async def query(
    prompt: str,
    options: ClaudeAgentOptions,
    transport: Optional[Transport] = None
) -> AsyncIterator[Message]:
    # Implementation
```

**Characteristics:**
- Optional static typing (mypy)
- Runtime duck typing
- Type hints for documentation
- Union types for message variants

**Limitations:**
- Not enforced at runtime
- Can be ignored
- No compile-time guarantees

---

### Elixir: Dynamic with Specs
```elixir
defmodule ClaudeAgentSDK.Options do
  @type t :: %__MODULE__{
    system: String.t() | nil,
    max_turns: pos_integer() | nil,
    mcp_servers: [map()] | nil,
    # ...
  }

  defstruct [
    :system,
    :max_turns,
    :mcp_servers
    # ...
  ]

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    struct(__MODULE__, opts)
  end
end

@spec query(String.t(), Options.t()) :: Enumerable.t()
def query(prompt, options) do
  # Implementation
end
```

**Characteristics:**
- Dynamic runtime typing
- `@spec` for function signatures
- `@type` for custom types
- Dialyzer for static analysis

**Advantages:**
- Structs enforce structure
- Pattern matching for type checking
- Dialyzer catches type errors
- More flexible than static typing

---

## 6. Message Representation

### Python: Typed Classes
```python
@dataclass
class TextBlock:
    type: Literal["text"] = "text"
    text: str

@dataclass
class ToolUseBlock:
    type: Literal["tool_use"] = "tool_use"
    id: str
    name: str
    input: dict

@dataclass
class AssistantMessage:
    type: Literal["assistant"] = "assistant"
    content: List[ContentBlock]
    stop_reason: Optional[str] = None

# Usage - strongly typed
message = AssistantMessage(
    content=[
        TextBlock(text="Hello"),
        ToolUseBlock(id="1", name="read", input={"path": "file.txt"})
    ]
)

text = message.content[0].text  # Type-safe access
```

**Advantages:**
- IDE autocomplete
- Type checking with mypy
- Clear structure
- Validated at construction

---

### Elixir: Maps with Pattern Matching
```elixir
# Raw JSON parsed to maps
message = %{
  "type" => "assistant",
  "content" => [
    %{"type" => "text", "text" => "Hello"},
    %{"type" => "tool_use", "id" => "1", "name" => "read", "input" => %{"path" => "file.txt"}}
  ],
  "stop_reason" => nil
}

# Pattern matching for access
case message do
  %{"type" => "assistant", "content" => [%{"type" => "text", "text" => text} | _]} ->
    IO.puts(text)

  %{"type" => "assistant", "content" => content} ->
    Enum.each(content, &process_block/1)
end

# Helper utilities
text = ClaudeAgentSDK.ContentExtractor.extract_text(message)
```

**Characteristics:**
- Flexible (no strict schema)
- Pattern matching for extraction
- Utility functions for common operations
- Direct JSON mapping

**Trade-offs:**
- Less IDE support
- No compile-time validation
- More flexible for schema changes
- Easier to work with JSON

**Proposed Enhancement:**
```elixir
# Could add structs for better structure
defmodule ClaudeAgentSDK.Message.Text do
  @type t :: %__MODULE__{type: String.t(), text: String.t()}
  defstruct type: "text", text: ""
end

defmodule ClaudeAgentSDK.Message.Assistant do
  @type t :: %__MODULE__{
    type: String.t(),
    content: [map()],
    stop_reason: String.t() | nil
  }
  defstruct [:type, :content, :stop_reason]
end
```

---

## 7. Hook System Architecture

### Python: Callback Functions
```python
from typing import Callable

HookCallback = Callable[[HookContext], HookJSONOutput]

def my_hook(context: HookContext) -> HookJSONOutput:
    if isinstance(context.input, PreToolUseHookInput):
        return {"decision": "block", "reason": "Not allowed"}
    return {"decision": "continue"}

options = ClaudeAgentOptions(
    hooks=[
        HookCallback(
            callback=my_hook,
            matcher=HookMatcher(event_types=["pre_tool_use"])
        )
    ]
)
```

**Characteristics:**
- Functions as hooks
- Type checking for input/output
- Matcher-based routing

---

### Elixir: Function + Output Builder
```elixir
alias ClaudeAgentSDK.Hooks.Output

my_hook = fn event ->
  case event.type do
    "pre_tool_use" ->
      Output.block("Not allowed")

    _ ->
      Output.continue()
  end
end

options = Options.new(
  hooks: [
    %{
      callback: my_hook,
      matcher: %{event_types: ["pre_tool_use"]}
    }
  ]
)
```

**Characteristics:**
- Anonymous functions
- Output builder module (advantage)
- Pattern matching in hooks
- Registry for hook management

**Elixir Advantage:**
```elixir
# Composable output builders
Output.deny("Rejected")
|> Output.with_reason("Security policy")
|> Output.add_context(%{policy_id: 123})
|> Output.with_system_message("This was blocked by policy 123")

# Validation
Output.validate(output)  # Checks structure
```

---

## 8. Testing Infrastructure

### Python: Pytest + Mocking
```python
# tests/test_client.py
import pytest
from unittest.mock import AsyncMock, patch

@pytest.mark.asyncio
async def test_client_query():
    transport = AsyncMock()
    transport.receive.return_value = async_iter([
        {"type": "assistant", "content": [{"type": "text", "text": "Hi"}]}
    ])

    client = ClaudeSDKClient(options, transport=transport)
    async with client:
        await client.query("Hello")
        messages = [msg async for msg in client.receive_messages()]

    assert len(messages) == 1
    assert messages[0].content[0].text == "Hi"
```

**Characteristics:**
- Pytest framework
- AsyncMock for async code
- Patch for dependency injection

---

### Elixir: ExUnit + Custom Mock
```elixir
# test/claude_agent_sdk/client_test.exs
defmodule ClaudeAgentSDK.ClientTest do
  use ExUnit.Case

  test "client sends and receives messages" do
    # Custom mock framework
    ClaudeAgentSDK.Mock.setup_responses([
      %{"type" => "assistant", "content" => [%{"type" => "text", "text" => "Hi"}]}
    ])

    {:ok, client} = ClaudeAgentSDK.Client.start_link(mock: true)
    :ok = ClaudeAgentSDK.Client.send_message(client, "Hello")

    messages =
      ClaudeAgentSDK.Client.stream_messages(client)
      |> Enum.to_list()

    assert length(messages) == 1
    assert hd(messages)["content"] |> hd() |> Map.get("text") == "Hi"
  end
end
```

**Characteristics:**
- ExUnit framework
- Custom mock module
- Process-based test isolation

**Elixir Advantage:**
- Process isolation (tests can't interfere)
- Custom mock framework integrated
- More control over async behavior

---

## 9. Dependency Management

### Python: pyproject.toml
```toml
[project]
name = "claude-agent-sdk"
version = "0.1.0"
requires-python = ">=3.10"
dependencies = [
    "anyio>=4.0.0",
    "mcp>=0.1.0",
    "typing_extensions>=4.0.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=7.0.0",
    "pytest-asyncio>=0.21.0",
    "mypy>=1.0.0",
    "ruff>=0.1.0",
]
```

**Characteristics:**
- PEP 621 standard
- Pip for installation
- Virtual environments for isolation

---

### Elixir: mix.exs
```elixir
defmodule ClaudeAgentSDK.MixProject do
  use Mix.Project

  def project do
    [
      app: :claude_agent_sdk,
      version: "0.3.0",
      elixir: "~> 1.14",
      deps: deps()
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.3", only: [:dev], runtime: false}
    ]
  end
end
```

**Characteristics:**
- Mix build tool
- Hex package manager
- OTP applications

---

## 10. Documentation

### Python: Docstrings + Sphinx
```python
def query(
    prompt: str,
    options: ClaudeAgentOptions,
    transport: Optional[Transport] = None
) -> AsyncIterator[Message]:
    """
    Execute a single query to the Claude agent.

    Args:
        prompt: The user's prompt
        options: Configuration options
        transport: Optional custom transport (defaults to CLI)

    Yields:
        Message objects from the agent

    Raises:
        CLINotFoundError: If Claude CLI is not installed
        ProcessError: If the process exits with error

    Example:
        >>> async for message in query("Hello", options):
        ...     print(message)
    """
```

**Characteristics:**
- Docstrings in code
- Sphinx for HTML generation
- Type hints as documentation

---

### Elixir: @moduledoc + @doc + ExDoc
```elixir
defmodule ClaudeAgentSDK do
  @moduledoc """
  Main entry point for the Claude Agent SDK.

  Provides high-level functions for querying Claude agents.

  ## Example

      iex> ClaudeAgentSDK.query("Hello", Options.new())
      #Stream<...>
  """

  @doc """
  Execute a single query to the Claude agent.

  ## Parameters

    * `prompt` - The user's prompt (string)
    * `options` - Configuration options

  ## Returns

    * `Stream.t()` - A stream of message maps

  ## Examples

      iex> ClaudeAgentSDK.query("Hello", Options.new())
      #Stream<...>

      iex> stream = ClaudeAgentSDK.query("Analyze code", opts)
      iex> Enum.take(stream, 1)
      [%{"type" => "assistant", ...}]
  """
  @spec query(String.t(), Options.t()) :: Enumerable.t()
  def query(prompt, options) do
    # Implementation
  end
end
```

**Characteristics:**
- @moduledoc and @doc attributes
- ExDoc for HTML generation
- Doctests (executable examples)
- Integrated with type specs

**Elixir Advantage:**
- Doctests run as part of test suite
- Better integration with code

---

## Architecture Comparison Matrix

| Aspect | Python | Elixir | Better For |
|--------|--------|--------|------------|
| **Concurrency** | Async/await (event loop) | Actor model (processes) | ✅ Elixir (scalability) |
| **State Management** | Mutable instances | Immutable GenServer | ✅ Elixir (safety) |
| **Error Handling** | Exceptions | Tuples + pattern matching | ✅ Elixir (explicit) |
| **Type System** | Gradual typing | Dynamic + specs | ⚠️ Tie |
| **Transport** | Abstract (pluggable) | Hardcoded (needs work) | ✅ Python |
| **Message Representation** | Typed classes | Maps | ✅ Python (IDE support) |
| **Hook System** | Callbacks | Callbacks + builders | ✅ Elixir (builders) |
| **Testing** | Pytest + mocks | ExUnit + custom mock | ✅ Elixir (isolation) |
| **Documentation** | Docstrings + Sphinx | @doc + ExDoc + doctests | ✅ Elixir (doctests) |
| **Dependency Mgmt** | pip + pyproject.toml | Mix + Hex | ⚠️ Tie |

---

## Recommendations

### Keep Elixir's Architectural Strengths
1. **GenServer for Client** - Superior state management
2. **Stream Abstraction** - Lazy, composable
3. **Actor Model** - Better concurrency
4. **Supervision** - Fault tolerance
5. **Output Builders** - Better DX for hooks

### Address Elixir's Gaps
1. **Transport Abstraction** - Define behavior, enable pluggability
2. **Message Structs** - Optional typed structs for better DX
3. **Error Hierarchy** - More specific error atoms/tuples

### Python Patterns Worth Adopting
1. **Typed Message Classes** - Better IDE support (optional in Elixir)
2. **Clear Interface Abstraction** - Transport behavior
3. **Comprehensive Type Hints** - Better specs and dialyzer types

### Elixir-Native Enhancements
1. **Supervision Trees** - Integrate client into supervision tree
2. **Telemetry** - Built-in observability
3. **Distribution** - Leverage Erlang distribution for multi-node queries
4. **OTP Patterns** - Use more OTP patterns (GenStage for backpressure, Registry for clients)

---

## Conclusion

The architectural differences reflect the **strengths of each language ecosystem**:

- **Python** excels at **simplicity, familiarity, and IDE support**
- **Elixir** excels at **concurrency, fault tolerance, and scalability**

The Elixir port should:
1. **Preserve** its architectural advantages (GenServer, supervision, actor model)
2. **Address** gaps (transport abstraction, optional typed structs)
3. **Leverage** Elixir-specific features (telemetry, distribution, OTP)
4. **Maintain** API compatibility where possible, but embrace idioms where appropriate

The goal is **functional parity** with **architectural excellence** suited to each platform.
