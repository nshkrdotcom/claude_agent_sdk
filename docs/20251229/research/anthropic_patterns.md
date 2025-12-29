# Anthropic SDK Patterns and Conventions Research

**Date:** 2025-12-29
**Status:** Research Complete

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Standard Anthropic SDK Terminology](#standard-anthropic-sdk-terminology)
3. [API Patterns](#api-patterns)
4. [Messages API Structure](#messages-api-structure)
5. [Tool Use Patterns](#tool-use-patterns)
6. [Streaming Patterns](#streaming-patterns)
7. [MCP (Model Context Protocol) Documentation Patterns](#mcp-model-context-protocol-documentation-patterns)
8. [Claude Agent SDK Patterns](#claude-agent-sdk-patterns)
9. [Best Practices from Official SDKs](#best-practices-from-official-sdks)
10. [Sources](#sources)

---

## Executive Summary

This document captures the standard patterns, terminology, and conventions used in Anthropic's official SDKs. The research covers:

- **Anthropic Python SDK** - Core API client for Claude models
- **Claude Agent SDK** - Higher-level agent framework (Python and Elixir ports)
- **Model Context Protocol (MCP)** - Standard for tool/resource integration

Key findings:
- Anthropic SDKs follow consistent patterns across languages
- The Agent SDK provides a layer above the base API with hooks, permissions, and MCP integration
- MCP is the standard protocol for extending Claude with external tools and resources
- Documentation patterns emphasize examples, type safety, and progressive disclosure

---

## Standard Anthropic SDK Terminology

### Core Concepts

| Term | Definition | Usage Context |
|------|-----------|---------------|
| **Messages** | Primary API endpoint for chat completions | `client.messages.create()` |
| **Content Block** | Individual content unit in a message | TextBlock, ToolUseBlock, ToolResultBlock |
| **Tool** | Function/capability Claude can invoke | Defined in `tools` parameter |
| **Tool Use** | When Claude decides to use a tool | `tool_use` content block type |
| **Tool Result** | Response after tool execution | `tool_result` message type |
| **Streaming** | Real-time incremental responses | Server-Sent Events (SSE) |
| **Model** | Claude variant (opus, sonnet, haiku) | `model` parameter |
| **System Prompt** | Initial instructions for Claude | `system` parameter |
| **Max Tokens** | Response length limit | `max_tokens` parameter |
| **Stop Sequences** | Custom stop conditions | `stop_sequences` parameter |

### Agent SDK Terminology

| Term | Definition | Usage Context |
|------|-----------|---------------|
| **Query** | Single prompt-response cycle | `query()` function |
| **Session** | Persistent conversation context | Session IDs, continuations |
| **Hook** | Callback at agent lifecycle points | PreToolUse, PostToolUse, etc. |
| **Permission** | Authorization for tool execution | Permission modes and callbacks |
| **MCP Server** | Tool/resource provider | SDK or external servers |
| **Agent** | Custom persona configuration | System prompt + tool constraints |
| **Control Protocol** | Bidirectional SDK-CLI communication | JSON-RPC messages |

---

## API Patterns

### Client Instantiation Pattern

```python
# Python SDK Pattern
from anthropic import Anthropic

client = Anthropic(
    api_key=os.environ.get("ANTHROPIC_API_KEY"),  # Optional - uses env var by default
    max_retries=2,         # Default retry count
    timeout=600.0,         # 10 minute default timeout
    base_url=None,         # Override API endpoint
    default_headers={},    # Additional headers
)
```

```elixir
# Elixir SDK Pattern (Agent SDK)
alias ClaudeAgentSDK.{Client, Options}

{:ok, client} = Client.start_link(%Options{
  model: "sonnet",
  max_turns: 5,
  cwd: "/path/to/project"
})
```

### Request-Response Pattern

```python
# Standard message creation
message = client.messages.create(
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    messages=[
        {"role": "user", "content": "Hello, Claude!"}
    ]
)

# Access response
print(message.content[0].text)
print(message.usage.input_tokens)
```

### Options/Configuration Pattern

Both SDKs use a configuration object pattern:

```python
# Python SDK Options
ClaudeAgentOptions(
    system_prompt="...",
    max_turns=5,
    model="sonnet",
    allowed_tools=["Read", "Write"],
    permission_mode="acceptEdits",
    mcp_servers={...},
    hooks={...}
)
```

```elixir
# Elixir SDK Options
%Options{
  system_prompt: "...",
  max_turns: 5,
  model: "sonnet",
  allowed_tools: ["Read", "Write"],
  permission_mode: :accept_edits,
  mcp_servers: %{...},
  hooks: %{...}
}
```

---

## Messages API Structure

### Message Format

```json
{
  "model": "claude-sonnet-4-5-20250929",
  "max_tokens": 1024,
  "system": "You are a helpful assistant.",
  "messages": [
    {
      "role": "user",
      "content": "What is 2 + 2?"
    },
    {
      "role": "assistant",
      "content": "2 + 2 equals 4."
    }
  ]
}
```

### Content Block Types

```json
// Text content
{"type": "text", "text": "Hello, world!"}

// Tool use (Claude requesting a tool)
{
  "type": "tool_use",
  "id": "toolu_01A09q90qw90lq917835lgs",
  "name": "get_weather",
  "input": {"location": "San Francisco, CA"}
}

// Tool result (user providing tool output)
{
  "type": "tool_result",
  "tool_use_id": "toolu_01A09q90qw90lq917835lgs",
  "content": "15 degrees Celsius, sunny"
}

// Image content
{
  "type": "image",
  "source": {
    "type": "base64",
    "media_type": "image/png",
    "data": "..."
  }
}
```

### Response Structure

```json
{
  "id": "msg_01XFDUDYJgAACzvnptvVoYEL",
  "type": "message",
  "role": "assistant",
  "content": [
    {"type": "text", "text": "The answer is 4."}
  ],
  "model": "claude-sonnet-4-5-20250929",
  "stop_reason": "end_turn",
  "stop_sequence": null,
  "usage": {
    "input_tokens": 25,
    "output_tokens": 10
  }
}
```

---

## Tool Use Patterns

### Tool Definition Schema

```python
# Tool definition follows JSON Schema
tools = [
    {
        "name": "get_weather",
        "description": "Get the current weather for a location",
        "input_schema": {
            "type": "object",
            "properties": {
                "location": {
                    "type": "string",
                    "description": "City and state/country"
                },
                "unit": {
                    "type": "string",
                    "enum": ["celsius", "fahrenheit"],
                    "description": "Temperature unit"
                }
            },
            "required": ["location"]
        }
    }
]
```

### Tool Use Flow

```
1. User sends message with tools parameter
2. Claude responds with tool_use content block
3. Application executes tool with provided input
4. Application sends tool_result back to Claude
5. Claude processes result and responds
```

### Elixir Tool Definition (deftool macro)

```elixir
defmodule MyTools do
  use ClaudeAgentSDK.Tool

  deftool :add, "Add two numbers", %{
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
end
```

---

## Streaming Patterns

### Server-Sent Events (SSE) Format

```
event: message_start
data: {"type": "message_start", "message": {...}}

event: content_block_start
data: {"type": "content_block_start", "index": 0, "content_block": {...}}

event: content_block_delta
data: {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "Hello"}}

event: content_block_stop
data: {"type": "content_block_stop", "index": 0}

event: message_stop
data: {"type": "message_stop"}
```

### Stream Event Types

| Event Type | Description | Data |
|------------|-------------|------|
| `message_start` | Message begins | Message metadata, model info |
| `content_block_start` | New content block | Block type, index |
| `content_block_delta` | Incremental update | Delta content |
| `content_block_stop` | Block complete | Index |
| `message_delta` | Message-level update | Stop reason, usage |
| `message_stop` | Message complete | - |

### Delta Types

| Delta Type | Description | Fields |
|------------|-------------|--------|
| `text_delta` | Text content chunk | `text` |
| `input_json_delta` | Tool input chunk | `partial_json` |
| `thinking_delta` | Extended thinking (Sonnet 4.5+) | `thinking` |

### Python Streaming Pattern

```python
# Raw streaming
with client.messages.stream(
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    messages=[{"role": "user", "content": "Hello"}]
) as stream:
    for text in stream.text_stream:
        print(text, end="", flush=True)
```

### Elixir Streaming Pattern

```elixir
alias ClaudeAgentSDK.Streaming

{:ok, session} = Streaming.start_session()

Streaming.send_message(session, "Hello")
|> Stream.each(fn
  %{type: :text_delta, text: chunk} -> IO.write(chunk)
  %{type: :message_stop} -> IO.puts("")
  _ -> :ok
end)
|> Stream.run()
```

---

## MCP (Model Context Protocol) Documentation Patterns

### MCP Overview

MCP is an open protocol enabling integration between LLM applications and external tools/data sources. It uses JSON-RPC 2.0 for communication.

### Core Architecture

```
Host (LLM Application)
    |
    v
Client (MCP Client)
    |
    v
Server (Tool/Resource Provider)
```

### MCP Primitives

| Primitive | Direction | Description |
|-----------|-----------|-------------|
| **Resources** | Server -> Client | Data/context for Claude to access |
| **Prompts** | Server -> Client | Templated messages/workflows |
| **Tools** | Server -> Client | Functions Claude can execute |
| **Sampling** | Server -> Client | LLM inference requests |
| **Roots** | Server -> Client | Filesystem/URI boundaries |

### MCP Message Format

```json
// Request
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/list",
  "params": {}
}

// Response
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "tools": [
      {
        "name": "calculator",
        "description": "Perform calculations",
        "inputSchema": {...}
      }
    ]
  }
}

// Error
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32601,
    "message": "Method not found"
  }
}
```

### Standard MCP Methods

| Method | Description |
|--------|-------------|
| `initialize` | Capability exchange |
| `tools/list` | List available tools |
| `tools/call` | Execute a tool |
| `resources/list` | List available resources |
| `resources/read` | Read resource content |
| `prompts/list` | List available prompts |
| `prompts/get` | Get prompt template |
| `notifications/initialized` | Server ready notification |

### MCP Transport Types

1. **stdio** - Subprocess communication via stdin/stdout
2. **SSE** - HTTP Server-Sent Events for web scenarios
3. **Custom** - WebSocket, gRPC, etc.

### SDK MCP Server Pattern

```python
# Python SDK - Creating an SDK MCP Server
from claude_agent_sdk import tool, create_sdk_mcp_server

@tool("add", "Add two numbers", {"a": int, "b": int})
async def add(args):
    return {"content": [{"type": "text", "text": str(args["a"] + args["b"])}]}

server = create_sdk_mcp_server(
    name="calculator",
    version="1.0.0",
    tools=[add]
)

options = ClaudeAgentOptions(
    mcp_servers={"calculator": server}
)
```

```elixir
# Elixir SDK - Creating an SDK MCP Server
server = ClaudeAgentSDK.create_sdk_mcp_server(
  name: "calculator",
  version: "1.0.0",
  tools: [MyTools.Add]
)

options = %Options{
  mcp_servers: %{"calculator" => server},
  allowed_tools: ["mcp__calculator__add"]
}
```

### MCP Security Patterns

1. **User Consent** - Explicit approval for data access/tool execution
2. **Tool Safety** - Treat tools as arbitrary code; require consent
3. **Data Privacy** - No transmission without authorization
4. **OAuth 2.1** - For protected resources

---

## Claude Agent SDK Patterns

### Hook System

Hooks are callbacks invoked at specific agent lifecycle points.

#### Hook Events

| Event | When Invoked | Purpose |
|-------|--------------|---------|
| `PreToolUse` | Before tool execution | Gate/modify tool calls |
| `PostToolUse` | After tool execution | Log/audit results |
| `UserPromptSubmit` | Before sending user message | Validate/modify input |
| `Stop` | Agent stopping | Cleanup, finalization |
| `SubagentStop` | Subagent completing | Subagent coordination |
| `PreCompact` | Before context compaction | Context management |
| `session_start` | Session initialization | Setup |
| `session_end` | Session termination | Cleanup |

#### Hook Pattern (Python)

```python
async def check_bash_command(input_data, tool_use_id, context):
    command = input_data.get("tool_input", {}).get("command", "")

    if "rm -rf" in command:
        return {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": "Blocked destructive command"
            }
        }
    return {}

options = ClaudeAgentOptions(
    hooks={
        "PreToolUse": [
            HookMatcher(matcher="Bash", hooks=[check_bash_command])
        ]
    }
)
```

#### Hook Pattern (Elixir)

```elixir
def block_dangerous(%{"tool_name" => "Bash", "tool_input" => %{"command" => cmd}}, _id, _ctx) do
  if String.contains?(cmd, "rm -rf") do
    Output.deny("Blocked destructive command")
  else
    Output.allow()
  end
end

options = %Options{
  hooks: %{
    pre_tool_use: [
      Matcher.new("Bash", [&block_dangerous/3])
    ]
  }
}
```

### Permission System

#### Permission Modes

| Mode | Behavior |
|------|----------|
| `default` | Ask for each tool use |
| `acceptEdits` / `:accept_edits` | Auto-accept file edits |
| `plan` | Review before execution |
| `bypassPermissions` / `:bypass_permissions` | Auto-allow all |

#### Permission Callback Pattern

```python
# Python
async def can_use_tool(tool_name, tool_input, context):
    if dangerous(tool_input):
        return PermissionResultDeny(
            message="Blocked by policy",
            interrupt=True
        )
    return PermissionResultAllow(
        updated_input=modified_input
    )
```

```elixir
# Elixir
permission_callback = fn ctx ->
  if dangerous?(ctx.tool_input) do
    Result.deny("Blocked by policy", interrupt: true)
  else
    Result.allow()
  end
end

options = %Options{
  can_use_tool: permission_callback
}
```

### Control Protocol

The control protocol enables bidirectional communication between SDK and CLI.

#### Message Types

| Type | Direction | Purpose |
|------|-----------|---------|
| `control_request` | CLI -> SDK | Request from CLI |
| `control_response` | SDK -> CLI | Response to CLI |
| `control_cancel_request` | CLI -> SDK | Cancel pending callback |

#### Request Subtypes

| Subtype | Purpose |
|---------|---------|
| `initialize` | Handshake and capability exchange |
| `hook_callback` | Invoke hook function |
| `can_use_tool` | Check tool permission |
| `sdk_mcp_request` | Route to SDK MCP server |
| `set_model` | Runtime model change |
| `set_permission_mode` | Runtime permission change |
| `interrupt` | Stop current operation |
| `rewind_files` | File checkpoint restore |

---

## Best Practices from Official SDKs

### 1. Environment-Based Configuration

```python
# Primary pattern: environment variables for credentials
# ANTHROPIC_API_KEY, CLAUDE_AGENT_OAUTH_TOKEN, etc.
client = Anthropic()  # Uses ANTHROPIC_API_KEY automatically
```

### 2. Error Handling Hierarchy

```python
# Python SDK Error Types
APIError (base)
├── APIConnectionError
├── APIStatusError
│   ├── BadRequestError (400)
│   ├── AuthenticationError (401)
│   ├── PermissionDeniedError (403)
│   ├── NotFoundError (404)
│   ├── RateLimitError (429)
│   └── InternalServerError (>=500)
└── APITimeoutError
```

```elixir
# Elixir SDK Error Pattern
{:error, :claude_not_found}
{:error, :connection_failed}
{:error, {:process_error, exit_code, stderr}}
```

### 3. Type Safety

- Full type hints/specs in both SDKs
- TypedDict for request params (Python)
- Structs with @type specs (Elixir)
- Pydantic models for responses (Python)

### 4. Retry Logic

```python
# Built-in retry with exponential backoff
client = Anthropic(max_retries=3)

# Per-request override
client.with_options(max_retries=5).messages.create(...)
```

### 5. Context Manager Pattern

```python
# Ensure cleanup with context managers
async with ClaudeSDKClient(options) as client:
    await client.query("Hello")
```

```elixir
# GenServer lifecycle management
{:ok, client} = Client.start_link(options)
# ... use client ...
Client.stop(client)
```

### 6. Progressive Disclosure

- Simple functions for common cases (`query/2`)
- Full client for advanced features (`Client`)
- Options object for configuration
- Separate modules for specialized features (hooks, permissions, MCP)

### 7. Documentation Patterns

1. **Quick Start** - Minimal example to get running
2. **API Reference** - Complete function/method documentation
3. **Examples** - Working code samples for each feature
4. **Guides** - Conceptual explanations with patterns
5. **Error Handling** - Clear error types and recovery strategies

### 8. Testing Support

```elixir
# Elixir SDK Mock System
ClaudeAgentSDK.Mock.enable()
ClaudeAgentSDK.Mock.set_response("mock response")
```

### 9. Version Compatibility

- Semantic versioning
- Version checks for CLI compatibility
- Deprecation warnings for old patterns
- Migration guides between versions

---

## Sources

- [Anthropic SDK Python - GitHub](https://github.com/anthropics/anthropic-sdk-python)
- [Claude Agent SDK Python - GitHub](https://github.com/anthropics/claude-agent-sdk-python)
- [Claude Agent SDK Overview - Claude Docs](https://docs.anthropic.com/en/docs/claude-code/sdk)
- [MCP Specification 2025-11-25](https://modelcontextprotocol.io/specification/2025-11-25)
- [Model Context Protocol - GitHub](https://github.com/modelcontextprotocol)
- [Anthropic Academy: Claude API Development](https://www.anthropic.com/learn/build-with-claude)
- [Building Agents with Claude Agent SDK](https://www.anthropic.com/engineering/building-agents-with-the-claude-agent-sdk)
- [Advanced Tool Use - Anthropic Engineering](https://www.anthropic.com/engineering/advanced-tool-use)
- [Tool Use Implementation - Claude Docs](https://platform.claude.com/docs/en/agents-and-tools/tool-use/implement-tool-use)

---

## Appendix: Type Mapping (Python to Elixir)

| Python | Elixir | Notes |
|--------|--------|-------|
| `TypedDict` | `%{}` map or struct | Structs for strong typing |
| `@dataclass` | `defstruct` | Compile-time structure |
| `Literal["a", "b"]` | `@type :: :a \| :b` | Atoms for constants |
| `list[T]` | `[T.t()]` | List type specs |
| `dict[K, V]` | `%{K.t() => V.t()}` | Map type specs |
| `Callable[[A], R]` | `(A.t() -> R.t())` | Function types |
| `Awaitable[T]` | `T.t()` | No async/await in Elixir |
| `AsyncIterator[T]` | `Stream` | Lazy enumerable |
| `Union[A, B]` | `A.t() \| B.t()` | Type unions |

---

*End of Research Document*
