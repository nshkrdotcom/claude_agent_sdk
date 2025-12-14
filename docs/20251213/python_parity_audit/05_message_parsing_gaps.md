# Python → Elixir Parity Audit: Message Parsing Gaps

---

Gap: `ResultMessage.usage` field is not extracted/exposed

Python Location: `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/message_parser.py:141-154`

Python Code:
```py
return ResultMessage(
    subtype=data["subtype"],
    duration_ms=data["duration_ms"],
    duration_api_ms=data["duration_api_ms"],
    is_error=data["is_error"],
    num_turns=data["num_turns"],
    session_id=data["session_id"],
    total_cost_usd=data.get("total_cost_usd"),
    usage=data.get("usage"),
    result=data.get("result"),
    structured_output=data.get("structured_output"),
)
```

Elixir Status: Partial

Elixir Location: `lib/claude_agent_sdk/message.ex:300-311`

Priority: Medium

Suggested Implementation:
Include `usage` in `%Message{type: :result, ...}` result `data` maps so callers can consume token usage consistently with Python.

Complexity: Simple

---

Gap: `stream_event` messages are not represented as `ClaudeAgentSDK.Message`

Python Location: `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/message_parser.py:160-171`

Python Code:
```py
case "stream_event":
    return StreamEvent(
        uuid=data["uuid"],
        session_id=data["session_id"],
        event=data["event"],
        parent_tool_use_id=data.get("parent_tool_use_id"),
    )
```

Elixir Status: Different approach

Elixir Location: `lib/claude_agent_sdk/client.ex:1249-1255`, `lib/claude_agent_sdk/streaming/event_parser.ex:290`

Priority: Low

Suggested Implementation:
If strict parity is desired, introduce a `%Message{type: :stream_event, ...}` variant (or a separate struct) mirroring Python’s `StreamEvent` so the stream can be handled uniformly without switching APIs.

Complexity: Moderate

---

Gap: Content-block parsing (text/thinking/tool_use/tool_result) is not exposed as structured types

Python Location: `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/message_parser.py:48-125`

Python Code:
```py
for block in data["message"]["content"]:
    match block["type"]:
        case "text":
            content_blocks.append(TextBlock(text=block["text"]))
        case "thinking":
            content_blocks.append(ThinkingBlock(...))
        case "tool_use":
            content_blocks.append(ToolUseBlock(...))
        case "tool_result":
            content_blocks.append(ToolResultBlock(...))
```

Elixir Status: Not implemented (raw-only)

Elixir Location: `lib/claude_agent_sdk/message.ex:283-291`

Priority: Low

Suggested Implementation:
Optionally add typed structs for content blocks (Text/Thinking/ToolUse/ToolResult) and parse `message.content` into them in `ClaudeAgentSDK.Message`, matching Python’s ergonomic API.

Complexity: Moderate

---

Gap: `parent_tool_use_id` is not extracted on user/assistant messages

Python Location: `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/message_parser.py:50-82`, `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/message_parser.py:119-124`

Python Code:
```py
parent_tool_use_id = data.get("parent_tool_use_id")
...
return UserMessage(..., parent_tool_use_id=parent_tool_use_id)
...
return AssistantMessage(..., parent_tool_use_id=data.get("parent_tool_use_id"), ...)
```

Elixir Status: Partial

Elixir Location: `lib/claude_agent_sdk/message.ex:248-258`, `lib/claude_agent_sdk/message.ex:283-291`

Priority: Low

Suggested Implementation:
Mirror Python’s explicit `parent_tool_use_id` extraction into the message `data` map (even if the raw payload retains it) for easier downstream consumption.

Complexity: Simple

