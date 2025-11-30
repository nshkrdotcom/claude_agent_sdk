# MCP SDK Manual Method Routing Limitation

- **What's missing:** The Python MCP SDK lacks a Transport abstraction, forcing the SDK to manually route MCP JSONRPC methods. This means any new MCP protocol methods require code changes to `_handle_sdk_mcp_request`.

- **Evidence:**
  - `src/claude_agent_sdk/_internal/query.py:401-407`:
    ```python
    # TODO: Python MCP SDK lacks the Transport abstraction that TypeScript has.
    # TypeScript: server.connect(transport) allows custom transports
    # Python: server.run(read_stream, write_stream) requires actual streams
    #
    # This forces us to manually route methods. When Python MCP adds Transport
    # support, we can refactor to match the TypeScript approach.
    ```

  - `src/claude_agent_sdk/_internal/query.py:408-496`: The method manually handles:
    - `initialize`
    - `tools/list`
    - `tools/call`
    - `notifications/initialized`

  - Line 489 explicitly notes the limitation:
    ```python
    # Add more methods here as MCP SDK adds them (resources, prompts, etc.)
    # This is the limitation Ashwin pointed out - we have to manually update
    ```

- **Impact:**
  1. When MCP SDK adds new methods (resources, prompts, sampling, etc.), they won't work until the SDK is updated
  2. Maintenance burden: each new MCP method requires SDK changes
  3. Feature lag: SDK users cannot use new MCP features until code is updated
  4. Only `tools/list` and `tools/call` are supported; other MCP capabilities are not available

- **Proposed fix:**
  1. Monitor the Python MCP SDK for Transport abstraction support
  2. When available, refactor to use `server.connect(transport)` pattern
  3. As a workaround, consider implementing a custom transport layer that bridges JSONRPC messages to the MCP server
  4. Add placeholder method handling that returns "method not found" for unknown methods but logs them for visibility
  5. Document supported vs unsupported MCP capabilities
