# Implementation Plan: Bidirectional Streaming
## Priority: SHOULD-HAVE (Medium)
## Estimated Effort: 1 week
## Target Version: 0.2.0

---

## 🎯 Objective

Enable interactive, real-time Claude conversations with:
- Bidirectional streaming (`--input-format stream-json`)
- Partial message chunks (`--include-partial-messages`)
- Real-time user message replay
- Interactive chat UIs and live collaboration

---

## 📋 Problem Statement

**Current**: Request-response only
```elixir
# Must wait for complete response
messages = ClaudeCodeSDK.query("Long task...") |> Enum.to_list()
# No way to see partial results
# No way to send follow-up without waiting
```

**Desired**: Interactive streaming
```elixir
# Start interactive session
{:ok, session} = ClaudeCodeSDK.Streaming.start_session()

# Send message, get immediate response stream
stream = ClaudeCodeSDK.Streaming.send_message(session, "Hello")

# See partial responses as they arrive
stream |> Stream.each(fn partial ->
  IO.write(partial.delta)  # Display each word as typed
end) |> Stream.run()

# Send follow-up immediately
ClaudeCodeSDK.Streaming.send_message(session, "Tell me more")
```

---

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────────┐
│ User Application                                     │
└────────────┬─────────────────────────────────────────┘
             │ send_message/2
┌────────────▼─────────────────────────────────────────┐
│ StreamingSession (GenServer)                         │
│ • Manages subprocess with stdin/stdout pipes         │
│ • Converts Elixir messages → JSON stdin              │
│ • Parses JSON stdout → Elixir messages               │
└────────────┬─────────────────────────────────────────┘
             │ bidirectional pipes
┌────────────▼─────────────────────────────────────────┐
│ claude --input-format stream-json \                  │
│        --output-format stream-json \                 │
│        --include-partial-messages                    │
└──────────────────────────────────────────────────────┘
```

---

## 📁 Implementation

### StreamingSession Module

```elixir
defmodule ClaudeCodeSDK.Streaming do
  @moduledoc """
  Bidirectional streaming for interactive Claude conversations.

  ## Features
  - Real-time message streaming
  - Partial message updates
  - Multi-turn conversations without blocking
  - Support for Phoenix LiveView integration

  ## Usage

      # Start session
      {:ok, session} = Streaming.start_session(options)

      # Send message and stream response
      response_stream = Streaming.send_message(session, "Hello")

      # Display partial responses
      response_stream
      |> Stream.each(fn chunk ->
        case chunk.type do
          :partial -> IO.write(chunk.delta)
          :complete -> IO.puts("\\n[Done]")
        end
      end)
      |> Stream.run()

      # Continue conversation
      Streaming.send_message(session, "Tell me more")

      # Close session
      Streaming.close_session(session)
  """

  defmodule Session do
    use GenServer

    defstruct [
      :subprocess,        # erlexec process
      :stdin_pipe,        # stdin port
      :stdout_pipe,       # stdout port
      :message_buffer,    # Accumulates partial messages
      :subscribers        # PIDs listening for messages
    ]

    ## Public API

    @spec start_session(Options.t()) :: {:ok, pid()} | {:error, term()}
    def start_session(options \\ %Options{}) do
      GenServer.start(__MODULE__, options)
    end

    @spec send_message(pid(), String.t()) :: Stream.t()
    def send_message(session, message) do
      # Subscribe to response stream
      ref = make_ref()
      GenServer.call(session, {:send_message, message, self(), ref})

      # Return stream that will receive messages
      Stream.resource(
        fn -> {session, ref} end,
        fn {session, ref} = state ->
          receive do
            {:message_chunk, ^ref, chunk} ->
              {[chunk], state}

            {:message_complete, ^ref} ->
              {:halt, state}
          after
            30_000 -> {:halt, state}
          end
        end,
        fn {session, _ref} ->
          GenServer.cast(session, :unsubscribe)
        end
      )
    end

    @spec close_session(pid()) :: :ok
    def close_session(session) do
      GenServer.stop(session)
    end

    ## GenServer Callbacks

    @impl true
    def init(options) do
      # Build command with streaming flags
      args = [
        "--print",
        "--input-format", "stream-json",
        "--output-format", "stream-json",
        "--include-partial-messages",
        "--replay-user-messages"
      ] ++ Options.to_args(options)

      # Start subprocess with stdin/stdout pipes
      cmd = build_claude_command(args)

      case :exec.run(cmd, [:stdin, :stdout, :stderr, :monitor]) do
        {:ok, pid, os_pid} ->
          state = %Session{
            subprocess: {pid, os_pid},
            message_buffer: "",
            subscribers: %{}
          }

          # Start reading stdout
          send(self(), :read_stdout)

          {:ok, state}

        {:error, reason} ->
          {:stop, reason}
      end
    end

    @impl true
    def handle_call({:send_message, message, subscriber_pid, ref}, _from, state) do
      # Register subscriber
      subscribers = Map.put(state.subscribers, ref, subscriber_pid)

      # Send message to Claude via stdin
      json_message = Jason.encode!(%{
        type: "user",
        message: %{
          role: "user",
          content: message
        }
      })

      {pid, _os_pid} = state.subprocess
      :exec.send(pid, json_message <> "\n")

      {:reply, :ok, %{state | subscribers: subscribers}}
    end

    @impl true
    def handle_info(:read_stdout, state) do
      {pid, os_pid} = state.subprocess

      receive do
        {:stdout, ^os_pid, data} ->
          # Parse JSON chunks
          {chunks, new_buffer} = parse_streaming_json(state.message_buffer <> data)

          # Broadcast chunks to subscribers
          Enum.each(chunks, fn chunk ->
            broadcast_chunk(state.subscribers, chunk)
          end)

          # Continue reading
          send(self(), :read_stdout)

          {:noreply, %{state | message_buffer: new_buffer}}

        {:DOWN, ^os_pid, :process, ^pid, _reason} ->
          # Process exited
          notify_subscribers_complete(state.subscribers)
          {:stop, :normal, state}
      after
        100 ->
          # Continue reading
          send(self(), :read_stdout)
          {:noreply, state}
      end
    end

    defp parse_streaming_json(buffer) do
      # Parse newline-delimited JSON
      lines = String.split(buffer, "\n")
      {complete_lines, [partial]} = Enum.split(lines, -1)

      chunks = Enum.flat_map(complete_lines, fn line ->
        case Jason.decode(line) do
          {:ok, json} -> [json]
          {:error, _} -> []
        end
      end)

      {chunks, partial}
    end

    defp broadcast_chunk(subscribers, chunk) do
      Enum.each(subscribers, fn {ref, pid} ->
        send(pid, {:message_chunk, ref, chunk})
      end)
    end

    defp notify_subscribers_complete(subscribers) do
      Enum.each(subscribers, fn {ref, pid} ->
        send(pid, {:message_complete, ref})
      end)
    end
  end
end
```

---

## 🧪 Testing

```elixir
defmodule ClaudeCodeSDK.StreamingTest do
  use ExUnit.Case

  @tag :integration
  test "bidirectional streaming works" do
    {:ok, session} = Streaming.start_session()

    # Send message and collect responses
    responses = Streaming.send_message(session, "Count to 5")
    |> Enum.to_list()

    assert length(responses) > 0
    assert Enum.any?(responses, &(&1.type == :partial))

    Streaming.close_session(session)
  end

  @tag :integration
  test "multi-turn conversation" do
    {:ok, session} = Streaming.start_session()

    # Turn 1
    response1 = Streaming.send_message(session, "Hello") |> Enum.to_list()
    assert Enum.any?(response1, &(&1.type == :assistant))

    # Turn 2 (context preserved)
    response2 = Streaming.send_message(session, "What did I just say?") 
    |> Enum.to_list()

    assert Enum.any?(response2, fn msg ->
      content = extract_content(msg)
      content && String.contains?(content, "hello")
    end)

    Streaming.close_session(session)
  end
end
```

---

## 📊 Phoenix LiveView Integration

```elixir
defmodule MyAppWeb.ClaudeChatLive do
  use MyAppWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, session} = ClaudeCodeSDK.Streaming.start_session()

    {:ok, assign(socket,
      claude_session: session,
      messages: [],
      current_response: ""
    )}
  end

  def handle_event("send_message", %{"message" => message}, socket) do
    # Add user message to UI immediately
    messages = socket.assigns.messages ++ [%{role: :user, content: message}]

    # Start streaming response
    spawn_link(fn ->
      ClaudeCodeSDK.Streaming.send_message(socket.assigns.claude_session, message)
      |> Stream.each(fn chunk ->
        send(self(), {:claude_chunk, chunk})
      end)
      |> Stream.run()
    end)

    {:noreply, assign(socket, messages: messages, current_response: "")}
  end

  def handle_info({:claude_chunk, %{type: :partial, delta: delta}}, socket) do
    # Update current response in real-time
    {:noreply, assign(socket, current_response: socket.assigns.current_response <> delta)}
  end

  def handle_info({:claude_chunk, %{type: :complete}}, socket) do
    # Finalize message
    messages = socket.assigns.messages ++ [
      %{role: :assistant, content: socket.assigns.current_response}
    ]

    {:noreply, assign(socket, messages: messages, current_response: "")}
  end
end
```

---

## ⏱️ Timeline

- Days 1-2: Core streaming implementation (12h)
- Day 3: Message parsing and buffering (6h)
- Day 4: Testing and integration (6h)
- Day 5: LiveView example and docs (4h)

**Total**: 28 hours (3.5 days, allocated 1 week for polish)

---

**Status**: Ready for Implementation
**Risk**: High (complex subprocess I/O, parsing challenges)
