defmodule ClaudeAgentSDK.SessionStore do
  @moduledoc """
  Persistent session storage and management.

  Provides save/load/search capabilities for Claude conversation sessions,
  enabling multi-step workflows that survive application restarts.

  ## Features

  - Save/load complete session message history
  - Tag sessions for organization
  - Search sessions by tags, date range, cost
  - Automatic cleanup of old sessions
  - Export/import session data
  - Session metadata tracking

  ## Usage

      # Start the store
      {:ok, _pid} = ClaudeAgentSDK.SessionStore.start_link()

      # Save a session
      messages = ClaudeAgentSDK.query("Build a feature") |> Enum.to_list()
      session_id = ClaudeAgentSDK.Session.extract_session_id(messages)

      :ok = SessionStore.save_session(session_id, messages,
        tags: ["feature-dev", "important"],
        description: "Implemented user authentication"
      )

      # Load session later
      {:ok, session_data} = SessionStore.load_session(session_id)

      # Resume the conversation
      ClaudeAgentSDK.resume(session_id, "Now add tests")

      # Search sessions
      sessions = SessionStore.search(tags: ["important"], after: ~D[2025-10-01])

  ## Storage

  Sessions are stored in `~/.claude_sdk/sessions/` by default.
  Each session is a JSON file with message history and metadata.

  Configure storage location:

      config :claude_agent_sdk,
        session_storage_dir: "/custom/path/sessions"
  """

  use GenServer
  require Logger

  @default_storage_dir Path.expand("~/.claude_sdk/sessions")
  @max_age_days 30

  defstruct [
    :storage_dir,
    # ETS cache for fast access
    :cache,
    :cleanup_timer
  ]

  @type session_metadata :: %{
          session_id: String.t(),
          created_at: DateTime.t(),
          updated_at: DateTime.t(),
          message_count: non_neg_integer(),
          total_cost: float(),
          tags: [String.t()],
          description: String.t() | nil,
          model: String.t() | nil
        }

  @type session_data :: %{
          session_id: String.t(),
          messages: [ClaudeAgentSDK.Message.t()],
          metadata: session_metadata()
        }

  ## Public API

  @doc """
  Starts the SessionStore GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Saves a session with messages and metadata.

  ## Parameters

  - `session_id` - Session identifier
  - `messages` - List of Message structs from query
  - `opts` - Keyword options:
    - `:tags` - List of tag strings
    - `:description` - Session description

  ## Examples

      :ok = SessionStore.save_session(session_id, messages,
        tags: ["code-review", "security"],
        description: "Security audit of auth module"
      )
  """
  @spec save_session(String.t(), [ClaudeAgentSDK.Message.t()], keyword()) ::
          :ok | {:error, term()}
  def save_session(session_id, messages, opts \\ []) do
    GenServer.call(__MODULE__, {:save_session, session_id, messages, opts})
  end

  @doc """
  Loads a session by ID.

  ## Examples

      {:ok, session_data} = SessionStore.load_session(session_id)
      # session_data.messages - List of messages
      # session_data.metadata - Session metadata
  """
  @spec load_session(String.t()) :: {:ok, session_data()} | {:error, :not_found}
  def load_session(session_id) do
    GenServer.call(__MODULE__, {:load_session, session_id})
  end

  @doc """
  Searches sessions by criteria.

  ## Parameters

  - `criteria` - Keyword options:
    - `:tags` - Match sessions with these tags (list)
    - `:after` - Sessions created after date (Date or DateTime)
    - `:before` - Sessions created before date
    - `:min_cost` - Minimum cost threshold
    - `:max_cost` - Maximum cost threshold

  ## Examples

      # Find all security review sessions
      sessions = SessionStore.search(tags: ["security"])

      # Find expensive sessions from last week
      sessions = SessionStore.search(
        after: ~D[2025-10-01],
        min_cost: 0.10
      )
  """
  @spec search(keyword()) :: [session_metadata()]
  def search(criteria \\ []) do
    GenServer.call(__MODULE__, {:search, criteria})
  end

  @doc """
  Lists all sessions.

  Returns metadata for all stored sessions, sorted by updated_at (newest first).
  """
  @spec list_sessions() :: [session_metadata()]
  def list_sessions do
    GenServer.call(__MODULE__, :list_sessions)
  end

  @doc """
  Deletes a session.

  ## Examples

      :ok = SessionStore.delete_session(session_id)
  """
  @spec delete_session(String.t()) :: :ok
  def delete_session(session_id) do
    GenServer.call(__MODULE__, {:delete_session, session_id})
  end

  @doc """
  Cleans up sessions older than specified days.

  ## Examples

      # Delete sessions older than 30 days
      count = SessionStore.cleanup_old_sessions(max_age_days: 30)
      # => 5 (number of sessions deleted)
  """
  @spec cleanup_old_sessions(keyword()) :: non_neg_integer()
  def cleanup_old_sessions(opts \\ []) do
    GenServer.call(__MODULE__, {:cleanup_old, opts})
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    storage_dir =
      Keyword.get(
        opts,
        :storage_dir,
        Application.get_env(:claude_agent_sdk, :session_storage_dir, @default_storage_dir)
      )

    # Ensure storage directory exists
    File.mkdir_p!(storage_dir)

    # Create ETS cache
    cache = :ets.new(:session_cache, [:set, :public])

    # Schedule periodic cleanup
    cleanup_timer = schedule_cleanup()

    state = %__MODULE__{
      storage_dir: storage_dir,
      cache: cache,
      cleanup_timer: cleanup_timer
    }

    # Load existing sessions into cache
    load_sessions_into_cache(state)

    {:ok, state}
  end

  @impl true
  def handle_call({:save_session, session_id, messages, opts}, _from, state) do
    metadata = build_metadata(session_id, messages, opts)

    session_data = %{
      session_id: session_id,
      messages: serialize_messages(messages),
      metadata: metadata
    }

    # Save to disk
    case write_session_file(state.storage_dir, session_id, session_data) do
      :ok ->
        # Update cache
        :ets.insert(state.cache, {session_id, metadata})
        {:reply, :ok, state}

      {:error, reason} = error ->
        Logger.error("Failed to save session #{session_id}: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:load_session, session_id}, _from, state) do
    case read_session_file(state.storage_dir, session_id) do
      {:ok, session_data} ->
        # Deserialize messages
        messages = deserialize_messages(session_data["messages"])

        result = %{
          session_id: session_id,
          messages: messages,
          metadata: session_data["metadata"]
        }

        {:reply, {:ok, result}, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:search, criteria}, _from, state) do
    results =
      :ets.tab2list(state.cache)
      |> Enum.map(fn {_id, metadata} -> metadata end)
      |> filter_by_criteria(criteria)
      |> Enum.sort_by(
        fn session ->
          # Handle both atom and string keys
          updated_at = session[:updated_at] || session["updated_at"]

          if is_binary(updated_at),
            do: DateTime.from_iso8601(updated_at) |> elem(1),
            else: updated_at
        end,
        {:desc, DateTime}
      )

    {:reply, results, state}
  end

  @impl true
  def handle_call(:list_sessions, _from, state) do
    sessions =
      :ets.tab2list(state.cache)
      |> Enum.map(fn {_id, metadata} -> metadata end)
      |> Enum.sort_by(
        fn session ->
          # Handle both atom and string keys
          updated_at = session[:updated_at] || session["updated_at"]

          if is_binary(updated_at),
            do: DateTime.from_iso8601(updated_at) |> elem(1),
            else: updated_at
        end,
        {:desc, DateTime}
      )

    {:reply, sessions, state}
  end

  @impl true
  def handle_call({:delete_session, session_id}, _from, state) do
    # Delete from disk
    path = session_path(state.storage_dir, session_id)
    File.rm(path)

    # Delete from cache
    :ets.delete(state.cache, session_id)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:cleanup_old, opts}, _from, state) do
    max_age_days = Keyword.get(opts, :max_age_days, @max_age_days)
    cutoff_date = DateTime.add(DateTime.utc_now(), -max_age_days * 86_400, :second)

    # Find old sessions
    old_sessions =
      :ets.tab2list(state.cache)
      |> Enum.filter(fn {_id, metadata} ->
        DateTime.compare(metadata.updated_at, cutoff_date) == :lt
      end)

    # Delete them
    Enum.each(old_sessions, fn {session_id, _metadata} ->
      delete_session(session_id)
    end)

    {:reply, length(old_sessions), state}
  end

  @impl true
  def handle_info(:cleanup_check, state) do
    # Periodic cleanup
    _deleted = cleanup_old_sessions(max_age_days: @max_age_days)

    # Reschedule
    cleanup_timer = schedule_cleanup()

    {:noreply, %{state | cleanup_timer: cleanup_timer}}
  end

  ## Private Helpers

  defp build_metadata(session_id, messages, opts) do
    %{
      session_id: session_id,
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      message_count: length(messages),
      total_cost: ClaudeAgentSDK.Session.calculate_cost(messages),
      tags: Keyword.get(opts, :tags, []),
      description: Keyword.get(opts, :description),
      model: extract_model(messages)
    }
  end

  defp extract_model(messages) do
    messages
    |> Enum.find(&(&1.type == :system))
    |> case do
      %{data: %{model: model}} -> model
      %{data: data} when is_map(data) -> data["model"]
      _ -> nil
    end
  end

  defp serialize_messages(messages) do
    Enum.map(messages, fn msg ->
      %{
        type: msg.type,
        subtype: msg.subtype,
        data: msg.data,
        raw: msg.raw
      }
    end)
  end

  defp deserialize_messages(serialized) do
    Enum.map(serialized, fn msg ->
      type = ClaudeAgentSDK.Message.__safe_type__(msg["type"] || "unknown")

      %ClaudeAgentSDK.Message{
        type: type,
        subtype: ClaudeAgentSDK.Message.__safe_subtype__(type, msg["subtype"]),
        data: msg["data"],
        raw: msg["raw"]
      }
    end)
  end

  defp write_session_file(storage_dir, session_id, session_data) do
    path = session_path(storage_dir, session_id)

    json = Jason.encode!(session_data, pretty: true)

    case File.write(path, json) do
      :ok ->
        # User read/write only
        File.chmod!(path, 0o600)
        :ok

      error ->
        error
    end
  end

  defp read_session_file(storage_dir, session_id) do
    path = session_path(storage_dir, session_id)

    case File.read(path) do
      {:ok, json} ->
        Jason.decode(json)

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp session_path(storage_dir, session_id) do
    Path.join(storage_dir, "#{session_id}.json")
  end

  defp load_sessions_into_cache(state) do
    case File.ls(state.storage_dir) do
      {:ok, files} ->
        load_session_files(files, state)

      {:error, _} ->
        :ok
    end
  end

  defp load_session_files(files, state) do
    files
    |> Enum.filter(&String.ends_with?(&1, ".json"))
    |> Enum.each(fn file ->
      load_single_session_file(file, state)
    end)
  end

  defp load_single_session_file(file, state) do
    session_id = Path.basename(file, ".json")

    case read_session_file(state.storage_dir, session_id) do
      {:ok, data} ->
        :ets.insert(state.cache, {session_id, data["metadata"]})

      {:error, _} ->
        :ok
    end
  end

  defp filter_by_criteria(sessions, criteria) do
    sessions
    |> filter_by_tags(Keyword.get(criteria, :tags))
    |> filter_by_date_after(Keyword.get(criteria, :after))
    |> filter_by_date_before(Keyword.get(criteria, :before))
    |> filter_by_min_cost(Keyword.get(criteria, :min_cost))
    |> filter_by_max_cost(Keyword.get(criteria, :max_cost))
  end

  defp filter_by_tags(sessions, nil), do: sessions

  defp filter_by_tags(sessions, tags) do
    Enum.filter(sessions, fn session ->
      # Handle both atom and string keys for backward compatibility
      session_tags = session[:tags] || session["tags"] || []
      Enum.any?(tags, fn tag -> tag in session_tags end)
    end)
  end

  defp filter_by_date_after(sessions, nil), do: sessions

  defp filter_by_date_after(sessions, date) do
    date = to_datetime(date)

    Enum.filter(sessions, fn session ->
      # Handle both atom and string keys
      created_at = session[:created_at] || session["created_at"]

      created_at =
        if is_binary(created_at),
          do: DateTime.from_iso8601(created_at) |> elem(1),
          else: created_at

      DateTime.compare(created_at, date) in [:gt, :eq]
    end)
  end

  defp filter_by_date_before(sessions, nil), do: sessions

  defp filter_by_date_before(sessions, date) do
    date = to_datetime(date)

    Enum.filter(sessions, fn session ->
      # Handle both atom and string keys
      created_at = session[:created_at] || session["created_at"]

      created_at =
        if is_binary(created_at),
          do: DateTime.from_iso8601(created_at) |> elem(1),
          else: created_at

      DateTime.compare(created_at, date) in [:lt, :eq]
    end)
  end

  defp filter_by_min_cost(sessions, nil), do: sessions

  defp filter_by_min_cost(sessions, min_cost) do
    Enum.filter(sessions, fn session ->
      # Handle both atom and string keys
      total_cost = session[:total_cost] || session["total_cost"] || 0
      total_cost >= min_cost
    end)
  end

  defp filter_by_max_cost(sessions, nil), do: sessions

  defp filter_by_max_cost(sessions, max_cost) do
    Enum.filter(sessions, fn session ->
      # Handle both atom and string keys
      total_cost = session[:total_cost] || session["total_cost"] || 0
      total_cost <= max_cost
    end)
  end

  defp to_datetime(%DateTime{} = dt), do: dt

  defp to_datetime(%Date{} = date) do
    DateTime.new!(date, ~T[00:00:00])
  end

  defp schedule_cleanup do
    # Check for old sessions every 24 hours
    Process.send_after(self(), :cleanup_check, 24 * 60 * 60 * 1000)
  end
end
