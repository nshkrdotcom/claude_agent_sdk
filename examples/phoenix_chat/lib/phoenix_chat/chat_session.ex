defmodule PhoenixChat.ChatSession do
  @moduledoc """
  Manages a single chat conversation with Claude Agent SDK.

  This GenServer maintains the state for a chat session, including:
  - Subscriber management (WebSocket connections)
  - Streaming state tracking
  - Claude SDK integration

  Similar to the TypeScript Session class in the reference demo,
  this module handles the bidirectional communication between
  WebSocket clients and the Claude agent.

  ## Usage

      # Start a session for a chat
      {:ok, pid} = ChatSession.start_link(chat_id: "chat-123")

      # Subscribe to receive messages
      :ok = ChatSession.subscribe(pid, self())

      # Send a user message (triggers Claude query)
      :ok = ChatSession.send_message(pid, "Hello, Claude!")

      # Receive streamed responses
      receive do
        {:assistant_message, content} -> IO.puts(content)
        {:tool_use, tool_name, tool_input} -> IO.inspect({tool_name, tool_input})
        {:result, cost, duration} -> IO.puts("Done! Cost: \#{cost}")
      end

  """
  use GenServer

  require Logger

  @type subscriber :: pid()
  @type state :: %{
          chat_id: String.t(),
          subscribers: MapSet.t(subscriber()),
          streaming: boolean(),
          metadata: map()
        }

  # Client API

  @doc """
  Starts a ChatSession GenServer.

  ## Options

    * `:chat_id` - The unique ID of the chat (required)
    * `:name` - Optional name to register the process under

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    chat_id = Keyword.fetch!(opts, :chat_id)
    name = Keyword.get(opts, :name)

    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, %{chat_id: chat_id}, gen_opts)
  end

  @doc """
  Gets the chat ID for this session.
  """
  @spec get_chat_id(GenServer.server()) :: String.t()
  def get_chat_id(server) do
    GenServer.call(server, :get_chat_id)
  end

  @doc """
  Subscribes a process to receive messages from this session.

  Subscribers will receive messages like:
    - `{:user_message, content}`
    - `{:assistant_message, content}`
    - `{:tool_use, tool_name, tool_id, tool_input}`
    - `{:result, success, cost, duration}`
    - `{:error, reason}`

  """
  @spec subscribe(GenServer.server(), subscriber()) :: :ok
  def subscribe(server, subscriber) do
    GenServer.call(server, {:subscribe, subscriber})
  end

  @doc """
  Unsubscribes a process from this session.
  """
  @spec unsubscribe(GenServer.server(), subscriber()) :: :ok
  def unsubscribe(server, subscriber) do
    GenServer.call(server, {:unsubscribe, subscriber})
  end

  @doc """
  Checks if a process is subscribed to this session.
  """
  @spec has_subscriber?(GenServer.server(), subscriber()) :: boolean()
  def has_subscriber?(server, subscriber) do
    GenServer.call(server, {:has_subscriber, subscriber})
  end

  @doc """
  Returns the number of current subscribers.
  """
  @spec subscriber_count(GenServer.server()) :: non_neg_integer()
  def subscriber_count(server) do
    GenServer.call(server, :subscriber_count)
  end

  @doc """
  Broadcasts a message to all subscribers.
  """
  @spec broadcast(GenServer.server(), term()) :: :ok
  def broadcast(server, message) do
    GenServer.cast(server, {:broadcast, message})
  end

  @doc """
  Checks if the session is currently streaming a response.
  """
  @spec is_streaming?(GenServer.server()) :: boolean()
  def is_streaming?(server) do
    GenServer.call(server, :is_streaming)
  end

  @doc """
  Sets the streaming state.
  """
  @spec set_streaming(GenServer.server(), boolean()) :: :ok
  def set_streaming(server, streaming) do
    GenServer.call(server, {:set_streaming, streaming})
  end

  @doc """
  Sets a metadata value.
  """
  @spec set_metadata(GenServer.server(), atom(), term()) :: :ok
  def set_metadata(server, key, value) do
    GenServer.call(server, {:set_metadata, key, value})
  end

  @doc """
  Gets a metadata value.
  """
  @spec get_metadata(GenServer.server(), atom()) :: term()
  def get_metadata(server, key) do
    GenServer.call(server, {:get_metadata, key})
  end

  @doc """
  Sends a user message and initiates Claude query.

  This is an async operation - responses will be broadcast to subscribers.
  """
  @spec send_message(GenServer.server(), String.t(), keyword()) :: :ok
  def send_message(server, content, opts \\ []) do
    GenServer.cast(server, {:send_message, content, opts})
  end

  # Server Callbacks

  @impl true
  def init(%{chat_id: chat_id}) do
    state = %{
      chat_id: chat_id,
      subscribers: MapSet.new(),
      streaming: false,
      metadata: %{},
      query_task: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_chat_id, _from, state) do
    {:reply, state.chat_id, state}
  end

  @impl true
  def handle_call({:subscribe, subscriber}, _from, state) do
    new_subscribers = MapSet.put(state.subscribers, subscriber)
    {:reply, :ok, %{state | subscribers: new_subscribers}}
  end

  @impl true
  def handle_call({:unsubscribe, subscriber}, _from, state) do
    new_subscribers = MapSet.delete(state.subscribers, subscriber)
    {:reply, :ok, %{state | subscribers: new_subscribers}}
  end

  @impl true
  def handle_call({:has_subscriber, subscriber}, _from, state) do
    {:reply, MapSet.member?(state.subscribers, subscriber), state}
  end

  @impl true
  def handle_call(:subscriber_count, _from, state) do
    {:reply, MapSet.size(state.subscribers), state}
  end

  @impl true
  def handle_call(:is_streaming, _from, state) do
    {:reply, state.streaming, state}
  end

  @impl true
  def handle_call({:set_streaming, streaming}, _from, state) do
    {:reply, :ok, %{state | streaming: streaming}}
  end

  @impl true
  def handle_call({:set_metadata, key, value}, _from, state) do
    new_metadata = Map.put(state.metadata, key, value)
    {:reply, :ok, %{state | metadata: new_metadata}}
  end

  @impl true
  def handle_call({:get_metadata, key}, _from, state) do
    {:reply, Map.get(state.metadata, key), state}
  end

  @impl true
  def handle_cast({:broadcast, message}, state) do
    do_broadcast(state.subscribers, message)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:send_message, content, opts}, state) do
    # Start the Claude query in a separate task
    session_pid = self()

    task =
      Task.async(fn ->
        run_claude_query(session_pid, state.chat_id, content, opts)
      end)

    {:noreply, %{state | streaming: true, query_task: task}}
  end

  @impl true
  def handle_info({ref, _result}, state) when is_reference(ref) do
    # Task completed normally
    Process.demonitor(ref, [:flush])
    {:noreply, %{state | streaming: false, query_task: nil}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    # Task crashed
    Logger.error("Query task crashed: #{inspect(reason)}")
    do_broadcast(state.subscribers, {:error, "Query failed: #{inspect(reason)}"})
    {:noreply, %{state | streaming: false, query_task: nil}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private helpers

  defp do_broadcast(subscribers, message) do
    Enum.each(subscribers, fn subscriber ->
      if Process.alive?(subscriber) do
        send(subscriber, message)
      end
    end)
  end

  defp run_claude_query(session_pid, chat_id, content, opts) do
    try do
      store = Keyword.get(opts, :store, PhoenixChat.ChatStore)

      # Store the user message
      case PhoenixChat.ChatStore.add_message(store, chat_id, "user", content) do
        {:ok, _msg} ->
          # Broadcast user message to subscribers
          GenServer.cast(session_pid, {:broadcast, {:user_message, content, chat_id}})

          # Run the Claude query
          options = build_claude_options(opts)

          ClaudeAgentSDK.query(content, options)
          |> Stream.each(fn message ->
            handle_sdk_message(session_pid, chat_id, message, store)
          end)
          |> Stream.run()

        {:error, reason} ->
          GenServer.cast(
            session_pid,
            {:broadcast, {:error, "Failed to store message: #{reason}"}}
          )
      end
    rescue
      e ->
        Logger.error("Claude query error: #{Exception.message(e)}")

        GenServer.cast(
          session_pid,
          {:broadcast, {:error, "Query error: #{Exception.message(e)}"}}
        )
    end
  end

  defp build_claude_options(opts) do
    system_prompt =
      Keyword.get(
        opts,
        :system_prompt,
        """
        You are a helpful AI assistant. You can help users with a wide variety of tasks including:
        - Answering questions
        - Writing and editing text
        - Coding and debugging
        - Analysis and research
        - Creative tasks

        Be concise but thorough in your responses.
        """
      )

    %ClaudeAgentSDK.Options{
      max_turns: Keyword.get(opts, :max_turns, 100),
      model: Keyword.get(opts, :model, "haiku"),
      system_prompt: system_prompt,
      output_format: :stream_json,
      permission_mode: :bypass_permissions,
      allowed_tools: [
        "Bash",
        "Read",
        "Write",
        "Edit",
        "Glob",
        "Grep",
        "WebSearch",
        "WebFetch"
      ]
    }
  end

  defp handle_sdk_message(session_pid, chat_id, %ClaudeAgentSDK.Message{} = message, store) do
    case message.type do
      :assistant ->
        handle_assistant_message(session_pid, chat_id, message, store)

      :result ->
        handle_result_message(session_pid, chat_id, message)

      _other ->
        :ok
    end
  end

  defp handle_sdk_message(_session_pid, _chat_id, _message, _store) do
    # Unknown message format
    :ok
  end

  defp handle_assistant_message(session_pid, chat_id, message, store) do
    content = get_in(message.data, [:message, "content"]) || message.data[:message]["content"]

    cond do
      is_binary(content) ->
        # Simple text response
        store_and_broadcast_text(session_pid, chat_id, content, store)

      is_list(content) ->
        # Content blocks
        Enum.each(content, fn block ->
          handle_content_block(session_pid, chat_id, block, store)
        end)

      true ->
        :ok
    end
  end

  defp store_and_broadcast_text(session_pid, chat_id, content, store) do
    # Convert escaped newlines to actual newlines
    processed_content = String.replace(content, "\\n", "\n")

    # Store assistant message
    case PhoenixChat.ChatStore.add_message(store, chat_id, "assistant", processed_content) do
      {:ok, _msg} -> :ok
      {:error, _} -> :ok
    end

    # Broadcast to subscribers
    GenServer.cast(session_pid, {:broadcast, {:assistant_message, processed_content, chat_id}})
  end

  defp handle_content_block(session_pid, chat_id, %{"type" => "text", "text" => text}, store) do
    store_and_broadcast_text(session_pid, chat_id, text, store)
  end

  defp handle_content_block(session_pid, chat_id, %{"type" => "tool_use"} = block, _store) do
    tool_name = block["name"]
    tool_id = block["id"]
    tool_input = block["input"] || %{}

    GenServer.cast(
      session_pid,
      {:broadcast, {:tool_use, tool_name, tool_id, tool_input, chat_id}}
    )
  end

  defp handle_content_block(_session_pid, _chat_id, _block, _store) do
    :ok
  end

  defp handle_result_message(session_pid, chat_id, message) do
    success = message.subtype == :success
    cost = get_in(message.data, [:total_cost_usd]) || 0.0
    duration = get_in(message.data, [:duration_ms]) || 0

    GenServer.cast(session_pid, {:broadcast, {:result, success, cost, duration, chat_id}})
  end
end
