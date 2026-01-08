defmodule PhoenixChat.SessionRegistry do
  @moduledoc """
  Registry and supervisor for chat sessions.

  Provides a way to look up or create chat sessions on demand.
  Sessions are created lazily when a client subscribes to a chat.

  ## Usage

      # Get or create a session for a chat
      {:ok, session_pid} = SessionRegistry.get_or_create_session("chat-123")

      # The session is now ready for subscriptions
      ChatSession.subscribe(session_pid, self())

  """

  use DynamicSupervisor

  alias PhoenixChat.ChatSession

  @doc """
  Starts the session registry as a dynamic supervisor.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    DynamicSupervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Gets an existing session or creates a new one for the given chat ID.

  ## Parameters

    * `supervisor` - The supervisor name or PID (defaults to `__MODULE__`)
    * `chat_id` - The unique chat ID

  ## Returns

    * `{:ok, pid}` - The session PID (existing or newly created)
    * `{:error, reason}` - If session creation failed

  """
  @spec get_or_create_session(GenServer.server(), String.t()) ::
          {:ok, pid()} | {:error, term()}
  def get_or_create_session(supervisor \\ __MODULE__, chat_id) do
    # Use a named process based on chat_id
    name = session_name(chat_id)

    case GenServer.whereis(name) do
      nil ->
        start_session(supervisor, chat_id, name)

      pid ->
        {:ok, pid}
    end
  end

  @doc """
  Closes and removes a session.

  ## Parameters

    * `supervisor` - The supervisor name or PID
    * `chat_id` - The chat ID to close

  """
  @spec close_session(GenServer.server(), String.t()) :: :ok
  def close_session(supervisor \\ __MODULE__, chat_id) do
    name = session_name(chat_id)

    case GenServer.whereis(name) do
      nil ->
        :ok

      pid ->
        DynamicSupervisor.terminate_child(supervisor, pid)
        :ok
    end
  end

  @doc """
  Checks if a session exists for the given chat ID.
  """
  @spec session_exists?(String.t()) :: boolean()
  def session_exists?(chat_id) do
    name = session_name(chat_id)
    GenServer.whereis(name) != nil
  end

  # Private helpers

  defp session_name(chat_id) do
    {:via, Registry, {PhoenixChat.SessionNames, chat_id}}
  end

  defp start_session(supervisor, chat_id, name) do
    spec = {ChatSession, chat_id: chat_id, name: name}

    case DynamicSupervisor.start_child(supervisor, spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end
end
