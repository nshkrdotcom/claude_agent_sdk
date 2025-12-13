# File Checkpointing and Rewind Files

**PR**: #395
**Commit**: 53482d8
**Author**: Noah Zweben
**Priority**: High

## Overview

This feature enables tracking file changes during a session and rewinding files to their state at any previous user message. Useful for:
- Undoing unwanted changes
- Branching from a previous state
- Error recovery

## Python Implementation

### Types (`types.py`)

```python
@dataclass
class ClaudeAgentOptions:
    # Enable file checkpointing to track file changes during the session.
    # When enabled, files can be rewound to their state at any user message
    # using `ClaudeSDKClient.rewind_files()`.
    enable_file_checkpointing: bool = False


class SDKControlRewindFilesRequest(TypedDict):
    subtype: Literal["rewind_files"]
    user_message_id: str


class SDKControlRequest(TypedDict):
    type: Literal["control_request"]
    request_id: str
    request: (
        SDKControlInitializeRequest
        | SDKControlSetModelRequest
        | SDKControlSetPermissionModeRequest
        | SDKHookCallbackRequest
        | SDKControlMcpMessageRequest
        | SDKControlRewindFilesRequest  # NEW
    )
```

### Transport (`subprocess_cli.py`)

```python
# Enable file checkpointing if requested
if self._options.enable_file_checkpointing:
    process_env["CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING"] = "true"
```

### Query (`query.py`)

```python
async def rewind_files(self, user_message_id: str) -> None:
    """Rewind tracked files to their state at a specific user message.

    Requires file checkpointing to be enabled via the `enable_file_checkpointing` option.

    Args:
        user_message_id: UUID of the user message to rewind to
    """
    await self._send_control_request(
        {
            "subtype": "rewind_files",
            "user_message_id": user_message_id,
        }
    )
```

### Client (`client.py`)

```python
async def rewind_files(self, user_message_id: str) -> None:
    """Rewind tracked files to their state at a specific user message.

    Requires file checkpointing to be enabled via the `enable_file_checkpointing` option
    when creating the ClaudeSDKClient.

    Args:
        user_message_id: UUID of the user message to rewind to. This should be
            the `uuid` field from a `UserMessage` received during the conversation.

    Example:
        ```python
        options = ClaudeAgentOptions(enable_file_checkpointing=True)
        async with ClaudeSDKClient(options) as client:
            await client.query("Make some changes to my files")
            async for msg in client.receive_response():
                if isinstance(msg, UserMessage):
                    checkpoint_id = msg.uuid  # Save this for later

            # Later, rewind to that point
            await client.rewind_files(checkpoint_id)
        ```
    """
    if not self._query:
        raise CLIConnectionError("Not connected. Call connect() first.")
    await self._query.rewind_files(user_message_id)
```

## Elixir Implementation

### 1. Add Options Field

In `lib/claude_agent_sdk/options.ex`:

```elixir
defstruct [
  # ... existing fields
  :timeout_ms,
  # NEW: File checkpointing (Python v0.1.15+)
  :enable_file_checkpointing,
  # ... existing fields
  :include_partial_messages,
  # ... rest of fields
]

@type t :: %__MODULE__{
        # ... existing fields
        timeout_ms: integer() | nil,
        enable_file_checkpointing: boolean() | nil,
        include_partial_messages: boolean() | nil,
        # ... rest of fields
      }
```

### 2. Set Environment Variable

In `lib/claude_agent_sdk/process.ex`, update `build_env_vars/1`:

```elixir
defp build_env_vars(%Options{} = options) do
  base_env =
    ["CLAUDE_AGENT_OAUTH_TOKEN", "ANTHROPIC_API_KEY", "PATH", "HOME"]
    |> Enum.reduce(%{}, fn var, acc ->
      case System.get_env(var) do
        nil -> acc
        "" -> acc
        value -> Map.put(acc, var, value)
      end
    end)

  # ... existing override logic ...

  merged
  |> maybe_put_user_env(options.user)
  |> Map.put_new("CLAUDE_CODE_ENTRYPOINT", "sdk-elixir")
  |> Map.put_new("CLAUDE_AGENT_SDK_VERSION", version_string())
  |> maybe_put_file_checkpointing_env(options)  # NEW
end

# NEW: Add file checkpointing environment variable
defp maybe_put_file_checkpointing_env(env_map, %Options{enable_file_checkpointing: true}) do
  Map.put(env_map, "CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING", "true")
end

defp maybe_put_file_checkpointing_env(env_map, _options), do: env_map
```

### 3. Add Control Protocol Request

In `lib/claude_agent_sdk/control_protocol/protocol.ex`:

```elixir
@doc """
Encodes a rewind_files control request.

## Parameters

- `user_message_id` - UUID of the user message to rewind to
- `request_id` - Optional request ID (generated if nil)

## Returns

`{request_id, json_string}` tuple
"""
@spec encode_rewind_files_request(String.t(), request_id() | nil) :: {request_id(), String.t()}
def encode_rewind_files_request(user_message_id, request_id \\ nil)
    when is_binary(user_message_id) do
  req_id = request_id || generate_request_id()

  request = %{
    "type" => "control_request",
    "request_id" => req_id,
    "request" => %{
      "subtype" => "rewind_files",
      "user_message_id" => user_message_id
    }
  }

  {req_id, Jason.encode!(request)}
end
```

### 4. Add Client Method

In `lib/claude_agent_sdk/client.ex`:

```elixir
@doc """
Rewinds tracked files to their state at a specific user message.

Requires file checkpointing to be enabled via the `enable_file_checkpointing` option.

## Parameters

- `client` - Client PID
- `user_message_id` - UUID of the user message to rewind to

## Returns

- `:ok` - Successfully rewound
- `{:error, :file_checkpointing_not_enabled}` - Feature not enabled
- `{:error, term}` - Other errors

## Examples

    options = %Options{enable_file_checkpointing: true}
    {:ok, pid} = Client.start_link(options)

    # Save checkpoint IDs from UserMessages during conversation
    # Later:
    Client.rewind_files(pid, saved_user_message_id)
"""
@spec rewind_files(pid(), String.t()) :: :ok | {:error, term()}
def rewind_files(client, user_message_id) when is_pid(client) and is_binary(user_message_id) do
  GenServer.call(client, {:rewind_files, user_message_id}, :infinity)
end
```

Add the handler:

```elixir
def handle_call({:rewind_files, user_message_id}, from, state) do
  # Check if file checkpointing is enabled
  unless state.options.enable_file_checkpointing do
    {:reply, {:error, :file_checkpointing_not_enabled}, state}
  else
    {request_id, json} = Protocol.encode_rewind_files_request(user_message_id)

    case send_payload(state, json) do
      :ok ->
        pending_requests =
          Map.put(state.pending_requests, request_id, {:rewind_files, from})

        {:noreply, %{state | pending_requests: pending_requests}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
end
```

Handle the response in `handle_control_response/2`:

```elixir
{{:rewind_files, from}, "success"} ->
  Logger.info("Files rewound successfully", request_id: request_id)
  GenServer.reply(from, :ok)
  updated_state

{{:rewind_files, from}, "error"} ->
  error = response["error"] || "rewind_files_failed"
  Logger.error("Rewind files failed", request_id: request_id, error: error)
  GenServer.reply(from, {:error, error})
  updated_state
```

### 5. Checkpoint IDs (`user_message_id`)

The Python API calls this parameter `user_message_id` and the Python `client.py` docstring
claims it should be the `uuid` field from a `UserMessage`. However, the current Python SDK
does **not** expose `uuid` on `UserMessage` (it only parses `uuid` on `stream_event` frames).

Before implementing the Elixir port, confirm where the Claude Code CLI actually provides
the checkpoint UUIDs, and only then add extraction in `lib/claude_agent_sdk/message.ex`.

If the CLI does emit a UUID for `type: "user"` frames at the top-level, one safe approach is to
capture it opportunistically (without breaking when it’s absent):

```elixir
defp parse_by_type(message, :user, raw) do
  data =
    %{message: raw["message"], session_id: raw["session_id"]}
    |> maybe_put_uuid(raw)

  %{message | data: data}
end

defp maybe_put_uuid(data, %{"uuid" => uuid}) when is_binary(uuid) and uuid != "" do
  Map.put(data, :uuid, uuid)
end

defp maybe_put_uuid(data, _raw), do: data
```

## Tests to Add

```elixir
# test/claude_agent_sdk/options_test.exs

describe "enable_file_checkpointing option" do
  test "sets environment variable when enabled" do
    options = %Options{enable_file_checkpointing: true}
    env_vars = ClaudeAgentSDK.Process.__env_vars__(options)

    env_map = Map.new(env_vars)
    assert env_map["CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING"] == "true"
  end

  test "does not set environment variable when not enabled" do
    options = %Options{enable_file_checkpointing: false}
    env_vars = ClaudeAgentSDK.Process.__env_vars__(options)

    env_map = Map.new(env_vars)
    refute Map.has_key?(env_map, "CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING")
  end

  test "does not set environment variable when nil" do
    options = %Options{}
    env_vars = ClaudeAgentSDK.Process.__env_vars__(options)

    env_map = Map.new(env_vars)
    refute Map.has_key?(env_map, "CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING")
  end
end

# test/claude_agent_sdk/control_protocol/protocol_test.exs

describe "encode_rewind_files_request/2" do
  test "encodes rewind_files request correctly" do
    user_message_id = "550e8400-e29b-41d4-a716-446655440000"
    {req_id, json} = Protocol.encode_rewind_files_request(user_message_id)

    assert String.starts_with?(req_id, "req_")

    decoded = Jason.decode!(json)
    assert decoded["type"] == "control_request"
    assert decoded["request_id"] == req_id
    assert decoded["request"]["subtype"] == "rewind_files"
    assert decoded["request"]["user_message_id"] == user_message_id
  end
end
```

## Usage Example

```elixir
# Enable file checkpointing
options = %ClaudeAgentSDK.Options{
  enable_file_checkpointing: true,
  max_turns: 10
}

{:ok, client} = ClaudeAgentSDK.Client.start_link(options)

# Run a request and collect messages until a result frame
:ok = ClaudeAgentSDK.Client.send_message(client, "Create a new config file")
{:ok, messages} = ClaudeAgentSDK.Client.receive_response(client)

checkpoint_ids =
  messages
  |> Enum.flat_map(fn
    %ClaudeAgentSDK.Message{type: :user, data: %{uuid: uuid}}
    when is_binary(uuid) and uuid != "" ->
      [uuid]

    _ ->
      []
  end)

# Later, rewind to a previous checkpoint (if available)
case checkpoint_ids do
  [checkpoint_id | _] ->
    :ok = ClaudeAgentSDK.Client.rewind_files(client, checkpoint_id)
    IO.puts("Files rewound to checkpoint: #{checkpoint_id}")

  [] ->
    IO.puts("No checkpoint UUIDs observed; confirm CLI payload and message parsing.")
end

ClaudeAgentSDK.Client.stop(client)
```

## Notes

1. File checkpointing must be enabled at client start time via `enable_file_checkpointing: true`
2. `user_message_id` is an opaque UUID provided by the CLI; confirm where it appears in the message stream before relying on `UserMessage.uuid`
3. This feature requires a Claude Code CLI version that supports `CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING` and `rewind_files` control requests (Python SDK bundles CLI `2.0.69`)

## Audit Notes

- The Python SDK’s `ClaudeSDKClient.rewind_files/1` docstring references `UserMessage.uuid`, but `src/claude_agent_sdk/types.py` defines `UserMessage` without a `uuid` field and `src/claude_agent_sdk/_internal/message_parser.py` does not parse UUIDs for `type: "user"` frames. The Elixir port should confirm actual CLI output before hard-coding a UUID extraction strategy.
