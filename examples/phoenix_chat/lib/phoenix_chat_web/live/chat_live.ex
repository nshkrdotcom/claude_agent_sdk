defmodule PhoenixChatWeb.ChatLive do
  @moduledoc """
  LiveView for the chat interface.

  This is the main UI component that provides:
  - Chat list sidebar
  - Message display area
  - Message input form
  - Real-time updates via Phoenix Channels

  The UI is similar to the React components in the TypeScript reference demo,
  implemented using Phoenix LiveView for server-rendered interactivity.
  """
  use PhoenixChatWeb, :live_view

  import Bitwise

  alias PhoenixChat.{ChatStore, ChatSession, SessionRegistry}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(PhoenixChat.PubSub, "chat_updates")
    end

    socket =
      socket
      |> assign(:chats, list_chats())
      |> assign(:selected_chat_id, nil)
      |> assign(:messages, [])
      |> assign(:is_loading, false)
      |> assign(:is_connected, connected?(socket))
      |> assign(:current_tool, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => chat_id}, _uri, socket) do
    socket = select_chat(socket, chat_id)
    {:noreply, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen bg-gray-100">
      <!-- Sidebar -->
      <div class="w-64 bg-gray-900 text-white flex flex-col">
        <!-- Header -->
        <div class="p-4 border-b border-gray-700">
          <button
            phx-click="new_chat"
            data-role="new-chat-button"
            class="w-full flex items-center justify-center gap-2 px-4 py-2 bg-gray-700 hover:bg-gray-600 rounded-lg transition-colors"
          >
            <span>+</span>
            <span>New Chat</span>
          </button>
        </div>
        
    <!-- Chat list -->
        <div class="flex-1 overflow-y-auto">
          <%= if @chats == [] do %>
            <div class="p-4 text-center text-gray-500">
              <p class="text-sm">No chats yet</p>
              <p class="text-xs mt-1">Click "New Chat" to start</p>
            </div>
          <% else %>
            <div class="p-2 space-y-1">
              <%= for chat <- @chats do %>
                <div
                  data-role="chat-item"
                  data-chat-id={chat.id}
                  phx-click="select_chat"
                  phx-value-chat_id={chat.id}
                  class={"group flex items-center gap-2 px-3 py-2 rounded-lg cursor-pointer transition-colors #{if @selected_chat_id == chat.id, do: "bg-gray-700", else: "hover:bg-gray-800"}"}
                >
                  <span class="text-gray-400 shrink-0">&#128172;</span>
                  <span class="flex-1 truncate text-sm">{chat.title}</span>
                  <button
                    data-role="delete-chat-button"
                    data-chat-id={chat.id}
                    phx-click="delete_chat"
                    phx-value-chat_id={chat.id}
                    class="opacity-0 group-hover:opacity-100 p-1 hover:bg-gray-600 rounded transition-all text-gray-400 hover:text-white"
                  >
                    &#10005;
                  </button>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
        
    <!-- Footer -->
        <div class="p-4 border-t border-gray-700">
          <p class="text-xs text-gray-500 text-center">
            Phoenix Chat - Claude Agent SDK Demo
          </p>
        </div>
      </div>
      
    <!-- Main chat area -->
      <%= if @selected_chat_id do %>
        <div data-role="chat-window" class="flex-1 flex flex-col bg-white">
          <!-- Header -->
          <div class="px-4 py-3 border-b border-gray-200 flex items-center justify-between">
            <h2 class="font-semibold text-gray-800">Chat</h2>
            <div class="flex items-center gap-2">
              <%= if @is_connected do %>
                <span class="text-xs text-green-600">&#9679; Connected</span>
              <% else %>
                <span class="text-xs text-red-600">&#9675; Disconnected</span>
              <% end %>
            </div>
          </div>
          
    <!-- Messages -->
          <div
            id="messages-container"
            phx-hook="ScrollToBottom"
            class="flex-1 overflow-y-auto p-4 space-y-4"
          >
            <%= if @messages == [] do %>
              <div class="text-center text-gray-400 mt-8">
                <p>Start a conversation</p>
              </div>
            <% else %>
              <%= for message <- @messages do %>
                <.message_bubble message={message} />
              <% end %>
              <%= if @is_loading do %>
                <div class="flex items-center gap-2 text-gray-500">
                  <span class="animate-pulse">&#9679;</span>
                  <span class="text-sm">Thinking...</span>
                </div>
              <% end %>
              <%= if @current_tool do %>
                <.tool_indicator tool={@current_tool} />
              <% end %>
            <% end %>
          </div>
          
    <!-- Input -->
          <div class="p-4 border-t border-gray-200">
            <form phx-submit="send_message" class="flex gap-2">
              <input
                type="text"
                name="content"
                data-role="message-input"
                placeholder={if @is_connected, do: "Type a message...", else: "Connecting..."}
                disabled={not @is_connected or @is_loading}
                autocomplete="off"
                class="flex-1 px-4 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent disabled:bg-gray-100"
              />
              <button
                type="submit"
                disabled={not @is_connected or @is_loading}
                class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
              >
                Send
              </button>
            </form>
          </div>
        </div>
      <% else %>
        <div class="flex-1 flex items-center justify-center bg-gray-50">
          <div class="text-center text-gray-500">
            <h1 class="text-2xl font-semibold mb-2">Phoenix Chat</h1>
            <p class="text-lg">Welcome to Simple Chat</p>
            <p class="text-sm mt-2">Select a chat or create a new one to get started</p>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Components

  defp message_bubble(assigns) do
    ~H"""
    <%= case @message.role do %>
      <% "tool_use" -> %>
        <.tool_use_block message={@message} />
      <% role -> %>
        <div class={"flex #{if role == "user", do: "justify-end", else: "justify-start"}"}>
          <div class={"max-w-[80%] rounded-lg px-4 py-2 #{if role == "user", do: "bg-blue-600 text-white", else: "bg-gray-100 text-gray-900"}"}>
            <p class="whitespace-pre-wrap">{@message.content}</p>
          </div>
        </div>
    <% end %>
    """
  end

  defp tool_use_block(assigns) do
    ~H"""
    <div class="my-2 border border-gray-200 bg-gray-50 rounded">
      <div class="p-2 flex items-center gap-2">
        <span class="text-xs font-semibold text-gray-600 uppercase">
          {@message.tool_name}
        </span>
        <span class="text-xs text-gray-500 truncate max-w-md">
          {tool_summary(@message)}
        </span>
      </div>
    </div>
    """
  end

  defp tool_indicator(assigns) do
    ~H"""
    <div class="my-2 border border-blue-200 bg-blue-50 rounded animate-pulse">
      <div class="p-2 flex items-center gap-2">
        <span class="text-xs font-semibold text-blue-600 uppercase">
          Using {@tool.name}
        </span>
      </div>
    </div>
    """
  end

  defp tool_summary(message) do
    input = message[:tool_input] || %{}

    case message[:tool_name] do
      "Read" -> input["file_path"] || ""
      "Write" -> input["file_path"] || ""
      "Edit" -> input["file_path"] || ""
      "Bash" -> String.slice(input["command"] || "", 0, 60)
      "Grep" -> "\"#{input["pattern"]}\" in #{input["path"] || "."}"
      "Glob" -> input["pattern"] || ""
      "WebSearch" -> input["query"] || ""
      "WebFetch" -> input["url"] || ""
      _ -> inspect(input) |> String.slice(0, 50)
    end
  end

  # Event handlers

  @impl true
  def handle_event("new_chat", _params, socket) do
    {:ok, chat} = ChatStore.create_chat(PhoenixChat.ChatStore)

    socket =
      socket
      |> assign(:chats, list_chats())
      |> select_chat(chat.id)

    {:noreply, push_patch(socket, to: ~p"/?id=#{chat.id}")}
  end

  @impl true
  def handle_event("select_chat", %{"chat_id" => chat_id}, socket) do
    socket = select_chat(socket, chat_id)
    {:noreply, push_patch(socket, to: ~p"/?id=#{chat_id}")}
  end

  @impl true
  def handle_event("delete_chat", %{"chat_id" => chat_id}, socket) do
    :ok = ChatStore.delete_chat(PhoenixChat.ChatStore, chat_id)
    :ok = SessionRegistry.close_session(chat_id)

    socket =
      socket
      |> assign(:chats, list_chats())
      |> then(fn s ->
        if s.assigns.selected_chat_id == chat_id do
          s
          |> assign(:selected_chat_id, nil)
          |> assign(:messages, [])
        else
          s
        end
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("send_message", %{"content" => content}, socket)
      when content != "" do
    chat_id = socket.assigns.selected_chat_id

    if chat_id do
      # Add user message optimistically
      user_message = %{
        id: generate_uuid(),
        role: "user",
        content: content,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      socket =
        socket
        |> assign(:messages, socket.assigns.messages ++ [user_message])
        |> assign(:is_loading, true)

      # Start the Claude query
      spawn_link(fn ->
        send_to_claude(chat_id, content, socket.root_pid)
      end)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("send_message", _params, socket) do
    {:noreply, socket}
  end

  # Handle messages from Claude session
  @impl true
  def handle_info({:assistant_message, content, chat_id}, socket) do
    if socket.assigns.selected_chat_id == chat_id do
      message = %{
        id: generate_uuid(),
        role: "assistant",
        content: content,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      socket =
        socket
        |> assign(:messages, socket.assigns.messages ++ [message])
        |> assign(:is_loading, false)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:tool_use, tool_name, tool_id, tool_input, chat_id}, socket) do
    if socket.assigns.selected_chat_id == chat_id do
      message = %{
        id: tool_id,
        role: "tool_use",
        tool_name: tool_name,
        tool_input: tool_input,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      socket =
        socket
        |> assign(:messages, socket.assigns.messages ++ [message])
        |> assign(:current_tool, %{name: tool_name})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:result, _success, _cost, _duration, chat_id}, socket) do
    if socket.assigns.selected_chat_id == chat_id do
      socket =
        socket
        |> assign(:is_loading, false)
        |> assign(:current_tool, nil)
        |> assign(:chats, list_chats())

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:error, reason}, socket) do
    socket =
      socket
      |> assign(:is_loading, false)
      |> assign(:current_tool, nil)
      |> put_flash(:error, "Error: #{reason}")

    {:noreply, socket}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # Private helpers

  defp list_chats do
    ChatStore.list_chats(PhoenixChat.ChatStore)
  end

  defp select_chat(socket, chat_id) do
    messages =
      ChatStore.get_messages(PhoenixChat.ChatStore, chat_id)
      |> Enum.map(&message_to_display/1)

    # Subscribe to session updates
    if connected?(socket) do
      case SessionRegistry.get_or_create_session(chat_id) do
        {:ok, session_pid} ->
          ChatSession.subscribe(session_pid, self())

        {:error, _} ->
          :ok
      end
    end

    socket
    |> assign(:selected_chat_id, chat_id)
    |> assign(:messages, messages)
    |> assign(:is_loading, false)
    |> assign(:current_tool, nil)
  end

  defp message_to_display(message) do
    %{
      id: message.id,
      role: message.role,
      content: message.content,
      timestamp: message.timestamp
    }
  end

  defp send_to_claude(chat_id, content, liveview_pid) do
    case SessionRegistry.get_or_create_session(chat_id) do
      {:ok, session_pid} ->
        ChatSession.subscribe(session_pid, liveview_pid)
        ChatSession.send_message(session_pid, content)

      {:error, reason} ->
        send(liveview_pid, {:error, "Failed to start session: #{inspect(reason)}"})
    end
  end

  defp generate_uuid do
    # Generate a UUID v4
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)

    :io_lib.format(
      "~8.16.0b-~4.16.0b-4~3.16.0b-~4.16.0b-~12.16.0b",
      [a, b, c &&& 0x0FFF, (d &&& 0x3FFF) ||| 0x8000, e]
    )
    |> IO.iodata_to_binary()
  end
end
