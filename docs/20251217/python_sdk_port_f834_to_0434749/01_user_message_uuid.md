# Port: `UserMessage.uuid` (File Checkpointing + `rewind_files`)

## Background

The Claude Code control protocol supports **file checkpointing** (`CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING=true`) and **rewind** via a `rewind_files` control request that targets a specific **user message id** (checkpoint).

In the Python SDK, issue #414 prompted a devX improvement:
- user message frames can include a top-level `"uuid"`
- the SDK now surfaces that value on the typed `UserMessage` object

This makes it easy to capture checkpoint ids while streaming and later call `rewind_files(uuid)`.

## Python Changes (0ae5c32)

Files touched:

- `src/claude_agent_sdk/types.py`
  - `UserMessage` dataclass gains `uuid: str | None = None`
- `src/claude_agent_sdk/_internal/message_parser.py`
  - On `"type": "user"` messages: `uuid = data.get("uuid")` → `UserMessage(uuid=uuid, ...)`
- `tests/test_message_parser.py`
  - Adds `test_parse_user_message_with_uuid`
- `src/claude_agent_sdk/client.py`
  - `rewind_files()` docs explain how to obtain and use the uuid (notably via `--replay-user-messages`)

## Elixir Current State

### What already works

- `ClaudeAgentSDK.Message` extracts `"uuid"` into `%Message{type: :user}.data.uuid`:
  - `lib/claude_agent_sdk/message.ex` includes `maybe_put_uuid/2`
- The streaming client command line includes `--replay-user-messages` by default in streaming mode:
  - `lib/claude_agent_sdk/client.ex` (command builder)

### What’s missing (parity gaps)

1. **Regression test coverage**
   - No ExUnit test asserts that user message `"uuid"` is parsed and surfaced.
2. **Documented, stable API surface**
   - Current public docs/examples do not consistently instruct users to use `message.data.uuid` as the checkpoint id.
3. **Ergonomics**
   - Users currently need to “know” where the id lives (`message.data.uuid`) and fall back to digging in `message.raw`.

## Port Design (Elixir)

### 1) Define a stable accessor

Add a small helper to reduce “hunt the id” friction:

- `ClaudeAgentSDK.Message.user_uuid/1 :: Message.t() -> String.t() | nil`
  - returns `message.data.uuid` when present
  - otherwise checks `message.raw["uuid"]` (defensive)

This keeps the core message shape stable while providing a discoverable API.

### 2) Add a unit test for parsing

Add an ExUnit test that covers:

- `Message.from_json/1` parsing a `"type":"user"` payload that contains `"uuid"`
- assert `%Message{type: :user, data: %{uuid: "msg-..."}}`

This is independent of live CLI access and should run in default CI.

Suggested fixture JSON:

```json
{
  "type": "user",
  "uuid": "msg-abc123-def456",
  "message": {"content": [{"type": "text", "text": "Hello"}]}
}
```

### 3) Update file-checkpointing docs & example(s)

Update the public guidance so the recommended path is:

1. Start a client with `%Options{enable_file_checkpointing: true, ...}`
2. While streaming, capture the checkpoint id from `%Message{type: :user}`:
   - `ClaudeAgentSDK.Message.user_uuid(message)` (preferred)
   - or `message.data.uuid` (direct)
3. Call `Client.rewind_files(client, checkpoint_id)`

The existing live example (`examples/file_checkpointing_live.exs`) already searches multiple candidates; it can be simplified to prefer `Message.user_uuid/1` and only fall back to raw inspection as a last resort.

## Proposed Elixir Touchpoints

- Update (docs/tests): `lib/claude_agent_sdk/message.ex` (already parses uuid; add `user_uuid/1` helper)
- New: `test/claude_agent_sdk/message_uuid_test.exs` (or add to an existing message parsing test module)
- Update (docs): `examples/file_checkpointing_live.exs` to prefer the helper and document the expectation that user frames include `"uuid"` when replay-user-messages is enabled

## Compatibility Notes

- The `"uuid"` field is optional and should remain so in Elixir.
- Existing code that ignores `uuid` is unaffected.
- If a user disables `--replay-user-messages` in the future (or uses a transport path that doesn’t include it), `uuid` may not appear; helpers must tolerate `nil`.

## Test Plan

- Unit:
  - `Message.from_json/1` parses user uuid into `data.uuid`
  - helper `Message.user_uuid/1` returns it
- Live/integration (optional):
  - A targeted “file checkpointing” integration test can assert at least one user message contains a uuid when file checkpointing is enabled.
