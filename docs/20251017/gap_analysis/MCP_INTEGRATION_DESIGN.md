# MCP Tool System Integration Design

**Date:** 2025-10-17
**Status:** DESIGN COMPLETE - Ready for TDD Implementation
**Based on:** Python SDK v1.x architecture analysis

---

## Executive Summary

After analyzing the Python Claude Agent SDK, I've discovered the **correct architecture** for MCP tool integration. The previous understanding was **partially incorrect** - Claude CLI handles ALL tool routing, including SDK tools. The SDK doesn't intercept tool_use messages; instead, it provides SDK MCP servers to the CLI via the control protocol, and the CLI calls back to the SDK when it needs to execute an SDK tool.

**Key Insight:** SDK MCP servers are **server instances exposed via control protocol**, not in-process interceptors.

---

## Python SDK Architecture (Correct Implementation)

### How It Actually Works

1. **Server Configuration** (Python SDK)
   ```python
   # User creates SDK MCP server
   server_config = create_sdk_mcp_server(
       name="math-tools",
       version="1.0.0",
       tools=[add_tool, multiply_tool]
   )
   # Returns: {
   #   "type": "sdk",
   #   "name": "math-tools",
   #   "instance": <MCP Server object>
   # }
   ```

2. **Options Configuration**
   ```python
   options = ClaudeAgentOptions(
       mcp_servers={
           "math-tools": server_config,  # SDK server
           "external-server": {           # External server
               "type": "stdio",
               "command": "mcp-server",
               "args": []
           }
       }
   )
   ```

3. **CLI Launch** (subprocess_cli.py:138-163)
   - SDK servers: Pass metadata ONLY (type, name, version)
   - **OMIT the "instance" field** from CLI args
   - External servers: Pass complete config (command, args, etc.)

   ```python
   # CLI receives:
   --mcp-config '{
     "math-tools": {"type": "sdk", "name": "math-tools"},
     "external-server": {"type": "stdio", "command": "mcp-server"}
   }'
   ```

4. **Tool Discovery** (Claude CLI side)
   - CLI sees `math-tools` has `type: "sdk"`
   - CLI sends control request to SDK: `sdk_mcp_request`
   - Request contains MCP JSONRPC message for `tools/list`

5. **Control Protocol Request** (query.py:357-468)
   - SDK receives control request: `{"subtype": "sdk_mcp_request", "serverName": "math-tools", "message": {...}}`
   - SDK routes to in-process MCP server instance
   - `_handle_sdk_mcp_request()` manually handles JSONRPC routing
   - Supports `initialize`, `tools/list`, and `tools/call` methods

6. **Tool Execution Flow**
   ```
   Claude → CLI → Control Protocol → SDK → MCP Server Instance → Tool Handler
   Claude ← CLI ← Control Protocol ← SDK ← MCP Server Instance ← Tool Result
   ```

### Critical Code Locations (Python)

**1. CLI Args Builder** (subprocess_cli.py:138-163)
```python
if self._options.mcp_servers:
    if isinstance(self._options.mcp_servers, dict):
        servers_for_cli: dict[str, Any] = {}
        for name, config in self._options.mcp_servers.items():
            if isinstance(config, dict) and config.get("type") == "sdk":
                # IMPORTANT: Strip the "instance" field!
                servers_for_cli[name] = {
                    k: v for k, v in config.items() if k != "instance"
                }
            else:
                servers_for_cli[name] = config

        cmd.extend(["--mcp-config", json.dumps(servers_for_cli)])
```

**2. SDK MCP Request Handler** (query.py:357-468)
```python
async def _handle_sdk_mcp_request(
    self, server_name: str, message: dict[str, Any]
) -> dict[str, Any]:
    """Bridge JSONRPC messages from CLI to in-process MCP server."""

    if server_name not in self.sdk_mcp_servers:
        return {"error": {"code": -32601, "message": "Server not found"}}

    server = self.sdk_mcp_servers[server_name]
    method = message.get("method")

    if method == "tools/list":
        request = ListToolsRequest(method=method)
        handler = server.request_handlers.get(ListToolsRequest)
        result = await handler(request)
        # Convert to JSONRPC response
        return {"jsonrpc": "2.0", "id": message["id"], "result": {...}}

    elif method == "tools/call":
        request = CallToolRequest(...)
        handler = server.request_handlers.get(CallToolRequest)
        result = await handler(request)
        # Convert to JSONRPC response
        return {"jsonrpc": "2.0", "id": message["id"], "result": {...}}
```

**3. Control Request Routing** (query.py:224-291)
```python
async def _handle_control_request(self, request: SDKControlRequest) -> dict[str, Any]:
    """Route control requests to appropriate handlers."""

    subtype = request.get("subtype")

    if subtype == "sdk_mcp_request":
        server_name = request.get("serverName")
        message = request.get("message")
        return await self._handle_sdk_mcp_request(server_name, message)

    elif subtype == "can_use_tool":
        # Permission callback handling
        ...

    elif subtype == "hook_callback":
        # Hook callback handling
        ...
```

---

## Elixir SDK Implementation Plan

### Phase 1: Type System Fix (FIRST!)

**Current Problem:**
```elixir
# Options.ex - BROKEN
@type mcp_config :: String.t() | nil

# Can't store server instances!
```

**Solution:**
```elixir
# Options.ex - FIXED
@type external_mcp_server :: %{
  type: :stdio | :sse | :http,
  command: String.t(),
  args: [String.t()],
  # ... other fields
}

@type sdk_mcp_server :: %{
  type: :sdk,
  name: String.t(),
  version: String.t(),
  registry_pid: pid()
}

@type mcp_server :: external_mcp_server() | sdk_mcp_server()

defstruct [
  # ... other fields

  # NEW: Replaces mcp_config for programmatic server definitions
  mcp_servers: %{String.t() => mcp_server()} | nil,

  # KEEP: For external config files (backward compatibility)
  mcp_config: String.t() | nil,

  # ... other fields
]
```

### Phase 2: CLI Args Builder

**File:** `lib/claude_agent_sdk/process.ex`

**Current (Broken):**
```elixir
defp add_mcp_config_args(args, %{mcp_config: config}) when is_binary(config) do
  args ++ ["--mcp-config", config]
end
# Crashes if mcp_config is a map!
```

**Fixed:**
```elixir
defp add_mcp_args(args, options) do
  cond do
    # File path config (backward compat)
    is_binary(options.mcp_config) ->
      args ++ ["--mcp-config", options.mcp_config]

    # Programmatic servers
    is_map(options.mcp_servers) and map_size(options.mcp_servers) > 0 ->
      servers_for_cli = prepare_servers_for_cli(options.mcp_servers)
      args ++ ["--mcp-config", Jason.encode!(servers_for_cli)]

    true ->
      args
  end
end

defp prepare_servers_for_cli(servers) do
  for {name, config} <- servers, into: %{} do
    case config do
      %{type: :sdk} = sdk_server ->
        # Strip the registry_pid field - CLI doesn't need it
        {name, %{
          type: "sdk",
          name: sdk_server.name,
          version: sdk_server.version || "1.0.0"
        }}

      external_server ->
        # Pass external servers as-is
        {name, external_server}
    end
  end
end
```

### Phase 3: Control Protocol Handler

**File:** `lib/claude_agent_sdk/client.ex`

**Add to Client state:**
```elixir
defstruct [
  # ... existing fields

  # NEW: Store SDK MCP server registry PIDs for lookup
  sdk_mcp_servers: %{String.t() => pid()} | nil,

  # ... existing fields
]
```

**Extract servers from options:**
```elixir
defp init_from_options(options) do
  # Extract SDK server PIDs for control protocol
  sdk_servers = case options.mcp_servers do
    nil -> %{}
    servers ->
      for {name, %{type: :sdk, registry_pid: pid}} <- servers, into: %{} do
        {name, pid}
      end
  end

  %{
    # ... other state
    sdk_mcp_servers: sdk_servers,
    # ... other state
  }
end
```

**Add control request handler:**
```elixir
defp handle_control_request(%{"subtype" => "sdk_mcp_request"} = request, state) do
  server_name = request["serverName"]
  message = request["message"]

  case Map.get(state.sdk_mcp_servers, server_name) do
    nil ->
      error_response(request["id"], -32601, "Server '#{server_name}' not found")

    registry_pid ->
      handle_sdk_mcp_request(registry_pid, message)
  end
end

defp handle_sdk_mcp_request(registry_pid, %{"method" => method} = message) do
  case method do
    "initialize" ->
      # Return MCP initialization response
      %{
        "jsonrpc" => "2.0",
        "id" => message["id"],
        "result" => %{
          "protocolVersion" => "2024-11-05",
          "capabilities" => %{"tools" => %{}},
          "serverInfo" => %{
            "name" => "sdk-mcp-server",
            "version" => "1.0.0"
          }
        }
      }

    "tools/list" ->
      # Query the registry for all tools
      tools = Tool.Registry.list_tools(registry_pid)

      tools_data = Enum.map(tools, fn tool ->
        %{
          "name" => to_string(tool.name),
          "description" => tool.description,
          "inputSchema" => tool.input_schema
        }
      end)

      %{
        "jsonrpc" => "2.0",
        "id" => message["id"],
        "result" => %{"tools" => tools_data}
      }

    "tools/call" ->
      # Execute the tool via registry
      params = message["params"] || %{}
      tool_name = String.to_atom(params["name"])
      tool_input = params["arguments"] || %{}

      case Tool.Registry.execute_tool(registry_pid, tool_name, tool_input) do
        {:ok, result} ->
          %{
            "jsonrpc" => "2.0",
            "id" => message["id"],
            "result" => result
          }

        {:error, reason} ->
          error_response(message["id"], -32603, "Tool execution failed: #{inspect(reason)}")
      end

    _ ->
      error_response(message["id"], -32601, "Method not found: #{method}")
  end
end

defp error_response(id, code, message) do
  %{
    "jsonrpc" => "2.0",
    "id" => id,
    "error" => %{
      "code" => code,
      "message" => message
    }
  }
end
```

**Route control messages:**
```elixir
defp handle_decoded_message(:control_request, request, state) do
  subtype = request["request"]["subtype"]

  response = case subtype do
    "sdk_mcp_request" ->
      handle_control_request(request["request"], state)

    "can_use_tool" ->
      handle_permission_request(request, state)

    "hook_callback" ->
      handle_hook_callback(request, state)

    _ ->
      %{"error" => "Unknown control request subtype: #{subtype}"}
  end

  # Send response back to CLI
  send_control_response(state.port, request["id"], response)
  state
end

defp send_control_response(port, request_id, response) do
  message = %{
    "type" => "control_response",
    "id" => request_id,
    "response" => response
  }

  Port.command(port, Jason.encode!(message) <> "\n")
end
```

### Phase 4: Integration Tests (TDD Approach)

**File:** `test/claude_agent_sdk/sdk_mcp_integration_test.exs`

```elixir
defmodule ClaudeAgentSDK.SDKMCPIntegrationTest do
  use ExUnit.Case, async: false

  alias ClaudeAgentSDK.{Options, Client, Tool}

  # These tests MUST use real CLI integration (not just mocks)
  @tag :integration
  @tag :skip  # Initially skip until implementation complete
  test "SDK MCP tool is listed by Claude CLI" do
    # Define a test tool
    defmodule TestListTool do
      use ClaudeAgentSDK.Tool

      deftool :test_list, "Test tool for listing", %{type: "object"} do
        def execute(_args) do
          {:ok, %{"content" => [%{"type" => "text", "text" => "executed"}]}}
        end
      end
    end

    # Create SDK MCP server
    server = ClaudeAgentSDK.create_sdk_mcp_server(
      name: "test-server",
      version: "1.0.0",
      tools: [TestListTool.TestList]
    )

    # Configure with SDK server
    options = Options.new(
      mcp_servers: %{"test-server" => server},
      max_turns: 1
    )

    {:ok, client} = Client.start_link(options)

    # Query Claude - it should discover the tool
    messages = ClaudeAgentSDK.query("List available tools", options)
    |> Enum.to_list()

    # Verify Claude received tool list
    # (This will fail until implementation is complete)
    assert Enum.any?(messages, fn msg ->
      # Check for tool discovery message
      msg["type"] == "assistant" &&
      String.contains?(Jason.encode!(msg), "test_list")
    end)

    Client.stop(client)
  end

  @tag :integration
  @tag :skip
  test "SDK MCP tool is executed by Claude during query" do
    # Track executions
    test_pid = self()

    defmodule TestExecuteTool do
      use ClaudeAgentSDK.Tool

      deftool :execute_me, "Execute this tool", %{
        type: "object",
        properties: %{value: %{type: "string"}},
        required: ["value"]
      } do
        def execute(%{"value" => val}) do
          # Signal test process
          send(unquote(test_pid), {:tool_executed, val})
          {:ok, %{"content" => [%{"type" => "text", "text" => "Result: #{val}"}]}}
        end
      end
    end

    server = ClaudeAgentSDK.create_sdk_mcp_server(
      name: "exec-server",
      version: "1.0.0",
      tools: [TestExecuteTool.ExecuteMe]
    )

    options = Options.new(
      mcp_servers: %{"exec-server" => server},
      max_turns: 3
    )

    # Query that should trigger tool use
    ClaudeAgentSDK.query("Please use the execute_me tool with value 'test123'", options)
    |> Stream.run()

    # Verify tool was actually called
    assert_receive {:tool_executed, "test123"}, 5000
  end

  @tag :integration
  @tag :skip
  test "SDK and external MCP servers work together" do
    # Define SDK tool
    defmodule SDKTool do
      use ClaudeAgentSDK.Tool

      deftool :sdk_add, "Add numbers (SDK)", %{
        type: "object",
        properties: %{a: %{type: "number"}, b: %{type: "number"}},
        required: ["a", "b"]
      } do
        def execute(%{"a" => a, "b" => b}) do
          {:ok, %{"content" => [%{"type" => "text", "text" => "Sum: #{a + b}"}]}}
        end
      end
    end

    sdk_server = ClaudeAgentSDK.create_sdk_mcp_server(
      name: "sdk-math",
      version: "1.0.0",
      tools: [SDKTool.SdkAdd]
    )

    # External server config (hypothetical)
    external_server = %{
      type: :stdio,
      command: "external-mcp-server",
      args: []
    }

    options = Options.new(
      mcp_servers: %{
        "sdk-math" => sdk_server,
        "external" => external_server
      },
      max_turns: 5
    )

    # Query should be able to use BOTH server types
    messages = ClaudeAgentSDK.query(
      "Add 5 and 3 using sdk_add, then use any external tools",
      options
    ) |> Enum.to_list()

    # Verify both tool types were available
    # (exact assertion depends on external server behavior)
    assert length(messages) > 0
  end

  @tag :integration
  @tag :skip
  test "SDK MCP tool errors are handled gracefully" do
    defmodule ErrorTool do
      use ClaudeAgentSDK.Tool

      deftool :will_fail, "Always fails", %{type: "object"} do
        def execute(_args) do
          {:error, "Intentional error"}
        end
      end
    end

    server = ClaudeAgentSDK.create_sdk_mcp_server(
      name: "error-server",
      version: "1.0.0",
      tools: [ErrorTool.WillFail]
    )

    options = Options.new(
      mcp_servers: %{"error-server" => server},
      max_turns: 2
    )

    # Query should not crash even if tool fails
    messages = ClaudeAgentSDK.query("Use the will_fail tool", options)
    |> Enum.to_list()

    # Verify error was returned to Claude
    assert Enum.any?(messages, fn msg ->
      Jason.encode!(msg) =~ "error" || Jason.encode!(msg) =~ "fail"
    end)
  end
end
```

---

## Implementation Checklist

### Pre-Implementation (DONE ✅)
- [x] Research Python SDK architecture
- [x] Document complete design
- [x] Identify all required changes
- [x] Write comprehensive integration tests (skipped initially)

### Phase 1: Type System (1-2 days)
- [ ] Update Options struct with `mcp_servers` field
- [ ] Add types for `external_mcp_server` and `sdk_mcp_server`
- [ ] Deprecate but keep `mcp_config` for backward compat
- [ ] Update Options.new/1 to handle both formats
- [ ] Write tests for Options type handling

### Phase 2: CLI Args (1 day)
- [ ] Refactor `add_mcp_config_args` to `add_mcp_args`
- [ ] Implement `prepare_servers_for_cli/1`
- [ ] Strip `registry_pid` from SDK servers for CLI
- [ ] Convert server configs to JSON for --mcp-config
- [ ] Test CLI args generation with mixed servers

### Phase 3: Control Protocol (2-3 days)
- [ ] Add `sdk_mcp_servers` to Client state
- [ ] Extract SDK server PIDs during Client initialization
- [ ] Implement `handle_control_request/2` for sdk_mcp_request
- [ ] Implement `handle_sdk_mcp_request/2` for JSONRPC routing
- [ ] Support `initialize`, `tools/list`, and `tools/call` methods
- [ ] Implement `send_control_response/3`
- [ ] Add error handling for missing servers and tool failures

### Phase 4: Integration Testing (2-3 days)
- [ ] Write tool listing integration test
- [ ] Write tool execution integration test
- [ ] Write mixed SDK+external server test
- [ ] Write error handling test
- [ ] Write concurrent tool execution test
- [ ] Unskip all integration tests
- [ ] Verify all tests pass

### Phase 5: Documentation & Examples (1-2 days)
- [ ] Update README with SDK MCP usage
- [ ] Create working live examples
- [ ] Update CHANGELOG
- [ ] Add API documentation
- [ ] Create troubleshooting guide

---

## Testing Strategy

### 1. Unit Tests (Fast, No CLI)
- Tool definition and metadata
- Tool execution (direct calls)
- Registry management
- Server configuration creation
- Type conversions

### 2. Control Protocol Tests (Mock CLI)
- Control request routing
- JSONRPC message handling
- Error responses
- Response serialization

### 3. Integration Tests (Real CLI) **MOST IMPORTANT**
- Full query workflow with SDK tools
- Tool discovery via CLI
- Tool execution via CLI
- Mixed SDK + external servers
- Error propagation

### 4. Live Tests (Manual, Real API)
- Create live examples that work
- Test with actual Claude API
- Verify tool execution end-to-end
- Document real-world usage

---

## Success Criteria

### Must Have (Blocking for v0.5.0)
✅ All integration tests passing (not skipped)
✅ SDK MCP tools work in real queries
✅ Mixed SDK + external servers supported
✅ Error handling robust
✅ Live examples work without crashes

### Should Have
✅ Zero warnings
✅ Comprehensive documentation
✅ Performance acceptable (< 100ms overhead per tool call)
✅ Memory usage reasonable (< 10MB per server)

### Nice to Have
⚪ Telemetry events for tool execution
⚪ Debugging tools for SDK servers
⚪ Performance benchmarks

---

## Risk Mitigation

### Risk: Control protocol mismatch with CLI
**Mitigation:** Test with real Claude CLI early and often

### Risk: JSONRPC routing bugs
**Mitigation:** Compare with Python SDK byte-for-byte

### Risk: Concurrent tool execution issues
**Mitigation:** Add concurrency tests, use GenServer serialization

### Risk: Memory leaks in long-running servers
**Mitigation:** Add cleanup logic, test with many tool calls

---

## Timeline

- **Week 1 (Days 1-5):** Implementation (Phases 1-3)
- **Week 2 (Days 6-10):** Testing & Polish (Phases 4-5)
- **Total:** 10 working days for 100% complete MCP integration

---

## Conclusion

The MCP Tool System infrastructure is **70% complete**. The remaining 30% is:
1. Type system refactoring (10%)
2. CLI args preparation (5%)
3. Control protocol JSONRPC routing (10%)
4. Integration testing (5%)

With the proper architecture now understood and documented, implementation should be straightforward following TDD principles. All tests are written FIRST (currently skipped), implementation follows, then tests are unskipped and must pass.

**This design is ready for implementation.**
