# Python SDK vs Elixir SDK Gap Analysis

**Date:** 2025-10-26
**Elixir SDK Version:** v0.6.0
**Python SDK Version:** Latest (analyzed from claude-agent-sdk-python/)

---

## Executive Summary

This document provides a comprehensive gap analysis comparing the Python SDK implementation with the Elixir SDK. The analysis identifies missing functionality that needs to be implemented in the Elixir SDK to achieve feature parity with the Python SDK.

**Key Findings:**
- **Overall Status:** Elixir SDK has ~95% feature parity with Python SDK
- **Critical Gaps:** 2 major features missing
- **Minor Gaps:** 5 smaller features missing
- **Unique Strengths:** Elixir has 3 features Python lacks

---

## Table of Contents

1. [Feature Comparison Matrix](#feature-comparison-matrix)
2. [Critical Gaps (Must Implement)](#critical-gaps-must-implement)
3. [Minor Gaps (Nice to Have)](#minor-gaps-nice-to-have)
4. [Elixir-Specific Strengths](#elixir-specific-strengths)
5. [Implementation Recommendations](#implementation-recommendations)
6. [Detailed Feature Analysis](#detailed-feature-analysis)

---

## Feature Comparison Matrix

| Feature Category | Python SDK | Elixir SDK | Status | Priority |
|-----------------|------------|------------|--------|----------|
| **Core APIs** |
| `query()` function | ✅ | ✅ | Complete | - |
| `ClaudeSDKClient` class | ✅ | ✅ (`Client`) | Complete | - |
| Bidirectional streaming | ✅ | ✅ | Complete | - |
| **Session Management** |
| Continue conversation | ✅ | ✅ | Complete | - |
| Resume by session ID | ✅ | ✅ | Complete | - |
| Fork session | ✅ | ✅ | Complete | - |
| Session store | ❌ | ✅ | Elixir advantage | - |
| **Streaming Features** |
| Partial message streaming | ✅ | ✅ | Complete | - |
| Stream events | ✅ | ✅ | Complete | - |
| Character-level streaming | ✅ | ✅ | Complete | - |
| **Tool System** |
| Tool permission callbacks | ✅ | ✅ | Complete | - |
| Permission modes (4 modes) | ✅ | ✅ | Complete | - |
| Permission updates | ✅ | ❌ | **GAP** | **HIGH** |
| Tool input modification | ✅ | ✅ | Complete | - |
| **Hook System** |
| PreToolUse hooks | ✅ | ✅ | Complete | - |
| PostToolUse hooks | ✅ | ✅ | Complete | - |
| UserPromptSubmit hooks | ✅ | ✅ | Complete | - |
| Stop hooks | ✅ | ✅ | Complete | - |
| SubagentStop hooks | ✅ | ✅ | Complete | - |
| PreCompact hooks | ✅ | ✅ | Complete | - |
| Hook matchers | ✅ | ✅ | Complete | - |
| Async/deferred hooks | ✅ | ❌ | **GAP** | **MEDIUM** |
| Hook output helpers | ✅ | ✅ | Complete | - |
| **MCP Integration** |
| SDK MCP servers | ✅ | ✅ | Complete | - |
| stdio servers | ✅ | ✅ | Complete | - |
| SSE servers | ✅ | ✅ | Complete | - |
| HTTP servers | ✅ | ✅ | Complete | - |
| MCP tool definition macro | ❌ | ✅ | Elixir advantage | - |
| **Configuration** |
| System prompts | ✅ | ✅ | Complete | - |
| System prompt presets | ✅ | ❌ | **GAP** | **LOW** |
| Model selection | ✅ | ✅ | Complete | - |
| Runtime model switching | ✅ | ✅ | Complete | - |
| Fallback models | ✅ | ✅ | Complete | - |
| Custom agents | ✅ | ✅ | Complete | - |
| Runtime agent switching | ✅ | ✅ | Complete | - |
| Tool allowlist/blocklist | ✅ | ✅ | Complete | - |
| Working directory control | ✅ | ✅ | Complete | - |
| Environment variables | ✅ | ❌ | **GAP** | **LOW** |
| Custom CLI path | ✅ | ✅ | Complete | - |
| Extra CLI args | ✅ | ❌ | **GAP** | **LOW** |
| Stderr callback | ✅ | ❌ | **GAP** | **LOW** |
| **Plugin System** |
| Local plugins | ✅ | ❌ | **GAP** | **MEDIUM** |
| Plugin configuration | ✅ | ❌ | **GAP** | **MEDIUM** |
| **Advanced Features** |
| Interrupt support | ✅ | ✅ | Complete | - |
| Dynamic control (mode/model) | ✅ | ✅ | Complete | - |
| Permission mode switching | ✅ | ✅ | Complete | - |
| Server info retrieval | ✅ | ❌ | **GAP** | **LOW** |
| Custom transport | ✅ | ✅ | Complete | - |
| **Error Handling** |
| Structured error hierarchy | ✅ | ✅ | Complete | - |
| CLIConnectionError | ✅ | ✅ | Complete | - |
| ProcessError | ✅ | ✅ | Complete | - |
| **Orchestration** |
| Concurrent queries | ❌ | ✅ | Elixir advantage | - |
| Sequential pipelines | ❌ | ✅ | Elixir advantage | - |
| Auto-retry with backoff | ❌ | ✅ | Elixir advantage | - |
| **Testing** |
| Mock system | ❌ | ✅ | Elixir advantage | - |

---

## Critical Gaps (Must Implement)

### 1. Permission Updates System ⚠️ **HIGH PRIORITY**

**Python SDK Implementation:**
```python
# Permission update types
@dataclass
class PermissionUpdate:
    type: Literal[
        "addRules",
        "replaceRules",
        "removeRules",
        "setMode",
        "addDirectories",
        "removeDirectories",
    ]
    rules: list[PermissionRuleValue] | None = None
    behavior: PermissionBehavior | None = None
    mode: PermissionMode | None = None
    directories: list[str] | None = None
    destination: PermissionUpdateDestination | None = None

# Used in permission results
@dataclass
class PermissionResultAllow:
    behavior: Literal["allow"] = "allow"
    updated_input: dict[str, Any] | None = None
    updated_permissions: list[PermissionUpdate] | None = None
```

**Elixir SDK Status:** ❌ Not implemented

**What's Missing:**
- `PermissionUpdate` struct/module
- Support for permission update destinations (userSettings, projectSettings, localSettings, session)
- Permission rules management (add/replace/remove)
- Directory permissions (add/remove)
- Integration with `PermissionResult.Allow`

**Impact:** Users cannot dynamically update permission rules during execution. This is a key feature for building adaptive permission systems.

**Implementation Required:**
1. Create `ClaudeAgentSDK.Permission.Update` module
2. Add `PermissionRuleValue` struct with `tool_name` and `rule_content`
3. Add `PermissionUpdate` struct with all update types
4. Update `Permission.Result.Allow` to support `updated_permissions` field
5. Add `to_json_map/1` conversion for control protocol
6. Add validation functions
7. Document usage patterns

**Estimated Effort:** 4-6 hours

---

## Minor Gaps (Nice to Have)

### 2. Async/Deferred Hooks ⚠️ **MEDIUM PRIORITY**

**Python SDK Implementation:**
```python
class AsyncHookJSONOutput(TypedDict):
    async_: Literal[True]
    asyncTimeout: NotRequired[int]
```

**Elixir SDK Status:** ❌ Not implemented

**What's Missing:**
- Support for `async: true` in hook outputs
- Timeout support for async operations
- Deferred hook execution model

**Impact:** Hooks must complete synchronously. Cannot defer expensive operations or perform async work during hook callbacks.

**Implementation Required:**
1. Add `async` and `async_timeout` fields to `Hooks.Output`
2. Update hook response encoding in `Client`
3. Add documentation for async hook patterns
4. Consider Task-based async execution model

**Estimated Effort:** 2-3 hours

---

### 3. Plugin System ⚠️ **MEDIUM PRIORITY**

**Python SDK Implementation:**
```python
class SdkPluginConfig(TypedDict):
    type: Literal["local"]
    path: str

# In ClaudeAgentOptions
plugins: list[SdkPluginConfig] = field(default_factory=list)
```

**Elixir SDK Status:** ❌ Not implemented

**What's Missing:**
- Plugin configuration structure
- Local plugin loading
- Plugin path support in Options
- CLI argument generation for plugins

**Impact:** Cannot load custom Claude Code plugins from local directories.

**Implementation Required:**
1. Add `plugins` field to `Options` struct
2. Create plugin configuration struct
3. Add `--plugin` CLI argument support
4. Document plugin usage patterns

**Estimated Effort:** 2-3 hours

---

### 4. System Prompt Presets ⚠️ **LOW PRIORITY**

**Python SDK Implementation:**
```python
class SystemPromptPreset(TypedDict):
    type: Literal["preset"]
    preset: Literal["claude_code"]
    append: NotRequired[str]

# In ClaudeAgentOptions
system_prompt: str | SystemPromptPreset | None = None
```

**Elixir SDK Status:** ❌ Not implemented

**What's Missing:**
- Preset support (e.g., "claude_code" preset)
- Append functionality for presets
- Type union for `system_prompt` field

**Impact:** Cannot use built-in Claude Code system prompt presets with optional appended content.

**Implementation Required:**
1. Add preset support to `Options.system_prompt`
2. Update type spec to allow map/struct for preset config
3. Add CLI argument generation for preset format
4. Document preset usage

**Estimated Effort:** 1-2 hours

---

### 5. Environment Variables Control ⚠️ **LOW PRIORITY**

**Python SDK Implementation:**
```python
# In ClaudeAgentOptions
env: dict[str, str] = field(default_factory=dict)
```

**Elixir SDK Status:** ❌ Not implemented

**What's Missing:**
- `env` field in Options
- Environment variable passing to CLI subprocess
- CLI argument support for env vars

**Impact:** Cannot pass custom environment variables to Claude CLI process.

**Implementation Required:**
1. Add `env` field to `Options` struct
2. Update process spawning to include environment
3. Add CLI argument generation
4. Document environment variable patterns

**Estimated Effort:** 1-2 hours

---

### 6. Extra CLI Arguments ⚠️ **LOW PRIORITY**

**Python SDK Implementation:**
```python
# In ClaudeAgentOptions
extra_args: dict[str, str | None] = field(default_factory=dict)
```

**Elixir SDK Status:** ❌ Not implementation

**What's Missing:**
- `extra_args` field for arbitrary CLI flags
- Support for passing undefined/future CLI arguments

**Impact:** Cannot pass experimental or newly-added CLI flags that aren't yet in Options.

**Implementation Required:**
1. Add `extra_args` field to `Options`
2. Append extra args during CLI command building
3. Document usage

**Estimated Effort:** 30 minutes - 1 hour

---

### 7. Stderr Callback ⚠️ **LOW PRIORITY**

**Python SDK Implementation:**
```python
# In ClaudeAgentOptions
stderr: Callable[[str], None] | None = None
```

**Elixir SDK Status:** ❌ Not implemented

**What's Missing:**
- Callback function for CLI stderr output
- Stderr capture and routing

**Impact:** Cannot monitor or log CLI stderr output programmatically.

**Implementation Required:**
1. Add `stderr_callback` field to `Options`
2. Update Port/Transport to capture stderr
3. Invoke callback with stderr lines
4. Document debugging patterns

**Estimated Effort:** 1-2 hours

---

### 8. Server Info Retrieval ⚠️ **LOW PRIORITY**

**Python SDK Implementation:**
```python
async def get_server_info(self) -> dict[str, Any] | None:
    """Get server initialization info including available commands and output styles."""
    return getattr(self._query, "_initialization_result", None)
```

**Elixir SDK Status:** ❌ Not implemented

**What's Missing:**
- `get_server_info/1` function in Client
- Storage of initialization result from control protocol
- Return of server capabilities, commands, output styles

**Impact:** Cannot programmatically query server capabilities.

**Implementation Required:**
1. Store initialization response in Client state
2. Add `get_server_info/1` function
3. Return initialization data
4. Document server info structure

**Estimated Effort:** 30 minutes - 1 hour

---

## Elixir-Specific Strengths

These features exist in the Elixir SDK but not in Python SDK:

### 1. Session Store & Search ✅

**Elixir Implementation:**
```elixir
# Session persistence and search
ClaudeAgentSDK.SessionStore.save_session(session)
ClaudeAgentSDK.SessionStore.list_sessions()
ClaudeAgentSDK.SessionStore.search_sessions(tag: "feature-x")
ClaudeAgentSDK.SessionStore.cleanup_old_sessions(days: 30)
```

**Python SDK:** ❌ No session store

**Advantage:** Persistent session management with tagging, metadata, and search capabilities.

---

### 2. Orchestration System ✅

**Elixir Implementation:**
```elixir
# Concurrent queries
Orchestrator.parallel([
  {"Query 1", opts1},
  {"Query 2", opts2}
])

# Sequential pipelines
Orchestrator.sequence([
  {"Step 1", opts1},
  {"Step 2", opts2}
])

# Auto-retry
Orchestrator.with_retry("Query", opts, max_attempts: 3)
```

**Python SDK:** ❌ No orchestration

**Advantage:** Built-in concurrency, pipelines, and retry logic.

---

### 3. Tool Definition Macro ✅

**Elixir Implementation:**
```elixir
defmodule MyTools do
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
```

**Python SDK:** Uses decorator pattern, less structured

**Advantage:** Compile-time tool definition with strong typing and validation.

---

### 4. Mock System for Testing ✅

**Elixir Implementation:**
```elixir
# Test mode with mock responses
ClaudeAgentSDK.Mock.enable()
ClaudeAgentSDK.Mock.set_response("mock response")
```

**Python SDK:** ❌ No built-in mock system

**Advantage:** First-class testing support without external dependencies.

---

## Implementation Recommendations

### Phase 1: Critical Gaps (Week 1)

**Priority 1: Permission Updates System**
- Implement `Permission.Update` module
- Update `Permission.Result` to support updates
- Add control protocol integration
- Write comprehensive tests
- Document usage patterns

**Estimated Time:** 6-8 hours

### Phase 2: Medium Priority (Week 2)

**Priority 2: Async Hooks**
- Add async support to `Hooks.Output`
- Update Client hook handling
- Document async patterns

**Priority 3: Plugin System**
- Add plugin configuration
- Update Options and CLI args
- Document plugin loading

**Estimated Time:** 6-8 hours total

### Phase 3: Polish (Week 3)

**Priority 4-8: Low Priority Features**
- System prompt presets
- Environment variables
- Extra CLI args
- Stderr callback
- Server info retrieval

**Estimated Time:** 4-6 hours total

---

## Detailed Feature Analysis

### 1. Core API Comparison

Both SDKs provide equivalent core functionality:

#### Python SDK
```python
# Query API
async for message in query(prompt="Hello", options=options):
    print(message)

# Client API
async with ClaudeSDKClient(options) as client:
    await client.query("Hello")
    async for msg in client.receive_response():
        print(msg)
```

#### Elixir SDK
```elixir
# Query API
ClaudeAgentSDK.query("Hello", options)
|> Enum.each(&IO.inspect/1)

# Client API
{:ok, client} = Client.start_link(options)
Client.send_message(client, "Hello")
Client.stream_messages(client)
|> Enum.each(&IO.inspect/1)
```

**Status:** ✅ Feature parity

---

### 2. Hook System Comparison

Both SDKs support 6 hook types with matchers:

#### Python SDK
```python
options = ClaudeAgentOptions(
    hooks={
        "PreToolUse": [
            HookMatcher(matcher="Bash", hooks=[check_bash_hook])
        ]
    }
)
```

#### Elixir SDK
```elixir
options = %Options{
  hooks: %{
    pre_tool_use: [
      Matcher.new("Bash", [&check_bash_hook/3])
    ]
  }
}
```

**Missing in Elixir:**
- Async/deferred hooks (`async: true`)
- AsyncTimeout support

**Status:** 🟡 95% parity, missing async support

---

### 3. Permission System Comparison

Both SDKs support permission callbacks and 4 modes:

#### Python SDK
```python
async def can_use_tool(tool_name, tool_input, context):
    if dangerous(tool_input):
        return PermissionResultDeny(
            message="Blocked",
            interrupt=True
        )
    return PermissionResultAllow(
        updated_input=modified_input,
        updated_permissions=[
            PermissionUpdate(
                type="addRules",
                rules=[...],
                behavior="allow",
                destination="session"
            )
        ]
    )
```

#### Elixir SDK
```elixir
def can_use_tool(context) do
  if dangerous?(context.tool_input) do
    Result.deny(message: "Blocked", interrupt: true)
  else
    Result.allow(updated_input: modified_input)
    # ❌ No updated_permissions support
  end
end
```

**Missing in Elixir:**
- `PermissionUpdate` struct and types
- `updated_permissions` in Result.Allow
- Permission rules management
- Directory permissions

**Status:** 🟡 80% parity, missing permission updates

---

### 4. MCP Integration Comparison

Both SDKs support SDK MCP servers and external servers:

#### Python SDK
```python
from mcp.server import Server

server = create_sdk_mcp_server(
    name="calc",
    version="1.0.0",
    tools=[AddTool, SubtractTool]
)

options = ClaudeAgentOptions(
    mcp_servers={"calc": {
        "type": "sdk",
        "name": "calc",
        "instance": server
    }}
)
```

#### Elixir SDK
```elixir
server = ClaudeAgentSDK.create_sdk_mcp_server(
  name: "calc",
  version: "1.0.0",
  tools: [MyTools.Add, MyTools.Subtract]
)

options = %Options{
  mcp_servers: %{"calc" => server}
}
```

**Status:** ✅ Feature parity

**Elixir Advantage:** `deftool` macro for cleaner tool definitions

---

### 5. Configuration Options Comparison

#### Python SDK: ~57 configuration options

Key options:
```python
ClaudeAgentOptions(
    # Basic
    max_turns=5,
    system_prompt="...",
    model="sonnet",

    # Tools
    allowed_tools=["Bash"],
    can_use_tool=callback,

    # MCP
    mcp_servers={...},

    # Advanced
    env={"KEY": "value"},
    extra_args={"--experimental": None},
    stderr=stderr_callback,
    plugins=[{"type": "local", "path": "..."}],

    # Hooks
    hooks={...},

    # Sessions
    fork_session=True,
    resume="session-id"
)
```

#### Elixir SDK: ~30 configuration options

```elixir
%Options{
  # Basic
  max_turns: 5,
  system_prompt: "...",
  model: "sonnet",

  # Tools
  allowed_tools: ["Bash"],
  can_use_tool: &callback/1,

  # MCP
  mcp_servers: %{...},

  # Advanced - MISSING:
  # env: %{},           ❌
  # extra_args: %{},    ❌
  # stderr_callback: fn ❌
  # plugins: []         ❌

  # Hooks
  hooks: %{...},

  # Sessions
  fork_session: true
}
```

**Missing Options:**
1. `env` - Environment variables
2. `extra_args` - Extra CLI arguments
3. `stderr` callback
4. `plugins` - Plugin configurations
5. System prompt presets

**Status:** 🟡 85% parity

---

### 6. Message Types Comparison

Both SDKs support equivalent message types:

| Message Type | Python | Elixir | Status |
|--------------|--------|--------|--------|
| UserMessage | ✅ | ✅ | ✅ |
| AssistantMessage | ✅ | ✅ | ✅ |
| SystemMessage | ✅ | ✅ | ✅ |
| ResultMessage | ✅ | ✅ | ✅ |
| StreamEvent | ✅ | ✅ | ✅ |

**Content Blocks:**

| Block Type | Python | Elixir | Status |
|------------|--------|--------|--------|
| TextBlock | ✅ | ✅ | ✅ |
| ThinkingBlock | ✅ | ✅ | ✅ |
| ToolUseBlock | ✅ | ✅ | ✅ |
| ToolResultBlock | ✅ | ✅ | ✅ |

**Status:** ✅ Complete parity

---

### 7. Error Handling Comparison

Both SDKs have structured error hierarchies:

#### Python SDK
```python
ClaudeSDKError
├── CLIConnectionError
├── CLINotFoundError
├── ProcessError
├── CLIJSONDecodeError
└── MessageParseError
```

#### Elixir SDK
```elixir
# Error tuples with atoms
{:error, :claude_not_found}
{:error, :connection_failed}
{:error, :invalid_json}
{:error, {:process_error, exit_code, stderr}}
```

**Status:** ✅ Equivalent functionality, different style (Pythonic classes vs Elixir tuples)

---

### 8. Transport Layer Comparison

Both SDKs support custom transports:

#### Python SDK
```python
class CustomTransport(Transport):
    async def connect(self): ...
    async def write(self, data): ...
    async def read(self): ...
    async def close(self): ...

client = ClaudeSDKClient(transport=CustomTransport())
```

#### Elixir SDK
```elixir
defmodule CustomTransport do
  @behaviour ClaudeAgentSDK.Transport

  def start_link(opts), do: ...
  def send(transport, data), do: ...
  def subscribe(transport, pid), do: ...
  def close(transport), do: ...
end

{:ok, client} = Client.start_link(options, transport: CustomTransport)
```

**Status:** ✅ Feature parity

---

## Testing & Examples Coverage

### Python SDK Examples (14 files)
- quick_start.py
- streaming_mode.py
- mcp_calculator.py
- tool_permission_callback.py
- hooks.py
- agents.py
- system_prompt.py
- include_partial_messages.py
- plugin_example.py
- setting_sources.py
- stderr_callback_example.py
- streaming_mode_trio.py
- streaming_mode_ipython.py
- And more...

### Elixir SDK Examples (32 files)
- Basic queries and streaming
- SDK MCP servers
- Hooks and permissions
- Agents and models
- Session management
- Orchestration patterns
- Mock testing
- And more...

**Status:** ✅ Elixir has more examples, both well-documented

---

## Summary Table: Implementation Checklist

| # | Feature | Priority | Effort | Status |
|---|---------|----------|--------|--------|
| 1 | Permission Updates System | HIGH | 6-8h | ❌ Not Started |
| 2 | Async/Deferred Hooks | MEDIUM | 2-3h | ❌ Not Started |
| 3 | Plugin System | MEDIUM | 2-3h | ❌ Not Started |
| 4 | System Prompt Presets | LOW | 1-2h | ❌ Not Started |
| 5 | Environment Variables | LOW | 1-2h | ❌ Not Started |
| 6 | Extra CLI Args | LOW | 0.5-1h | ❌ Not Started |
| 7 | Stderr Callback | LOW | 1-2h | ❌ Not Started |
| 8 | Server Info Retrieval | LOW | 0.5-1h | ❌ Not Started |

**Total Estimated Effort:** 15-22 hours

---

## Conclusion

The Elixir SDK has achieved impressive feature parity with the Python SDK (~95% coverage of core features). The main gaps are:

1. **Permission Updates** - Most critical missing feature
2. **Async Hooks** - Important for advanced use cases
3. **Plugin System** - Medium priority for extensibility
4. **Configuration Options** - Several minor options missing

The Elixir SDK also has unique strengths:
- Session store and search
- Built-in orchestration (parallel, sequence, retry)
- Tool definition macros
- Mock testing system

### Recommended Implementation Order

**Week 1 (Critical):**
1. Permission Updates System

**Week 2 (Medium Priority):**
2. Async/Deferred Hooks
3. Plugin System

**Week 3 (Polish):**
4. System Prompt Presets
5. Environment Variables
6. Extra CLI Args
7. Stderr Callback
8. Server Info Retrieval

After completing these implementations, the Elixir SDK will have full parity with Python SDK plus additional Elixir-specific advantages.

---

## Appendix A: Type System Mapping

### Python Types → Elixir Types

| Python | Elixir | Notes |
|--------|--------|-------|
| `TypedDict` | `%{}` map or struct | Elixir uses structs for strong typing |
| `@dataclass` | `defstruct` | Similar compile-time structure |
| `Literal["a", "b"]` | `@type :: :a \| :b` | Atoms for string constants |
| `list[T]` | `[T.t()]` | List type specs |
| `dict[K, V]` | `%{K.t() => V.t()}` | Map type specs |
| `Callable[[A, B], R]` | `(A.t(), B.t() -> R.t())` | Function types |
| `Awaitable[T]` | `T.t()` | Elixir doesn't have async/await |
| `Union[A, B]` | `A.t() \| B.t()` | Type unions |

### Python Async → Elixir Concurrency

| Python | Elixir | Notes |
|--------|--------|-------|
| `async def` | `def` | All Elixir functions can be concurrent |
| `await` | (implicit) | No special syntax needed |
| `AsyncIterator` | `Stream` | Lazy enumerable |
| `async for` | `Enum/Stream` | Pipeline operators |
| `async with` | GenServer lifecycle | Different paradigm |

---

## Appendix B: Control Protocol Messages

Both SDKs implement the same control protocol for bidirectional communication.

### Request Types

| Type | Python | Elixir | Status |
|------|--------|--------|--------|
| initialize | ✅ | ✅ | ✅ |
| interrupt | ✅ | ✅ | ✅ |
| can_use_tool | ✅ | ✅ | ✅ |
| hook_callback | ✅ | ✅ | ✅ |
| set_permission_mode | ✅ | ✅ | ✅ |
| set_model | ✅ | ✅ | ✅ |
| sdk_mcp_request | ✅ | ✅ | ✅ |

**Status:** ✅ Complete parity

---

*End of Gap Analysis*
