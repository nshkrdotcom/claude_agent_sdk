# MCP Implementation Comparison: Python vs Elixir Claude Agent SDK

## Overview

Both SDKs support the Model Context Protocol (MCP) for tool integration. This document compares MCP server configuration, external server types, JSONRPC routing, and protocol compliance.

## Parity Status

| Feature | Python SDK | Elixir SDK | Parity |
|---------|------------|------------|--------|
| SDK MCP Servers | Yes | Yes | Full |
| Stdio External Servers | Yes | Yes | Full |
| SSE External Servers | Yes | Partial | Partial |
| HTTP External Servers | Yes | Partial | Partial |
| JSONRPC Routing | Manual | Manual | Full |
| Protocol Version | 2024-11-05 | 2024-11-05 | Full |
| Tools Capability | Yes | Yes | Full |
| Resources Capability | Stub | Stub | Full |
| Prompts Capability | Stub | Stub | Full |

## SDK MCP Server Support

### Python Configuration

```python
from mcp.server import Server as McpServer
from claude_agent_sdk import query, ClaudeAgentOptions

# Create MCP server with tools
server = McpServer("calculator")

@server.call_tool()
async def handle_call(name: str, arguments: dict):
    # Tool implementation
    pass

# Configure SDK
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

### Elixir Configuration

```elixir
defmodule MyTools do
  use ClaudeAgentSDK.Tool

  deftool :add, "Add numbers", %{type: "object"} do
    def execute(%{"a" => a, "b" => b}) do
      {:ok, %{"content" => [%{"type" => "text", "text" => "#{a + b}"}]}}
    end
  end
end

# Start registry
{:ok, registry} = ClaudeAgentSDK.Tool.Registry.start_link([])

# Register tools
for tool <- ClaudeAgentSDK.Tool.list_tools(MyTools) do
  ClaudeAgentSDK.Tool.Registry.register_tool(registry, tool)
end

# Configure SDK
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

### Key Difference

**Python**: Uses MCP SDK `Server` class instances directly with the `instance` field.

**Elixir**: Uses a custom `Registry` GenServer with `registry_pid` field. The tools are defined via the `deftool` macro.

## External Server Types

### Stdio Servers

Both SDKs support subprocess-based MCP servers via stdio transport.

#### Python

```python
# types.py
class McpStdioServerConfig(TypedDict):
    type: NotRequired[Literal["stdio"]]  # Optional for backwards compatibility
    command: str
    args: NotRequired[list[str]]
    env: NotRequired[dict[str, str]]

# Usage
options = ClaudeAgentOptions(
    mcp_servers={
        "my-server": {
            "type": "stdio",
            "command": "npx",
            "args": ["-y", "@modelcontextprotocol/server-filesystem"],
            "env": {"PATH": "/usr/bin"}
        }
    }
)
```

#### Elixir

```elixir
# Passed through to CLI via --mcp-config
options = %Options{
  mcp_servers: %{
    "my-server" => %{
      type: "stdio",
      command: "npx",
      args: ["-y", "@modelcontextprotocol/server-filesystem"],
      env: %{"PATH" => "/usr/bin"}
    }
  }
}
```

### SSE Servers

Server-Sent Events transport for remote MCP servers.

#### Python

```python
class McpSSEServerConfig(TypedDict):
    type: Literal["sse"]
    url: str
    headers: NotRequired[dict[str, str]]

options = ClaudeAgentOptions(
    mcp_servers={
        "remote": {
            "type": "sse",
            "url": "https://mcp.example.com/sse",
            "headers": {"Authorization": "Bearer token"}
        }
    }
)
```

#### Elixir

```elixir
# Passed to CLI - handled by CLI, not SDK
options = %Options{
  mcp_servers: %{
    "remote" => %{
      type: "sse",
      url: "https://mcp.example.com/sse",
      headers: %{"Authorization" => "Bearer token"}
    }
  }
}
```

### HTTP Servers

HTTP-based MCP transport (Streamable HTTP).

#### Python

```python
class McpHttpServerConfig(TypedDict):
    type: Literal["http"]
    url: str
    headers: NotRequired[dict[str, str]]

options = ClaudeAgentOptions(
    mcp_servers={
        "http-server": {
            "type": "http",
            "url": "https://mcp.example.com/http",
            "headers": {"X-API-Key": "key"}
        }
    }
)
```

#### Elixir

Same pattern - passed to CLI via `--mcp-config`.

## JSONRPC Routing

Both SDKs implement manual JSONRPC method routing for SDK MCP servers. Neither can use the MCP SDK's native transport due to API limitations.

### Python Implementation

```python
# From query.py
async def _handle_sdk_mcp_request(
    self, server_name: str, message: dict[str, Any]
) -> dict[str, Any]:
    server = self.sdk_mcp_servers[server_name]
    method = message.get("method")
    params = message.get("params", {})

    if method == "initialize":
        return {
            "jsonrpc": "2.0",
            "id": message.get("id"),
            "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {}},
                "serverInfo": {
                    "name": server.name,
                    "version": server.version or "1.0.0",
                },
            },
        }

    elif method == "tools/list":
        request = ListToolsRequest(method=method)
        handler = server.request_handlers.get(ListToolsRequest)
        result = await handler(request)
        # Convert to JSONRPC format...

    elif method == "tools/call":
        call_request = CallToolRequest(
            method=method,
            params=CallToolRequestParams(
                name=params.get("name"),
                arguments=params.get("arguments", {})
            ),
        )
        handler = server.request_handlers.get(CallToolRequest)
        result = await handler(call_request)
        # Convert to JSONRPC format...
```

### Elixir Implementation

```elixir
# From client.ex
defp dispatch_sdk_mcp_method("initialize", _registry_pid, server_name, message_id, _params) do
  %{
    "jsonrpc" => "2.0",
    "id" => message_id,
    "result" => %{
      "protocolVersion" => "2024-11-05",
      "capabilities" => %{"tools" => %{}},
      "serverInfo" => %{
        "name" => server_name,
        "version" => "1.0.0"
      }
    }
  }
end

defp dispatch_sdk_mcp_method("tools/list", registry_pid, _server_name, message_id, _params) do
  {:ok, tools} = ClaudeAgentSDK.Tool.Registry.list_tools(registry_pid)

  tools_data = Enum.map(tools, fn tool ->
    %{
      "name" => to_string(tool.name),
      "description" => tool.description,
      "inputSchema" => tool.input_schema
    }
  end)

  %{
    "jsonrpc" => "2.0",
    "id" => message_id,
    "result" => %{"tools" => tools_data}
  }
end

defp dispatch_sdk_mcp_method("tools/call", registry_pid, _server_name, message_id, params) do
  tool_name = String.to_atom(params["name"])
  tool_input = params["arguments"] || %{}

  case ClaudeAgentSDK.Tool.Registry.execute_tool(registry_pid, tool_name, tool_input) do
    {:ok, result} ->
      %{"jsonrpc" => "2.0", "id" => message_id, "result" => result}
    {:error, reason} ->
      %{"jsonrpc" => "2.0", "id" => message_id,
        "error" => %{"code" => -32603, "message" => "..."}}
  end
end
```

### Routing Comparison

| Method | Python | Elixir |
|--------|--------|--------|
| `initialize` | Returns hardcoded capabilities | Returns hardcoded capabilities |
| `tools/list` | Calls `ListToolsRequest` handler | Calls `Registry.list_tools/1` |
| `tools/call` | Calls `CallToolRequest` handler | Calls `Registry.execute_tool/3` |
| `resources/list` | Not implemented | Returns empty list |
| `prompts/list` | Not implemented | Returns empty list |
| `notifications/initialized` | Returns empty result | Returns empty result |
| Unknown method | Returns -32601 error | Returns -32601 error |

## Protocol Version Compliance

Both SDKs implement MCP protocol version `2024-11-05`.

### Capabilities Advertised

```json
{
  "protocolVersion": "2024-11-05",
  "capabilities": {
    "tools": {}
  },
  "serverInfo": {
    "name": "<server_name>",
    "version": "1.0.0"
  }
}
```

### Notable Limitations

1. **No `listChanged` capability**: Neither SDK advertises tool list change notifications
2. **No resources support**: Both return empty resource lists
3. **No prompts support**: Both return empty prompt lists
4. **No sampling support**: Neither SDK implements MCP sampling

## Control Protocol Integration

MCP requests flow through the SDK's control protocol:

### Request Flow

1. CLI sends `control_request` with subtype `mcp_message` (Python) or `sdk_mcp_request`/`mcp_message` (Elixir)
2. SDK extracts `server_name` and JSONRPC `message`
3. SDK routes to appropriate handler based on method
4. SDK wraps JSONRPC response in `control_response`

### Request Format

```json
{
  "type": "control_request",
  "request_id": "req_123",
  "request": {
    "subtype": "mcp_message",
    "server_name": "calculator",
    "message": {
      "jsonrpc": "2.0",
      "id": 1,
      "method": "tools/call",
      "params": {
        "name": "add",
        "arguments": {"a": 1, "b": 2}
      }
    }
  }
}
```

### Response Format

```json
{
  "type": "control_response",
  "response": {
    "subtype": "success",
    "request_id": "req_123",
    "response": {
      "mcp_response": {
        "jsonrpc": "2.0",
        "id": 1,
        "result": {
          "content": [{"type": "text", "text": "3"}]
        }
      }
    }
  }
}
```

## Differences Summary

### 1. Server Instance vs Registry

**Python**: Uses MCP SDK `Server` instances directly, leveraging its built-in request handler system.

**Elixir**: Uses a custom GenServer registry that stores tool metadata and execution modules.

### 2. Subtype Field Names

**Python**: Uses `mcp_message` subtype consistently.

**Elixir**: Accepts both `sdk_mcp_request` and `mcp_message` for compatibility.

### 3. Resources/Prompts Stubs

**Python**: Does not implement these methods (returns method not found).

**Elixir**: Returns empty lists for forward compatibility.

### 4. External Server Handling

Both SDKs pass external server configurations (stdio, sse, http) directly to the CLI via `--mcp-config`. The SDK itself does not manage these connections.

## Recommendations

1. **Unified Subtype**: Standardize on `mcp_message` subtype for both SDKs
2. **Resources/Prompts**: Both SDKs should implement empty stubs for consistency
3. **Transport Abstraction**: When Python MCP SDK adds Transport support, refactor to use it
4. **ListChanged Support**: Consider adding tool list change notification support
