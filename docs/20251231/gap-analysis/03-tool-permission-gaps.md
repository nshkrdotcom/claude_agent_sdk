# Tool Handling and Permissions Gap Analysis

**Date:** 2025-12-31
**Focus Area:** Tool Permission System and Callbacks
**Python SDK Version:** v0.1.x
**Elixir SDK Version:** v0.7.2

---

## Executive Summary

The Elixir SDK has achieved **full parity** with the Python SDK for the core tool permission system. Both SDKs implement the `can_use_tool` callback mechanism, permission contexts with suggestions, allow/deny results with input modification, and permission updates. The Elixir implementation follows idiomatic patterns while maintaining wire-protocol compatibility.

**Key Findings:**
- **Full Feature Coverage**: All 7 core permission features are implemented
- **Complete Type Coverage**: PermissionResult, PermissionUpdate, PermissionRuleValue all present
- **Runtime Mode Switching**: Implemented via `set_permission_mode`
- **Control Protocol Integration**: Properly handles `can_use_tool` requests from CLI

**Remaining Opportunities:**
- Minor: `blocked_path` field usage could be documented better
- Minor: Example file similar to Python's `tool_permission_callback.py` would help adoption

---

## Feature Comparison Table

| Feature | Python SDK | Elixir SDK | Status | Notes |
|---------|-----------|------------|--------|-------|
| **can_use_tool callback** | `CanUseTool` type in `types.py` | `:can_use_tool` in `Options.t()` | Complete | Elixir uses arity-1 function vs Python's arity-3 async |
| **ToolPermissionContext** | `ToolPermissionContext` dataclass | `Permission.Context` struct | Complete | All fields present |
| **Context.signal** | `signal: Any \| None` | `signal: AbortSignal.t() \| nil` | Complete | Elixir has typed AbortSignal |
| **Context.suggestions** | `suggestions: list[PermissionUpdate]` | `suggestions: [map()]` | Complete | Maps from CLI |
| **Context.blocked_path** | `blocked_path: str \| None` | `blocked_path: String.t() \| nil` | Complete | Added in Elixir |
| **PermissionResultAllow** | `PermissionResultAllow` dataclass | `Result.allow/1` function | Complete | Fluent builder pattern |
| **PermissionResultDeny** | `PermissionResultDeny` dataclass | `Result.deny/2` function | Complete | Fluent builder pattern |
| **updated_input** | `updated_input: dict[str, Any] \| None` | `updated_input: map() \| nil` | Complete | Same semantics |
| **updated_permissions** | `updated_permissions: list[PermissionUpdate]` | `updated_permissions: [Update.t() \| map()]` | Complete | Supports both structs and maps |
| **interrupt flag** | `interrupt: bool = False` | `interrupt: boolean()` | Complete | Same behavior |
| **PermissionUpdate types** | 6 types: addRules, replaceRules, removeRules, setMode, addDirectories, removeDirectories | 6 types: same | Complete | Full parity |
| **PermissionUpdateDestination** | 4 options: userSettings, projectSettings, localSettings, session | 4 options: same | Complete | Same destinations |
| **PermissionBehavior** | allow, deny, ask | allow, deny, ask | Complete | Same behaviors |
| **PermissionRuleValue** | `PermissionRuleValue` dataclass | `RuleValue` struct | Complete | Same structure |
| **set_permission_mode runtime** | `Query.set_permission_mode()` | `Protocol.encode_set_permission_mode_request()` | Complete | Implemented |
| **Permission modes** | default, acceptEdits, plan, bypassPermissions | :default, :accept_edits, :plan, :bypass_permissions | Complete | Atom naming in Elixir |

---

## Detailed Implementation Comparison

### 1. can_use_tool Callback Support

**Python SDK (types.py:155-157):**
```python
CanUseTool = Callable[
    [str, dict[str, Any], ToolPermissionContext], Awaitable[PermissionResult]
]
```

**Elixir SDK (permission.ex:88-92):**
```elixir
@typedoc """
Permission callback function type.

Receives permission context and returns permission result.
"""
@type callback :: (Context.t() -> Result.t())
```

**Analysis:**
- Python uses a 3-argument async callable: `(tool_name, input, context) -> PermissionResult`
- Elixir consolidates into a 1-argument sync function: `(context) -> Result.t()`
- Elixir's approach is cleaner as all data is in `Context.t()`
- Both achieve the same functionality

**Status:** Complete - architectural difference is intentional for Elixir idioms

---

### 2. ToolPermissionContext (signal, suggestions)

**Python SDK (types.py:124-131):**
```python
@dataclass
class ToolPermissionContext:
    """Context information for tool permission callbacks."""
    signal: Any | None = None  # Future: abort signal support
    suggestions: list[PermissionUpdate] = field(default_factory=list)
```

**Elixir SDK (permission/context.ex:74-84):**
```elixir
@type t :: %__MODULE__{
        tool_name: String.t(),
        tool_input: map(),
        session_id: String.t(),
        suggestions: [map()],
        blocked_path: String.t() | nil,
        signal: ClaudeAgentSDK.AbortSignal.t() | nil
      }

@enforce_keys [:tool_name, :tool_input, :session_id]
defstruct [:tool_name, :tool_input, :session_id, :signal, :blocked_path, suggestions: []]
```

**Analysis:**
- Elixir context includes more fields (`tool_name`, `tool_input`, `session_id`) since callback is arity-1
- Both support `signal` and `suggestions`
- Elixir adds `blocked_path` which Python receives but doesn't include in context struct
- Elixir has proper AbortSignal type vs Python's Any

**Status:** Complete - Elixir has richer context structure

---

### 3. PermissionResult Types

**Python SDK (types.py:134-153):**
```python
@dataclass
class PermissionResultAllow:
    behavior: Literal["allow"] = "allow"
    updated_input: dict[str, Any] | None = None
    updated_permissions: list[PermissionUpdate] | None = None

@dataclass
class PermissionResultDeny:
    behavior: Literal["deny"] = "deny"
    message: str = ""
    interrupt: bool = False

PermissionResult = PermissionResultAllow | PermissionResultDeny
```

**Elixir SDK (permission/result.ex:73-85):**
```elixir
@type t :: %__MODULE__{
        behavior: behavior(),
        updated_input: map() | nil,
        updated_permissions: [Update.t() | map()] | nil,
        message: String.t() | nil,
        interrupt: boolean()
      }

defstruct behavior: :allow,
          updated_input: nil,
          updated_permissions: nil,
          message: nil,
          interrupt: false
```

**Builder Functions (permission/result.ex:114-150):**
```elixir
@spec allow(keyword()) :: t()
def allow(opts \\ []) do
  %__MODULE__{
    behavior: :allow,
    updated_input: Keyword.get(opts, :updated_input),
    updated_permissions: Keyword.get(opts, :updated_permissions)
  }
end

@spec deny(String.t(), keyword()) :: t()
def deny(message, opts \\ []) when is_binary(message) do
  %__MODULE__{
    behavior: :deny,
    message: message,
    interrupt: Keyword.get(opts, :interrupt, false)
  }
end
```

**Analysis:**
- Python uses separate dataclasses for Allow/Deny
- Elixir uses a single struct with builder functions - more idiomatic
- Both support `updated_input`, `updated_permissions`, `message`, `interrupt`
- Elixir's fluent API: `Result.allow(updated_input: %{...})`

**Status:** Complete - idiomatic implementation

---

### 4. PermissionUpdate Types

**Python SDK (types.py:69-120):**
```python
@dataclass
class PermissionUpdate:
    type: Literal["addRules", "replaceRules", "removeRules", "setMode", "addDirectories", "removeDirectories"]
    rules: list[PermissionRuleValue] | None = None
    behavior: PermissionBehavior | None = None
    mode: PermissionMode | None = None
    directories: list[str] | None = None
    destination: PermissionUpdateDestination | None = None

    def to_dict(self) -> dict[str, Any]:
        # Serialization logic...
```

**Elixir SDK (permission/update.ex:54-102):**
```elixir
@type update_type ::
        :add_rules
        | :replace_rules
        | :remove_rules
        | :set_mode
        | :add_directories
        | :remove_directories

@type t :: %__MODULE__{
        type: update_type(),
        rules: [RuleValue.t()] | nil,
        behavior: behavior() | nil,
        mode: ClaudeAgentSDK.Permission.permission_mode() | nil,
        directories: [String.t()] | nil,
        destination: destination() | nil
      }

defstruct [:type, :rules, :behavior, :mode, :directories, :destination]
```

**Builder Functions (permission/update.ex:104-144):**
```elixir
def add_rules(opts \\ []), do: new(:add_rules, opts)
def replace_rules(opts \\ []), do: new(:replace_rules, opts)
def remove_rules(opts \\ []), do: new(:remove_rules, opts)
def set_mode(mode, opts \\ []), do: new(:set_mode, Keyword.put(opts, :mode, mode))
def add_directories(directories, opts \\ [])
def remove_directories(directories, opts \\ [])
```

**Analysis:**
- All 6 update types implemented
- Elixir uses atoms for types (`:add_rules`) vs Python strings (`"addRules"`)
- Both have serialization to camelCase for wire protocol
- Elixir provides convenient builder functions

**Status:** Complete - full parity with idiomatic API

---

### 5. PermissionRuleValue Structure

**Python SDK (types.py:60-66):**
```python
@dataclass
class PermissionRuleValue:
    tool_name: str
    rule_content: str | None = None
```

**Elixir SDK (permission/rule_value.ex:23-28):**
```elixir
@type t :: %__MODULE__{
        tool_name: String.t(),
        rule_content: String.t() | nil
      }

defstruct [:tool_name, :rule_content]
```

**Status:** Complete - exact same structure

---

### 6. PermissionUpdateDestination Options

**Python SDK (types.py:52-55):**
```python
PermissionUpdateDestination = Literal[
    "userSettings", "projectSettings", "localSettings", "session"
]
```

**Elixir SDK (permission/update.ex:44):**
```elixir
@type destination :: :user_settings | :project_settings | :local_settings | :session
```

**Serialization (permission/update.ex:183-186):**
```elixir
defp destination_to_string(:user_settings), do: "userSettings"
defp destination_to_string(:project_settings), do: "projectSettings"
defp destination_to_string(:local_settings), do: "localSettings"
defp destination_to_string(:session), do: "session"
```

**Status:** Complete - all destinations supported with proper serialization

---

### 7. Runtime Permission Mode Changes

**Python SDK (query.py:524-531):**
```python
async def set_permission_mode(self, mode: str) -> None:
    """Change permission mode."""
    await self._send_control_request({
        "subtype": "set_permission_mode",
        "mode": mode,
    })
```

**Elixir SDK (control_protocol/protocol.ex:162-182):**
```elixir
@spec encode_set_permission_mode_request(String.t(), request_id() | nil) ::
        {request_id(), String.t()}
def encode_set_permission_mode_request(mode, request_id \\ nil) when is_binary(mode) do
  req_id = request_id || generate_request_id()

  request = %{
    "type" => "control_request",
    "request_id" => req_id,
    "request" => %{
      "subtype" => "set_permission_mode",
      "mode" => mode
    }
  }

  {req_id, Jason.encode!(request)}
end
```

**Status:** Complete - implemented in control protocol

---

## Control Request Handling

**Python SDK (query.py:237-278):**
```python
if subtype == "can_use_tool":
    permission_request: SDKControlPermissionRequest = request_data
    context = ToolPermissionContext(
        signal=None,
        suggestions=permission_request.get("permission_suggestions", []) or [],
    )
    response = await self.can_use_tool(
        permission_request["tool_name"],
        permission_request["input"],
        context,
    )
    # Convert to response format...
```

**Elixir SDK (client.ex:1863-1906):**
```elixir
defp handle_can_use_tool_request(request_id, request, state) do
  tool_name = request["tool_name"]
  tool_input = request["input"]
  suggestions = request["permission_suggestions"] || []
  blocked_path = request["blocked_path"]
  session_id = state.session_id || "unknown"

  case state.options.can_use_tool do
    nil ->
      json = encode_permission_response(request_id, :allow, nil, tool_input)
      _ = send_payload(state, json)
      state

    callback when is_function(callback, 1) ->
      # Execute in Task with timeout
      context = Context.new(
        tool_name: tool_name,
        tool_input: tool_input,
        session_id: session_id,
        suggestions: suggestions,
        blocked_path: blocked_path,
        signal: signal
      )
      # ... async execution with callback
  end
end
```

**Status:** Complete - properly handles `can_use_tool` control requests

---

## Response Encoding

**Python SDK (query.py:257-278):**
```python
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
elif isinstance(response, PermissionResultDeny):
    response_data = {"behavior": "deny", "message": response.message}
    if response.interrupt:
        response_data["interrupt"] = response.interrupt
```

**Elixir SDK (client.ex:1991-2022):**
```elixir
defp encode_permission_response(request_id, :allow, result, original_input) do
  result_map =
    result
    |> then(&(&1 || Result.allow()))
    |> Result.to_json_map()
    |> Map.put_new("updatedInput", original_input)
  # ... wrap in control_response
end

defp encode_permission_response(request_id, :deny, result, _original_input) do
  response = %{
    "type" => "control_response",
    "response" => %{
      "request_id" => request_id,
      "subtype" => "success",
      "response" => Result.to_json_map(result)
    }
  }
  # ...
end
```

**Status:** Complete - proper JSON encoding for both allow and deny responses

---

## Priority Recommendations

### Priority 1: Documentation (Low Effort, High Impact)

1. **Create Example File**: Add `examples/tool_permission_callback.exs` similar to Python's example
   - Demonstrates basic allow/deny logic
   - Shows input modification
   - Demonstrates security policy patterns

2. **Document blocked_path Usage**: The Elixir SDK includes `blocked_path` in Context but its usage isn't documented

### Priority 2: Testing Enhancement (Low Effort, Medium Impact)

1. **Integration Tests**: The test file has placeholder tests for permission modes that say "validated at integration level"
   - Add actual integration tests with mock transport

### Priority 3: Minor API Improvements (Optional)

1. **Suggestions Type**: Currently `suggestions: [map()]` - could be typed more specifically
   - Consider `suggestions: [Update.t() | map()]` for type safety

---

## Conclusion

The Elixir SDK has achieved **complete feature parity** with the Python SDK for tool handling and permissions. The implementation follows Elixir idioms while maintaining full wire-protocol compatibility:

- Single context struct instead of multiple function arguments
- Fluent builder API with `Result.allow/1` and `Result.deny/2`
- Atom-based types internally, proper camelCase serialization for protocol
- AbortSignal properly typed (not just `Any`)
- Additional `blocked_path` field in context

The only remaining work is documentation and examples, not functionality gaps.
