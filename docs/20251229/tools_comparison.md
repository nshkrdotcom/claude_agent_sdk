# Tool Systems Comparison: Python vs Elixir Claude Agent SDK

## Overview

Both SDKs support SDK MCP servers - in-process tool definitions that run without subprocess overhead. This document compares the tool definition, registration, and execution approaches.

## Parity Status

| Feature | Python SDK | Elixir SDK | Parity |
|---------|------------|------------|--------|
| Tool Definition | `@tool` decorator (via MCP SDK) | `deftool` macro | Full |
| Schema Definition | Pydantic / dict | Map-based JSON Schema | Full |
| Tool Registry | MCP Server instance | GenServer registry | Full |
| MCP Server Creation | `McpServer` class | `ClaudeAgentSDK.Tool.Registry` | Full |
| Tool Execution | Handler function | `execute/1` callback | Full |
| JSONRPC Routing | Manual routing | Manual routing | Full |

## Tool Definition

### Python: MCP SDK `@tool` Decorator

```python
from mcp.server import Server
from mcp.types import TextContent

server = Server("calculator")

@server.call_tool()
async def handle_tool_call(name: str, arguments: dict):
    if name == "add":
        result = arguments["a"] + arguments["b"]
        return [TextContent(type="text", text=str(result))]

@server.list_tools()
async def list_tools():
    return [
        {
            "name": "add",
            "description": "Add two numbers",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "a": {"type": "number"},
                    "b": {"type": "number"}
                },
                "required": ["a", "b"]
            }
        }
    ]
```

### Elixir: `deftool` Macro

```elixir
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
      {:ok, %{"content" => [%{"type" => "text", "text" => "Result: #{a + b}"}]}}
    end
  end
end
```

### Key Differences

| Aspect | Python | Elixir |
|--------|--------|--------|
| Approach | Decorator on handler functions | Macro generating modules |
| Module Generation | N/A (uses MCP Server) | Creates nested module per tool |
| Discovery | Via `list_tools()` handler | Via `__tools__/0` function |
| Error Handling | Raises exceptions | Returns `{:ok, _}` or `{:error, _}` |

## Schema Definition

### Python Approach

Python SDK relies on the MCP SDK's schema handling, typically using dicts that conform to JSON Schema:

```python
{
    "type": "object",
    "properties": {
        "expression": {"type": "string", "description": "Math expression"}
    },
    "required": ["expression"]
}
```

Or via Pydantic models when using `pydantic` integration:

```python
from pydantic import BaseModel

class AddInput(BaseModel):
    a: float
    b: float
```

### Elixir Approach

Elixir uses plain maps that represent JSON Schema:

```elixir
%{
  type: "object",
  properties: %{
    expression: %{type: "string", description: "Math expression"}
  },
  required: ["expression"]
}
```

Validation is minimal - only checks for `type` field presence:

```elixir
def valid_schema?(schema) when is_map(schema) do
  Map.has_key?(schema, :type) or Map.has_key?(schema, "type")
end
```

## Tool Registry Implementations

### Python: MCP Server Instance

The Python SDK uses the MCP SDK's `Server` class as the registry:

```python
from mcp.server import Server

server = Server("my-tools")

# Register tool handlers via decorators
@server.call_tool()
async def handle_call(name, arguments):
    ...

# Pass to SDK
options = ClaudeAgentOptions(
    mcp_servers={
        "my-tools": {"type": "sdk", "instance": server}
    }
)
```

### Elixir: GenServer Registry

The Elixir SDK uses a dedicated `GenServer` for tool registration:

```elixir
# Start registry
{:ok, registry} = ClaudeAgentSDK.Tool.Registry.start_link([])

# Register tools from module
for tool <- ClaudeAgentSDK.Tool.list_tools(MyTools) do
  :ok = ClaudeAgentSDK.Tool.Registry.register_tool(registry, tool)
end

# Pass to SDK
options = %Options{
  mcp_servers: %{
    "my-tools" => %{type: :sdk, registry_pid: registry}
  }
}
```

### Registry API Comparison

| Operation | Python | Elixir |
|-----------|--------|--------|
| Start | `Server("name")` | `Registry.start_link([])` |
| Register | `@server.call_tool()` decorator | `Registry.register_tool(pid, tool)` |
| List | `list_tools()` handler | `Registry.list_tools(pid)` |
| Execute | `call_tool()` handler | `Registry.execute_tool(pid, name, input)` |
| Lookup | N/A (routed internally) | `Registry.get_tool(pid, name)` |

## MCP Server Creation

### Python: McpSdkServerConfig

```python
from mcp.server import Server

server = Server("calculator")

# Register with SDK
options = ClaudeAgentOptions(
    mcp_servers={
        "calculator": {
            "type": "sdk",
            "name": "calculator",
            "instance": server
        }
    }
)
```

### Elixir: Registry-Based

```elixir
# Create registry and register tools
{:ok, registry} = ClaudeAgentSDK.Tool.Registry.start_link(name: :calculator)

for tool <- ClaudeAgentSDK.Tool.list_tools(MyTools) do
  ClaudeAgentSDK.Tool.Registry.register_tool(registry, tool)
end

# Register with SDK
options = %Options{
  mcp_servers: %{
    "calculator" => %{
      type: :sdk,
      name: "calculator",
      version: "1.0.0",
      registry_pid: registry
    }
  }
}
```

## Tool Execution Flow

### Python Flow

1. CLI sends `control_request` with `mcp_message` subtype
2. `Query._handle_sdk_mcp_request` receives request
3. Routes based on JSONRPC method:
   - `initialize` - Returns protocol version and capabilities
   - `tools/list` - Calls `server.request_handlers[ListToolsRequest]`
   - `tools/call` - Calls `server.request_handlers[CallToolRequest]`
4. Converts MCP result to JSONRPC response
5. Sends `control_response` back to CLI

```python
# From query.py
async def _handle_sdk_mcp_request(self, server_name: str, message: dict) -> dict:
    server = self.sdk_mcp_servers[server_name]
    method = message.get("method")

    if method == "tools/call":
        call_request = CallToolRequest(
            method=method,
            params=CallToolRequestParams(
                name=params.get("name"),
                arguments=params.get("arguments", {})
            ),
        )
        handler = server.request_handlers.get(CallToolRequest)
        result = await handler(call_request)
        # Convert to JSONRPC...
```

### Elixir Flow

1. CLI sends `control_request` with `sdk_mcp_request` or `mcp_message` subtype
2. `Client.handle_sdk_mcp_request/3` receives request
3. Looks up registry PID from `state.sdk_mcp_servers`
4. Dispatches based on JSONRPC method via pattern matching
5. Calls `Registry.execute_tool/3` for tool calls
6. Wraps result in JSONRPC response
7. Sends `control_response` back to CLI

```elixir
# From client.ex
defp handle_sdk_mcp_request(request_id, request, state) do
  server_name = request["serverName"] || request["server_name"]
  message = request["message"]

  case Map.get(state.sdk_mcp_servers, server_name) do
    nil -> # Error response
    registry_pid ->
      response = handle_sdk_mcp_jsonrpc(registry_pid, server_name, message)
      send_sdk_mcp_response(state, request_id, response)
  end
end

defp dispatch_sdk_mcp_method("tools/call", registry_pid, _server_name, message_id, params) do
  tool_name = String.to_atom(params["name"])
  tool_input = params["arguments"] || %{}

  case ClaudeAgentSDK.Tool.Registry.execute_tool(registry_pid, tool_name, tool_input) do
    {:ok, result} -> %{"jsonrpc" => "2.0", "id" => message_id, "result" => result}
    {:error, reason} -> # Error response
  end
end
```

## JSONRPC Method Support

Both SDKs implement manual JSONRPC routing for these methods:

| Method | Python | Elixir | Notes |
|--------|--------|--------|-------|
| `initialize` | Yes | Yes | Returns protocol version 2024-11-05 |
| `tools/list` | Yes | Yes | Lists registered tools |
| `tools/call` | Yes | Yes | Executes tool with arguments |
| `resources/list` | No | Yes (empty) | Elixir returns empty list |
| `prompts/list` | No | Yes (empty) | Elixir returns empty list |
| `notifications/initialized` | Yes | Yes | Acknowledges initialization |

## Differences and Gaps

### 1. Tool Definition Ergonomics

**Python**: Uses decorators which are more familiar to Python developers but require understanding the MCP SDK.

**Elixir**: The `deftool` macro is SDK-specific but provides a more integrated experience.

### 2. Error Handling

**Python**: Tool handlers raise exceptions which are caught and converted to error responses.

**Elixir**: Tools return tagged tuples (`{:ok, result}` / `{:error, reason}`) following Elixir conventions.

### 3. Module Structure

**Python**: Tools are functions attached to an MCP Server instance.

**Elixir**: Each tool becomes its own nested module with metadata functions.

### 4. Schema Validation

**Python**: Relies on MCP SDK or Pydantic for validation.

**Elixir**: Minimal validation (only checks `type` field exists).

### 5. Transport Layer Limitation

Both SDKs note that the MCP Python SDK lacks a proper Transport abstraction:

```python
# From query.py
# TODO: Python MCP SDK lacks the Transport abstraction that TypeScript has.
# TypeScript: server.connect(transport) allows custom transports
# Python: server.run(read_stream, write_stream) requires actual streams
#
# This forces us to manually route methods.
```

## Recommendations

1. **Elixir**: Consider adding Pydantic-like schema validation for better input validation
2. **Python**: The manual JSONRPC routing should be updated when MCP SDK adds Transport support
3. **Both**: Add support for MCP resources and prompts capabilities beyond empty stubs
