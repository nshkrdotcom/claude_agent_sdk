defmodule ClaudeAgentSDK.SessionStore.InMemory do
  @moduledoc """
  In-memory SessionStore reference adapter.

  This adapter is intended for tests, local development, and examples. It keeps
  opaque transcript entries in append order and maintains summary sidecars via
  `ClaudeAgentSDK.SessionStore.Summary.fold_session_summary/3`.
  """

  alias ClaudeAgentSDK.SessionStore.{Key, Summary}

  defstruct [:server]

  @type t :: %__MODULE__{server: pid()}

  @doc """
  Starts a new in-memory store and returns the adapter struct.
  """
  @spec new() :: {:ok, t()} | {:error, term()}
  def new do
    with {:ok, pid} <- Agent.start_link(fn -> initial_state() end) do
      {:ok, %__MODULE__{server: pid}}
    end
  end

  @doc """
  Starts a new in-memory store and raises on failure.
  """
  @spec new!() :: t()
  def new! do
    case new() do
      {:ok, store} -> store
      {:error, reason} -> raise "failed to start in-memory SessionStore: #{inspect(reason)}"
    end
  end

  @spec append(t(), Key.input(), [map()]) :: :ok
  def append(%__MODULE__{server: server}, key, entries) when is_list(entries) do
    key = Key.new!(key)

    Agent.update(server, fn state ->
      append_entries_to_state(state, key, entries)
    end)
  end

  @spec load(t(), Key.input()) :: [map()] | nil
  def load(%__MODULE__{server: server}, key) do
    storage_key = Key.storage_key(key)
    Agent.get(server, fn state -> copy_entries(Map.get(state.store, storage_key)) end)
  end

  @spec list_sessions(t(), String.t()) :: [%{session_id: String.t(), mtime: integer()}]
  def list_sessions(%__MODULE__{server: server}, project_key) when is_binary(project_key) do
    Agent.get(server, fn state ->
      state.store
      |> Map.keys()
      |> Enum.flat_map(fn
        {^project_key, session_id, nil} = storage_key ->
          [%{session_id: session_id, mtime: Map.get(state.mtimes, storage_key, 0)}]

        _other ->
          []
      end)
    end)
  end

  @spec list_session_summaries(t(), String.t()) :: [map()]
  def list_session_summaries(%__MODULE__{server: server}, project_key)
      when is_binary(project_key) do
    Agent.get(server, fn state ->
      state.summaries
      |> Enum.flat_map(fn
        {{^project_key, _session_id}, summary} -> [summary]
        _other -> []
      end)
    end)
  end

  @spec delete(t(), Key.input()) :: :ok
  def delete(%__MODULE__{server: server}, key) do
    key = Key.new!(key)

    Agent.update(server, fn state ->
      delete_key_from_state(state, key)
    end)
  end

  @spec list_subkeys(t(), Key.input()) :: [String.t()]
  def list_subkeys(%__MODULE__{server: server}, key) do
    key = Key.new!(key)

    Agent.get(server, fn state ->
      state.store
      |> Map.keys()
      |> Enum.flat_map(fn
        {project_key, session_id, subpath}
        when project_key == key.project_key and session_id == key.session_id and
               is_binary(subpath) ->
          [subpath]

        _other ->
          []
      end)
      |> Enum.sort()
    end)
  end

  @doc false
  @spec get_entries(t(), Key.input()) :: [map()]
  def get_entries(store, key), do: load(store, key) || []

  @doc false
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{server: server}) do
    Agent.get(server, fn state ->
      Enum.count(state.store, fn {{_project_key, _session_id, subpath}, _entries} ->
        is_nil(subpath)
      end)
    end)
  end

  @doc false
  @spec clear(t()) :: :ok
  def clear(%__MODULE__{server: server}),
    do: Agent.update(server, fn _state -> initial_state() end)

  defp initial_state, do: %{store: %{}, mtimes: %{}, summaries: %{}, last_mtime: 0}

  defp append_entries_to_state(state, _key, []), do: state

  defp append_entries_to_state(state, key, entries) do
    storage_key = Key.storage_key(key)
    existing = Map.get(state.store, storage_key, [])
    entries = dedupe_entries(existing, entries)
    updated_entries = existing ++ entries
    {mtime, state} = next_mtime(state)

    %{
      state
      | store: Map.put(state.store, storage_key, updated_entries),
        mtimes: Map.put(state.mtimes, storage_key, mtime),
        summaries: update_summary(state.summaries, key, entries, mtime)
    }
  end

  defp update_summary(summaries, key, entries, mtime) do
    if Key.main?(key) do
      summary_key = {key.project_key, key.session_id}

      summaries
      |> Map.get(summary_key)
      |> Summary.fold_session_summary(key, entries)
      |> Map.put(:mtime, mtime)
      |> then(&Map.put(summaries, summary_key, &1))
    else
      summaries
    end
  end

  defp delete_key_from_state(state, key) do
    if Key.main?(key) do
      delete_main_key_from_state(state, key)
    else
      storage_key = Key.storage_key(key)

      %{
        state
        | store: Map.delete(state.store, storage_key),
          mtimes: Map.delete(state.mtimes, storage_key)
      }
    end
  end

  defp delete_main_key_from_state(state, key) do
    doomed? = fn
      {project_key, session_id, _subpath} ->
        project_key == key.project_key and session_id == key.session_id
    end

    %{
      state
      | store: Map.reject(state.store, fn {storage_key, _entries} -> doomed?.(storage_key) end),
        mtimes: Map.reject(state.mtimes, fn {storage_key, _mtime} -> doomed?.(storage_key) end),
        summaries: Map.delete(state.summaries, {key.project_key, key.session_id})
    }
  end

  defp next_mtime(state) do
    now = System.system_time(:millisecond)
    mtime = if now <= state.last_mtime, do: state.last_mtime + 1, else: now
    {mtime, %{state | last_mtime: mtime}}
  end

  defp dedupe_entries(existing, incoming) do
    existing_uuids =
      existing
      |> Enum.map(&entry_uuid/1)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    {_seen, entries} =
      Enum.reduce(incoming, {existing_uuids, []}, fn entry, {seen, acc} ->
        dedupe_entry(entry, seen, acc)
      end)

    Enum.reverse(entries)
  end

  defp dedupe_entry(entry, seen, acc) do
    case entry_uuid(entry) do
      nil -> {seen, [entry | acc]}
      uuid -> maybe_add_uuid_entry(entry, uuid, seen, acc)
    end
  end

  defp maybe_add_uuid_entry(entry, uuid, seen, acc) do
    if MapSet.member?(seen, uuid) do
      {seen, acc}
    else
      {MapSet.put(seen, uuid), [entry | acc]}
    end
  end

  defp entry_uuid(entry) when is_map(entry), do: Map.get(entry, "uuid") || Map.get(entry, :uuid)
  defp entry_uuid(_entry), do: nil

  defp copy_entries(nil), do: nil
  defp copy_entries(entries), do: Enum.map(entries, &Map.new/1)
end
