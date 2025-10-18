# Detailed Feature Gap Analysis

**Date:** 2025-10-17

This document provides a granular, feature-by-feature comparison between the Python SDK and Elixir port.

---

## 1. Query Interfaces

### ✅ FULL PARITY

| Feature | Python | Elixir | Status |
|---------|--------|--------|--------|
| One-shot query | `query(prompt, options)` | `query(prompt, options)` | ✅ Complete |
| Async streaming | AsyncIterator | Stream/Enum | ✅ Complete |
| Bidirectional client | `ClaudeSDKClient` | `ClaudeAgentSDK.Client` | ✅ Complete |
| Message streaming | `receive_messages()` | `stream_messages()` | ✅ Complete |
| Session management | Via client | Via GenServer | ✅ Complete |

**Assessment:** The Elixir port provides equivalent query functionality with idiomatic Elixir patterns (GenServer for state, Stream for lazy evaluation).

---

## 2. MCP Tool System

### ❌ MAJOR GAP - NOT IMPLEMENTED

| Feature | Python | Elixir | Status |
|---------|--------|--------|--------|
| Tool decorator | `@tool(name, description, schema)` | ❌ None | ❌ Missing |
| SDK MCP server | `create_sdk_mcp_server()` | ❌ None | ❌ Missing |
| Tool registration | Automatic via decorator | ❌ None | ❌ Missing |
| Tool execution | Callback routing | ❌ None | ❌ Missing |
| In-process tools | Yes (no subprocess) | ❌ None | ❌ Missing |

**Python Implementation Details:**
```python
from claude_agent_sdk import tool, create_sdk_mcp_server

@tool(
    name="calculator",
    description="Performs calculations",
    input_schema={
        "type": "object",
        "properties": {
            "expression": {"type": "string"}
        }
    }
)
async def calculator(expression: str) -> str:
    return str(eval(expression))

server = create_sdk_mcp_server(
    name="math-tools",
    version="1.0.0",
    tools=[calculator]
)
```

**Elixir Gap:**
- No macro-based tool definition
- No server creation utilities
- No tool callback system
- Tools must be external MCP servers (subprocess overhead)

**Impact:** HIGH - This is a **core SDK feature** that enables efficient in-process tool execution.

**Recommendation:**
```elixir
defmodule ClaudeAgentSDK.Tool do
  defmacro deftool(name, description, schema, do: block) do
    # Register tool with SDK MCP server
  end
end

defmodule MyTools do
  use ClaudeAgentSDK.Tool

  deftool :calculator, "Performs calculations",
    %{type: "object", properties: %{expression: %{type: "string"}}} do
    def execute(%{"expression" => expr}) do
      # Implementation
    end
  end
end

server = ClaudeAgentSDK.create_sdk_mcp_server(
  name: "math-tools",
  version: "1.0.0",
  tools: [MyTools.Calculator]
)
```

---

## 3. Permission System

### ⚠️ PARTIAL IMPLEMENTATION

| Feature | Python | Elixir | Status |
|---------|--------|--------|--------|
| Permission callbacks | `can_use_tool` async fn | ❌ None | ❌ Missing |
| Permission modes | 4 modes (default, acceptEdits, plan, bypass) | ❌ None | ❌ Missing |
| Tool-specific permissions | Yes | Via hooks (partial) | ⚠️ Partial |
| Permission updates | Add/remove/replace rules | ❌ None | ❌ Missing |
| Destination-aware | user/project/local/session | ❌ None | ❌ Missing |
| Context in callbacks | `ToolPermissionContext` | ❌ None | ❌ Missing |

**Python Implementation:**
```python
async def can_use_tool(context: ToolPermissionContext) -> PermissionResult:
    if context.tool_name == "dangerous_tool":
        return PermissionResultDeny(reason="Not allowed")
    return PermissionResultAllow()

options = ClaudeAgentOptions(
    permission_mode="plan",
    can_use_tool=can_use_tool
)

# Runtime updates
client.set_permission_mode("acceptEdits")
```

**Elixir Status:**
- Hooks system can intercept tool use (pre_tool_use)
- No structured permission callback API
- No permission modes
- No runtime permission updates

**Impact:** MEDIUM - Important for security/control scenarios

**Recommendation:** Extend hooks system with dedicated permission callbacks:
```elixir
options = Options.new(
  permission_mode: :plan,
  can_use_tool: fn context ->
    if context.tool_name == "dangerous_tool" do
      {:deny, reason: "Not allowed"}
    else
      :allow
    end
  end
)

ClaudeAgentSDK.Client.set_permission_mode(client, :accept_edits)
```

---

## 4. Agent Definitions

### ❌ NOT IMPLEMENTED

| Feature | Python | Elixir | Status |
|---------|--------|--------|--------|
| Agent profiles | `AgentDefinition` type | ❌ None | ❌ Missing |
| Custom agent prompts | Yes | ❌ None | ❌ Missing |
| Agent-specific tools | Yes | ❌ None | ❌ Missing |
| Agent-specific models | Yes | ❌ None | ❌ Missing |
| Agent switching | `set_agent()` | ❌ None | ❌ Missing |

**Python Implementation:**
```python
code_agent = AgentDefinition(
    description="Python coding expert",
    prompt="You are a Python expert...",
    allowed_tools=["read", "write", "bash"],
    model="claude-sonnet-4"
)

research_agent = AgentDefinition(
    description="Research specialist",
    prompt="You excel at research...",
    allowed_tools=["websearch", "webfetch"],
    model="claude-opus-4"
)

options = ClaudeAgentOptions(
    agents=[code_agent, research_agent],
    agent=code_agent  # Start with code_agent
)

# Switch agents at runtime
client.set_agent(research_agent)
```

**Elixir Gap:**
- No agent definition structure
- Cannot configure per-agent behavior
- No agent switching API

**Impact:** HIGH - Limits multi-agent workflows

**Recommendation:**
```elixir
defmodule ClaudeAgentSDK.Agent do
  defstruct [:name, :description, :prompt, :allowed_tools, :model]
end

code_agent = %Agent{
  name: :code_expert,
  description: "Python coding expert",
  prompt: "You are a Python expert...",
  allowed_tools: ["read", "write", "bash"],
  model: "claude-sonnet-4"
}

options = Options.new(
  agents: [code_agent, research_agent],
  agent: code_agent
)

ClaudeAgentSDK.Client.set_agent(client, research_agent)
```

---

## 5. Configuration Options

### ⚠️ PARTIAL PARITY

| Option | Python | Elixir | Status |
|--------|--------|--------|--------|
| `system` | ✅ System prompt | ✅ Yes | ✅ Complete |
| `max_turns` | ✅ Yes | ✅ Yes | ✅ Complete |
| `working_directory` | ✅ Yes | ✅ `cwd` | ✅ Complete |
| `mcp_servers` | ✅ Yes | ✅ Yes | ✅ Complete |
| `permission_mode` | ✅ 4 modes | ❌ None | ❌ Missing |
| `can_use_tool` | ✅ Callback | ❌ None | ❌ Missing |
| `model` | ✅ Yes | ✅ Yes | ✅ Complete |
| `allowed_tools` | ✅ Yes | ⚠️ Via hooks | ⚠️ Partial |
| `hooks` | ✅ Yes | ✅ Yes | ✅ Complete |
| `agents` | ✅ Agent list | ❌ None | ❌ Missing |
| `agent` | ✅ Active agent | ❌ None | ❌ Missing |
| `setting_source` | ✅ user/project/local | ⚠️ Implicit | ⚠️ Partial |
| `include_partial_messages` | ✅ Yes | ❌ None | ❌ Missing |
| `stderr_callback` | ✅ Yes | ❌ None | ❌ Missing |

**Python Options:**
```python
ClaudeAgentOptions(
    system="Custom system prompt",
    max_turns=10,
    working_directory="/path",
    mcp_servers=[server1, server2],
    permission_mode="plan",
    can_use_tool=callback,
    model="claude-sonnet-4",
    allowed_tools=["read", "write"],
    hooks=[hook1, hook2],
    agents=[agent1, agent2],
    agent=agent1,
    setting_source=SettingSource.PROJECT,
    include_partial_messages=True,
    stderr_callback=handle_stderr
)
```

**Elixir Options:**
```elixir
Options.new(
  system: "Custom system prompt",
  max_turns: 10,
  cwd: "/path",
  mcp_servers: [server1, server2],
  # Missing: permission_mode, can_use_tool
  model: "claude-sonnet-4",
  # Missing: allowed_tools (use hooks instead)
  hooks: [hook1, hook2],
  # Missing: agents, agent
  # Missing: setting_source explicit control
  # Missing: include_partial_messages
  # Missing: stderr_callback
)
```

---

## 6. Message Types & Content Blocks

### ✅ FULL PARITY

| Type | Python | Elixir | Status |
|------|--------|--------|--------|
| `UserMessage` | ✅ | ✅ `user` type | ✅ Complete |
| `AssistantMessage` | ✅ | ✅ `assistant` type | ✅ Complete |
| `SystemMessage` | ✅ | ✅ `system` type | ✅ Complete |
| `ResultMessage` | ✅ | ✅ `result` type | ✅ Complete |
| `TextBlock` | ✅ | ✅ Parsed from JSON | ✅ Complete |
| `ThinkingBlock` | ✅ | ✅ Parsed from JSON | ✅ Complete |
| `ToolUseBlock` | ✅ | ✅ Parsed from JSON | ✅ Complete |
| `ToolResultBlock` | ✅ | ✅ Parsed from JSON | ✅ Complete |

**Assessment:** Message parsing is complete and functionally equivalent.

---

## 7. Hooks System

### ✅ FULL PARITY (WITH ENHANCEMENTS)

| Feature | Python | Elixir | Status |
|---------|--------|--------|--------|
| Hook types | 6 types | 6 types | ✅ Complete |
| Pattern matching | Yes | Yes | ✅ Complete |
| Async/sync hooks | Yes | Yes (via Task) | ✅ Complete |
| Hook outputs | Multiple types | 13+ builder functions | ✅ Enhanced |
| Context attachment | Yes | ✅ `add_context/2` | ✅ Complete |
| System messages | Yes | ✅ `with_system_message/2` | ✅ Complete |
| Hook registry | Implicit | ✅ Explicit registry | ✅ Enhanced |

**Python Hook Types:**
1. `PreToolUseHookInput`
2. `PostToolUseHookInput`
3. `UserPromptSubmitHookInput`
4. `StopHookInput`
5. `SubagentStopHookInput`
6. `PreCompactHookInput`

**Elixir Hook Types:** Same 6 types

**Elixir Advantages:**
- Comprehensive output builder module (13 functions)
- Explicit hook registry for management
- Better validation and error handling

---

## 8. Transport Layer

### ⚠️ PARTIAL - NO ABSTRACTION

| Feature | Python | Elixir | Status |
|---------|--------|--------|--------|
| Transport ABC | ✅ `Transport` protocol | ❌ None | ❌ Missing |
| CLI transport | ✅ `SubprocessCliTransport` | ✅ Hardcoded | ⚠️ Partial |
| Custom transports | ✅ Pluggable | ❌ None | ❌ Missing |
| Transport interface | `send()`, `receive()`, `close()` | ❌ None | ❌ Missing |

**Python Architecture:**
```python
class Transport(ABC):
    @abstractmethod
    async def send(self, message: str) -> None: ...

    @abstractmethod
    async def receive(self) -> AsyncIterator[str]: ...

    @abstractmethod
    async def close(self) -> None: ...

# Usage
transport = SubprocessCliTransport()
# Or custom:
transport = CustomTransport(config)
```

**Elixir Status:**
- Process execution hardcoded in `ClaudeAgentSDK.Process`
- No behavior/protocol for custom transports
- Cannot plug in HTTP, WebSocket, or other transports

**Impact:** MEDIUM - Limits extensibility

**Recommendation:**
```elixir
defmodule ClaudeAgentSDK.Transport do
  @callback send(t(), String.t()) :: :ok | {:error, term()}
  @callback receive(t()) :: {:ok, Stream.t()} | {:error, term()}
  @callback close(t()) :: :ok
end

defmodule ClaudeAgentSDK.Transport.CLI do
  @behaviour ClaudeAgentSDK.Transport
  # Existing Process.stream implementation
end

# Usage
transport = ClaudeAgentSDK.Transport.CLI.new()
# Or custom:
transport = MyCustomTransport.new(config)

ClaudeAgentSDK.query(prompt, transport: transport)
```

---

## 9. Error Handling

### ⚠️ SIMPLIFIED

| Error Type | Python | Elixir | Status |
|------------|--------|--------|--------|
| Base error | `ClaudeSDKError` | Generic errors | ⚠️ Different |
| Connection error | `CLIConnectionError` | Pattern match on exit | ⚠️ Different |
| CLI not found | `CLINotFoundError` | Pattern match | ⚠️ Different |
| Process error | `ProcessError` (exit code + stderr) | Pattern match | ⚠️ Different |
| JSON decode | `CLIJSONDecodeError` | Jason.DecodeError | ⚠️ Different |

**Python Hierarchy:**
```python
ClaudeSDKError (base)
├── CLIConnectionError
├── CLINotFoundError
├── ProcessError
└── CLIJSONDecodeError
```

**Elixir Approach:**
- Uses Elixir's `{:ok, result}` / `{:error, reason}` tuples
- Less specific exception types
- More idiomatic Elixir error handling

**Assessment:** Different but idiomatic to each language. Not a critical gap.

---

## 10. Client Control Flow

### ⚠️ PARTIAL

| Feature | Python | Elixir | Status |
|---------|--------|--------|--------|
| `connect()` | ✅ Explicit | ✅ `start_link()` | ✅ Complete |
| `query()` | ✅ Send message | ✅ `send_message()` | ✅ Complete |
| `receive_messages()` | ✅ Stream | ✅ `stream_messages()` | ✅ Complete |
| `interrupt()` | ✅ Stop execution | ❌ None | ❌ Missing |
| `set_permission_mode()` | ✅ Change mode | ❌ None | ❌ Missing |
| `set_model()` | ✅ Switch model | ❌ None | ❌ Missing |
| `set_agent()` | ✅ Switch agent | ❌ None | ❌ Missing |
| `disconnect()` | ✅ Close | ✅ `stop()` | ✅ Complete |

**Python Control APIs:**
```python
client.interrupt()  # Stop current execution
client.set_permission_mode("plan")
client.set_model("claude-opus-4")
client.set_agent(research_agent)
```

**Impact:** MEDIUM - Runtime control is limited

**Recommendation:** Add to `ClaudeAgentSDK.Client` GenServer:
```elixir
ClaudeAgentSDK.Client.interrupt(client)
ClaudeAgentSDK.Client.set_permission_mode(client, :plan)
ClaudeAgentSDK.Client.set_model(client, "claude-opus-4")
ClaudeAgentSDK.Client.set_agent(client, research_agent)
```

---

## 11. Orchestration & Concurrency

### ✅ ELIXIR EXCEEDS PYTHON

| Feature | Python | Elixir | Status |
|---------|--------|--------|--------|
| Parallel execution | ❌ None | ✅ `query_parallel/2` | ✅ Elixir advantage |
| Pipeline workflows | ❌ None | ✅ `query_pipeline/2` | ✅ Elixir advantage |
| Retry with backoff | ❌ None | ✅ `query_with_retry/3` | ✅ Elixir advantage |
| Rate limiting | ❌ None | ✅ Built-in | ✅ Elixir advantage |

**Elixir Orchestrator:**
```elixir
# Parallel execution
ClaudeAgentSDK.Orchestrator.query_parallel([
  {"Analyze file1.ex", opts},
  {"Analyze file2.ex", opts},
  {"Analyze file3.ex", opts}
], max_concurrent: 3)

# Pipeline
ClaudeAgentSDK.Orchestrator.query_pipeline([
  {"Generate outline", opts},
  {"Write section 1", opts},
  {"Write section 2", opts}
], opts)

# Retry
ClaudeAgentSDK.Orchestrator.query_with_retry(
  {"Complex task", opts},
  max_attempts: 3,
  backoff: :exponential
)
```

**Assessment:** Elixir's concurrency primitives enable superior orchestration.

---

## 12. Authentication

### ✅ ELIXIR EXCEEDS PYTHON

| Feature | Python | Elixir | Status |
|---------|--------|--------|--------|
| Provider abstraction | ❌ CLI only | ✅ Multi-provider | ✅ Elixir advantage |
| Token management | ❌ CLI handles | ✅ AuthManager GenServer | ✅ Elixir advantage |
| Token refresh | ❌ None | ✅ Automatic | ✅ Elixir advantage |
| Auth validation | ❌ None | ✅ AuthChecker | ✅ Elixir advantage |
| Anthropic API | ❌ Via CLI | ✅ Direct | ✅ Elixir advantage |
| AWS Bedrock | ❌ Via CLI | ✅ Direct | ✅ Elixir advantage |
| Google Vertex | ❌ Via CLI | ✅ Direct | ✅ Elixir advantage |

**Elixir Auth System:**
```elixir
# Multi-provider support
ClaudeAgentSDK.AuthManager.setup_token(provider: :anthropic)
ClaudeAgentSDK.AuthManager.setup_token(provider: :bedrock)
ClaudeAgentSDK.AuthManager.setup_token(provider: :vertex)

# Automatic token management
ClaudeAgentSDK.AuthManager.ensure_authenticated()
ClaudeAgentSDK.AuthManager.refresh_token()
ClaudeAgentSDK.AuthManager.status()
```

**Assessment:** Elixir's authentication is significantly more advanced.

---

## 13. Debug & Diagnostics

### ✅ ELIXIR EXCEEDS PYTHON

| Feature | Python | Elixir | Status |
|---------|--------|--------|--------|
| Query profiling | ❌ None | ✅ `profile_query/2` | ✅ Elixir advantage |
| Benchmarking | ❌ None | ✅ `benchmark/3` | ✅ Elixir advantage |
| Message analysis | ❌ None | ✅ `analyze_messages/1` | ✅ Elixir advantage |
| System diagnostics | ❌ None | ✅ `run_diagnostics/0` | ✅ Elixir advantage |
| Debug mode | ❌ None | ✅ Full module (712 LOC) | ✅ Elixir advantage |

**Elixir Debug Capabilities:**
```elixir
# Profiling
ClaudeAgentSDK.DebugMode.profile_query(prompt, opts)
# => %{duration_ms: 1234, message_count: 15, tokens: 5000}

# Benchmarking
ClaudeAgentSDK.DebugMode.benchmark(fn ->
  ClaudeAgentSDK.query(prompt, opts)
end, iterations: 10)

# Diagnostics
ClaudeAgentSDK.DebugMode.run_diagnostics()
```

**Assessment:** Elixir provides comprehensive debugging tools.

---

## 14. Testing & Mocking

### ⚠️ DIFFERENT APPROACHES

| Feature | Python | Elixir | Status |
|---------|--------|--------|--------|
| Unit tests | 11 files, 4,451 LOC | 13 files, 3,576 LOC | ✅ Both adequate |
| E2E tests | 7 files, 824 LOC | 14 adhoc files | ✅ Both adequate |
| Mock framework | ❌ Standard pytest | ✅ Custom Mock module | ✅ Elixir advantage |
| Test utilities | ❌ None | ✅ Mock.Process | ✅ Elixir advantage |

**Elixir Mock Framework:**
```elixir
ClaudeAgentSDK.Mock.setup_responses([
  %{type: "user", content: "Hello"},
  %{type: "assistant", content: "Hi there!"}
])

result = ClaudeAgentSDK.query("Test", mock: true)
```

**Assessment:** Elixir's custom mock framework is more integrated.

---

## 15. Examples & Documentation

### ⚠️ PYTHON HAS MORE EXAMPLES

| Category | Python | Elixir | Status |
|----------|--------|--------|--------|
| Examples | 12 files, 2,065 LOC | 3 files | ❌ Gap |
| Guides | 4 docs | 8 comprehensive guides | ✅ Elixir advantage |
| API docs | In-code | @moduledoc + @doc | ✅ Both good |
| Reference docs | 4 files | 8 files | ✅ Elixir advantage |

**Python Examples Missing in Elixir:**
1. `quick_start.py` - Basic usage (✅ Elixir has README examples)
2. `streaming_mode.py` - Interactive client (⚠️ Partial examples)
3. `streaming_mode_trio.py` - Alternative runtime (N/A for Elixir)
4. `streaming_mode_ipython.py` - Jupyter integration (❌ Missing)
5. `agents.py` - Agent switching (❌ Missing - feature not implemented)
6. `hooks.py` - Comprehensive hooks (⚠️ Partial in HOOKS_GUIDE)
7. `system_prompt.py` - Custom prompts (✅ Covered)
8. `tool_permission_callback.py` - Permissions (❌ Missing - feature not implemented)
9. `setting_sources.py` - Config sources (❌ Missing)
10. `mcp_calculator.py` - SDK MCP tools (❌ Missing - feature not implemented)
11. `include_partial_messages.py` - Partial messages (❌ Missing)
12. `stderr_callback_example.py` - Error handling (❌ Missing)

**Recommendation:** Port 6-8 key examples, especially:
- Comprehensive hooks example
- Setting sources example
- Error callback example
- Once implemented: MCP tools, agents, permissions

---

## Summary Matrix

| Feature Area | Completeness | Priority | Effort |
|--------------|--------------|----------|--------|
| Query/Streaming | ✅ 100% | - | - |
| Messages/Content | ✅ 100% | - | - |
| Hooks System | ✅ 100% | - | - |
| MCP Tools | ❌ 0% | HIGH | 2-3 weeks |
| Agent Definitions | ❌ 0% | HIGH | 1 week |
| Permission System | ⚠️ 30% | MEDIUM | 1-2 weeks |
| Transport Abstraction | ⚠️ 50% | MEDIUM | 3-5 days |
| Configuration Options | ⚠️ 70% | MEDIUM | 1 week |
| Client Control Flow | ⚠️ 70% | MEDIUM | 3-5 days |
| Error Handling | ⚠️ 80% | LOW | 2-3 days |
| Examples | ⚠️ 25% | LOW | 1 week |
| Authentication | ✅ 150% (exceeds) | - | - |
| Debug/Diagnostics | ✅ 200% (exceeds) | - | - |
| Orchestration | ✅ 200% (exceeds) | - | - |

**Overall Feature Parity: 65-70%**
