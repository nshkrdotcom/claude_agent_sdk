# Python Claude Agent SDK Features

This document provides a comprehensive reference of all features available in the Python Claude Agent SDK (`anthropics/claude-agent-sdk-python`).

## Table of Contents

1. [ClaudeAgentOptions Fields](#claudeagentoptions-fields)
2. [Message Types and Content Blocks](#message-types-and-content-blocks)
3. [Tool System](#tool-system)
4. [Control Protocol Features](#control-protocol-features)
5. [Hook System](#hook-system)
6. [Permission System](#permission-system)
7. [Error Handling](#error-handling)

---

## ClaudeAgentOptions Fields

The `ClaudeAgentOptions` dataclass defines all configuration options for agent sessions.

### Core Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `prompt` | `str` | Required | The initial prompt/query to send to Claude |
| `cwd` | `str \| None` | `None` | Working directory for CLI execution |
| `model` | `str \| None` | `None` | Model to use (e.g., `"claude-sonnet-4-20250514"`) |
| `max_turns` | `int \| None` | `None` | Maximum conversation turns |
| `system_prompt` | `str \| None` | `None` | Custom system prompt |
| `allowed_tools` | `list[str] \| None` | `None` | List of allowed tool names |
| `disallowed_tools` | `list[str] \| None` | `None` | List of disallowed tool names |
| `session_id` | `str \| None` | `None` | Session ID for conversation resumption |

### Permission Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `permission_mode` | `PermissionMode` | `"default"` | Permission handling mode |
| `permission_prompt_tool_name` | `str \| None` | `None` | Custom permission prompt tool |

### MCP Server Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `mcp_servers` | `dict[str, MCPServerConfig] \| None` | `None` | MCP server configurations |

### Hook Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `hooks` | `Hooks \| None` | `None` | Hook configuration for callbacks |

### Advanced Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `cli_path` | `str \| None` | `None` | Custom path to Claude CLI |
| `resume` | `bool` | `False` | Resume previous session |
| `continue_conversation` | `bool` | `False` | Continue existing conversation |

### Example

```python
from claude_agent_sdk import ClaudeAgentOptions, query

options = ClaudeAgentOptions(
    prompt="Write a hello world function",
    model="claude-sonnet-4-20250514",
    max_turns=10,
    allowed_tools=["Bash", "Write", "Read"],
    system_prompt="You are a helpful coding assistant.",
    cwd="/path/to/project"
)

for message in query(options):
    print(message)
```

---

## Message Types and Content Blocks

### Message Types

Messages from the SDK are categorized by type:

| Type | Description |
|------|-------------|
| `system` | System/initialization messages |
| `assistant` | Claude's responses |
| `user` | User messages |
| `result` | Query result/completion messages |

### Message Subtypes

| Subtype | Type | Description |
|---------|------|-------------|
| `init` | system | Session initialization info |
| `text` | assistant | Text content from Claude |
| `tool_use` | assistant | Tool invocation |
| `tool_result` | user | Result from tool execution |
| `success` | result | Successful query completion |
| `error` | result | Error during query |
| `error_max_turns` | result | Max turns exceeded |
| `error_during_execution` | result | Execution error |
| `interrupted` | result | Query was interrupted |

### Content Block Types

Content blocks are components of assistant messages:

| Block Type | Description |
|------------|-------------|
| `text` | Plain text content |
| `tool_use` | Tool usage with name, input, and ID |
| `tool_result` | Result from tool execution |

### Example Message Structure

```python
# System initialization message
{
    "type": "system",
    "subtype": "init",
    "session_id": "abc123",
    "model": "claude-sonnet-4-20250514"
}

# Assistant text message
{
    "type": "assistant",
    "message": {
        "role": "assistant",
        "content": [
            {
                "type": "text",
                "text": "Here's a hello world function:"
            }
        ]
    }
}

# Tool use message
{
    "type": "assistant",
    "message": {
        "role": "assistant",
        "content": [
            {
                "type": "tool_use",
                "id": "toolu_abc123",
                "name": "Write",
                "input": {
                    "file_path": "/path/to/file.py",
                    "content": "def hello(): print('Hello')"
                }
            }
        ]
    }
}

# Result message
{
    "type": "result",
    "subtype": "success",
    "total_cost_usd": 0.0123,
    "duration_seconds": 5.2
}
```

---

## Tool System

### The @tool Decorator

The Python SDK provides a `@tool` decorator for defining custom tools:

```python
from claude_agent_sdk import tool

@tool
def calculate_sum(a: int, b: int) -> int:
    """Calculate the sum of two numbers.

    Args:
        a: First number
        b: Second number

    Returns:
        The sum of a and b
    """
    return a + b
```

### Tool Schema Generation

The decorator automatically generates JSON Schema from:
- Function signature (parameter types)
- Docstring (descriptions)
- Type hints (for validation)

### create_sdk_mcp_server

Creates an SDK-hosted MCP server for custom tools:

```python
from claude_agent_sdk import create_sdk_mcp_server, tool

@tool
def my_tool(param: str) -> str:
    """My custom tool."""
    return f"Result: {param}"

# Create MCP server with tools
server = create_sdk_mcp_server(
    name="my-tools",
    version="1.0.0",
    tools=[my_tool]
)

# Use in options
options = ClaudeAgentOptions(
    prompt="Use my tool",
    mcp_servers={"my-tools": server}
)
```

### Built-in Tools

The SDK supports Claude's built-in tools:

| Tool Name | Description |
|-----------|-------------|
| `Bash` | Execute shell commands |
| `Read` | Read file contents |
| `Write` | Write to files |
| `Edit` | Edit file contents |
| `MultiEdit` | Multiple file edits |
| `Glob` | File pattern matching |
| `Grep` | Search file contents |
| `WebFetch` | Fetch web content |
| `WebSearch` | Search the web |
| `NotebookEdit` | Edit Jupyter notebooks |
| `TodoWrite` | Manage todo lists |

---

## Control Protocol Features

The control protocol enables bidirectional communication between the SDK and CLI.

### Message Types

| Direction | Type | Description |
|-----------|------|-------------|
| SDK -> CLI | `control_request` | Request from SDK to CLI |
| CLI -> SDK | `control_response` | Response to SDK request |
| CLI -> SDK | `control_request` | Request from CLI (hooks) |
| SDK -> CLI | `control_response` | Response to CLI request |
| SDK -> CLI | `control_cancel_request` | Cancel pending request |

### Control Request Subtypes

| Subtype | Description |
|---------|-------------|
| `initialize` | Initialize session with hooks config |
| `set_model` | Change model at runtime |
| `set_permission_mode` | Change permission mode |
| `interrupt` | Interrupt current operation |
| `rewind_files` | Rewind file changes to checkpoint |
| `hook_callback` | Hook callback request from CLI |
| `can_use_tool` | Permission check request |
| `sdk_mcp_request` | SDK MCP server request |

### Example Control Flow

```
SDK                              CLI
 |                                |
 |-- control_request (init) ----->|
 |<-- control_response (success) -|
 |                                |
 |-- user message --------------->|
 |<-- assistant message ----------|
 |<-- control_request (hook) -----|
 |-- control_response (allow) --->|
 |<-- tool_result ----------------|
 |<-- result (success) -----------|
```

---

## Hook System

Hooks enable interception and modification of SDK behavior at various points.

### Hook Events

| Event | Trigger | Description |
|-------|---------|-------------|
| `PreToolUse` | Before tool execution | Validate/modify tool inputs |
| `PostToolUse` | After tool execution | Process tool results |
| `StopGeneration` | (If supported) | Stop response generation |

### Hook Configuration

```python
from claude_agent_sdk import ClaudeAgentOptions, Hooks, Matcher

def pre_tool_hook(input_data, tool_use_id, context):
    """Hook called before tool execution."""
    tool_name = input_data.get("tool_name")

    if tool_name == "Bash":
        command = input_data.get("command", "")
        if "rm -rf" in command:
            return {"behavior": "deny", "message": "Dangerous command blocked"}

    return {"behavior": "allow"}

hooks = Hooks(
    pre_tool_use=[
        Matcher(
            tool_name="Bash",
            hooks=[pre_tool_hook]
        )
    ]
)

options = ClaudeAgentOptions(
    prompt="Run a command",
    hooks=hooks
)
```

### Matcher Configuration

| Field | Type | Description |
|-------|------|-------------|
| `tool_name` | `str \| list[str]` | Tool(s) to match |
| `hooks` | `list[Callable]` | Hook callbacks |
| `timeout_ms` | `int \| None` | Callback timeout |

### Hook Callback Signature

```python
def hook_callback(
    input_data: dict,      # Tool input data
    tool_use_id: str,      # Unique tool use ID
    context: dict          # Context with abort signal
) -> dict:
    """
    Returns:
        {"behavior": "allow"} - Allow tool execution
        {"behavior": "deny", "message": "..."} - Deny with message
        {"behavior": "modify", "updatedInput": {...}} - Modify input
    """
```

---

## Permission System

The permission system controls tool execution authorization.

### Permission Modes

| Mode | Description |
|------|-------------|
| `default` | All tools go through permission callback |
| `acceptEdits` | Edit operations auto-allowed |
| `plan` | Show plan before execution |
| `bypassPermissions` | All tools allowed without callback |

### Permission Callback

```python
def permission_callback(context):
    """
    Called when a tool needs permission.

    Args:
        context: Permission context with:
            - tool_name: Name of tool
            - tool_input: Tool input parameters
            - session_id: Current session ID
            - suggestions: Permission suggestions
            - blocked_path: Path that was blocked (if any)

    Returns:
        Permission result (allow/deny/modify)
    """
    if context.tool_name == "Write":
        path = context.tool_input.get("file_path", "")
        if path.startswith("/etc/"):
            return {"behavior": "deny", "message": "Cannot write to /etc"}

    return {"behavior": "allow"}

options = ClaudeAgentOptions(
    prompt="Write a file",
    can_use_tool=permission_callback
)
```

### Permission Result Types

| Behavior | Description |
|----------|-------------|
| `allow` | Allow tool execution |
| `deny` | Deny with optional message |
| `modify` | Modify input and allow |

---

## Error Handling

### Exception Types

| Exception | Description |
|-----------|-------------|
| `CLIConnectionError` | Failed to connect to CLI |
| `CLINotFoundError` | Claude CLI not found |
| `ProcessError` | CLI process error |
| `CLIJSONDecodeError` | Invalid JSON from CLI |
| `MessageParseError` | Message parsing failed |

### Error Handling Example

```python
from claude_agent_sdk import query, ClaudeAgentOptions
from claude_agent_sdk._errors import (
    CLIConnectionError,
    CLINotFoundError,
    ProcessError
)

try:
    options = ClaudeAgentOptions(prompt="Hello")
    for message in query(options):
        if message.type == "result":
            if message.subtype == "error":
                print(f"Query error: {message.data}")
            else:
                print(f"Success! Cost: ${message.data.get('total_cost_usd', 0)}")

except CLINotFoundError:
    print("Claude CLI not installed. Run: npm install -g @anthropic-ai/claude-code")

except CLIConnectionError as e:
    print(f"Connection failed: {e.message}")
    print(f"Working directory: {e.cwd}")

except ProcessError as e:
    print(f"Process error: {e.message}")
    print(f"Exit code: {e.exit_code}")
    print(f"Stderr: {e.stderr}")
```

### Result Subtypes for Errors

| Subtype | Description |
|---------|-------------|
| `error` | General error |
| `error_max_turns` | Exceeded maximum turns |
| `error_during_execution` | Error during tool execution |
| `interrupted` | Query was interrupted |

---

## Summary

The Python Claude Agent SDK provides:

- **Streaming query interface** via `query()` function
- **Interactive client** via `ClaudeSDKClient` for bidirectional communication
- **Hook system** for pre/post tool use interception
- **Permission system** for fine-grained tool authorization
- **MCP server support** for custom tool hosting
- **Comprehensive error handling** with typed exceptions

For more information, see the [official documentation](https://docs.anthropic.com/en/docs/claude-code/sdk).
