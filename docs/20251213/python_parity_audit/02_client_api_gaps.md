# Python → Elixir Parity Audit: Client API Gaps

---

Gap: `query(prompt, session_id=...)` convenience (session_id injection per request)

Python Location: `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/client.py:180-209`

Python Code:
```py
async def query(
    self, prompt: str | AsyncIterable[dict[str, Any]], session_id: str = "default"
) -> None:
    ...
    if isinstance(prompt, str):
        message = {
            "type": "user",
            "message": {"role": "user", "content": prompt},
            "parent_tool_use_id": None,
            "session_id": session_id,
        }
        await self._transport.write(json.dumps(message) + "\n")
    else:
        async for msg in prompt:
            if "session_id" not in msg:
                msg["session_id"] = session_id
            await self._transport.write(json.dumps(msg) + "\n")
```

Elixir Status: Partial

Elixir Location: `lib/claude_agent_sdk/client.ex:2004-2012`

Priority: Medium

Suggested Implementation:
Provide a higher-level `Client.query/3` (or extend `send_message/2`) that injects `session_id` (default `"default"`) and `parent_tool_use_id: nil` for string prompts, matching the Python message envelope.

Complexity: Simple

---

Gap: `receive_messages()` typed parsing (client yields typed Messages, not raw maps)

Python Location: `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/client.py:170-179`

Python Code:
```py
async def receive_messages(self) -> AsyncIterator[Message]:
    ...
    from ._internal.message_parser import parse_message
    async for data in self._query.receive_messages():
        yield parse_message(data)
```

Elixir Status: Different approach

Elixir Location: `lib/claude_agent_sdk/client.ex:201-205` (streaming API), `lib/claude_agent_sdk/message.ex:105-120` (Message parsing)

Priority: Low

Suggested Implementation:
If you want Python-like parity, expose an API that yields a strongly-typed message union (including stream events) instead of a mix of `%Message{}` plus separate stream-event structures.

Complexity: Moderate

