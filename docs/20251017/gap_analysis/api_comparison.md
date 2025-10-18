# API Surface Comparison: Python vs Elixir

**Date:** 2025-10-17

This document compares the public APIs of both SDKs side-by-side.

---

## 1. Main Entry Points

### Python
```python
# One-shot query (async generator)
from claude_agent_sdk import query

async for message in query("Hello", options):
    print(message)

# Bidirectional client
from claude_agent_sdk import ClaudeSDKClient

async with ClaudeSDKClient(options) as client:
    await client.query("Hello")
    async for message in client.receive_messages():
        print(message)
```

### Elixir
```elixir
# One-shot query (stream)
alias ClaudeAgentSDK

ClaudeAgentSDK.query("Hello", options)
|> Stream.each(&IO.inspect/1)
|> Stream.run()

# Bidirectional client
{:ok, client} = ClaudeAgentSDK.Client.start_link(options)
ClaudeAgentSDK.Client.send_message(client, "Hello")

ClaudeAgentSDK.Client.stream_messages(client)
|> Stream.each(&IO.inspect/1)
|> Stream.run()
```

**Status:** ✅ Equivalent functionality, different idioms

---

## 2. Configuration Options

### Python
```python
from claude_agent_sdk import ClaudeAgentOptions, SettingSource

options = ClaudeAgentOptions(
    # Basic options
    system="Custom system prompt",
    max_turns=10,
    working_directory="/path/to/dir",
    model="claude-sonnet-4",

    # MCP servers
    mcp_servers=[server1, server2],

    # Permission control
    permission_mode="plan",  # "default" | "acceptEdits" | "plan" | "bypassPermissions"
    can_use_tool=callback_fn,
    allowed_tools=["read", "write"],

    # Agent system
    agents=[agent1, agent2],
    agent=agent1,

    # Hooks
    hooks=[hook1, hook2],

    # Advanced
    setting_source=SettingSource.PROJECT,
    include_partial_messages=True,
    stderr_callback=handle_stderr
)
```

### Elixir
```elixir
alias ClaudeAgentSDK.Options

options = Options.new(
  # Basic options
  system: "Custom system prompt",
  max_turns: 10,
  cwd: "/path/to/dir",
  model: "claude-sonnet-4",

  # MCP servers
  mcp_servers: [server1, server2],

  # Permission control
  # ❌ permission_mode: not implemented
  # ❌ can_use_tool: not implemented
  # ⚠️  allowed_tools: use hooks instead

  # Agent system
  # ❌ agents: not implemented
  # ❌ agent: not implemented

  # Hooks
  hooks: [hook1, hook2],

  # Advanced
  # ❌ setting_source: implicit
  # ❌ include_partial_messages: not implemented
  # ❌ stderr_callback: not implemented
)
```

**Gap Summary:**
- ❌ `permission_mode` - Missing
- ❌ `can_use_tool` - Missing
- ❌ `agents`, `agent` - Missing
- ❌ `setting_source` - Implicit only
- ❌ `include_partial_messages` - Missing
- ❌ `stderr_callback` - Missing

---

## 3. Client Methods

### Python `ClaudeSDKClient`
```python
class ClaudeSDKClient:
    # Connection management
    async def connect(self) -> None
    async def disconnect(self) -> None
    async def __aenter__(self) -> "ClaudeSDKClient"
    async def __aexit__(self, ...) -> None

    # Messaging
    async def query(self, prompt: str) -> None
    async def receive_messages(self) -> AsyncIterator[Message]

    # Control flow
    async def interrupt(self) -> None

    # Runtime configuration
    async def set_permission_mode(self, mode: str) -> None
    async def set_model(self, model: str) -> None
    async def set_agent(self, agent: AgentDefinition) -> None
```

### Elixir `ClaudeAgentSDK.Client`
```elixir
defmodule ClaudeAgentSDK.Client do
  # GenServer callbacks (automatic)
  def start_link(options)
  def stop(client)

  # Messaging
  def send_message(client, prompt)
  def stream_messages(client)  # Returns Stream

  # Control flow
  # ❌ interrupt/1 - Not implemented

  # Runtime configuration
  # ❌ set_permission_mode/2 - Not implemented
  # ❌ set_model/2 - Not implemented
  # ❌ set_agent/2 - Not implemented
end
```

**Gap Summary:**
- ❌ `interrupt/1` - Missing
- ❌ `set_permission_mode/2` - Missing
- ❌ `set_model/2` - Missing
- ❌ `set_agent/2` - Missing

---

## 4. Message Types

### Python
```python
from claude_agent_sdk import (
    Message,
    UserMessage,
    AssistantMessage,
    SystemMessage,
    ResultMessage,
    ContentBlock,
    TextBlock,
    ThinkingBlock,
    ToolUseBlock,
    ToolResultBlock,
)

# Message union type
Message = UserMessage | AssistantMessage | SystemMessage | ResultMessage

# Usage
msg = UserMessage(content=[TextBlock(text="Hello")])
```

### Elixir
```elixir
# Messages are maps parsed from JSON
%{
  "type" => "user",
  "content" => [
    %{"type" => "text", "text" => "Hello"}
  ]
}

# Helper functions
alias ClaudeAgentSDK.Message

Message.final?(msg)
Message.error?(msg)
Message.session_id(msg)
Message.from_json(json_string)
```

**Status:** ✅ Functionally equivalent (Python uses typed classes, Elixir uses maps)

---

## 5. MCP Tool System

### Python
```python
from claude_agent_sdk import tool, create_sdk_mcp_server

# Define tools
@tool(
    name="calculator",
    description="Performs calculations",
    input_schema={
        "type": "object",
        "properties": {
            "expression": {"type": "string"}
        },
        "required": ["expression"]
    }
)
async def calculator(expression: str) -> str:
    return str(eval(expression))

@tool(name="weather", description="Get weather", input_schema={...})
async def weather(location: str) -> str:
    return f"Weather in {location}"

# Create SDK MCP server
server = create_sdk_mcp_server(
    name="my-tools",
    version="1.0.0",
    tools=[calculator, weather]
)

# Use in options
options = ClaudeAgentOptions(
    mcp_servers=[server]
)
```

### Elixir
```elixir
# ❌ NOT IMPLEMENTED

# Workaround: Use external MCP servers
options = Options.new(
  mcp_servers: [
    %{
      command: "path/to/mcp-server",
      args: ["--port", "8080"],
      env: %{"KEY" => "value"}
    }
  ]
)

# No in-process tools available
```

**Gap:** Complete MCP tool system missing

---

## 6. Permission System

### Python
```python
from claude_agent_sdk import (
    CanUseTool,
    ToolPermissionContext,
    PermissionResult,
    PermissionResultAllow,
    PermissionResultDeny,
    PermissionUpdate,
)

# Define permission callback
async def can_use_tool(context: ToolPermissionContext) -> PermissionResult:
    if context.tool_name == "dangerous_tool":
        return PermissionResultDeny(reason="Not allowed in this context")
    if context.tool_name == "read":
        if "/etc/" in context.tool_input.get("file_path", ""):
            return PermissionResultDeny(reason="Cannot read system files")
    return PermissionResultAllow()

# Use in options
options = ClaudeAgentOptions(
    permission_mode="plan",
    can_use_tool=can_use_tool
)

# Runtime updates
update = PermissionUpdate(
    destination="projectSettings",
    operation="add",
    rules=[
        {"tool_name": "bash", "allowed": False}
    ]
)
await client.update_permissions(update)
```

### Elixir
```elixir
# ❌ Structured permission callbacks not implemented

# Workaround: Use hooks
alias ClaudeAgentSDK.Hooks.Output

hook = fn event ->
  case event do
    %{type: "pre_tool_use", tool_name: "dangerous_tool"} ->
      Output.deny("Not allowed in this context")

    %{type: "pre_tool_use", tool_name: "read", input: input} ->
      if String.contains?(input["file_path"], "/etc/") do
        Output.deny("Cannot read system files")
      else
        Output.allow()
      end

    _ ->
      Output.continue()
  end
end

options = Options.new(hooks: [hook])

# ❌ No permission modes
# ❌ No runtime permission updates
```

**Gap:** Structured permission system missing

---

## 7. Agent Definitions

### Python
```python
from claude_agent_sdk import AgentDefinition, ClaudeAgentOptions

# Define agents
code_agent = AgentDefinition(
    description="Expert Python developer",
    prompt="You are an expert Python developer...",
    allowed_tools=["read", "write", "bash"],
    model="claude-sonnet-4"
)

research_agent = AgentDefinition(
    description="Research specialist",
    prompt="You excel at research and analysis...",
    allowed_tools=["websearch", "webfetch"],
    model="claude-opus-4"
)

# Use in options
options = ClaudeAgentOptions(
    agents=[code_agent, research_agent],
    agent=code_agent  # Start with code agent
)

# Switch at runtime
await client.set_agent(research_agent)
```

### Elixir
```elixir
# ❌ NOT IMPLEMENTED

# No agent definitions available
# No agent switching available

# Workaround: Manually change system prompt
ClaudeAgentSDK.query(
  "Research task",
  Options.new(system: "You excel at research...")
)
```

**Gap:** Complete agent system missing

---

## 8. Hooks System

### Python
```python
from claude_agent_sdk import (
    HookCallback,
    HookContext,
    HookMatcher,
    HookJSONOutput,
    PreToolUseHookInput,
    PostToolUseHookInput,
    UserPromptSubmitHookInput,
    StopHookInput,
    SubagentStopHookInput,
    PreCompactHookInput,
)

# Define hook
def my_hook(context: HookContext) -> HookJSONOutput:
    if isinstance(context.input, PreToolUseHookInput):
        if context.input.tool_name == "bash":
            return {
                "decision": "block",
                "reason": "Bash not allowed"
            }
    return {"decision": "continue"}

# With matcher
hook = HookCallback(
    callback=my_hook,
    matcher=HookMatcher(event_types=["pre_tool_use"])
)

options = ClaudeAgentOptions(hooks=[hook])
```

### Elixir
```elixir
alias ClaudeAgentSDK.Hooks.Output

# Define hook
my_hook = fn event ->
  case event.type do
    "pre_tool_use" ->
      if event.tool_name == "bash" do
        Output.block("Bash not allowed")
      else
        Output.continue()
      end
    _ ->
      Output.continue()
  end
end

# With matcher
hook = %{
  callback: my_hook,
  matcher: %{event_types: ["pre_tool_use"]}
}

options = Options.new(hooks: [hook])

# Output builder functions (Elixir advantage)
Output.allow("Approved")
Output.deny("Rejected")
Output.ask("Please confirm")
Output.stop("Execution stopped")
Output.block("Blocked")
Output.continue()
Output.add_context(output, %{key: "value"})
Output.with_system_message(output, "Additional context")
Output.with_reason(output, "Because...")
Output.suppress_output(true)
```

**Status:** ✅ Equivalent with Elixir enhancements

---

## 9. Orchestration (Elixir Exclusive)

### Python
```python
# ❌ NOT AVAILABLE

# Must manually implement parallel/pipeline/retry logic
```

### Elixir
```elixir
alias ClaudeAgentSDK.Orchestrator

# Parallel execution
{:ok, results} = Orchestrator.query_parallel([
  {"Analyze file1.ex", opts},
  {"Analyze file2.ex", opts},
  {"Analyze file3.ex", opts}
], max_concurrent: 2)

# Pipeline (sequential with context passing)
{:ok, final_result} = Orchestrator.query_pipeline([
  {"Generate outline for article about AI", opts},
  fn prev_result ->
    outline = extract_text(prev_result)
    {"Write section 1 based on: #{outline}", opts}
  end,
  fn prev_result ->
    section1 = extract_text(prev_result)
    {"Write section 2 that follows: #{section1}", opts}
  end
], opts)

# Retry with backoff
{:ok, result} = Orchestrator.query_with_retry(
  {"Complex task that might fail", opts},
  max_attempts: 3,
  backoff: :exponential  # or {:constant, 1000}
)
```

**Status:** ✅ Elixir exclusive advantage

---

## 10. Authentication (Elixir Exclusive)

### Python
```python
# ❌ NOT AVAILABLE

# Auth handled entirely by CLI subprocess
```

### Elixir
```elixir
alias ClaudeAgentSDK.AuthManager

# Setup authentication
AuthManager.setup_token(provider: :anthropic)
AuthManager.setup_token(provider: :bedrock)
AuthManager.setup_token(provider: :vertex)

# Token management
{:ok, token} = AuthManager.get_token()
:ok = AuthManager.refresh_token()
:ok = AuthManager.clear_auth()

# Status
%{authenticated: true, provider: :anthropic} = AuthManager.status()

# Automatic authentication
:ok = AuthManager.ensure_authenticated()
```

**Status:** ✅ Elixir exclusive advantage

---

## 11. Debug & Diagnostics (Elixir Exclusive)

### Python
```python
# ❌ NOT AVAILABLE

# Must manually implement profiling/benchmarking
```

### Elixir
```elixir
alias ClaudeAgentSDK.DebugMode

# Profile a query
%{
  duration_ms: 1234,
  message_count: 15,
  token_count: 5000,
  result: result
} = DebugMode.profile_query("Analyze this code", opts)

# Benchmark
stats = DebugMode.benchmark(fn ->
  ClaudeAgentSDK.query("Test", opts)
end, iterations: 10)

# Analyze messages
analysis = DebugMode.analyze_messages(message_stream)

# System diagnostics
DebugMode.run_diagnostics()

# Inspect individual message
DebugMode.inspect_message(msg)
```

**Status:** ✅ Elixir exclusive advantage

---

## 12. Transport Layer

### Python
```python
from claude_agent_sdk import Transport, SubprocessCliTransport

# Abstract interface
class Transport(ABC):
    @abstractmethod
    async def send(self, message: str) -> None: ...

    @abstractmethod
    async def receive(self) -> AsyncIterator[str]: ...

    @abstractmethod
    async def close(self) -> None: ...

# Built-in CLI transport
transport = SubprocessCliTransport()

# Custom transport
class MyCustomTransport(Transport):
    async def send(self, message: str) -> None:
        # Custom implementation
        pass

    async def receive(self) -> AsyncIterator[str]:
        # Custom implementation
        pass

    async def close(self) -> None:
        # Custom implementation
        pass

# Use custom transport
client = ClaudeSDKClient(options, transport=MyCustomTransport())
```

### Elixir
```elixir
# ❌ NO ABSTRACTION LAYER

# Process execution hardcoded in ClaudeAgentSDK.Process
# Cannot plug in custom transports

# Would need:
defmodule ClaudeAgentSDK.Transport do
  @callback send(t(), String.t()) :: :ok | {:error, term()}
  @callback receive(t()) :: {:ok, Stream.t()} | {:error, term()}
  @callback close(t()) :: :ok
end
```

**Gap:** Transport abstraction missing

---

## 13. Error Types

### Python
```python
from claude_agent_sdk import (
    ClaudeSDKError,
    CLIConnectionError,
    CLINotFoundError,
    ProcessError,
    CLIJSONDecodeError,
)

try:
    async for message in query("Hello", options):
        print(message)
except CLINotFoundError as e:
    print("Claude CLI not found")
except CLIConnectionError as e:
    print("Connection failed")
except ProcessError as e:
    print(f"Process exited with code {e.exit_code}: {e.stderr}")
except CLIJSONDecodeError as e:
    print(f"Invalid JSON: {e.raw_output}")
except ClaudeSDKError as e:
    print(f"SDK error: {e}")
```

### Elixir
```elixir
# Idiomatic error tuples
case ClaudeAgentSDK.query("Hello", opts) do
  {:ok, stream} ->
    Stream.run(stream)

  {:error, :cli_not_found} ->
    IO.puts("Claude CLI not found")

  {:error, {:process_error, exit_code, stderr}} ->
    IO.puts("Process exited with code #{exit_code}: #{stderr}")

  {:error, {:json_decode_error, raw}} ->
    IO.puts("Invalid JSON: #{raw}")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end

# Can also raise for exceptions
try do
  ClaudeAgentSDK.query!("Hello", opts)  # Bang version
rescue
  e in Jason.DecodeError ->
    IO.puts("JSON decode failed")
end
```

**Status:** ✅ Different but idiomatic

---

## 14. Utilities

### Python
```python
# Content extraction (basic)
from claude_agent_sdk import Message

text = message.content[0].text if message.content else None
```

### Elixir
```elixir
# Content extraction (built-in utilities)
alias ClaudeAgentSDK.ContentExtractor

text = ContentExtractor.extract_text(message)
content = ContentExtractor.extract_content_text(messages)

# Message utilities
alias ClaudeAgentSDK.Message

is_final = Message.final?(msg)
is_error = Message.error?(msg)
session_id = Message.session_id(msg)
```

**Status:** ✅ Elixir has better utilities

---

## API Completeness Summary

| API Category | Python | Elixir | Parity |
|-------------|--------|--------|--------|
| Query/Streaming | ✅ Full | ✅ Full | 100% |
| Configuration | ✅ 11 options | ⚠️ 6 options | 55% |
| Client Methods | ✅ 8 methods | ⚠️ 4 methods | 50% |
| Message Types | ✅ Typed | ✅ Maps | 100% |
| MCP Tools | ✅ Full | ❌ None | 0% |
| Permissions | ✅ Full | ⚠️ Partial | 30% |
| Agents | ✅ Full | ❌ None | 0% |
| Hooks | ✅ Full | ✅ Enhanced | 100% |
| Orchestration | ❌ None | ✅ Full | N/A (Elixir exclusive) |
| Authentication | ❌ Basic | ✅ Advanced | N/A (Elixir exclusive) |
| Debug/Diagnostics | ❌ None | ✅ Full | N/A (Elixir exclusive) |
| Transport | ✅ Pluggable | ❌ Hardcoded | 50% |
| Errors | ✅ Hierarchy | ✅ Tuples | 100% (different styles) |
| Utilities | ⚠️ Basic | ✅ Rich | N/A (Elixir advantage) |

---

## Recommendations

### High Priority (Core Feature Gaps)
1. **Implement MCP Tool System** - Critical missing feature
2. **Add Agent Definitions** - Key abstraction missing
3. **Complete Permission System** - Security/control feature
4. **Add Runtime Control Methods** - `interrupt()`, `set_model()`, etc.

### Medium Priority (Usability)
5. **Transport Abstraction** - Enable custom transports
6. **Missing Options** - `include_partial_messages`, `stderr_callback`, etc.
7. **Example Parity** - Port key Python examples

### Low Priority (Nice to Have)
8. **Typed Structs for Messages** - Currently just maps
9. **Error Hierarchy** - More specific error types
10. **Setting Source Control** - Explicit destination control

### Keep Elixir Advantages
- Orchestration system
- Advanced authentication
- Debug/diagnostics module
- Content extraction utilities
