# Rate Limit Detection Fix

**PR**: #405
**Commit**: 3cbb9e5
**Author**: lif
**Priority**: Medium

## Overview

This fix enables detection of API errors (especially rate limits) by properly parsing the `error` field in `AssistantMessage`. Before this fix, applications couldn't detect rate limits or implement retry logic.

## Problem

The SDK defined `AssistantMessage.error` with types including `"rate_limit"`, but the message parser never extracted this field from the CLI response.

## Python Implementation

### Message Parser (`message_parser.py`)

Before:
```python
return AssistantMessage(
    content=content_blocks,
    model=data["message"]["model"],
    parent_tool_use_id=data.get("parent_tool_use_id"),
)
```

After:
```python
return AssistantMessage(
    content=content_blocks,
    model=data["message"]["model"],
    parent_tool_use_id=data.get("parent_tool_use_id"),
    error=data["message"].get("error"),  # NEW
)
```

### Usage Example (Python)

```python
async for message in client.receive_response():
    if isinstance(message, AssistantMessage):
        if message.error == "rate_limit":
            print("Rate limit hit! Implementing backoff...")
            await asyncio.sleep(60)
            # Retry logic here
        elif message.error:
            print(f"API error: {message.error}")
```

## Elixir Implementation Status

**Good news**: The Elixir SDK already has partial support for this! Looking at `lib/claude_agent_sdk/message.ex`:

```elixir
@type assistant_error :: AssistantError.t()
@type assistant_data :: %{
        required(:message) => map(),
        required(:session_id) => String.t() | nil,
        optional(:error) => assistant_error() | nil
      }
```

And in `lib/claude_agent_sdk/assistant_error.ex`:

```elixir
defmodule ClaudeAgentSDK.AssistantError do
  @type t ::
          :authentication_failed
          | :billing_error
          | :rate_limit
          | :invalid_request
          | :server_error
          | :unknown

  @spec cast(String.t() | atom() | nil) :: t() | nil
  # …see lib/claude_agent_sdk/assistant_error.ex for full implementation…
end
```

### Verify the Parsing

Check if `build_assistant_data/1` in `message.ex` extracts the error:

```elixir
defp build_assistant_data(raw) do
  %{
    message: raw["message"],
    session_id: raw["session_id"]
  }
  |> maybe_put_assistant_error(raw["error"])  # This might be wrong location!
end
```

**Issue**: The Python code extracts `data["message"].get("error")` (nested inside message), but the Elixir code might be extracting `raw["error"]` (at root level).

### Fix Required

Update `build_assistant_data/1` to extract error from the correct location:

```elixir
defp build_assistant_data(raw) do
  # The CLI error field is nested under message.error (Python fix: 3cbb9e5).
  # Keep a root-level fallback for any existing manual parsing behavior.
  error_value = get_in(raw, ["message", "error"]) || raw["error"]

  %{
    message: raw["message"],
    session_id: raw["session_id"]
  }
  |> maybe_put_assistant_error(error_value)
end
```

### Also Update Manual Parsing

In the fallback `parse_json_manual/1`:

```elixir
String.contains?(str, ~s("type":"assistant")) ->
  content = extract_nested_field(str, ["message", "content"], "text")

  %{
    "type" => "assistant",
    "message" => %{
      "role" => "assistant",
      "content" => content,
      "error" => extract_string_field(str, "error")
    },
    "session_id" => extract_string_field(str, "session_id"),
    # Optional: keep root-level "error" if build_assistant_data/1 falls back to raw["error"]
    "error" => extract_string_field(str, "error")
  }
```

## Tests to Add

```elixir
# test/claude_agent_sdk/message_test.exs

describe "assistant message error parsing" do
  test "parses rate_limit error from message" do
    json = ~s({
      "type": "assistant",
      "message": {
        "role": "assistant",
        "content": [{"type": "text", "text": "Please try again later."}],
        "model": "claude-sonnet-4-5-20250929",
        "error": "rate_limit"
      },
      "session_id": "test-session"
    })

    {:ok, message} = Message.from_json(json)

    assert message.type == :assistant
    assert message.data.error == :rate_limit
  end

  test "parses authentication_failed error" do
    json = ~s({
      "type": "assistant",
      "message": {
        "role": "assistant",
        "content": [],
        "model": "claude-sonnet-4-5-20250929",
        "error": "authentication_failed"
      },
      "session_id": "test-session"
    })

    {:ok, message} = Message.from_json(json)

    assert message.data.error == :authentication_failed
  end

  test "parses billing_error error" do
    json = ~s({
      "type": "assistant",
      "message": {
        "role": "assistant",
        "content": [],
        "model": "claude-sonnet-4-5-20250929",
        "error": "billing_error"
      },
      "session_id": "test-session"
    })

    {:ok, message} = Message.from_json(json)

    assert message.data.error == :billing_error
  end

  test "unknown error maps to :unknown" do
    json = ~s({
      "type": "assistant",
      "message": {
        "role": "assistant",
        "content": [],
        "model": "claude-sonnet-4-5-20250929",
        "error": "some_new_error_type"
      },
      "session_id": "test-session"
    })

    {:ok, message} = Message.from_json(json)

    assert message.data.error == :unknown
  end

  test "no error field results in nil error" do
    json = ~s({
      "type": "assistant",
      "message": {
        "role": "assistant",
        "content": [{"type": "text", "text": "Hello!"}],
        "model": "claude-sonnet-4-5-20250929"
      },
      "session_id": "test-session"
    })

    {:ok, message} = Message.from_json(json)

    assert message.data.error == nil
  end
end
```

## Usage Example

```elixir
defmodule MyApp.ClaudeClient do
  require Logger

  def query_with_retry(prompt, options, max_retries \\ 3) do
    do_query(prompt, options, max_retries, 0)
  end

  defp do_query(_prompt, _options, max_retries, attempt) when attempt >= max_retries do
    {:error, :max_retries_exceeded}
  end

  defp do_query(prompt, options, max_retries, attempt) do
    result =
      ClaudeAgentSDK.query(prompt, options)
      |> Enum.to_list()

    # Check for rate limit errors in assistant messages
    rate_limited? =
      Enum.any?(result, fn message ->
        message.type == :assistant and message.data[:error] == :rate_limit
      end)

    if rate_limited? do
      backoff_ms = calculate_backoff(attempt)
      Logger.warning("Rate limited, retrying in #{backoff_ms}ms (attempt #{attempt + 1})")
      Process.sleep(backoff_ms)
      do_query(prompt, options, max_retries, attempt + 1)
    else
      {:ok, result}
    end
  end

  defp calculate_backoff(attempt) do
    # Exponential backoff: 1s, 2s, 4s, 8s...
    base_ms = 1000
    :math.pow(2, attempt) |> round() |> Kernel.*(base_ms) |> min(60_000)
  end
end
```

## Error Types

| Error | Atom | Description |
|-------|------|-------------|
| `rate_limit` | `:rate_limit` | API rate limit exceeded |
| `authentication_failed` | `:authentication_failed` | Invalid or expired credentials |
| `billing_error` | `:billing_error` | Account billing issue |
| `invalid_request` | `:invalid_request` | Invalid request sent to API |
| `server_error` | `:server_error` | Transient server-side error |
| `unknown` / other | `:unknown` | Unrecognized error code |

## Notes

1. The error field is optional - most assistant messages won't have it
2. Error atoms are defined in `ClaudeAgentSDK.AssistantError`
3. This is a bug fix, not a new feature - ensure correct extraction location (`message.error`)
