defmodule ClaudeAgentSDK.SessionStore.Helpers do
  @moduledoc """
  Session helper APIs backed by a SessionStore adapter.
  """

  alias ClaudeAgentSDK.Session.{ForkResult, SessionMessage}
  alias ClaudeAgentSDK.SessionStore.{Adapter, Summary}

  @transcript_types ["user", "assistant", "progress", "system", "attachment"]

  @spec list_sessions_from_store(term(), keyword()) :: [ClaudeAgentSDK.Session.SessionInfo.t()]
  def list_sessions_from_store(store, opts \\ []) do
    project_key = project_key(opts)
    project_path = Keyword.get(opts, :directory)

    sessions =
      case Adapter.list_session_summaries(store, project_key) do
        {:ok, summaries} ->
          summaries
          |> Enum.map(&Summary.summary_entry_to_session_info(&1, project_path))
          |> Enum.reject(&is_nil/1)

        {:error, _reason} ->
          list_sessions_from_store_slow(store, project_key, project_path)
      end

    sessions
    |> Enum.sort_by(& &1.last_modified, :desc)
    |> apply_pagination(Keyword.get(opts, :limit), Keyword.get(opts, :offset, 0))
  end

  @spec get_session_info_from_store(String.t(), term(), keyword()) ::
          ClaudeAgentSDK.Session.SessionInfo.t() | nil
  def get_session_info_from_store(session_id, store, opts \\ []) do
    list_sessions_from_store(store, opts)
    |> Enum.find(&(&1.session_id == session_id))
    |> case do
      nil -> load_session_info(session_id, store, opts)
      info -> info
    end
  end

  @spec get_session_messages_from_store(String.t(), term(), keyword()) :: [SessionMessage.t()]
  def get_session_messages_from_store(session_id, store, opts \\ []) do
    key = %{project_key: project_key(opts), session_id: session_id}

    case Adapter.load(store, key) do
      {:ok, entries} when is_list(entries) ->
        entries
        |> visible_session_messages()
        |> apply_pagination(Keyword.get(opts, :limit), Keyword.get(opts, :offset, 0))

      _ ->
        []
    end
  end

  @spec list_subagents_from_store(String.t(), term(), keyword()) :: [String.t()]
  def list_subagents_from_store(session_id, store, opts \\ []) do
    key = %{project_key: project_key(opts), session_id: session_id}

    case Adapter.list_subkeys(store, key) do
      {:ok, subkeys} ->
        subkeys
        |> Enum.flat_map(&agent_id_from_subkey/1)
        |> Enum.sort()

      _ ->
        []
    end
  end

  @spec get_subagent_messages_from_store(String.t(), String.t(), term(), keyword()) :: [
          SessionMessage.t()
        ]
  def get_subagent_messages_from_store(session_id, agent_id, store, opts \\ []) do
    project_key = project_key(opts)

    key =
      case find_agent_subkey(session_id, agent_id, store, project_key) do
        nil -> nil
        subpath -> %{project_key: project_key, session_id: session_id, subpath: subpath}
      end

    case key && Adapter.load(store, key) do
      {:ok, entries} when is_list(entries) ->
        entries
        |> visible_session_messages()
        |> apply_pagination(Keyword.get(opts, :limit), Keyword.get(opts, :offset, 0))

      _ ->
        []
    end
  end

  @spec rename_session_via_store(String.t(), String.t(), term(), keyword()) ::
          :ok | {:error, term()}
  def rename_session_via_store(session_id, title, store, opts \\ []) do
    title = String.trim(title)

    cond do
      not valid_uuid?(session_id) ->
        {:error, :invalid_session_id}

      title == "" ->
        {:error, :empty_title}

      true ->
        append_metadata(store, session_id, opts, %{
          "type" => "custom-title",
          "customTitle" => title
        })
    end
  end

  @spec tag_session_via_store(String.t(), String.t() | nil, term(), keyword()) ::
          :ok | {:error, term()}
  def tag_session_via_store(session_id, tag, store, opts \\ []) do
    tag =
      if is_binary(tag) do
        tag
        |> String.normalize(:nfc)
        |> String.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/, "")
        |> String.trim()
      end

    cond do
      not valid_uuid?(session_id) -> {:error, :invalid_session_id}
      is_binary(tag) and tag == "" -> {:error, :empty_tag}
      true -> append_metadata(store, session_id, opts, %{"type" => "tag", "tag" => tag || ""})
    end
  end

  @spec delete_session_via_store(String.t(), term(), keyword()) :: :ok | {:error, term()}
  def delete_session_via_store(session_id, store, opts \\ []) do
    if valid_uuid?(session_id) do
      Adapter.delete(store, %{project_key: project_key(opts), session_id: session_id})
    else
      {:error, :invalid_session_id}
    end
  end

  @spec fork_session_via_store(String.t(), term(), keyword()) :: ForkResult.t() | {:error, term()}
  def fork_session_via_store(session_id, store, opts \\ []) do
    project_key = project_key(opts)
    source_key = %{project_key: project_key, session_id: session_id}

    with true <- valid_uuid?(session_id),
         {:ok, entries} when is_list(entries) and entries != [] <- Adapter.load(store, source_key) do
      new_session_id = Keyword.get(opts, :new_session_id) || generate_uuid_v4()
      up_to_message_id = Keyword.get(opts, :up_to_message_id)
      title = Keyword.get(opts, :title) || default_fork_title(entries)

      forked =
        entries
        |> slice_entries(up_to_message_id)
        |> remap_entries(session_id, new_session_id)
        |> Kernel.++([
          metadata_entry(new_session_id, %{"type" => "custom-title", "customTitle" => title})
        ])

      :ok = Adapter.append(store, %{project_key: project_key, session_id: new_session_id}, forked)

      %ForkResult{source_session_id: session_id, session_id: new_session_id, file_path: nil}
    else
      false -> {:error, :invalid_session_id}
      {:ok, _empty_or_nil} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp list_sessions_from_store_slow(store, project_key, project_path) do
    case Adapter.list_sessions(store, project_key) do
      {:ok, entries} ->
        entries
        |> Enum.map(fn entry ->
          session_id = map_value(entry, :session_id)
          mtime = map_value(entry, :mtime) || 0

          load_session_info(session_id, store,
            project_key: project_key,
            mtime: mtime,
            directory: project_path
          )
        end)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp load_session_info(session_id, store, opts) do
    project_key = Keyword.get(opts, :project_key) || project_key(opts)
    mtime = Keyword.get(opts, :mtime, System.system_time(:millisecond))

    case Adapter.load(store, %{project_key: project_key, session_id: session_id}) do
      {:ok, entries} when is_list(entries) ->
        Summary.entries_to_session_info(session_id, entries, mtime, Keyword.get(opts, :directory))

      _ ->
        nil
    end
  end

  defp visible_session_messages(entries) do
    entries
    |> Enum.filter(&visible_message?/1)
    |> Enum.map(&to_session_message/1)
  end

  defp visible_message?(entry) do
    map_value(entry, :type) in ["user", "assistant"] and
      not truthy?(map_value(entry, :isMeta)) and
      not truthy?(map_value(entry, :isSidechain)) and
      not truthy?(map_value(entry, :teamName))
  end

  defp to_session_message(entry) do
    %SessionMessage{
      type: map_value(entry, :type),
      uuid: map_value(entry, :uuid) || "",
      session_id: map_value(entry, :sessionId) || map_value(entry, :session_id) || "",
      message: map_value(entry, :message),
      parent_tool_use_id: nil
    }
  end

  defp append_metadata(store, session_id, opts, entry) do
    key = %{project_key: project_key(opts), session_id: session_id}
    Adapter.append(store, key, [metadata_entry(session_id, entry)])
  end

  defp metadata_entry(session_id, entry) do
    entry
    |> Map.put("sessionId", session_id)
    |> Map.put("uuid", generate_uuid_v4())
    |> Map.put(
      "timestamp",
      DateTime.utc_now() |> DateTime.truncate(:millisecond) |> DateTime.to_iso8601()
    )
  end

  defp project_key(opts) do
    Keyword.get(opts, :project_key) ||
      Summary.project_key_for_directory(Keyword.get(opts, :directory))
  end

  defp agent_id_from_subkey("subagents/" <> rest) do
    rest
    |> Path.basename()
    |> String.replace_prefix("agent-", "")
    |> case do
      "" -> []
      id -> [id]
    end
  end

  defp agent_id_from_subkey(_subkey), do: []

  defp find_agent_subkey(session_id, agent_id, store, project_key) do
    case Adapter.list_subkeys(store, %{project_key: project_key, session_id: session_id}) do
      {:ok, subkeys} -> Enum.find(subkeys, &(agent_id_from_subkey(&1) == [agent_id]))
      _ -> nil
    end
  end

  defp apply_pagination(messages, limit, offset) when is_integer(limit) and limit > 0 do
    messages |> Enum.drop(normalize_offset(offset)) |> Enum.take(limit)
  end

  defp apply_pagination(messages, _limit, offset),
    do: Enum.drop(messages, normalize_offset(offset))

  defp normalize_offset(offset) when is_integer(offset) and offset > 0, do: offset
  defp normalize_offset(_offset), do: 0

  defp slice_entries(entries, nil), do: entries

  defp slice_entries(entries, up_to_message_id) do
    case Enum.find_index(entries, &(map_value(&1, :uuid) == up_to_message_id)) do
      nil -> entries
      index -> Enum.take(entries, index + 1)
    end
  end

  defp remap_entries(entries, source_session_id, new_session_id) do
    uuid_map =
      entries
      |> Enum.flat_map(fn entry ->
        if map_value(entry, :type) in @transcript_types and is_binary(map_value(entry, :uuid)) do
          [{map_value(entry, :uuid), generate_uuid_v4()}]
        else
          []
        end
      end)
      |> Map.new()

    Enum.map(entries, fn entry ->
      entry
      |> maybe_replace("uuid", uuid_map[map_value(entry, :uuid)])
      |> maybe_replace("parentUuid", uuid_map[map_value(entry, :parentUuid)])
      |> Map.put("sessionId", new_session_id)
      |> Map.put("forkedFrom", %{
        "sessionId" => source_session_id,
        "uuid" => map_value(entry, :uuid)
      })
    end)
  end

  defp maybe_replace(entry, _key, nil), do: entry
  defp maybe_replace(entry, key, value), do: Map.put(entry, key, value)

  defp default_fork_title(entries) do
    title =
      entries
      |> Enum.reverse()
      |> Enum.find_value(&(map_value(&1, :customTitle) || map_value(&1, :aiTitle)))

    if title, do: title <> " (fork)", else: "Forked session"
  end

  defp map_value(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp map_value(_map, _key), do: nil

  defp truthy?(value), do: value in [true, "true", 1, "1"]

  defp valid_uuid?(value) when is_binary(value) do
    Regex.match?(~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i, value)
  end

  defp valid_uuid?(_value), do: false

  defp generate_uuid_v4 do
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)
    c = Bitwise.bor(Bitwise.band(c, 0x0FFF), 0x4000)
    d = Bitwise.bor(Bitwise.band(d, 0x3FFF), 0x8000)

    :io_lib.format("~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b", [a, b, c, d, e])
    |> IO.iodata_to_binary()
    |> String.downcase()
  end
end
