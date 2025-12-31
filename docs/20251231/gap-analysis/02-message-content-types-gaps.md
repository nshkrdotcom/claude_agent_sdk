# Gap Analysis: Message and Content Types

**Date:** 2025-12-31
**Component:** Message and Content Types
**Python SDK Version:** claude-agent-sdk-python (current main)
**Elixir Port Version:** claude_agent_sdk (current main)

---

## Executive Summary

The Elixir port provides **functional parity** for core message and content type handling but uses a fundamentally different architectural approach. Where Python uses distinct dataclasses for each message and content type, Elixir uses a single unified `Message` struct with a `type` field discriminator and nested data maps. This design is idiomatic for Elixir but creates some differences in developer ergonomics and type safety.

### Key Findings

| Category | Status | Notes |
|----------|--------|-------|
| Message Types | **Complete** | All 5 types supported (user, assistant, system, result, stream_event) |
| Content Blocks | **Complete** | All 4 types parsed (text, thinking, tool_use, tool_result) |
| ResultMessage Fields | **Complete** | All 10 fields present |
| StreamEvent Support | **Complete** | Full streaming event support with EventParser |
| Type Safety | **Architectural Gap** | Python has typed dataclasses; Elixir uses dynamic maps |
| Assistant Error Types | **Complete** | All 6 error codes mapped |

### Critical Gaps

1. **No dedicated struct types for content blocks** - Python uses `TextBlock`, `ThinkingBlock`, `ToolUseBlock`, `ToolResultBlock` dataclasses; Elixir uses plain maps with `:type` atoms
2. **No dedicated structs for message variants** - Python has `UserMessage`, `AssistantMessage`, `SystemMessage`, `ResultMessage`, `StreamEvent` dataclasses; Elixir uses unified `Message` struct

---

## 1. Message Types Comparison

### Python SDK Message Types

```python
# types.py - Distinct dataclasses for each message type

@dataclass
class UserMessage:
    content: str | list[ContentBlock]
    uuid: str | None = None
    parent_tool_use_id: str | None = None

@dataclass
class AssistantMessage:
    content: list[ContentBlock]
    model: str
    parent_tool_use_id: str | None = None
    error: AssistantMessageError | None = None

@dataclass
class SystemMessage:
    subtype: str
    data: dict[str, Any]

@dataclass
class ResultMessage:
    subtype: str
    duration_ms: int
    duration_api_ms: int
    is_error: bool
    num_turns: int
    session_id: str
    total_cost_usd: float | None = None
    usage: dict[str, Any] | None = None
    result: str | None = None
    structured_output: Any = None

@dataclass
class StreamEvent:
    uuid: str
    session_id: str
    event: dict[str, Any]
    parent_tool_use_id: str | None = None

Message = UserMessage | AssistantMessage | SystemMessage | ResultMessage | StreamEvent
```

### Elixir Port Message Types

```elixir
# message.ex - Single unified struct with type discriminator

defstruct [:type, :subtype, :data, :raw]

@type message_type ::
        :assistant | :user | :result | :system | :stream_event | :unknown | String.t()
@type result_subtype :: :success | :error_max_turns | :error_during_execution | String.t()
@type system_subtype :: :init | String.t()
```

### Field-by-Field Comparison

#### UserMessage

| Field | Python | Elixir | Notes |
|-------|--------|--------|-------|
| content | `str \| list[ContentBlock]` | `data.message["content"]` | Nested in data map |
| uuid | `str \| None` | `data.uuid` or `data[:uuid]` | Present via `maybe_put_uuid/2` |
| parent_tool_use_id | `str \| None` | `data.parent_tool_use_id` | Present |
| **Accessor** | Direct field access | Requires map navigation | Ergonomic difference |

#### AssistantMessage

| Field | Python | Elixir | Notes |
|-------|--------|--------|-------|
| content | `list[ContentBlock]` | `data.message["content"]` | Nested in data map |
| model | `str` | `data.message["model"]` | Extracted from message |
| parent_tool_use_id | `str \| None` | `data.parent_tool_use_id` | Present |
| error | `AssistantMessageError \| None` | `data.error` | Uses `AssistantError.cast/1` |
| **Accessor** | Direct field access | Requires map navigation | Ergonomic difference |

#### SystemMessage

| Field | Python | Elixir | Notes |
|-------|--------|--------|-------|
| subtype | `str` | `subtype` (atom) | Direct struct field |
| data | `dict[str, Any]` | `data` (map) | Present |
| **Extra Fields** | N/A | `api_key_source`, `cwd`, `session_id`, `tools`, `mcp_servers`, `model`, `permission_mode` | Elixir extracts init data |

#### ResultMessage

| Field | Python | Elixir | Notes |
|-------|--------|--------|-------|
| subtype | `str` | `subtype` (atom) | `:success`, `:error_max_turns`, `:error_during_execution` |
| duration_ms | `int` | `data.duration_ms` | Present |
| duration_api_ms | `int` | `data.duration_api_ms` | Present |
| is_error | `bool` | `data.is_error` | Present |
| num_turns | `int` | `data.num_turns` | Present |
| session_id | `str` | `data.session_id` | Present |
| total_cost_usd | `float \| None` | `data.total_cost_usd` | Present |
| usage | `dict[str, Any] \| None` | `data.usage` | Present |
| result | `str \| None` | `data.result` | Present |
| structured_output | `Any` | `data.structured_output` | Present |

#### StreamEvent

| Field | Python | Elixir | Notes |
|-------|--------|--------|-------|
| uuid | `str` | `data.uuid` | Present |
| session_id | `str` | `data.session_id` | Present |
| event | `dict[str, Any]` | `data.event` | Present |
| parent_tool_use_id | `str \| None` | `data.parent_tool_use_id` | Present |

---

## 2. Content Block Types Comparison

### Python SDK Content Blocks

```python
# types.py - Typed dataclasses for content blocks

@dataclass
class TextBlock:
    text: str

@dataclass
class ThinkingBlock:
    thinking: str
    signature: str

@dataclass
class ToolUseBlock:
    id: str
    name: str
    input: dict[str, Any]

@dataclass
class ToolResultBlock:
    tool_use_id: str
    content: str | list[dict[str, Any]] | None = None
    is_error: bool | None = None

ContentBlock = TextBlock | ThinkingBlock | ToolUseBlock | ToolResultBlock
```

### Elixir Port Content Blocks

```elixir
# message.ex - Plain maps with :type atom discriminator

defp parse_content_block(%{"type" => "text", "text" => text}),
  do: %{type: :text, text: text}

defp parse_content_block(%{"type" => "thinking"} = block) do
  %{type: :thinking, thinking: block["thinking"], signature: block["signature"]}
end

defp parse_content_block(%{"type" => "tool_use"} = block) do
  %{type: :tool_use, id: block["id"], name: block["name"], input: block["input"] || %{}}
end

defp parse_content_block(%{"type" => "tool_result"} = block) do
  %{type: :tool_result, tool_use_id: block["tool_use_id"],
   content: block["content"], is_error: block["is_error"]}
end
```

### Content Block Field Comparison

| Block Type | Python Fields | Elixir Fields | Status |
|------------|---------------|---------------|--------|
| TextBlock | `text: str` | `text: String.t()` | **Complete** |
| ThinkingBlock | `thinking: str`, `signature: str` | `thinking: String.t()`, `signature: String.t()` | **Complete** |
| ToolUseBlock | `id: str`, `name: str`, `input: dict` | `id: String.t()`, `name: String.t()`, `input: map()` | **Complete** |
| ToolResultBlock | `tool_use_id: str`, `content: str \| list \| None`, `is_error: bool \| None` | `tool_use_id: String.t()`, `content: any()`, `is_error: boolean() \| nil` | **Complete** |

---

## 3. Message Parsing Logic Comparison

### Python Message Parser (`message_parser.py`)

```python
def parse_message(data: dict[str, Any]) -> Message:
    message_type = data.get("type")

    match message_type:
        case "user":
            # Parse content blocks, extract uuid, parent_tool_use_id
            return UserMessage(...)
        case "assistant":
            # Parse content blocks, extract model, error
            return AssistantMessage(...)
        case "system":
            return SystemMessage(subtype=data["subtype"], data=data)
        case "result":
            return ResultMessage(...)
        case "stream_event":
            return StreamEvent(...)
        case _:
            raise MessageParseError(...)
```

### Elixir Message Parser (`message.ex`)

```elixir
defp parse_message(raw) do
  type = safe_type(raw["type"])
  message = %__MODULE__{type: type, raw: raw}
  parse_by_type(message, type, raw)
end

defp parse_by_type(message, :assistant, raw), do: %{message | data: build_assistant_data(raw)}
defp parse_by_type(message, :user, raw), do: %{message | data: build_user_data(raw)}
defp parse_by_type(message, :result, raw), do: handle_result(message, raw)
defp parse_by_type(message, :system, raw), do: handle_system(message, raw)
defp parse_by_type(message, :stream_event, raw), do: handle_stream_event(message, raw)
defp parse_by_type(message, _unknown, raw), do: %{message | data: raw}
```

### Parsing Feature Comparison

| Feature | Python | Elixir | Notes |
|---------|--------|--------|-------|
| Type validation | `MessageParseError` on unknown | Falls back to `data: raw` | Elixir more lenient |
| Field validation | `KeyError` raised on missing | Uses `Map.get` with defaults | Elixir more lenient |
| Content block parsing | Explicit match per type | Similar pattern matching | Equivalent |
| Error propagation | Raises `MessageParseError` | Returns `{:error, reason}` | Elixir idiomatic |
| JSON fallback | No fallback | `parse_json_manual/1` fallback | Elixir has fallback parser |

---

## 4. Assistant Error Types Comparison

### Python SDK

```python
# types.py
AssistantMessageError = Literal[
    "authentication_failed",
    "billing_error",
    "rate_limit",
    "invalid_request",
    "server_error",
    "unknown",
]
```

### Elixir Port

```elixir
# assistant_error.ex
@type t ::
        :authentication_failed
        | :billing_error
        | :rate_limit
        | :invalid_request
        | :server_error
        | :unknown

@errors [
  :authentication_failed,
  :billing_error,
  :rate_limit,
  :invalid_request,
  :server_error,
  :unknown
]
```

| Error Code | Python | Elixir | Status |
|------------|--------|--------|--------|
| authentication_failed | Yes | Yes | **Complete** |
| billing_error | Yes | Yes | **Complete** |
| rate_limit | Yes | Yes | **Complete** |
| invalid_request | Yes | Yes | **Complete** |
| server_error | Yes | Yes | **Complete** |
| unknown | Yes | Yes | **Complete** |

---

## 5. Streaming Event Types Comparison

### Python StreamEvent

```python
@dataclass
class StreamEvent:
    uuid: str
    session_id: str
    event: dict[str, Any]  # Raw Anthropic API stream event
    parent_tool_use_id: str | None = None
```

### Elixir StreamEvent Handling

The Elixir port has a comprehensive streaming system split across multiple modules:

#### `message.ex` - Basic StreamEvent Parsing

```elixir
defp parse_by_type(message, :stream_event, raw) do
  data = %{
    uuid: raw["uuid"],
    session_id: raw["session_id"],
    event: raw["event"],
    parent_tool_use_id: raw["parent_tool_use_id"]
  }
  %{message | data: data}
end
```

#### `streaming/event_parser.ex` - Detailed Event Parsing

Elixir has **enhanced** streaming event parsing beyond Python:

```elixir
# Event types parsed by EventParser
- message_start       # Message initialization
- content_block_start # Block begins (text/tool_use/thinking)
- content_block_delta # Incremental updates
  - text_delta        # Character streaming
  - input_json_delta  # Tool input JSON
  - thinking_delta    # Thinking content
- content_block_stop  # Block complete
- message_delta       # Message metadata
- message_stop        # Message complete
- error               # Error events
```

### Streaming Comparison

| Feature | Python | Elixir | Notes |
|---------|--------|--------|-------|
| Basic StreamEvent struct | Yes | Yes (as Message with `:stream_event` type) | Equivalent |
| Detailed event parsing | Event dict passed through | Full EventParser module | **Elixir enhanced** |
| Text accumulation | Not in SDK | `EventParser.parse_event/2` accumulates | **Elixir enhanced** |
| Buffer parsing | Not in SDK | `EventParser.parse_buffer/2` | **Elixir enhanced** |
| Event type normalization | Not in SDK | `EventAdapter.to_events/1` | **Elixir enhanced** |

---

## 6. Content Extraction Utilities

### Python SDK

Python SDK does not include a dedicated content extraction utility. Consumers access content directly:

```python
# Direct access pattern
message.content[0].text  # TextBlock
message.content[0].thinking  # ThinkingBlock
```

### Elixir Port (`content_extractor.ex`)

Elixir provides a dedicated module for content extraction:

```elixir
# Extract text from any message type
ContentExtractor.extract_text(message)

# Check if message has text
ContentExtractor.has_text?(message)

# Extract all text from stream
ContentExtractor.extract_all_text(messages)

# Summarize with truncation
ContentExtractor.summarize(message, max_length)
```

| Utility | Python | Elixir | Notes |
|---------|--------|--------|-------|
| extract_text | N/A | Yes | **Elixir enhancement** |
| has_text? | N/A | Yes | **Elixir enhancement** |
| extract_all_text | N/A | Yes | **Elixir enhancement** |
| summarize | N/A | Yes | **Elixir enhancement** |
| Tool use representation | N/A | `[Tool: name]` | **Elixir enhancement** |

---

## 7. Architectural Differences

### Type Safety

| Aspect | Python | Elixir |
|--------|--------|--------|
| Message types | Union of dataclasses | Single struct with type atom |
| Content blocks | Union of dataclasses | Plain maps with type key |
| Field access | Static type checking | Dynamic map access |
| Pattern matching | match statement | function head matching |
| Invalid data | MessageParseError | Graceful fallback |

### Developer Ergonomics

| Operation | Python | Elixir |
|-----------|--------|--------|
| Check message type | `isinstance(msg, AssistantMessage)` | `msg.type == :assistant` |
| Access content | `msg.content[0].text` | `msg.data.message["content"]` |
| Access model | `msg.model` | `msg.data.message["model"]` or accessor |
| Pattern match | Limited | `%Message{type: :assistant, data: data}` |

---

## 8. Gap Summary and Recommendations

### Gaps Identified

| Gap | Severity | Impact | Recommendation |
|-----|----------|--------|----------------|
| No typed content block structs | Low | API ergonomics | Consider adding optional TextBlock, etc. structs |
| No typed message variant structs | Low | API ergonomics | Consider adding UserMessage, etc. type aliases |
| Map access vs field access | Low | Developer UX | Add accessor functions for common fields |

### Recommendations by Priority

#### Priority 1: API Ergonomics (Optional)

Add convenience functions for common access patterns:

```elixir
# Proposed additions to Message module
def model(%Message{type: :assistant, data: %{message: %{"model" => model}}}), do: model
def content(%Message{data: %{message: %{"content" => content}}}), do: content
def error(%Message{data: %{error: error}}), do: error
```

#### Priority 2: Type Definitions (Optional)

Consider adding typed structs for content blocks if stronger typing is desired:

```elixir
# Proposed content block structs
defmodule ClaudeAgentSDK.TextBlock do
  defstruct [:text]
  @type t :: %__MODULE__{text: String.t()}
end

defmodule ClaudeAgentSDK.ToolUseBlock do
  defstruct [:id, :name, :input]
  @type t :: %__MODULE__{id: String.t(), name: String.t(), input: map()}
end
```

#### Priority 3: Documentation

Add comprehensive documentation showing idiomatic Elixir patterns for message handling:

```elixir
# Pattern matching example
def handle_message(%Message{type: :assistant, data: %{message: msg}}) do
  case msg["content"] do
    [%{"type" => "text", "text" => text} | _] -> {:text, text}
    [%{"type" => "tool_use"} = tool | _] -> {:tool, tool}
  end
end
```

---

## 9. Conclusion

The Elixir port achieves **complete functional parity** with the Python SDK for message and content types. All message types (user, assistant, system, result, stream_event) and content block types (text, thinking, tool_use, tool_result) are fully supported with all required fields.

The architectural difference (unified struct vs typed dataclasses) is an idiomatic Elixir design choice that enables powerful pattern matching while trading some static type safety. The Elixir port actually **exceeds** Python functionality in streaming event parsing and content extraction utilities.

**Overall Assessment:** No critical gaps. The implementation is production-ready and follows Elixir best practices.
