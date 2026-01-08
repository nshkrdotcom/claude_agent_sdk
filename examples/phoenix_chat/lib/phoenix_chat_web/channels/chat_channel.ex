defmodule PhoenixChatWeb.ChatChannel do
  @moduledoc """
  WebSocket channel for real-time chat communication.

  This channel handles bidirectional communication between the browser
  and the Phoenix server, similar to the WebSocket server in the
  TypeScript reference demo.

  ## Client -> Server Messages

    * `subscribe` - Subscribe to a chat's messages
    * `chat` - Send a message to Claude

  ## Server -> Client Messages

    * `history` - Initial message history when subscribing
    * `user_message` - User message confirmation
    * `assistant_message` - Claude's response text
    * `tool_use` - Tool being invoked by Claude
    * `result` - Query completion with cost/duration
    * `error` - Error notification

  """
  use Phoenix.Channel

  require Logger

  alias PhoenixChat.{ChatStore, ChatSession, SessionRegistry}

  @impl true
  def join("chat:lobby", _payload, socket) do
    {:ok, assign(socket, :topic, "chat:lobby")}
  end

  @impl true
  def join("chat:" <> chat_id, _payload, socket) do
    {:ok, %{}, assign(socket, :chat_id, chat_id)}
  end

  @impl true
  def handle_in("subscribe", %{"chat_id" => chat_id}, socket) do
    store = get_store(socket)

    # Get or create a session for this chat
    case SessionRegistry.get_or_create_session(chat_id) do
      {:ok, session_pid} ->
        # Subscribe this channel to session updates
        :ok = ChatSession.subscribe(session_pid, self())

        # Get message history
        messages =
          ChatStore.get_messages(store, chat_id)
          |> Enum.map(&message_to_map/1)

        socket = assign(socket, :chat_id, chat_id)
        socket = assign(socket, :session_pid, session_pid)

        {:reply, {:ok, %{"messages" => messages}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: "Failed to create session: #{inspect(reason)}"}}, socket}
    end
  end

  @impl true
  def handle_in("subscribe", _payload, socket) do
    {:reply, {:error, %{reason: "chat_id required"}}, socket}
  end

  @impl true
  def handle_in("chat", %{"chat_id" => chat_id, "content" => content}, socket)
      when is_binary(content) and content != "" do
    store = get_store(socket)

    # Ensure we have a session
    case SessionRegistry.get_or_create_session(chat_id) do
      {:ok, session_pid} ->
        # Subscribe if not already
        :ok = ChatSession.subscribe(session_pid, self())

        # Send the message to Claude
        :ok = ChatSession.send_message(session_pid, content, store: store)

        socket = assign(socket, :chat_id, chat_id)
        socket = assign(socket, :session_pid, session_pid)

        {:reply, :ok, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: "Session error: #{inspect(reason)}"}}, socket}
    end
  end

  @impl true
  def handle_in("chat", %{"chat_id" => _chat_id}, socket) do
    {:reply, {:error, %{reason: "content required"}}, socket}
  end

  @impl true
  def handle_in("chat", _payload, socket) do
    {:reply, {:error, %{reason: "chat_id required"}}, socket}
  end

  # Handle messages from ChatSession broadcasts
  @impl true
  def handle_info({:user_message, content, chat_id}, socket) do
    broadcast!(socket, "user_message", %{content: content, chat_id: chat_id})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:assistant_message, content, chat_id}, socket) do
    broadcast!(socket, "assistant_message", %{content: content, chat_id: chat_id})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:tool_use, tool_name, tool_id, tool_input, chat_id}, socket) do
    broadcast!(socket, "tool_use", %{
      tool_name: tool_name,
      tool_id: tool_id,
      tool_input: tool_input,
      chat_id: chat_id
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:result, success, cost, duration, chat_id}, socket) do
    broadcast!(socket, "result", %{
      success: success,
      cost: cost,
      duration: duration,
      chat_id: chat_id
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:error, reason}, socket) do
    push(socket, "error", %{error: reason})
    {:noreply, socket}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    # Unsubscribe from session if we have one
    case Map.get(socket.assigns, :session_pid) do
      nil -> :ok
      session_pid -> ChatSession.unsubscribe(session_pid, self())
    end

    :ok
  end

  # Private helpers

  defp get_store(socket) do
    Map.get(socket.assigns, :store, PhoenixChat.ChatStore)
  end

  defp message_to_map(message) do
    %{
      "id" => message.id,
      "chat_id" => message.chat_id,
      "role" => message.role,
      "content" => message.content,
      "timestamp" => message.timestamp
    }
  end
end
