defmodule ClaudeAgentSDK.SessionStore.MirrorBatcher do
  @moduledoc """
  Batches `transcript_mirror` frames and appends them to a SessionStore.
  """

  use Agent

  alias ClaudeAgentSDK.Message
  alias ClaudeAgentSDK.SessionStore.{Adapter, Key, Summary}

  @max_pending_entries 500
  @max_pending_bytes 1_048_576
  @append_attempts 3
  @backoff_ms [200, 800]

  @type t :: pid()

  @doc false
  def max_pending_entries, do: @max_pending_entries
  @doc false
  def max_pending_bytes, do: @max_pending_bytes

  @spec start_link(term(), String.t(), keyword()) :: Agent.on_start()
  def start_link(store, projects_dir, opts \\ []) do
    Agent.start_link(fn ->
      %{
        store: store,
        projects_dir: projects_dir,
        pending: [],
        pending_entries: 0,
        pending_bytes: 0,
        send_timeout_ms: Keyword.get(opts, :send_timeout_ms, 60_000),
        max_pending_entries: Keyword.get(opts, :max_pending_entries, @max_pending_entries),
        max_pending_bytes: Keyword.get(opts, :max_pending_bytes, @max_pending_bytes)
      }
    end)
  end

  @spec enqueue(t(), String.t(), [map()]) :: [Message.t()]
  def enqueue(pid, file_path, entries)
      when is_pid(pid) and is_binary(file_path) and is_list(entries) do
    flush? =
      Agent.get_and_update(pid, fn state ->
        bytes = entries |> Jason.encode!() |> byte_size()

        state = %{
          state
          | pending: state.pending ++ [{file_path, entries}],
            pending_entries: state.pending_entries + length(entries),
            pending_bytes: state.pending_bytes + bytes
        }

        flush? =
          state.pending_entries > state.max_pending_entries or
            state.pending_bytes > state.max_pending_bytes

        {flush?, state}
      end)

    if flush?, do: flush(pid), else: []
  end

  @spec flush(t()) :: [Message.t()]
  def flush(pid) when is_pid(pid) do
    state =
      Agent.get_and_update(pid, fn state ->
        {state, %{state | pending: [], pending_entries: 0, pending_bytes: 0}}
      end)

    state.pending
    |> coalesce_by_path()
    |> Enum.flat_map(fn {file_path, entries} ->
      flush_path(state, file_path, entries)
    end)
  end

  @spec close(t()) :: [Message.t()]
  def close(pid) when is_pid(pid), do: flush(pid)

  @spec message_from_error(Key.t() | nil, String.t()) :: Message.t()
  def message_from_error(key, error) do
    raw = %{
      "type" => "system",
      "subtype" => "mirror_error",
      "key" => if(key, do: Key.to_map(key), else: nil),
      "error" => error
    }

    %Message{
      type: :system,
      subtype: :mirror_error,
      data: %{subtype: :mirror_error, key: raw["key"], error: error, session_id: nil},
      raw: raw
    }
  end

  defp coalesce_by_path(items) do
    Enum.reduce(items, %{}, fn {file_path, entries}, acc ->
      Map.update(acc, file_path, entries, &(&1 ++ entries))
    end)
  end

  defp flush_path(_state, _file_path, []), do: []

  defp flush_path(state, file_path, entries) do
    case Summary.file_path_to_session_key(file_path, state.projects_dir) do
      nil ->
        []

      key ->
        case append_with_retries(state.store, key, entries, state.send_timeout_ms) do
          :ok -> []
          {:error, reason} -> [message_from_error(key, Exception.message(reason))]
        end
    end
  end

  defp append_with_retries(store, key, entries, timeout_ms) do
    append_with_retries(store, key, entries, timeout_ms, 1, nil)
  end

  defp append_with_retries(_store, _key, _entries, _timeout_ms, attempt, last_error)
       when attempt > @append_attempts do
    {:error, exception(last_error || :append_failed)}
  end

  defp append_with_retries(store, key, entries, timeout_ms, attempt, _last_error) do
    if attempt > 1 do
      Process.sleep(Enum.at(@backoff_ms, attempt - 2, 0))
    end

    task = Task.async(fn -> Adapter.append(store, key, entries) end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, :ok} ->
        :ok

      {:ok, {:error, reason}} ->
        append_with_retries(store, key, entries, timeout_ms, attempt + 1, reason)

      nil ->
        {:error, RuntimeError.exception("append timed out after #{timeout_ms}ms")}

      {:exit, reason} ->
        append_with_retries(store, key, entries, timeout_ms, attempt + 1, reason)
    end
  end

  defp exception(%_{} = exception), do: exception
  defp exception(reason), do: RuntimeError.exception(inspect(reason))
end
