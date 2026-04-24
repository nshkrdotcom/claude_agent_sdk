defmodule ClaudeAgentSDK.SessionStore.Resume do
  @moduledoc """
  Materializes SessionStore-backed resume data into a temporary Claude config dir.
  """

  alias ClaudeAgentSDK.Options
  alias ClaudeAgentSDK.SessionStore.{Adapter, Summary}

  defstruct [:config_dir, :resume_session_id]

  @type t :: %__MODULE__{config_dir: String.t(), resume_session_id: String.t()}

  @spec materialize(Options.t()) :: {:ok, t() | nil} | {:error, term()}
  def materialize(%Options{session_store: nil}), do: {:ok, nil}

  def materialize(%Options{} = options) do
    cond do
      is_binary(options.resume) ->
        materialize_session(options, options.resume)

      options.continue_conversation ->
        resolve_continue(options)

      true ->
        {:ok, nil}
    end
  end

  @spec apply_options(Options.t(), t() | nil) :: Options.t()
  def apply_options(%Options{} = options, nil), do: options

  def apply_options(%Options{} = options, %__MODULE__{} = materialized) do
    env =
      options.env
      |> Kernel.||(%{})
      |> Map.put("CLAUDE_CONFIG_DIR", materialized.config_dir)

    %{options | env: env, resume: materialized.resume_session_id, continue_conversation: false}
  end

  @spec cleanup(t() | nil) :: :ok
  def cleanup(nil), do: :ok

  def cleanup(%__MODULE__{config_dir: config_dir}),
    do: File.rm_rf(config_dir) |> then(fn _ -> :ok end)

  defp resolve_continue(%Options{} = options) do
    project_key = Summary.project_key_for_directory(options.cwd)

    case Adapter.list_sessions(options.session_store, project_key) do
      {:ok, sessions} ->
        sessions
        |> Enum.sort_by(&entry_mtime/1, :desc)
        |> Enum.find_value(&continue_candidate(options.session_store, project_key, &1))
        |> materialize_continue_candidate(options, project_key)

      {:error, :not_implemented} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp continue_candidate(store, project_key, session) do
    session_id = entry_session_id(session)

    if valid_uuid?(session_id) do
      load_continue_candidate(store, project_key, session_id)
    end
  end

  defp load_continue_candidate(store, project_key, session_id) do
    case Adapter.load(store, %{project_key: project_key, session_id: session_id}) do
      {:ok, [first | _] = entries} ->
        if sidechain?(first), do: nil, else: {session_id, entries}

      _other ->
        nil
    end
  end

  defp materialize_continue_candidate(nil, _options, _project_key), do: {:ok, nil}

  defp materialize_continue_candidate({session_id, entries}, options, project_key) do
    write_materialized(options, project_key, session_id, entries)
  end

  defp materialize_session(%Options{} = options, session_id) do
    if valid_uuid?(session_id) do
      project_key = Summary.project_key_for_directory(options.cwd)

      case Adapter.load(options.session_store, %{project_key: project_key, session_id: session_id}) do
        {:ok, entries} when is_list(entries) and entries != [] ->
          write_materialized(options, project_key, session_id, entries)

        {:ok, _empty_or_nil} ->
          {:ok, nil}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:ok, nil}
    end
  end

  defp write_materialized(%Options{} = options, project_key, session_id, entries) do
    tmp_dir = Path.join(System.tmp_dir!(), "claude-resume-#{System.unique_integer([:positive])}")

    try do
      project_dir = Path.join([tmp_dir, "projects", project_key])
      File.mkdir_p!(project_dir)
      write_jsonl(Path.join(project_dir, "#{session_id}.jsonl"), entries)
      copy_auth_files(tmp_dir, options.env || %{})
      materialize_subkeys(options.session_store, tmp_dir, project_dir, project_key, session_id)
      {:ok, %__MODULE__{config_dir: tmp_dir, resume_session_id: session_id}}
    rescue
      exception ->
        File.rm_rf(tmp_dir)
        {:error, exception}
    end
  end

  defp materialize_subkeys(store, tmp_dir, project_dir, project_key, session_id) do
    key = %{project_key: project_key, session_id: session_id}

    case Adapter.list_subkeys(store, key) do
      {:ok, subkeys} ->
        subkeys
        |> Enum.filter(&safe_subpath?/1)
        |> Enum.each(&write_subkey(store, tmp_dir, project_dir, project_key, session_id, &1))

      {:error, _reason} ->
        :ok
    end
  end

  defp write_subkey(store, _tmp_dir, project_dir, project_key, session_id, subpath) do
    key = %{project_key: project_key, session_id: session_id, subpath: subpath}

    with {:ok, entries} when is_list(entries) and entries != [] <- Adapter.load(store, key) do
      {metadata, transcript} =
        Enum.split_with(
          entries,
          &(is_map(&1) and (Map.get(&1, "type") || Map.get(&1, :type)) == "agent_metadata")
        )

      sub_file = Path.join([project_dir, session_id, subpath <> ".jsonl"])

      if transcript != [] do
        write_jsonl(sub_file, transcript)
      end

      case List.last(metadata) do
        nil ->
          :ok

        meta ->
          meta =
            meta
            |> Map.delete("type")
            |> Map.delete(:type)

          meta_file = String.replace_suffix(sub_file, ".jsonl", ".meta.json")
          File.mkdir_p!(Path.dirname(meta_file))
          File.write!(meta_file, Jason.encode!(meta))
          File.chmod(meta_file, 0o600)
      end
    end
  end

  defp write_jsonl(path, entries) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Summary.entries_to_jsonl(entries))
    File.chmod(path, 0o600)
  end

  defp copy_auth_files(tmp_dir, env) do
    config_dir = Map.get(env, "CLAUDE_CONFIG_DIR") || System.get_env("CLAUDE_CONFIG_DIR")
    source_config_dir = config_dir || Path.join(System.user_home!(), ".claude")

    copy_if_present(
      Path.join(source_config_dir, ".credentials.json"),
      Path.join(tmp_dir, ".credentials.json"),
      &redact_credentials/1
    )

    claude_json =
      if config_dir do
        Path.join(config_dir, ".claude.json")
      else
        Path.join(System.user_home!(), ".claude.json")
      end

    copy_if_present(claude_json, Path.join(tmp_dir, ".claude.json"), & &1)
  end

  defp copy_if_present(src, dst, transform) do
    case File.read(src) do
      {:ok, content} ->
        File.write!(dst, transform.(content))
        File.chmod(dst, 0o600)

      {:error, _reason} ->
        :ok
    end
  end

  defp redact_credentials(content) do
    case Jason.decode(content) do
      {:ok, %{"claudeAiOauth" => oauth} = data} when is_map(oauth) ->
        data
        |> put_in(["claudeAiOauth"], Map.delete(oauth, "refreshToken"))
        |> Jason.encode!()

      _ ->
        content
    end
  end

  defp safe_subpath?(subpath) when is_binary(subpath) and subpath != "" do
    not String.starts_with?(subpath, ["/", "\\"]) and
      not String.contains?(subpath, ["..", "\\", <<0>>])
  end

  defp safe_subpath?(_subpath), do: false

  defp entry_session_id(entry), do: Map.get(entry, :session_id) || Map.get(entry, "session_id")
  defp entry_mtime(entry), do: Map.get(entry, :mtime) || Map.get(entry, "mtime") || 0

  defp sidechain?(entry),
    do: (Map.get(entry, :isSidechain) || Map.get(entry, "isSidechain")) in [true, "true", 1, "1"]

  defp valid_uuid?(value) when is_binary(value) do
    Regex.match?(~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i, value)
  end

  defp valid_uuid?(_value), do: false
end
