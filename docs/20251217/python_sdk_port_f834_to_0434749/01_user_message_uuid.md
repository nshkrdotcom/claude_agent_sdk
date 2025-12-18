# Port: `UserMessage.uuid` (File Checkpointing + `rewind_files`)

## Background

The Claude Code control protocol supports **file checkpointing** (`enable_file_checkpointing: true`) and **rewind** via a `rewind_files` control request that targets a specific **user message id** (checkpoint).

In the Python SDK, issue #414 prompted a devX improvement:
- User message frames can include a top-level `"uuid"` field
- The SDK surfaces that value on the typed `UserMessage` object
- The uuid is only present when `--replay-user-messages` is passed to the CLI

This makes it easy to capture checkpoint ids while streaming and later call `rewind_files(uuid)`.

## Python Changes (0ae5c32)

Files touched:

- `src/claude_agent_sdk/types.py:565`
  - `UserMessage` dataclass gains `uuid: str | None = None`
- `src/claude_agent_sdk/_internal/message_parser.py:51,78,83`
  - On `"type": "user"` messages: `uuid = data.get("uuid")` → `UserMessage(uuid=uuid, ...)`
- `tests/test_message_parser.py:34-46`
  - Adds `test_parse_user_message_with_uuid` (unit test, no CLI needed)
- `src/claude_agent_sdk/client.py:264-297`
  - Updates `rewind_files()` docstring to clarify:
    - Requires `enable_file_checkpointing=True`
    - Requires `extra_args={"replay-user-messages": None}` to receive `uuid` in UserMessage objects
    - Example code shows `if isinstance(msg, UserMessage) and msg.uuid:` pattern

**Key insight from Python docstring change:** The uuid field is only populated when `--replay-user-messages` is used. Without it, user messages may not include the uuid.

## Elixir Current State

### What already works

- **UUID parsing:** `ClaudeAgentSDK.Message` extracts `"uuid"` into `%Message{type: :user}.data.uuid`:
  - `lib/claude_agent_sdk/message.ex:276-284` - `parse_by_type(message, :user, raw)` calls `maybe_put_uuid/2`
  - `lib/claude_agent_sdk/message.ex:347-351` - `maybe_put_uuid/2` extracts uuid when present and non-empty

- **`--replay-user-messages` already included:** The streaming client always includes this flag:
  - `lib/claude_agent_sdk/client.ex:1417` - hardcoded in `build_cli_command/1` args list
  - This means Elixir users don't need `extra_args` like Python users do

### What's missing (parity gaps)

1. **Unit test coverage**
   - No ExUnit test asserts that `Message.from_json/1` parses user message `"uuid"` into `data.uuid`

2. **Optional ergonomic helper**
   - No `Message.user_uuid/1` helper function (Python doesn't have one either, but Elixir tends toward helper functions)

3. **Documentation clarity**
   - Existing `examples/file_checkpointing_live.exs` works but searches multiple candidate fields
   - Could be simplified to prefer `message.data.uuid` directly

## Port Design (Elixir)

### 1) Add a unit test for parsing (required)

Add an ExUnit test that covers:

- `Message.from_json/1` parsing a `"type":"user"` payload that contains `"uuid"`
- Assert `%Message{type: :user, data: %{uuid: "msg-..."}}`

This is independent of live CLI access and should run in default CI (no tags needed).

Suggested test location: `test/claude_agent_sdk/message_test.exs` (add to existing or create new)

```elixir
test "parses uuid from user message" do
  json = ~s({"type":"user","uuid":"msg-abc123-def456","message":{"content":[{"type":"text","text":"Hello"}]}})
  assert {:ok, message} = Message.from_json(json)
  assert message.type == :user
  assert message.data.uuid == "msg-abc123-def456"
end

test "handles user message without uuid" do
  json = ~s({"type":"user","message":{"content":[{"type":"text","text":"Hello"}]}})
  assert {:ok, message} = Message.from_json(json)
  assert message.type == :user
  refute Map.has_key?(message.data, :uuid)
end
```

### 2) Optional: Add `user_uuid/1` helper

Add a small helper to `ClaudeAgentSDK.Message`:

```elixir
@doc """
Returns the checkpoint UUID from a user message, or nil.
"""
@spec user_uuid(t()) :: String.t() | nil
def user_uuid(%__MODULE__{type: :user, data: %{uuid: uuid}}) when is_binary(uuid), do: uuid
def user_uuid(%__MODULE__{type: :user, raw: %{"uuid" => uuid}}) when is_binary(uuid), do: uuid
def user_uuid(_), do: nil
```

This is purely ergonomic; `message.data.uuid` works fine without it.

### 3) Update file-checkpointing example (optional cleanup)

The existing `examples/file_checkpointing_live.exs` already works. Minor cleanup could:
- Simplify to prefer `message.data.uuid` directly
- Add a comment noting that uuid is present because `--replay-user-messages` is included by default

## Proposed Elixir Touchpoints

| File | Change |
|------|--------|
| `test/claude_agent_sdk/message_test.exs` | Add unit tests for uuid parsing |
| `lib/claude_agent_sdk/message.ex` | (Optional) Add `user_uuid/1` helper |
| `examples/file_checkpointing_live.exs` | (Optional) Simplify uuid extraction |

## Compatibility Notes

- The `"uuid"` field is optional in the wire protocol and should remain so in Elixir
- Existing code that ignores `uuid` is unaffected
- Elixir already includes `--replay-user-messages` by default, so users don't need extra config (unlike Python)
- If a future transport path doesn't include `--replay-user-messages`, uuid may be absent; code must tolerate `nil`

## Test Plan

| Test type | What to test | Tag |
|-----------|--------------|-----|
| Unit | `Message.from_json/1` parses user uuid into `data.uuid` | (none - runs by default) |
| Unit | `Message.from_json/1` handles missing uuid gracefully | (none - runs by default) |
| Unit (optional) | `Message.user_uuid/1` returns uuid or nil | (none - runs by default) |

## Risks / Open Questions

None significant. The core parsing already works; this is purely about test coverage and optional ergonomics.
