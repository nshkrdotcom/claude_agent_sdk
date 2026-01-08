defmodule PhoenixChat.ChatStore do
  @moduledoc """
  In-memory storage for chat sessions and messages.

  This GenServer manages chat state using ETS tables for efficient
  concurrent read access. Each chat has a list of messages.

  The store is similar to the TypeScript ChatStore in the reference demo,
  providing CRUD operations for chats and messages.

  ## Usage

      # Start the store (usually done by the application supervisor)
      {:ok, _pid} = ChatStore.start_link(name: ChatStore)

      # Create a new chat
      {:ok, chat} = ChatStore.create_chat(ChatStore, "My Chat")

      # Add messages
      {:ok, msg} = ChatStore.add_message(ChatStore, chat.id, "user", "Hello!")

      # List all chats
      chats = ChatStore.list_chats(ChatStore)

  """
  use GenServer
  import Bitwise

  @type chat :: %{
          id: String.t(),
          title: String.t(),
          created_at: String.t(),
          updated_at: String.t()
        }

  @type message :: %{
          id: String.t(),
          chat_id: String.t(),
          role: String.t(),
          content: String.t(),
          timestamp: String.t()
        }

  # Client API

  @doc """
  Starts the ChatStore GenServer.

  ## Options

    * `:name` - The name to register the server under (required for multiple instances)

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Creates a new chat session.

  ## Parameters

    * `server` - The ChatStore server name or PID
    * `title` - Optional title for the chat (defaults to "New Chat")

  ## Returns

    * `{:ok, chat}` - The created chat with its generated ID

  """
  @spec create_chat(GenServer.server(), String.t() | nil) :: {:ok, chat()}
  def create_chat(server, title \\ nil) do
    GenServer.call(server, {:create_chat, title})
  end

  @doc """
  Gets a chat by its ID.

  ## Parameters

    * `server` - The ChatStore server name or PID
    * `chat_id` - The chat's unique ID

  ## Returns

    * `{:ok, chat}` - The found chat
    * `{:error, :not_found}` - If the chat doesn't exist

  """
  @spec get_chat(GenServer.server(), String.t()) :: {:ok, chat()} | {:error, :not_found}
  def get_chat(server, chat_id) do
    GenServer.call(server, {:get_chat, chat_id})
  end

  @doc """
  Lists all chats sorted by most recently updated first.

  ## Parameters

    * `server` - The ChatStore server name or PID

  ## Returns

    * A list of chats sorted by `updated_at` descending

  """
  @spec list_chats(GenServer.server()) :: [chat()]
  def list_chats(server) do
    GenServer.call(server, :list_chats)
  end

  @doc """
  Deletes a chat and all its messages.

  ## Parameters

    * `server` - The ChatStore server name or PID
    * `chat_id` - The chat's unique ID

  ## Returns

    * `:ok` - If deletion was successful
    * `{:error, :not_found}` - If the chat doesn't exist

  """
  @spec delete_chat(GenServer.server(), String.t()) :: :ok | {:error, :not_found}
  def delete_chat(server, chat_id) do
    GenServer.call(server, {:delete_chat, chat_id})
  end

  @doc """
  Adds a message to a chat.

  If the chat title is still "New Chat" and this is a user message,
  the title will be updated based on the message content.

  ## Parameters

    * `server` - The ChatStore server name or PID
    * `chat_id` - The chat's unique ID
    * `role` - The message role ("user" or "assistant")
    * `content` - The message content

  ## Returns

    * `{:ok, message}` - The created message
    * `{:error, :not_found}` - If the chat doesn't exist

  """
  @spec add_message(GenServer.server(), String.t(), String.t(), String.t()) ::
          {:ok, message()} | {:error, :not_found}
  def add_message(server, chat_id, role, content) do
    GenServer.call(server, {:add_message, chat_id, role, content})
  end

  @doc """
  Gets all messages for a chat.

  ## Parameters

    * `server` - The ChatStore server name or PID
    * `chat_id` - The chat's unique ID

  ## Returns

    * A list of messages in chronological order (empty if chat not found)

  """
  @spec get_messages(GenServer.server(), String.t()) :: [message()]
  def get_messages(server, chat_id) do
    GenServer.call(server, {:get_messages, chat_id})
  end

  @doc """
  Updates a chat's timestamp to the current time.

  ## Parameters

    * `server` - The ChatStore server name or PID
    * `chat_id` - The chat's unique ID

  """
  @spec update_chat_timestamp(GenServer.server(), String.t()) :: :ok
  def update_chat_timestamp(server, chat_id) do
    GenServer.call(server, {:update_timestamp, chat_id})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      chats: %{},
      messages: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:create_chat, title}, _from, state) do
    id = generate_id()
    now = timestamp()

    chat = %{
      id: id,
      title: title || "New Chat",
      created_at: now,
      updated_at: now
    }

    new_state = %{
      state
      | chats: Map.put(state.chats, id, chat),
        messages: Map.put(state.messages, id, [])
    }

    {:reply, {:ok, chat}, new_state}
  end

  @impl true
  def handle_call({:get_chat, chat_id}, _from, state) do
    case Map.get(state.chats, chat_id) do
      nil -> {:reply, {:error, :not_found}, state}
      chat -> {:reply, {:ok, chat}, state}
    end
  end

  @impl true
  def handle_call(:list_chats, _from, state) do
    chats =
      state.chats
      |> Map.values()
      |> Enum.sort_by(& &1.updated_at, :desc)

    {:reply, chats, state}
  end

  @impl true
  def handle_call({:delete_chat, chat_id}, _from, state) do
    case Map.get(state.chats, chat_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      _chat ->
        new_state = %{
          state
          | chats: Map.delete(state.chats, chat_id),
            messages: Map.delete(state.messages, chat_id)
        }

        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:add_message, chat_id, role, content}, _from, state) do
    case Map.get(state.chats, chat_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      chat ->
        now = timestamp()
        message_id = generate_id()

        message = %{
          id: message_id,
          chat_id: chat_id,
          role: role,
          content: content,
          timestamp: now
        }

        # Update messages
        current_messages = Map.get(state.messages, chat_id, [])
        new_messages = current_messages ++ [message]

        # Update chat - maybe update title from first user message
        updated_chat = update_chat_on_message(chat, role, content, now)

        new_state = %{
          state
          | chats: Map.put(state.chats, chat_id, updated_chat),
            messages: Map.put(state.messages, chat_id, new_messages)
        }

        {:reply, {:ok, message}, new_state}
    end
  end

  @impl true
  def handle_call({:get_messages, chat_id}, _from, state) do
    messages = Map.get(state.messages, chat_id, [])
    {:reply, messages, state}
  end

  @impl true
  def handle_call({:update_timestamp, chat_id}, _from, state) do
    case Map.get(state.chats, chat_id) do
      nil ->
        {:reply, :ok, state}

      chat ->
        updated_chat = %{chat | updated_at: timestamp()}
        new_state = %{state | chats: Map.put(state.chats, chat_id, updated_chat)}
        {:reply, :ok, new_state}
    end
  end

  # Private helpers

  defp generate_id do
    # Generate a UUID v4
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)

    :io_lib.format(
      "~8.16.0b-~4.16.0b-4~3.16.0b-~4.16.0b-~12.16.0b",
      [a, b, c &&& 0x0FFF, (d &&& 0x3FFF) ||| 0x8000, e]
    )
    |> IO.iodata_to_binary()
  end

  defp timestamp do
    DateTime.utc_now() |> DateTime.to_iso8601()
  end

  defp update_chat_on_message(chat, "user", content, now) when chat.title == "New Chat" do
    title = truncate_title(content)
    %{chat | title: title, updated_at: now}
  end

  defp update_chat_on_message(chat, _role, _content, now) do
    %{chat | updated_at: now}
  end

  defp truncate_title(content) do
    if String.length(content) > 50 do
      String.slice(content, 0, 50) <> "..."
    else
      content
    end
  end
end
