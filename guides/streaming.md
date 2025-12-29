# Streaming Guide

This guide covers streaming in the Claude Agent SDK for Elixir, from simple queries to advanced real-time streaming with multi-turn conversations.

## Table of Contents

1. [Overview](#overview)
2. [Simple Query Streaming with query/2](#simple-query-streaming-with-query2)
3. [Streaming API](#streaming-api)
4. [Event Types](#event-types)
5. [Real-Time Typewriter Effect](#real-time-typewriter-effect)
6. [Multi-Turn Conversations](#multi-turn-conversations)
7. [Error Handling in Streams](#error-handling-in-streams)
8. [Best Practices](#best-practices)

---

## Overview

The Claude Agent SDK provides two streaming approaches:

1. **Simple Streaming via `query/2`** - Returns a lazy Elixir stream of parsed messages. Best for simple queries where you want aggregated responses.

2. **Bidirectional Streaming API** - Provides persistent sessions with real-time character-by-character updates. Best for chat interfaces and interactive applications.

### Key Differences

| Feature | `query/2` | Streaming API |
|---------|-----------|---------------|
| Real-time text | No (aggregated) | Yes (character-level) |
| Multi-turn | Via `resume/3` | Native session support |
| Event granularity | Message-level | Token-level |
| Resource usage | Lower | Session process |
| Use case | Scripts, batch | Chat UIs, interactive |

---

## Simple Query Streaming with query/2

The `ClaudeAgentSDK.query/2` function returns a lazy stream of `Message` structs. This is the simplest way to interact with Claude.

### Basic Usage

```elixir
alias ClaudeAgentSDK.{Options, ContentExtractor}

# Simple query with default options
ClaudeAgentSDK.query("Write a haiku about Elixir")
|> Enum.each(fn message ->
  case message.type do
    :system ->
      IO.puts("Session started: #{message.data.session_id}")

    :assistant ->
      text = ContentExtractor.extract_text(message)
      IO.puts("Claude: #{text}")

    :result ->
      IO.puts("Cost: $#{message.data.total_cost_usd}")

    _ ->
      :ok
  end
end)
```

### With Options

```elixir
options = %Options{
  model: "haiku",
  max_turns: 5,
  system_prompt: "You are a helpful coding assistant.",
  output_format: :stream_json
}

messages = ClaudeAgentSDK.query("Explain pattern matching", options)
  |> Enum.to_list()

# Extract just the text responses
text = messages
  |> Enum.filter(&(&1.type == :assistant))
  |> Enum.map(&ContentExtractor.extract_text/1)
  |> Enum.join("\n")

IO.puts(text)
```

### Using OptionBuilder Presets

```elixir
alias ClaudeAgentSDK.OptionBuilder

# Quick preset with Haiku model
options = OptionBuilder.with_haiku()

# Development preset (verbose, permissive)
options = OptionBuilder.build_development_options()

# Production preset (restrictive, safe)
options = OptionBuilder.build_production_options()

ClaudeAgentSDK.query("Hello!", options) |> Enum.to_list()
```

### Collecting Results

```elixir
# Collect all messages
messages = ClaudeAgentSDK.query("Hello") |> Enum.to_list()

# Find specific message types
init_message = Enum.find(messages, &(&1.type == :system and &1.subtype == :init))
result = Enum.find(messages, &(&1.type == :result))

# Extract session ID for later resumption
session_id = init_message.data.session_id

# Check for successful completion
success? = match?(%{type: :result, subtype: :success}, result)
```

---

## Streaming API

The Streaming API provides persistent sessions with real-time character-level updates. This is ideal for building chat interfaces.

### Starting a Session

```elixir
alias ClaudeAgentSDK.{Streaming, Options}

options = %Options{
  model: "haiku",
  max_turns: 10,
  allowed_tools: []
}

{:ok, session} = Streaming.start_session(options)
```

### Sending Messages

```elixir
# Send a message and receive stream of events
Streaming.send_message(session, "Hello! What can you do?")
|> Enum.each(fn event ->
  case event do
    %{type: :text_delta, text: text} ->
      IO.write(text)

    %{type: :message_stop} ->
      IO.puts("")  # Newline after response

    _ ->
      :ok
  end
end)
```

### Closing Sessions

Always close sessions when done to release resources:

```elixir
# Close session
Streaming.close_session(session)

# Or use try/after pattern
{:ok, session} = Streaming.start_session(options)

try do
  Streaming.send_message(session, "Hello")
  |> Enum.to_list()
after
  Streaming.close_session(session)
end
```

### Getting Session ID

```elixir
{:ok, session_id} = Streaming.get_session_id(session)
IO.puts("Session ID: #{session_id}")
```

---

## Event Types

The Streaming API emits various event types for fine-grained control.

### Text Streaming Events

```elixir
# Text delta - partial text as it's generated
%{type: :text_delta, text: "Hello", accumulated: "Hello"}

# Message stop - response complete
%{type: :message_stop, final_text: "Hello, how can I help?"}
```

### Message Lifecycle Events

```elixir
# Message start - new response beginning
%{type: :message_start, model: "claude-3-haiku", role: "assistant", usage: %{}}

# Content block lifecycle
%{type: :content_block_start}
%{type: :content_block_stop, final_text: "Complete text"}

# Message delta with metadata
%{type: :message_delta, stop_reason: "end_turn", stop_sequence: nil}
```

### Tool Events

When Claude uses tools, you receive lifecycle events:

```elixir
# Tool use start
%{type: :tool_use_start, name: "Bash", id: "tool_123"}

# Tool input being streamed
%{type: :tool_input_delta, json: "{\"command\": \"ls\"}"}

# Tool execution complete
%{type: :tool_complete, tool_name: "Bash", result: "..."}
```

### Thinking Events (Extended Thinking)

```elixir
# Thinking start
%{type: :thinking_start}

# Thinking content
%{type: :thinking_delta, thinking: "Let me analyze this..."}

# Thinking end
%{type: :thinking_stop}
```

### Error Events

```elixir
# Stream error
%{type: :error, error: :timeout}
%{type: :error, error: :connection_closed}
%{type: :error, error: {:api_error, "Rate limit exceeded"}}
```

### Complete Event Handling Pattern

```elixir
Streaming.send_message(session, prompt)
|> Enum.reduce_while(%{text: "", tools: [], error: nil}, fn event, acc ->
  case event do
    %{type: :text_delta, text: chunk} ->
      IO.write(chunk)
      {:cont, %{acc | text: acc.text <> chunk}}

    %{type: :tool_use_start, name: name, id: id} ->
      IO.puts("\n[Using tool: #{name}]")
      {:cont, %{acc | tools: [{name, id} | acc.tools]}}

    %{type: :tool_complete, tool_name: name} ->
      IO.puts("[Tool #{name} complete]")
      {:cont, acc}

    %{type: :message_stop} ->
      IO.puts("")
      {:halt, acc}

    %{type: :error, error: reason} ->
      {:halt, %{acc | error: reason}}

    _ ->
      {:cont, acc}
  end
end)
```

---

## Real-Time Typewriter Effect

Creating a typewriter effect for chat interfaces:

### Basic Typewriter

```elixir
alias ClaudeAgentSDK.{Streaming, Options}

defmodule Typewriter do
  def chat(prompt) do
    options = %Options{model: "haiku", max_turns: 1, allowed_tools: []}

    {:ok, session} = Streaming.start_session(options)

    try do
      IO.write("Claude: ")

      Streaming.send_message(session, prompt)
      |> Enum.each(fn
        %{type: :text_delta, text: text} ->
          IO.write(text)
          # Optional: add delay for visible effect
          Process.sleep(10)

        %{type: :message_stop} ->
          IO.puts("\n")

        _ ->
          :ok
      end)
    after
      Streaming.close_session(session)
    end
  end
end

Typewriter.chat("Tell me a short story")
```

### With Character Count and Progress

```elixir
defmodule TypewriterWithStats do
  def stream_response(session, prompt) do
    IO.write("Claude: ")

    result = Streaming.send_message(session, prompt)
    |> Enum.reduce(%{chars: 0, words: 0}, fn event, acc ->
      case event do
        %{type: :text_delta, text: text} ->
          IO.write(text)
          words = text |> String.split() |> length()
          %{acc | chars: acc.chars + String.length(text), words: acc.words + words}

        %{type: :message_stop} ->
          IO.puts("")
          acc

        _ ->
          acc
      end
    end)

    IO.puts("Stats: #{result.chars} characters, #{result.words} words")
    result
  end
end
```

### LiveView Integration Pattern

For Phoenix LiveView applications:

```elixir
defmodule MyAppWeb.ChatLive do
  use Phoenix.LiveView

  alias ClaudeAgentSDK.{Streaming, Options}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, messages: [], streaming: false, current_text: "")}
  end

  def handle_event("send_message", %{"message" => text}, socket) do
    # Start streaming in background task
    parent = self()

    Task.start(fn ->
      options = %Options{model: "haiku", max_turns: 1}
      {:ok, session} = Streaming.start_session(options)

      try do
        Streaming.send_message(session, text)
        |> Enum.each(fn event ->
          send(parent, {:stream_event, event})
        end)
      after
        Streaming.close_session(session)
      end
    end)

    {:noreply, assign(socket, streaming: true, current_text: "")}
  end

  def handle_info({:stream_event, event}, socket) do
    case event do
      %{type: :text_delta, text: chunk} ->
        new_text = socket.assigns.current_text <> chunk
        {:noreply, assign(socket, current_text: new_text)}

      %{type: :message_stop} ->
        messages = socket.assigns.messages ++ [socket.assigns.current_text]
        {:noreply, assign(socket, messages: messages, streaming: false, current_text: "")}

      _ ->
        {:noreply, socket}
    end
  end
end
```

---

## Multi-Turn Conversations

The Streaming API maintains context across messages within a session.

### Basic Multi-Turn

```elixir
alias ClaudeAgentSDK.{Streaming, Options}

options = %Options{model: "haiku", max_turns: 5}
{:ok, session} = Streaming.start_session(options)

try do
  # First message
  IO.puts("You: My name is Alice")
  IO.write("Claude: ")
  Streaming.send_message(session, "My name is Alice")
  |> Enum.each(fn
    %{type: :text_delta, text: t} -> IO.write(t)
    %{type: :message_stop} -> IO.puts("\n")
    _ -> :ok
  end)

  # Follow-up - Claude remembers context
  IO.puts("You: What's my name?")
  IO.write("Claude: ")
  Streaming.send_message(session, "What's my name?")
  |> Enum.each(fn
    %{type: :text_delta, text: t} -> IO.write(t)
    %{type: :message_stop} -> IO.puts("\n")
    _ -> :ok
  end)
after
  Streaming.close_session(session)
end
```

### Interactive Chat Loop

```elixir
defmodule InteractiveChat do
  alias ClaudeAgentSDK.{Streaming, Options}

  def start do
    options = %Options{
      model: "haiku",
      max_turns: 50,
      system_prompt: "You are a helpful assistant. Be concise."
    }

    {:ok, session} = Streaming.start_session(options)
    IO.puts("Chat started. Type 'quit' to exit.\n")
    chat_loop(session)
  end

  defp chat_loop(session) do
    IO.write("You: ")
    input = IO.gets("") |> String.trim()

    case input do
      "quit" ->
        Streaming.close_session(session)
        IO.puts("Goodbye!")

      "" ->
        chat_loop(session)

      message ->
        IO.write("Claude: ")

        Streaming.send_message(session, message)
        |> Enum.each(fn
          %{type: :text_delta, text: text} -> IO.write(text)
          %{type: :message_stop} -> IO.puts("\n")
          %{type: :error, error: reason} -> IO.puts("\n[Error: #{inspect(reason)}]")
          _ -> :ok
        end)

        chat_loop(session)
    end
  end
end

InteractiveChat.start()
```

### Resuming Sessions with query/2

For non-streaming session resumption:

```elixir
alias ClaudeAgentSDK.{Options, Session}

# Initial query
messages = ClaudeAgentSDK.query("My name is Bob", options) |> Enum.to_list()
session_id = Session.extract_session_id(messages)

# Later: resume the conversation
resumed = ClaudeAgentSDK.resume(session_id, "What's my name?", options)
  |> Enum.to_list()
```

---

## Error Handling in Streams

### Handling Stream Errors

```elixir
alias ClaudeAgentSDK.{Streaming, Options}

{:ok, session} = Streaming.start_session(%Options{})

result = Streaming.send_message(session, prompt)
|> Enum.reduce_while({:ok, ""}, fn event, {status, text} ->
  case event do
    %{type: :text_delta, text: chunk} ->
      {:cont, {status, text <> chunk}}

    %{type: :message_stop} ->
      {:halt, {:ok, text}}

    %{type: :error, error: reason} ->
      {:halt, {:error, reason}}

    _ ->
      {:cont, {status, text}}
  end
end)

case result do
  {:ok, response} ->
    IO.puts("Response: #{response}")

  {:error, :timeout} ->
    IO.puts("Request timed out")

  {:error, :connection_closed} ->
    IO.puts("Connection was closed")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end
```

### Detecting Assistant Errors

```elixir
# In aggregated message mode
messages = ClaudeAgentSDK.query(prompt, options) |> Enum.to_list()

# Check for assistant errors
assistant_error = Enum.find_value(messages, fn
  %{type: :assistant, data: %{error: err}} when not is_nil(err) -> err
  _ -> nil
end)

case assistant_error do
  nil -> :ok
  :rate_limit -> IO.puts("Rate limited, please retry")
  :authentication_failed -> IO.puts("Authentication issue")
  error -> IO.puts("Error: #{inspect(error)}")
end
```

### Handling Connection Issues

```elixir
defmodule ResilientChat do
  alias ClaudeAgentSDK.{Streaming, Options}

  @max_retries 3

  def send_with_retry(session, message, retries \\ 0) do
    result = collect_response(session, message)

    case result do
      {:ok, text} ->
        {:ok, text}

      {:error, :connection_closed} when retries < @max_retries ->
        IO.puts("[Retrying... attempt #{retries + 1}]")
        Process.sleep(1000 * (retries + 1))  # Exponential backoff
        send_with_retry(session, message, retries + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp collect_response(session, message) do
    Streaming.send_message(session, message)
    |> Enum.reduce_while({:ok, ""}, fn event, {_, text} ->
      case event do
        %{type: :text_delta, text: chunk} ->
          {:cont, {:ok, text <> chunk}}
        %{type: :message_stop} ->
          {:halt, {:ok, text}}
        %{type: :error, error: reason} ->
          {:halt, {:error, reason}}
        _ ->
          {:cont, {:ok, text}}
      end
    end)
  end
end
```

### Timeout Handling

```elixir
alias ClaudeAgentSDK.Options

# Set custom timeout in options
options = %Options{
  model: "haiku",
  timeout_ms: 120_000  # 2 minutes
}

# Or use Task.yield for client-side timeout
task = Task.async(fn ->
  Streaming.send_message(session, prompt) |> Enum.to_list()
end)

case Task.yield(task, 30_000) || Task.shutdown(task) do
  {:ok, events} ->
    process_events(events)

  nil ->
    IO.puts("Request timed out after 30 seconds")
end
```

---

## Best Practices

### 1. Always Close Sessions

```elixir
# Use try/after pattern
{:ok, session} = Streaming.start_session(options)

try do
  Streaming.send_message(session, prompt)
  |> Enum.to_list()
after
  Streaming.close_session(session)
end
```

### 2. Use Appropriate Streaming Mode

```elixir
# For simple queries without real-time needs
messages = ClaudeAgentSDK.query(prompt, options) |> Enum.to_list()

# For chat UIs needing real-time updates
{:ok, session} = Streaming.start_session(options)
Streaming.send_message(session, prompt) |> ...
```

### 3. Handle All Event Types

```elixir
# Be explicit about handling events
Streaming.send_message(session, prompt)
|> Enum.each(fn
  %{type: :text_delta, text: t} -> handle_text(t)
  %{type: :tool_use_start, name: n} -> handle_tool_start(n)
  %{type: :message_stop} -> handle_complete()
  %{type: :error, error: e} -> handle_error(e)
  event -> Logger.debug("Unhandled event: #{inspect(event)}")
end)
```

### 4. Limit Memory Usage with Large Streams

```elixir
# Process events without collecting all in memory
Streaming.send_message(session, prompt)
|> Stream.filter(&match?(%{type: :text_delta}, &1))
|> Stream.map(& &1.text)
|> Enum.reduce("", &(&2 <> &1))
```

### 5. Use Appropriate Options for Your Use Case

```elixir
# For quick responses
options = %Options{
  model: "haiku",
  max_turns: 1,
  allowed_tools: []  # Disable tools for faster response
}

# For complex tasks
options = %Options{
  model: "sonnet",
  max_turns: 10,
  permission_mode: :accept_edits,
  timeout_ms: 300_000  # 5 minutes
}
```

### 6. Monitor Session State

```elixir
# Get session ID for logging/debugging
{:ok, session_id} = Streaming.get_session_id(session)
Logger.info("Starting chat in session #{session_id}")
```

### 7. Consider Using OptionBuilder

```elixir
alias ClaudeAgentSDK.OptionBuilder

# Environment-appropriate defaults
options = OptionBuilder.for_environment()

# Add specific overrides
options = OptionBuilder.merge(:development, %{max_turns: 10})
```

### 8. Handle Partial Message Mode

```elixir
# Enable partial messages for streaming events
options = %Options{
  include_partial_messages: true,
  preferred_transport: :auto
}

# Now you'll receive text_delta events
```

### 9. Use Streaming with Hooks

```elixir
alias ClaudeAgentSDK.Hooks.{Matcher, Output}

callback = fn input, _id, _ctx ->
  IO.puts("[Tool: #{input["tool_name"]}]")
  Output.allow()
end

options = %Options{
  hooks: %{
    pre_tool_use: [Matcher.new("*", [callback])]
  }
}

{:ok, session} = Streaming.start_session(options)
```

### 10. Clean Shutdown Pattern

```elixir
defmodule ChatManager do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    Process.flag(:trap_exit, true)
    {:ok, %{session: nil}}
  end

  def terminate(_reason, %{session: session}) when not is_nil(session) do
    Streaming.close_session(session)
  end
  def terminate(_reason, _state), do: :ok
end
```

---

## Summary

The Claude Agent SDK provides flexible streaming options:

- **`query/2`** for simple, aggregated responses
- **Streaming API** for real-time, interactive applications

Key patterns:

1. Use `Streaming.start_session/1` for persistent sessions
2. Handle events with pattern matching for clean code
3. Always close sessions in `after` blocks
4. Use `Enum.reduce_while/3` for early termination on errors
5. Consider `include_partial_messages: true` for streaming events

For more examples, see the `examples/streaming_tools/` directory in the SDK source.
