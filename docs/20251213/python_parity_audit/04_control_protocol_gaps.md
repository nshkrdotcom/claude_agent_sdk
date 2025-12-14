# Python → Elixir Parity Audit: Query & Control Protocol Gaps

---

Gap: Permission response field casing (`updatedInput` / `updatedPermissions`)

Python Location: `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/query.py:237-270`

Python Code:
```py
if isinstance(response, PermissionResultAllow):
    response_data = {
        "behavior": "allow",
        "updatedInput": (
            response.updated_input
            if response.updated_input is not None
            else original_input
        ),
    }
    if response.updated_permissions is not None:
        response_data["updatedPermissions"] = [
            permission.to_dict()
            for permission in response.updated_permissions
        ]
```

Elixir Status: Partial

Elixir Location: `lib/claude_agent_sdk/permission/result.ex:167-174`

Priority: Critical

Suggested Implementation:
Update the permission response encoder to emit CLI-expected camelCase keys (`updatedInput`, `updatedPermissions`) instead of snake_case (`updated_input`, `updated_permissions`). Consider also accepting both forms on input and normalizing internally.

Complexity: Simple

---

Gap: Control request timeout + cleanup (Python defaults to 60s; Elixir waits indefinitely)

Python Location: `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/query.py:339-385`

Python Code:
```py
async def _send_control_request(self, request: dict[str, Any], timeout: float = 60.0) -> dict[str, Any]:
    ...
    with anyio.fail_after(timeout):
        await event.wait()
    ...
except TimeoutError as e:
    ...
    raise Exception(f"Control request timeout: {request.get('subtype')}") from e
```

Elixir Status: Not implemented

Elixir Location: `lib/claude_agent_sdk/client.ex:264` (public API uses `GenServer.call(..., :infinity)`) and `lib/claude_agent_sdk/client.ex:1295` (pending requests have no per-request timers)

Priority: Medium

Suggested Implementation:
Add per-request timeouts for control requests (set_model, set_permission_mode, interrupt, rewind_files, etc.) and ensure timed-out entries are removed from `state.pending_requests` with a deterministic reply (e.g., `{:error, :timeout}`) instead of hanging.

Complexity: Moderate

---

Gap: SDK MCP request subtype + field name compatibility (`mcp_message` vs `sdk_mcp_request`)

Python Location: `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/types.py:714-718`, `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/query.py:296-314`

Python Code:
```py
class SDKControlMcpMessageRequest(TypedDict):
    subtype: Literal["mcp_message"]
    server_name: str
    message: Any

elif subtype == "mcp_message":
    server_name = request_data.get("server_name")
    mcp_message = request_data.get("message")
    ...
```

Elixir Status: Different approach (potential interop gap)

Elixir Location: `lib/claude_agent_sdk/client.ex:1268-1270`, `test/claude_agent_sdk/sdk_mcp_routing_test.exs:45`

Priority: High

Suggested Implementation:
Accept both protocol variants:
- subtype `"mcp_message"` with keys `"server_name"` / `"serverName"`
- subtype `"sdk_mcp_request"` with keys `"server_name"` / `"serverName"`
and route to the same internal MCP handler. This makes Elixir compatible with the Python SDK’s expected control messages while preserving current behavior/tests.

Complexity: Moderate

---

Gap: Permission request `blocked_path` not surfaced to callbacks

Python Location: `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/types.py:687-694`

Python Code:
```py
class SDKControlPermissionRequest(TypedDict):
    subtype: Literal["can_use_tool"]
    tool_name: str
    input: dict[str, Any]
    permission_suggestions: list[Any] | None
    blocked_path: str | None
```

Elixir Status: Not implemented

Elixir Location: `lib/claude_agent_sdk/permission/context.ex:74-83`, `lib/claude_agent_sdk/client.ex:1548-1588`

Priority: Low

Suggested Implementation:
Add `blocked_path` to `ClaudeAgentSDK.Permission.Context` and pass it through from incoming `can_use_tool` requests so callbacks can make path-aware decisions.

Complexity: Simple
