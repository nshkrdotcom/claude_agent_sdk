defmodule ClaudeAgentSDK.SessionStore.Import do
  @moduledoc """
  Imports local Claude JSONL session transcripts into a SessionStore adapter.
  """

  alias ClaudeAgentSDK.SessionStore.{Adapter, MirrorBatcher, Summary}

  @max_pending_bytes MirrorBatcher.max_pending_bytes()

  @spec import_session(String.t(), term(), keyword()) :: :ok | {:error, term()}
  def import_session(session_id, store, opts \\ []) when is_binary(session_id) do
    with :ok <- validate_uuid(session_id),
         {:ok, file_path} <- find_session_file(session_id, opts),
         :ok <- import_main_session(file_path, session_id, store, opts) do
      maybe_import_subagents(file_path, session_id, store, opts)
    end
  end

  defp import_main_session(file_path, session_id, store, opts) do
    project_key = Path.basename(Path.dirname(file_path))
    batch_size = Keyword.get(opts, :batch_size, MirrorBatcher.max_pending_entries())
    main_key = %{project_key: project_key, session_id: session_id}
    append_jsonl_file(file_path, main_key, store, batch_size)
  end

  defp maybe_import_subagents(file_path, session_id, store, opts) do
    if Keyword.get(opts, :include_subagents, true) do
      project_key = Path.basename(Path.dirname(file_path))
      batch_size = Keyword.get(opts, :batch_size, MirrorBatcher.max_pending_entries())
      import_subagents(file_path, project_key, session_id, store, batch_size)
    else
      :ok
    end
  end

  defp find_session_file(session_id, opts) do
    projects_dir =
      Keyword.get(opts, :projects_dir) ||
        Path.join(
          System.get_env("CLAUDE_CONFIG_DIR") || Path.join(System.user_home!(), ".claude"),
          "projects"
        )

    candidate_dirs =
      case Keyword.get(opts, :directory) do
        nil ->
          Path.wildcard(Path.join(projects_dir, "*"))

        directory ->
          [Path.join(projects_dir, Summary.project_key_for_directory(directory))]
      end

    candidate_dirs
    |> Enum.map(&Path.join(&1, "#{session_id}.jsonl"))
    |> Enum.find(&File.regular?/1)
    |> case do
      nil -> {:error, :not_found}
      path -> {:ok, path}
    end
  end

  defp append_jsonl_file(path, key, store, batch_size) do
    path
    |> File.stream!(:line, [])
    |> Enum.reduce_while({[], 0}, &append_jsonl_line(&1, &2, key, store, batch_size))
    |> flush_remaining_batch(key, store)
  rescue
    exception -> {:error, exception}
  end

  defp append_jsonl_line(line, {batch, bytes}, key, store, batch_size) do
    line = String.trim_trailing(line, "\n")

    if line == "" do
      {:cont, {batch, bytes}}
    else
      line
      |> add_line_to_batch(batch, bytes)
      |> maybe_flush_batch(key, store, batch_size)
    end
  end

  defp add_line_to_batch(line, batch, bytes) do
    {batch ++ [Jason.decode!(line)], bytes + byte_size(line)}
  end

  defp maybe_flush_batch({batch, bytes}, key, store, batch_size) do
    if length(batch) >= batch_size or bytes >= @max_pending_bytes do
      case Adapter.append(store, key, batch) do
        :ok -> {:cont, {[], 0}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    else
      {:cont, {batch, bytes}}
    end
  end

  defp flush_remaining_batch({:error, reason}, _key, _store), do: {:error, reason}
  defp flush_remaining_batch({[], _bytes}, _key, _store), do: :ok
  defp flush_remaining_batch({batch, _bytes}, key, store), do: Adapter.append(store, key, batch)

  defp import_subagents(file_path, project_key, session_id, store, batch_size) do
    subagents_dir = Path.join([Path.dirname(file_path), session_id, "subagents"])

    subagents_dir
    |> Path.join("**/*.jsonl")
    |> Path.wildcard()
    |> Enum.reduce_while(:ok, fn sub_path, :ok ->
      session_dir = Path.join(Path.dirname(file_path), session_id)
      rel = Path.relative_to(sub_path, session_dir)
      subpath = String.replace_suffix(rel, ".jsonl", "")
      key = %{project_key: project_key, session_id: session_id, subpath: subpath}

      with :ok <- append_jsonl_file(sub_path, key, store, batch_size),
           :ok <- import_meta(sub_path, key, store) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp import_meta(sub_path, key, store) do
    meta_path = String.replace_suffix(sub_path, ".jsonl", ".meta.json")

    case File.read(meta_path) do
      {:ok, json} ->
        meta = Jason.decode!(json) |> Map.put("type", "agent_metadata")
        Adapter.append(store, key, [meta])

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_uuid(session_id) do
    if Regex.match?(
         ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
         session_id
       ) do
      :ok
    else
      {:error, :invalid_session_id}
    end
  end
end
