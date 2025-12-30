# Error Handling Guide

This guide covers error handling in the Claude Agent SDK for Elixir, including error types, handling patterns, and best practices.

## Table of Contents

1. [Error Types Overview](#error-types-overview)
2. [CLI Errors](#cli-errors)
3. [Process Errors](#process-errors)
4. [JSON Decode Errors](#json-decode-errors)
5. [Message Parse Errors](#message-parse-errors)
6. [Assistant Errors](#assistant-errors)
7. [Handling Errors in Streams](#handling-errors-in-streams)
8. [Result Subtypes](#result-subtypes)
9. [Retry Strategies](#retry-strategies)
10. [Best Practices](#best-practices)

---

## Error Types Overview

The Claude Agent SDK defines several structured error types in the `ClaudeAgentSDK.Errors` module. These errors follow Elixir conventions, implementing the `Exception` behaviour for use with `raise/rescue` while also supporting the `{:error, reason}` tuple pattern.

### Error Hierarchy

| Error Type | Module | Description |
|------------|--------|-------------|
| CLI Connection Error | `CLIConnectionError` | Failed to connect to Claude CLI subprocess |
| CLI Not Found Error | `CLINotFoundError` | Claude CLI executable not found |
| Process Error | `ProcessError` | CLI process exited with error |
| JSON Decode Error | `CLIJSONDecodeError` | Failed to parse JSON from CLI output |
| Message Parse Error | `MessageParseError` | Failed to parse message structure |

### Assistant-Level Errors

In addition to the exception types above, the SDK defines assistant-level error codes in `ClaudeAgentSDK.AssistantError`:

| Error Code | Description |
|------------|-------------|
| `:authentication_failed` | API authentication failed |
| `:billing_error` | Billing or quota issues |
| `:rate_limit` | Rate limit exceeded |
| `:invalid_request` | Malformed request |
| `:server_error` | Anthropic server error |
| `:unknown` | Unrecognized error |

---

## CLI Errors

### CLIConnectionError

Raised when the SDK cannot establish a connection to the Claude CLI subprocess.

```elixir
%ClaudeAgentSDK.Errors.CLIConnectionError{
  message: String.t(),      # Human-readable error message
  cwd: String.t() | nil,    # Working directory where connection was attempted
  reason: term()            # Underlying error reason
}
```

**Common causes:**
- Working directory does not exist
- Insufficient permissions to spawn subprocess
- System resource limits exceeded

**Example handling:**

```elixir
alias ClaudeAgentSDK.Errors.CLIConnectionError

try do
  ClaudeAgentSDK.query("Hello", %Options{cwd: "/nonexistent/path"})
  |> Enum.to_list()
rescue
  %CLIConnectionError{message: msg, cwd: cwd, reason: reason} ->
    Logger.error("CLI connection failed in #{cwd}: #{msg}")
    Logger.debug("Underlying reason: #{inspect(reason)}")
    {:error, :connection_failed}
end
```

### CLINotFoundError

Raised when the Claude CLI executable cannot be located.

```elixir
%ClaudeAgentSDK.Errors.CLINotFoundError{
  message: String.t(),        # Human-readable error message
  cli_path: String.t() | nil  # Path that was searched
}
```

**Common causes:**
- Claude CLI not installed
- Claude CLI not in system PATH
- Incorrect custom CLI path specified

**Example handling:**

```elixir
alias ClaudeAgentSDK.Errors.CLINotFoundError

case ClaudeAgentSDK.CLI.find_executable() do
  {:ok, path} ->
    Logger.info("Found Claude CLI at: #{path}")

  {:error, %CLINotFoundError{message: msg}} ->
    Logger.error("Claude CLI not found: #{msg}")
    Logger.info("Install Claude CLI: npm install -g @anthropic-ai/claude-code")
    {:error, :cli_not_installed}
end
```

**Proactive validation:**

```elixir
# Check CLI availability at application startup
def ensure_cli_available! do
  case ClaudeAgentSDK.CLI.find_executable() do
    {:ok, path} ->
      {:ok, version} = ClaudeAgentSDK.CLI.version()
      Logger.info("Claude CLI v#{version} ready at #{path}")
      :ok

    {:error, error} ->
      raise error
  end
end
```

---

## Process Errors

### ProcessError

Raised when the Claude CLI subprocess exits with a non-zero status code.

```elixir
%ClaudeAgentSDK.Errors.ProcessError{
  message: String.t(),        # Human-readable error message
  exit_code: integer() | nil, # Process exit code
  stderr: String.t() | nil    # Captured stderr output
}
```

**Common causes:**
- CLI internal error
- Timeout exceeded
- Authentication issues at CLI level
- Invalid arguments passed to CLI

**Example handling:**

```elixir
alias ClaudeAgentSDK.Errors.ProcessError

try do
  ClaudeAgentSDK.query("Hello")
  |> Enum.to_list()
rescue
  %ProcessError{exit_code: code, stderr: stderr} ->
    Logger.error("CLI process failed with exit code #{code}")
    if stderr, do: Logger.error("stderr: #{stderr}")

    case code do
      1 -> {:error, :general_error}
      2 -> {:error, :invalid_arguments}
      _ -> {:error, :unknown_process_error}
    end
end
```

**Capturing stderr for debugging:**

```elixir
# Configure stderr callback for detailed debugging
stderr_handler = fn line ->
  Logger.debug("[Claude CLI stderr] #{line}")
end

options = %Options{
  stderr: stderr_handler,
  verbose: true
}

ClaudeAgentSDK.query("Debug this issue", options)
|> Enum.to_list()
```

---

## JSON Decode Errors

### CLIJSONDecodeError

Raised when the SDK fails to parse JSON output from the CLI.

```elixir
%ClaudeAgentSDK.Errors.CLIJSONDecodeError{
  message: String.t(),       # Human-readable error message
  line: String.t(),          # The raw line that failed to parse
  original_error: term()     # The underlying JSON decode error
}
```

**Common causes:**
- Corrupted CLI output
- Partial message received due to process termination
- Non-JSON output mixed with JSON (debug output, warnings)
- JSON frames exceeding `max_buffer_size` (default: 1MB)

When a frame exceeds the buffer limit, the error message is `JSON message exceeded maximum buffer size of <N> bytes` and the stream terminates.

**Example handling:**

```elixir
alias ClaudeAgentSDK.Errors.CLIJSONDecodeError

try do
  ClaudeAgentSDK.query("Hello")
  |> Enum.to_list()
rescue
  %CLIJSONDecodeError{line: line, original_error: error} ->
    Logger.error("Failed to parse CLI output")
    Logger.debug("Raw line: #{inspect(line)}")
    Logger.debug("Parse error: #{inspect(error)}")
    {:error, :json_decode_failed}
end
```

**Defensive stream processing:**

```elixir
# Process stream with error recovery
def safe_query(prompt, options \\ nil) do
  ClaudeAgentSDK.query(prompt, options)
  |> Stream.transform([], fn
    msg, acc when is_struct(msg, ClaudeAgentSDK.Message) ->
      {[msg], [msg | acc]}
    _, acc ->
      # Skip malformed entries
      {[], acc}
  end)
  |> Enum.to_list()
rescue
  %CLIJSONDecodeError{} = error ->
    Logger.warning("JSON decode error, returning partial results: #{error.message}")
    []
end
```

---

## Message Parse Errors

### MessageParseError

Raised when JSON was successfully decoded but the message structure is invalid.

```elixir
%ClaudeAgentSDK.Errors.MessageParseError{
  message: String.t(),    # Human-readable error message
  data: map() | nil       # The parsed JSON data that was invalid
}
```

**Common causes:**
- Unexpected message format from CLI
- CLI version mismatch
- Missing required fields in message

**Example handling:**

```elixir
alias ClaudeAgentSDK.Errors.MessageParseError

try do
  ClaudeAgentSDK.query("Hello")
  |> Enum.to_list()
rescue
  %MessageParseError{message: msg, data: data} ->
    Logger.error("Message parse error: #{msg}")
    Logger.debug("Raw data: #{inspect(data)}")

    # Check for version mismatch
    case ClaudeAgentSDK.CLI.version() do
      {:ok, version} ->
        Logger.info("CLI version: #{version}")
        ClaudeAgentSDK.CLI.warn_if_outdated()
      _ ->
        Logger.warning("Could not determine CLI version")
    end

    {:error, :message_parse_failed}
end
```

---

## Assistant Errors

Assistant errors are API-level errors returned within message data, not as exceptions. They indicate problems with the request or the Anthropic service.

### Error Codes

```elixir
# Available error codes
ClaudeAgentSDK.AssistantError.values()
# => [:authentication_failed, :billing_error, :rate_limit,
#     :invalid_request, :server_error, :unknown]
```

### Checking for Assistant Errors

```elixir
alias ClaudeAgentSDK.{Message, AssistantError}

ClaudeAgentSDK.query("Hello")
|> Enum.each(fn msg ->
  case msg do
    %Message{type: :assistant, data: %{error: error}} when not is_nil(error) ->
      handle_assistant_error(AssistantError.cast(error))

    %Message{type: :result, subtype: :error_during_execution, data: data} ->
      Logger.error("Execution error: #{inspect(data)}")

    _ ->
      :ok
  end
end)

defp handle_assistant_error(:rate_limit) do
  Logger.warning("Rate limited - will retry with backoff")
  {:retry, :rate_limit}
end

defp handle_assistant_error(:authentication_failed) do
  Logger.error("Authentication failed - check API key")
  {:error, :auth_failed}
end

defp handle_assistant_error(:billing_error) do
  Logger.error("Billing error - check account status")
  {:error, :billing}
end

defp handle_assistant_error(:server_error) do
  Logger.warning("Server error - retrying")
  {:retry, :server_error}
end

defp handle_assistant_error(:invalid_request) do
  Logger.error("Invalid request - check parameters")
  {:error, :invalid_request}
end

defp handle_assistant_error(:unknown) do
  Logger.warning("Unknown error")
  {:error, :unknown}
end
```

### Rate Limit Handling

```elixir
defmodule MyApp.ClaudeClient do
  @max_retries 3
  @base_delay_ms 1000

  def query_with_rate_limit_handling(prompt, options \\ nil, retry_count \\ 0) do
    messages = ClaudeAgentSDK.query(prompt, options) |> Enum.to_list()

    # Check for rate limit in messages
    rate_limited? = Enum.any?(messages, fn
      %Message{type: :assistant, data: %{error: "rate_limit"}} -> true
      %Message{type: :assistant, data: %{error: :rate_limit}} -> true
      _ -> false
    end)

    if rate_limited? and retry_count < @max_retries do
      delay = @base_delay_ms * :math.pow(2, retry_count) |> round()
      Logger.info("Rate limited, retrying in #{delay}ms (attempt #{retry_count + 1})")
      Process.sleep(delay)
      query_with_rate_limit_handling(prompt, options, retry_count + 1)
    else
      {:ok, messages}
    end
  end
end
```

### Authentication Error Handling

```elixir
alias ClaudeAgentSDK.{AuthChecker, AuthManager}

def ensure_authenticated_query(prompt, options) do
  # Pre-check authentication
  case AuthChecker.diagnose() do
    %{authenticated: false, recommendations: recs} ->
      Logger.error("Not authenticated")
      Enum.each(recs, &Logger.info("Recommendation: #{&1}"))
      {:error, :not_authenticated}

    %{authenticated: true} ->
      do_query(prompt, options)
  end
end

defp do_query(prompt, options) do
  messages = ClaudeAgentSDK.query(prompt, options) |> Enum.to_list()

  # Check for auth errors in response
  auth_error? = Enum.any?(messages, fn
    %Message{type: :assistant, data: %{error: "authentication_failed"}} -> true
    _ -> false
  end)

  if auth_error? do
    Logger.warning("Authentication failed during query, attempting refresh")

    case AuthManager.refresh_token() do
      {:ok, _token} ->
        # Retry once after refresh
        messages = ClaudeAgentSDK.query(prompt, options) |> Enum.to_list()
        {:ok, messages}

      {:error, reason} ->
        Logger.error("Token refresh failed: #{inspect(reason)}")
        {:error, :authentication_failed}
    end
  else
    {:ok, messages}
  end
end
```

---

## Handling Errors in Streams

Since queries return lazy streams, errors may occur during enumeration. Here are patterns for handling errors in streams.

### Basic Stream Error Handling

```elixir
def safe_query(prompt, options \\ nil) do
  try do
    messages =
      ClaudeAgentSDK.query(prompt, options)
      |> Enum.to_list()
    {:ok, messages}
  rescue
    %CLIConnectionError{message: msg} ->
      {:error, {:connection_failed, msg}}

    %ProcessError{exit_code: code, stderr: stderr} ->
      {:error, {:process_failed, code, stderr}}

    %CLIJSONDecodeError{line: line} ->
      {:error, {:json_decode_failed, line}}

    %MessageParseError{message: msg} ->
      {:error, {:message_parse_failed, msg}}
  end
end
```

### Stream Processing with Error Recovery

```elixir
def query_with_partial_results(prompt, options \\ nil) do
  messages = []

  try do
    messages =
      ClaudeAgentSDK.query(prompt, options)
      |> Enum.reduce([], fn msg, acc ->
        case msg do
          %Message{type: :assistant, data: %{error: error}} when not is_nil(error) ->
            Logger.warning("Assistant error in stream: #{inspect(error)}")
            [{:error, error} | acc]

          %Message{} = msg ->
            [msg | acc]
        end
      end)
      |> Enum.reverse()

    {:ok, messages}
  rescue
    error ->
      Logger.error("Stream error: #{inspect(error)}")
      {:partial, Enum.reverse(messages), error}
  end
end
```

### Streaming Session Error Handling

```elixir
alias ClaudeAgentSDK.Streaming

def safe_streaming_session(handler_fn) do
  case Streaming.start_session() do
    {:ok, session} ->
      try do
        handler_fn.(session)
      after
        Streaming.close_session(session)
      end

    {:error, reason} ->
      Logger.error("Failed to start streaming session: #{inspect(reason)}")
      {:error, :session_start_failed}
  end
end

# Usage
safe_streaming_session(fn session ->
  Streaming.send_message(session, "Hello")
  |> Stream.each(fn
    %{type: :error, error: error} ->
      Logger.error("Stream error: #{inspect(error)}")

    %{type: :text_delta, text: text} ->
      IO.write(text)

    %{type: :message_stop} ->
      IO.puts("")

    _ ->
      :ok
  end)
  |> Stream.run()
end)
```

---

## Result Subtypes

The final `result` message in a query stream includes a subtype indicating how the conversation ended.

### Success

```elixir
%Message{
  type: :result,
  subtype: :success,
  data: %{
    total_cost_usd: 0.025,
    duration_ms: 1500,
    num_turns: 3,
    session_id: "abc123"
  }
}
```

The conversation completed successfully.

### Error Max Turns

```elixir
%Message{
  type: :result,
  subtype: :error_max_turns,
  data: %{
    total_cost_usd: 0.050,
    duration_ms: 3000,
    num_turns: 5,
    session_id: "abc123"
  }
}
```

The conversation was terminated because the `max_turns` limit was reached.

### Error During Execution

```elixir
%Message{
  type: :result,
  subtype: :error_during_execution,
  data: %{
    error: "...",
    total_cost_usd: 0.010,
    duration_ms: 500,
    session_id: "abc123"
  }
}
```

An error occurred during conversation execution.

### Comprehensive Result Handling

```elixir
alias ClaudeAgentSDK.Message

def handle_query_result(prompt, options \\ nil) do
  messages = ClaudeAgentSDK.query(prompt, options) |> Enum.to_list()

  # Find the result message
  result = Enum.find(messages, &(&1.type == :result))

  case result do
    %Message{subtype: :success, data: data} ->
      Logger.info("Query completed successfully")
      Logger.info("Cost: $#{data.total_cost_usd}, Duration: #{data.duration_ms}ms")
      {:ok, messages, data}

    %Message{subtype: :error_max_turns, data: data} ->
      Logger.warning("Max turns (#{data.num_turns}) reached")
      # Consider continuing the conversation
      {:max_turns, messages, data}

    %Message{subtype: :error_during_execution, data: data} ->
      Logger.error("Execution error: #{inspect(data.error)}")
      {:error, messages, data}

    nil ->
      Logger.error("No result message received")
      {:error, messages, nil}
  end
end

# Handle max turns by continuing
def query_until_complete(prompt, options \\ nil, max_continuations \\ 3) do
  do_query_until_complete(prompt, options, max_continuations, [])
end

defp do_query_until_complete(_prompt, _options, 0, acc) do
  Logger.warning("Max continuations reached")
  {:incomplete, Enum.reverse(acc)}
end

defp do_query_until_complete(prompt, options, remaining, acc) do
  messages = ClaudeAgentSDK.query(prompt, options) |> Enum.to_list()
  result = Enum.find(messages, &(&1.type == :result))

  case result do
    %Message{subtype: :success} ->
      {:ok, Enum.reverse(messages ++ acc)}

    %Message{subtype: :error_max_turns, data: %{session_id: session_id}} ->
      Logger.info("Continuing conversation #{session_id}")
      new_options = %{(options || %Options{}) | session_id: session_id}
      do_query_until_complete(nil, new_options, remaining - 1, messages ++ acc)

    %Message{subtype: :error_during_execution} ->
      {:error, Enum.reverse(messages ++ acc)}

    nil ->
      {:error, Enum.reverse(messages ++ acc)}
  end
end
```

---

## Retry Strategies

### Exponential Backoff

```elixir
defmodule MyApp.RetryStrategy do
  require Logger

  @default_max_retries 3
  @default_base_delay_ms 1000
  @default_max_delay_ms 30_000

  @retriable_errors [:rate_limit, :server_error]

  def with_retry(fun, opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, @default_max_retries)
    base_delay = Keyword.get(opts, :base_delay_ms, @default_base_delay_ms)
    max_delay = Keyword.get(opts, :max_delay_ms, @default_max_delay_ms)

    do_retry(fun, 0, max_retries, base_delay, max_delay)
  end

  defp do_retry(fun, attempt, max_retries, base_delay, max_delay) do
    case fun.() do
      {:ok, result} ->
        {:ok, result}

      {:error, error} when error in @retriable_errors and attempt < max_retries ->
        delay = calculate_delay(attempt, base_delay, max_delay)
        Logger.info("Retriable error #{inspect(error)}, retrying in #{delay}ms (#{attempt + 1}/#{max_retries})")
        Process.sleep(delay)
        do_retry(fun, attempt + 1, max_retries, base_delay, max_delay)

      {:error, error} ->
        Logger.error("Non-retriable error or max retries exceeded: #{inspect(error)}")
        {:error, error}
    end
  end

  defp calculate_delay(attempt, base_delay, max_delay) do
    # Exponential backoff with jitter
    delay = base_delay * :math.pow(2, attempt) |> round()
    jitter = :rand.uniform(div(delay, 4))
    min(delay + jitter, max_delay)
  end
end

# Usage
MyApp.RetryStrategy.with_retry(fn ->
  messages = ClaudeAgentSDK.query("Hello") |> Enum.to_list()

  # Check for retriable errors
  error = find_assistant_error(messages)

  if error in [:rate_limit, :server_error] do
    {:error, error}
  else
    {:ok, messages}
  end
end, max_retries: 5, base_delay_ms: 2000)
```

### Circuit Breaker Pattern

```elixir
defmodule MyApp.CircuitBreaker do
  use GenServer
  require Logger

  @failure_threshold 5
  @reset_timeout_ms 60_000

  defstruct [:state, :failure_count, :last_failure_time]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def call(fun) do
    GenServer.call(__MODULE__, {:call, fun})
  end

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{state: :closed, failure_count: 0, last_failure_time: nil}}
  end

  @impl true
  def handle_call({:call, fun}, _from, %{state: :open, last_failure_time: time} = state) do
    if System.monotonic_time(:millisecond) - time > @reset_timeout_ms do
      # Try half-open
      execute_with_state(fun, %{state | state: :half_open})
    else
      {:reply, {:error, :circuit_open}, state}
    end
  end

  def handle_call({:call, fun}, _from, state) do
    execute_with_state(fun, state)
  end

  defp execute_with_state(fun, state) do
    case fun.() do
      {:ok, result} ->
        {:reply, {:ok, result}, %{state | state: :closed, failure_count: 0}}

      {:error, _} = error ->
        new_count = state.failure_count + 1

        if new_count >= @failure_threshold do
          Logger.warning("Circuit breaker opened after #{new_count} failures")
          {:reply, error, %{state |
            state: :open,
            failure_count: new_count,
            last_failure_time: System.monotonic_time(:millisecond)
          }}
        else
          {:reply, error, %{state | failure_count: new_count}}
        end
    end
  end
end

# Usage
MyApp.CircuitBreaker.start_link()

MyApp.CircuitBreaker.call(fn ->
  case safe_query("Hello") do
    {:ok, messages} -> {:ok, messages}
    {:error, _} = error -> error
  end
end)
```

---

## Best Practices

### 1. Always Handle All Error Types

```elixir
def comprehensive_error_handling(prompt, options \\ nil) do
  try do
    messages = ClaudeAgentSDK.query(prompt, options) |> Enum.to_list()

    # Check for assistant-level errors
    case find_assistant_error(messages) do
      nil -> {:ok, messages}
      error -> {:error, {:assistant_error, error}}
    end
  rescue
    %CLIConnectionError{} = e ->
      Logger.error("Connection error: #{e.message}")
      {:error, :connection_failed}

    %CLINotFoundError{} = e ->
      Logger.error("CLI not found: #{e.message}")
      {:error, :cli_not_found}

    %ProcessError{} = e ->
      Logger.error("Process error: #{e.message}")
      {:error, {:process_error, e.exit_code}}

    %CLIJSONDecodeError{} = e ->
      Logger.error("JSON decode error: #{e.message}")
      {:error, :json_decode_error}

    %MessageParseError{} = e ->
      Logger.error("Message parse error: #{e.message}")
      {:error, :message_parse_error}
  end
end
```

### 2. Validate Before Querying

```elixir
def validated_query(prompt, options \\ nil) do
  with :ok <- validate_cli_available(),
       :ok <- validate_authenticated(),
       :ok <- validate_options(options) do
    ClaudeAgentSDK.query(prompt, options) |> Enum.to_list()
  end
end

defp validate_cli_available do
  case ClaudeAgentSDK.CLI.find_executable() do
    {:ok, _} -> :ok
    {:error, _} -> {:error, :cli_not_available}
  end
end

defp validate_authenticated do
  if ClaudeAgentSDK.AuthChecker.authenticated?() do
    :ok
  else
    {:error, :not_authenticated}
  end
end

defp validate_options(nil), do: :ok
defp validate_options(options) do
  case ClaudeAgentSDK.OptionBuilder.validate(options) do
    {:ok, _} -> :ok
    {:warning, _, warnings} ->
      Logger.warning("Option warnings: #{inspect(warnings)}")
      :ok
    {:error, reason} -> {:error, {:invalid_options, reason}}
  end
end
```

### 3. Log Contextual Information

```elixir
def query_with_logging(prompt, options \\ nil) do
  request_id = generate_request_id()

  Logger.metadata(request_id: request_id)
  Logger.info("Starting query", prompt_length: String.length(prompt))

  start_time = System.monotonic_time(:millisecond)

  try do
    messages = ClaudeAgentSDK.query(prompt, options) |> Enum.to_list()
    duration = System.monotonic_time(:millisecond) - start_time

    result = Enum.find(messages, &(&1.type == :result))

    Logger.info("Query completed",
      duration_ms: duration,
      cost_usd: result && result.data[:total_cost_usd],
      num_turns: result && result.data[:num_turns]
    )

    {:ok, messages}
  rescue
    error ->
      duration = System.monotonic_time(:millisecond) - start_time
      Logger.error("Query failed",
        duration_ms: duration,
        error: inspect(error)
      )
      {:error, error}
  end
end
```

### 4. Implement Graceful Degradation

```elixir
def query_with_fallback(prompt, options \\ nil) do
  # Try primary model
  case try_query(prompt, options) do
    {:ok, messages} ->
      {:ok, messages}

    {:error, :rate_limit} ->
      # Fall back to different model
      Logger.info("Rate limited on primary model, trying fallback")
      fallback_options = %{(options || %Options{}) |
        model: "haiku",
        fallback_model: nil
      }
      try_query(prompt, fallback_options)

    {:error, _} = error ->
      error
  end
end
```

### 5. Clean Up Resources

```elixir
def with_session(options \\ nil, fun) do
  {:ok, session} = ClaudeAgentSDK.Streaming.start_session(options)

  try do
    fun.(session)
  after
    ClaudeAgentSDK.Streaming.close_session(session)
  end
end

# Usage
with_session(%Options{max_turns: 5}, fn session ->
  ClaudeAgentSDK.Streaming.send_message(session, "Hello")
  |> Enum.to_list()
end)
```

### 6. Monitor and Alert

```elixir
defmodule MyApp.ClaudeMonitor do
  use GenServer
  require Logger

  @error_threshold 10
  @window_ms 60_000

  def record_error(error_type) do
    GenServer.cast(__MODULE__, {:error, error_type})
  end

  def record_success do
    GenServer.cast(__MODULE__, :success)
  end

  # ... GenServer implementation that tracks errors
  # and sends alerts when threshold exceeded
end

def monitored_query(prompt, options \\ nil) do
  case comprehensive_error_handling(prompt, options) do
    {:ok, messages} ->
      MyApp.ClaudeMonitor.record_success()
      {:ok, messages}

    {:error, error} = result ->
      MyApp.ClaudeMonitor.record_error(error)
      result
  end
end
```

### 7. Test Error Scenarios

```elixir
# In your test suite
defmodule MyApp.ClaudeClientTest do
  use ExUnit.Case

  describe "error handling" do
    test "handles CLI not found gracefully" do
      # Mock CLI not found scenario
      assert {:error, :cli_not_found} = MyApp.ClaudeClient.query("test")
    end

    test "handles rate limit with retry" do
      # Mock rate limit response
      assert {:ok, _messages} = MyApp.ClaudeClient.query_with_retry("test")
    end

    test "handles authentication failure" do
      # Mock auth failure
      assert {:error, :auth_failed} = MyApp.ClaudeClient.query("test")
    end
  end
end
```

---

## Summary

Effective error handling in the Claude Agent SDK involves:

1. **Understanding error types**: Know the difference between CLI errors, process errors, JSON errors, and assistant errors
2. **Using appropriate patterns**: Match errors with rescue blocks or pattern match on result tuples
3. **Implementing retries**: Use exponential backoff for transient errors like rate limits
4. **Validating early**: Check CLI availability and authentication before querying
5. **Handling result subtypes**: React appropriately to success, max_turns, and execution errors
6. **Cleaning up resources**: Always close sessions and handles in after blocks
7. **Logging and monitoring**: Track errors for debugging and alerting

By following these patterns, you can build robust applications that gracefully handle the various error conditions that may arise when working with the Claude Agent SDK.
