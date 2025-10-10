defmodule ClaudeCodeSDK.Streaming do
  @moduledoc """
  Bidirectional streaming for interactive Claude conversations.

  Enables real-time, character-by-character streaming with persistent sessions
  using Claude CLI's `--include-partial-messages` flag.

  ## Features

  - **Real-time streaming**: Character-by-character text updates (typewriter effect)
  - **Persistent sessions**: Send multiple messages without restarting subprocess
  - **Partial messages**: Receive `text_delta` events as Claude types
  - **Multi-turn conversations**: Context preserved across messages
  - **Phoenix LiveView ready**: Perfect for chat UIs and interactive apps

  ## Architecture

  ```
  Your App
      ↓
  ClaudeCodeSDK.Streaming (Public API)
      ↓
  Session GenServer (Manages subprocess)
      ↓
  claude --input-format stream-json \\
         --output-format stream-json \\
         --include-partial-messages
  ```

  ## Quick Start

  ```elixir
  # Start a streaming session
  {:ok, session} = ClaudeCodeSDK.Streaming.start_session()

  # Send message and get streaming response
  ClaudeCodeSDK.Streaming.send_message(session, "Hello")
  |> Stream.each(fn
    %{type: :text_delta, text: text} ->
      IO.write(text)  # Print each character immediately

    %{type: :message_stop} ->
      IO.puts("")  # Message complete
  end)
  |> Stream.run()

  # Continue conversation (context preserved)
  ClaudeCodeSDK.Streaming.send_message(session, "Tell me more")
  |> Enum.to_list()

  # Close when done
  ClaudeCodeSDK.Streaming.close_session(session)
  ```

  ## Event Types

  The stream yields event maps with these types:

  ### Text Streaming (Primary)
  - `%{type: :text_delta, text: "...", accumulated: "..."}` - Character chunk + full text so far
  - `%{type: :message_stop, final_text: "..."}` - Message complete

  ### Message Lifecycle
  - `%{type: :message_start, model: "...", role: "...", usage: %{}}` - Message begins
  - `%{type: :content_block_start}` - Content block starts
  - `%{type: :content_block_stop, final_text: "..."}` - Content block complete

  ### Tools & Thinking
  - `%{type: :tool_use_start, name: "...", id: "..."}` - Tool call begins
  - `%{type: :tool_input_delta, json: "..."}` - Tool input JSON chunk
  - `%{type: :thinking_start}` - Thinking block starts (Sonnet 4.5+)
  - `%{type: :thinking_delta, thinking: "..."}` - Thinking content chunk

  ### Metadata & Errors
  - `%{type: :message_delta, stop_reason: "...", stop_sequence: "..."}` - Final metadata
  - `%{type: :error, error: ...}` - Error occurred

  ## Examples

  ### Typewriter Effect

  ```elixir
  {:ok, session} = ClaudeCodeSDK.Streaming.start_session()

  ClaudeCodeSDK.Streaming.send_message(session, "Write a poem")
  |> Stream.each(fn
    %{type: :text_delta, text: text} ->
      IO.write(text)
      Process.sleep(10)  # Slow down for effect

    %{type: :message_stop} ->
      IO.puts("\\n[Complete]")
  end)
  |> Stream.run()
  ```

  ### Phoenix LiveView Integration

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
      # Add user message
      messages = socket.assigns.messages ++ [%{role: :user, content: message}]

      # Start streaming in background
      pid = self()
      spawn_link(fn ->
        ClaudeCodeSDK.Streaming.send_message(socket.assigns.claude_session, message)
        |> Stream.each(fn event -> send(pid, {:claude_event, event}) end)
        |> Stream.run()
      end)

      {:noreply, assign(socket, messages: messages, current_response: "")}
    end

    def handle_info({:claude_event, %{type: :text_delta, text: text}}, socket) do
      # Update response in real-time
      {:noreply, assign(socket, current_response: socket.assigns.current_response <> text)}
    end

    def handle_info({:claude_event, %{type: :message_stop}}, socket) do
      # Finalize message
      messages = socket.assigns.messages ++ [
        %{role: :assistant, content: socket.assigns.current_response}
      ]
      {:noreply, assign(socket, messages: messages, current_response: "")}
    end
  end
  ```

  ### Multi-Turn Conversation

  ```elixir
  {:ok, session} = ClaudeCodeSDK.Streaming.start_session()

  # First message
  response1 = ClaudeCodeSDK.Streaming.send_message(session, "My name is Alice")
  |> collect_text()

  IO.puts("Claude: \#{response1}")

  # Second message (context preserved)
  response2 = ClaudeCodeSDK.Streaming.send_message(session, "What's my name?")
  |> collect_text()

  IO.puts("Claude: \#{response2}")  # Should mention "Alice"

  ClaudeCodeSDK.Streaming.close_session(session)

  defp collect_text(stream) do
    stream
    |> Stream.filter(&(&1.type == :text_delta))
    |> Stream.map(& &1.text)
    |> Enum.join("")
  end
  ```

  ### Custom Options

  ```elixir
  # Start session with custom configuration
  {:ok, session} = ClaudeCodeSDK.Streaming.start_session(%ClaudeCodeSDK.Options{
    model: "opus",              # Use most capable model
    max_turns: 10,              # Allow up to 10 turns
    allowed_tools: ["Read"],    # Only allow Read tool
    verbose: true               # Enable verbose logging
  })
  ```

  ## Configuration

  See `ClaudeCodeSDK.Options` for all available configuration options.

  ## Performance

  - Memory-efficient: Uses lazy streams, constant memory regardless of response size
  - Low latency: Events delivered as soon as received from Claude
  - Concurrent: Multiple sessions can run simultaneously
  - Resource cleanup: Subprocess terminated on session close

  ## Error Handling

  ```elixir
  ClaudeCodeSDK.Streaming.send_message(session, "Hello")
  |> Stream.each(fn
    %{type: :text_delta, text: text} ->
      IO.write(text)

    %{type: :error, error: reason} ->
      IO.puts("\\nError: \#{inspect(reason)}")

    %{type: :message_stop} ->
      IO.puts("\\nComplete")
  end)
  |> Stream.run()
  ```

  ## Limitations

  - Requires Claude CLI v2.0+ with streaming support
  - Subprocess spawning has ~100ms overhead
  - No message history persistence (use `ClaudeCodeSDK.SessionStore` for that)
  - Single active message per session (sequential only)

  ## See Also

  - `ClaudeCodeSDK.Streaming.Session` - GenServer managing the subprocess
  - `ClaudeCodeSDK.Streaming.EventParser` - Event parsing logic
  - `ClaudeCodeSDK.Options` - Configuration options
  - `ClaudeCodeSDK` - Non-streaming API (simpler but blocks)
  """

  alias ClaudeCodeSDK.Streaming.Session
  alias ClaudeCodeSDK.Options

  @doc """
  Starts a new streaming session.

  Spawns a Claude CLI subprocess with streaming flags and begins listening
  for events.

  ## Parameters

  - `options` - Optional `ClaudeCodeSDK.Options` struct for configuration

  ## Returns

  - `{:ok, session_pid}` - Session started successfully
  - `{:error, reason}` - Failed to start (e.g., CLI not found, auth failed)

  ## Examples

      # Default configuration
      {:ok, session} = ClaudeCodeSDK.Streaming.start_session()

      # Custom configuration
      {:ok, session} = ClaudeCodeSDK.Streaming.start_session(%Options{
        model: "opus",
        max_turns: 5,
        verbose: true
      })
  """
  @spec start_session(Options.t() | nil) :: {:ok, pid()} | {:error, term()}
  defdelegate start_session(options \\ nil), to: Session, as: :start_link

  @doc """
  Sends a message to an active streaming session.

  Returns a stream of events that can be consumed in real-time for
  typewriter effects, progress indicators, and incremental UI updates.

  ## Parameters

  - `session` - Session PID from `start_session/1`
  - `message` - Message text to send to Claude

  ## Returns

  Lazy stream of event maps. See module documentation for event types.

  The stream will automatically complete when the message is finished.

  ## Examples

      {:ok, session} = start_session()

      # Simple text collection
      text = send_message(session, "Hello")
      |> Stream.filter(&(&1.type == :text_delta))
      |> Stream.map(& &1.text)
      |> Enum.join("")

      # Typewriter effect
      send_message(session, "Write a story")
      |> Stream.each(fn
        %{type: :text_delta, text: text} -> IO.write(text)
        %{type: :message_stop} -> IO.puts("")
      end)
      |> Stream.run()

      # Error handling
      send_message(session, "Hello")
      |> Stream.each(fn
        %{type: :text_delta, text: text} -> IO.write(text)
        %{type: :error, error: reason} -> IO.puts("Error: \#{inspect(reason)}")
      end)
      |> Stream.run()
  """
  @spec send_message(pid(), String.t()) :: Enumerable.t()
  defdelegate send_message(session, message), to: Session

  @doc """
  Closes a streaming session and terminates the subprocess.

  Cleans up all resources associated with the session.

  ## Parameters

  - `session` - Session PID to close

  ## Returns

  `:ok`

  ## Examples

      {:ok, session} = start_session()
      # ... use session ...
      :ok = close_session(session)
  """
  @spec close_session(pid()) :: :ok
  defdelegate close_session(session), to: Session, as: :close

  @doc """
  Gets the Claude session ID for an active session.

  The session ID is extracted from the first message and can be used
  for debugging or correlation with Claude API logs.

  ## Parameters

  - `session` - Session PID

  ## Returns

  - `{:ok, session_id}` - Session ID available (after first message)
  - `{:error, :no_session_id}` - Session not yet initialized

  ## Examples

      {:ok, session} = start_session()

      # Before first message
      {:error, :no_session_id} = get_session_id(session)

      # After sending a message
      send_message(session, "Hello") |> Enum.to_list()
      {:ok, session_id} = get_session_id(session)
      IO.puts("Session ID: \#{session_id}")
  """
  @spec get_session_id(pid()) :: {:ok, String.t()} | {:error, :no_session_id}
  defdelegate get_session_id(session), to: Session
end
