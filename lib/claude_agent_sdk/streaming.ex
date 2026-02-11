defmodule ClaudeAgentSDK.Streaming do
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
  ClaudeAgentSDK.Streaming (Public API)
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
  {:ok, session} = ClaudeAgentSDK.Streaming.start_session()

  # Send message and get streaming response
  ClaudeAgentSDK.Streaming.send_message(session, "Hello")
  |> Stream.each(fn
    %{type: :text_delta, text: text} ->
      IO.write(text)  # Print each character immediately

    %{type: :message_stop} ->
      IO.puts("")  # Message complete
  end)
  |> Stream.run()

  # Continue conversation (context preserved)
  ClaudeAgentSDK.Streaming.send_message(session, "Tell me more")
  |> Enum.to_list()

  # Close when done
  ClaudeAgentSDK.Streaming.close_session(session)
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
  {:ok, session} = ClaudeAgentSDK.Streaming.start_session()

  ClaudeAgentSDK.Streaming.send_message(session, "Write a poem")
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
      {:ok, session} = ClaudeAgentSDK.Streaming.start_session()

      {:ok, assign(socket,
        claude_session: session,
        messages: [],
        current_response: ""
      )}
    end

    def handle_event("send_message", %{"message" => message}, socket) do
      # Add user message
      messages = socket.assigns.messages ++ [%{role: :user, content: message}]

      # Start streaming in background using Task.Supervisor (OTP-safe pattern)
      # Add {Task.Supervisor, name: MyApp.TaskSupervisor} to your supervision tree
      pid = self()
      Task.Supervisor.start_child(MyApp.TaskSupervisor, fn ->
        ClaudeAgentSDK.Streaming.send_message(socket.assigns.claude_session, message)
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
  {:ok, session} = ClaudeAgentSDK.Streaming.start_session()

  # First message
  response1 = ClaudeAgentSDK.Streaming.send_message(session, "My name is Alice")
  |> collect_text()

  IO.puts("Claude: \#{response1}")

  # Second message (context preserved)
  response2 = ClaudeAgentSDK.Streaming.send_message(session, "What's my name?")
  |> collect_text()

  IO.puts("Claude: \#{response2}")  # Should mention "Alice"

  ClaudeAgentSDK.Streaming.close_session(session)

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
  {:ok, session} = ClaudeAgentSDK.Streaming.start_session(%ClaudeAgentSDK.Options{
    model: "opus",              # Use most capable model
    max_turns: 10,              # Allow up to 10 turns
    allowed_tools: ["Read"],    # Only allow Read tool
    verbose: true               # Enable verbose logging
  })
  ```

  ## Configuration

  See `ClaudeAgentSDK.Options` for all available configuration options.

  ## Performance

  - Memory-efficient: Uses lazy streams, constant memory regardless of response size
  - Low latency: Events delivered as soon as received from Claude
  - Concurrent: Multiple sessions can run simultaneously
  - Resource cleanup: Subprocess terminated on session close

  ## Error Handling

  ```elixir
  ClaudeAgentSDK.Streaming.send_message(session, "Hello")
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
  - No message history persistence (use `ClaudeAgentSDK.SessionStore` for that)
  - Single active message per session (sequential only)

  ## See Also

  - `ClaudeAgentSDK.Streaming.Session` - GenServer managing the subprocess
  - `ClaudeAgentSDK.Streaming.EventParser` - Event parsing logic
  - `ClaudeAgentSDK.Options` - Configuration options
  - `ClaudeAgentSDK` - Non-streaming API (simpler but blocks)
  """

  alias ClaudeAgentSDK.{Client, Options}
  alias ClaudeAgentSDK.Config.Timeouts
  alias ClaudeAgentSDK.Streaming.{Session, Termination}
  alias ClaudeAgentSDK.Transport.StreamingRouter

  @doc """
  Starts a new streaming session.

  Spawns a Claude CLI subprocess with streaming flags and begins listening
  for events.

  ## Parameters

  - `options` - Optional `ClaudeAgentSDK.Options` struct for configuration

  ## Returns

  - `{:ok, session_pid}` - Session started successfully
  - `{:error, reason}` - Failed to start (e.g., CLI not found, auth failed)

  ## Examples

      # Default configuration
      {:ok, session} = ClaudeAgentSDK.Streaming.start_session()

      # Custom configuration
      {:ok, session} = ClaudeAgentSDK.Streaming.start_session(%Options{
        model: "opus",
        max_turns: 5,
        verbose: true
      })
  """
  @spec start_session(Options.t() | nil) :: {:ok, session()} | {:error, term()}
  def start_session(options \\ nil) do
    opts = options || %Options{}

    # Force partial messages enabled for streaming
    opts = %{opts | include_partial_messages: true}

    case StreamingRouter.select_transport(opts) do
      :streaming_session ->
        # Fast path: Direct CLI streaming
        Session.start_link(opts)

      :control_client ->
        # Full features path: Control client with streaming
        start_control_streaming(opts)
    end
  end

  defp start_control_streaming(opts) do
    case Client.start_link(opts) do
      {:ok, client} ->
        # Wrap client to provide Session-compatible API
        {:ok, {:control_client, client}}

      error ->
        error
    end
  end

  @type session :: pid() | {:control_client, pid()}

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
  @spec send_message(session(), String.t()) :: Enumerable.t()
  def send_message({:control_client, client}, message) do
    # Route through control client with streaming
    stream_via_control_client(client, message)
  end

  def send_message(session, message) when is_pid(session) do
    # Original CLI-only path
    Session.send_message(session, message)
  end

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
  @spec close_session(session()) :: :ok
  def close_session({:control_client, client}), do: Client.stop(client)
  def close_session(session) when is_pid(session), do: Session.close(session)

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
  @spec get_session_id(session()) :: {:ok, String.t()} | {:error, :no_session_id}
  def get_session_id({:control_client, _client}) do
    # Control client doesn't expose session ID yet
    {:error, :not_supported}
  end

  def get_session_id(session) when is_pid(session) do
    Session.get_session_id(session)
  end

  ## Private - Control Client Streaming Adapter

  defp stream_via_control_client(client, message) do
    {client_pid, ref} = Client.subscribe(client)

    with :ok <- Client.await_initialized(client_pid),
         :ok <- Client.send_message(client_pid, message) do
      timeout_ms = control_client_timeout_ms(client_pid)

      # Return stream that adapts client messages to events
      # State: {client_pid, ref, status, accumulated_text, stop_reason, timeout_ms}
      # stop_reason is tracked so we can continue streaming for multi-turn tool conversations
      Stream.resource(
        fn -> {client_pid, ref, :active, "", nil, timeout_ms} end,
        &next_control_client_stream_state/1,
        fn {client, ref, _, _, _, _} ->
          GenServer.cast(client, {:unsubscribe, ref})
        end
      )
    else
      {:error, reason} ->
        return_error_stream(client_pid, ref, reason)
    end
  end

  defp return_error_stream(client, ref, reason) do
    Stream.resource(
      fn -> {client, ref, reason} end,
      fn state ->
        case state do
          {:done, client, ref, _reason} ->
            {:halt, {client, ref, :done}}

          {client, ref, reason} ->
            {[%{type: :error, error: reason}], {:done, client, ref, reason}}
        end
      end,
      fn
        {client, ref, _} ->
          GenServer.cast(client, {:unsubscribe, ref})

        {:done, client, ref, _reason} ->
          GenServer.cast(client, {:unsubscribe, ref})
      end
    )
  end

  defp next_control_client_stream_state(
         {_client, _ref, :complete, _accumulated, _stop_reason, _timeout_ms} =
           state
       ) do
    {:halt, state}
  end

  defp next_control_client_stream_state(
         {client, ref, :active, accumulated, stop_reason, timeout_ms} = state
       ) do
    receive do
      # Stream events from control client
      {:stream_event, ^ref, event} ->
        {new_stop_reason, message_complete?} =
          Termination.step(event, stop_reason)

        new_status =
          if message_complete? do
            :complete
          else
            :active
          end

        new_accumulated = Map.get(event, :accumulated, accumulated)

        {[event], {client, ref, new_status, new_accumulated, new_stop_reason, timeout_ms}}

      # Regular messages (tool results, etc.) - convert to event format
      {:claude_message, message} ->
        event = message_to_event(message, accumulated)
        {[event], state}
    after
      timeout_ms ->
        timeout_event = %{type: :error, error: :timeout}
        {[timeout_event], {client, ref, :complete, accumulated, stop_reason, timeout_ms}}
    end
  end

  defp control_client_timeout_ms(client_pid) when is_pid(client_pid) do
    case GenServer.call(client_pid, :stream_timeout_ms, Timeouts.streaming_session_ms()) do
      timeout_ms when is_integer(timeout_ms) and timeout_ms > 0 -> timeout_ms
      _ -> Timeouts.streaming_session_ms()
    end
  catch
    :exit, _ -> Timeouts.streaming_session_ms()
  end

  # Convert Message struct to streaming event format
  # Extract parent_tool_use_id from message data if present (for subagent messages)
  defp message_to_event(%{type: :tool_result} = msg, accumulated) do
    %{
      type: :tool_complete,
      tool_name: msg.tool_name,
      result: msg.content,
      accumulated: accumulated,
      parent_tool_use_id: get_parent_tool_use_id(msg)
    }
  end

  defp message_to_event(%{type: :error} = msg, accumulated) do
    %{
      type: :error,
      error: msg.content,
      accumulated: accumulated,
      parent_tool_use_id: get_parent_tool_use_id(msg)
    }
  end

  defp message_to_event(msg, accumulated) do
    %{
      type: :message,
      message: msg,
      accumulated: accumulated,
      parent_tool_use_id: get_parent_tool_use_id(msg)
    }
  end

  # Extract parent_tool_use_id from Message struct or map
  defp get_parent_tool_use_id(%ClaudeAgentSDK.Message{data: %{parent_tool_use_id: id}}), do: id
  defp get_parent_tool_use_id(%{data: %{parent_tool_use_id: id}}), do: id
  defp get_parent_tool_use_id(%{parent_tool_use_id: id}), do: id
  defp get_parent_tool_use_id(_), do: nil
end
