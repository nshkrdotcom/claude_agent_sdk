defmodule ClaudeAgentSDK.SessionStore.Summary do
  @moduledoc """
  Incremental summary folding for SessionStore adapters.
  """

  alias ClaudeAgentSDK.Session.History
  alias ClaudeAgentSDK.Session.SessionInfo
  alias ClaudeAgentSDK.SessionStore.Key

  @skip_first_prompt_pattern ~r/^(?:<local-command-stdout>|<session-start-hook>|<tick>|<goal>|\[Request interrupted by user[^\]]*\]|\s*<ide_opened_file>[\s\S]*<\/ide_opened_file>\s*$|\s*<ide_selection>[\s\S]*<\/ide_selection>\s*$)/
  @command_name_pattern ~r/<command-name>(.*?)<\/command-name>/
  @last_wins_fields %{
    "customTitle" => :custom_title,
    "aiTitle" => :ai_title,
    "lastPrompt" => :last_prompt,
    "summary" => :summary_hint,
    "gitBranch" => :git_branch
  }

  @doc """
  Derives the store `project_key` for a directory using the same path
  sanitization as local Claude transcript directories.
  """
  @spec project_key_for_directory(String.t() | nil) :: String.t()
  def project_key_for_directory(directory \\ nil) do
    (directory || ".")
    |> Path.expand()
    |> String.normalize(:nfc)
    |> History.sanitize_path()
  end

  @doc """
  Converts a local Claude transcript path into a SessionStore key.
  """
  @spec file_path_to_session_key(String.t(), String.t()) :: Key.t() | nil
  def file_path_to_session_key(file_path, projects_dir)
      when is_binary(file_path) and is_binary(projects_dir) do
    file_path = Path.expand(file_path)
    projects_dir = Path.expand(projects_dir)
    rel = Path.relative_to(file_path, projects_dir)

    cond do
      rel == file_path -> nil
      String.starts_with?(rel, "..") -> nil
      Path.type(rel) == :absolute -> nil
      true -> rel |> Path.split() |> parts_to_key()
    end
  end

  @doc """
  Folds appended transcript entries into an opaque summary sidecar.
  """
  @spec fold_session_summary(map() | nil, Key.input(), [map()]) :: map()
  def fold_session_summary(prev, key, entries) when is_list(entries) do
    key = Key.new!(key)

    summary =
      if is_map(prev) do
        %{
          session_id: value(prev, :session_id),
          mtime: value(prev, :mtime) || 0,
          data: Map.new(value(prev, :data) || %{})
        }
      else
        %{session_id: key.session_id, mtime: 0, data: %{}}
      end

    data =
      Enum.reduce(entries, summary.data, fn entry, acc ->
        entry = normalize_entry(entry)
        ms = iso_to_epoch_ms(value(entry, :timestamp))

        acc
        |> put_once(:is_sidechain, truthy?(value(entry, :isSidechain)))
        |> put_if_absent(:created_at, ms)
        |> put_if_absent(:cwd, nonempty_string(value(entry, :cwd)))
        |> fold_first_prompt(entry)
        |> fold_last_wins(entry)
        |> fold_tag(entry)
      end)

    %{summary | data: data}
  end

  @doc """
  Converts a folded summary into `ClaudeAgentSDK.Session.SessionInfo`.
  """
  @spec summary_entry_to_session_info(map(), String.t() | nil) :: SessionInfo.t() | nil
  def summary_entry_to_session_info(entry, project_path \\ nil) when is_map(entry) do
    data = value(entry, :data) || %{}

    if truthy?(value(data, :is_sidechain)),
      do: nil,
      else: build_session_info(entry, data, project_path)
  end

  defp build_session_info(entry, data, project_path) do
    first_prompt = summary_first_prompt(data)
    custom_title = value(data, :custom_title) || value(data, :ai_title)

    summary =
      custom_title || value(data, :last_prompt) || value(data, :summary_hint) || first_prompt

    if nonempty_binary?(summary) do
      %SessionInfo{
        session_id: value(entry, :session_id),
        summary: summary,
        last_modified: value(entry, :mtime) || 0,
        file_size: nil,
        custom_title: custom_title,
        first_prompt: first_prompt,
        git_branch: value(data, :git_branch),
        cwd: value(data, :cwd) || project_path,
        project_path: project_path,
        tag: value(data, :tag),
        created_at: value(data, :created_at)
      }
    end
  end

  defp summary_first_prompt(data) do
    if truthy?(value(data, :first_prompt_locked)),
      do: value(data, :first_prompt),
      else: value(data, :command_fallback)
  end

  defp nonempty_binary?(value), do: is_binary(value) and value != ""

  @doc false
  @spec entries_to_jsonl([map()]) :: String.t()
  def entries_to_jsonl(entries) do
    entries
    |> Enum.map_join("\n", fn entry ->
      entry
      |> type_first()
      |> Jason.encode!()
    end)
    |> Kernel.<>("\n")
  end

  @doc false
  @spec entries_to_session_info(String.t(), [map()], integer(), String.t() | nil) ::
          SessionInfo.t() | nil
  def entries_to_session_info(session_id, entries, mtime, project_path \\ nil) do
    %{session_id: session_id}
    |> Map.merge(%{mtime: mtime, data: %{}})
    |> fold_session_summary(%{project_key: "_", session_id: session_id}, entries)
    |> Map.put(:mtime, mtime)
    |> summary_entry_to_session_info(project_path)
  end

  defp parts_to_key([project_key, file_name]) do
    if String.ends_with?(file_name, ".jsonl") do
      %Key{project_key: project_key, session_id: String.replace_suffix(file_name, ".jsonl", "")}
    end
  end

  defp parts_to_key([project_key, session_id | subpath_parts]) when length(subpath_parts) >= 2 do
    subpath_parts =
      List.update_at(subpath_parts, -1, fn last ->
        String.replace_suffix(last, ".jsonl", "")
      end)

    %Key{project_key: project_key, session_id: session_id, subpath: Enum.join(subpath_parts, "/")}
  end

  defp parts_to_key(_parts), do: nil

  defp normalize_entry(entry) when is_map(entry), do: entry
  defp normalize_entry(_entry), do: %{}

  defp value(map, key) when is_map(map) and is_atom(key),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp value(map, key) when is_map(map) and is_binary(key), do: Map.get(map, key)

  defp iso_to_epoch_ms(value) when is_binary(value) do
    value
    |> normalize_iso8601()
    |> DateTime.from_iso8601()
    |> case do
      {:ok, datetime, _offset} -> DateTime.to_unix(datetime, :millisecond)
      _ -> nil
    end
  end

  defp iso_to_epoch_ms(_value), do: nil

  defp normalize_iso8601(value) do
    if String.ends_with?(value, "Z") or Regex.match?(~r/[+-]\d\d:\d\d$/, value) do
      value
    else
      value <> "Z"
    end
  end

  defp put_once(data, key, value) do
    if Map.has_key?(data, key), do: data, else: Map.put(data, key, value)
  end

  defp put_if_absent(data, _key, nil), do: data

  defp put_if_absent(data, key, value) do
    if Map.has_key?(data, key), do: data, else: Map.put(data, key, value)
  end

  defp nonempty_string(value) when is_binary(value) and value != "", do: value
  defp nonempty_string(_value), do: nil

  defp fold_last_wins(data, entry) do
    Enum.reduce(@last_wins_fields, data, fn {source, dest}, acc ->
      case value(entry, source) do
        val when is_binary(val) -> Map.put(acc, dest, val)
        _ -> acc
      end
    end)
  end

  defp fold_tag(data, entry) do
    if value(entry, :type) == "tag" do
      case value(entry, :tag) do
        tag when is_binary(tag) and tag != "" -> Map.put(data, :tag, tag)
        _ -> Map.delete(data, :tag)
      end
    else
      data
    end
  end

  defp fold_first_prompt(%{first_prompt_locked: true} = data, _entry), do: data

  defp fold_first_prompt(data, entry) do
    cond do
      value(entry, :type) != "user" ->
        data

      truthy?(value(entry, :isMeta)) or truthy?(value(entry, :isCompactSummary)) ->
        data

      contains_tool_result?(entry) ->
        data

      true ->
        entry
        |> entry_text_blocks()
        |> Enum.reduce_while(data, &next_first_prompt_state/2)
    end
  end

  defp contains_tool_result?(entry) do
    case value(value(entry, :message) || %{}, :content) do
      blocks when is_list(blocks) ->
        Enum.any?(blocks, &(is_map(&1) and value(&1, :type) == "tool_result"))

      _ ->
        false
    end
  end

  defp entry_text_blocks(entry) do
    message = value(entry, :message) || %{}

    case value(message, :content) do
      content when is_binary(content) ->
        [content]

      content when is_list(content) ->
        content
        |> Enum.filter(
          &(is_map(&1) and value(&1, :type) == "text" and is_binary(value(&1, :text)))
        )
        |> Enum.map(&value(&1, :text))

      _ ->
        []
    end
  end

  defp next_first_prompt_state(raw, data) do
    result = raw |> String.replace("\n", " ") |> String.trim()

    cond do
      result == "" ->
        {:cont, data}

      command = Regex.run(@command_name_pattern, result, capture: :all_but_first) ->
        [name] = command
        {:cont, Map.put_new(data, :command_fallback, name)}

      Regex.match?(@skip_first_prompt_pattern, result) ->
        {:cont, data}

      true ->
        prompt =
          if String.length(result) > 200, do: String.slice(result, 0, 200) <> "...", else: result

        {:halt, data |> Map.put(:first_prompt, prompt) |> Map.put(:first_prompt_locked, true)}
    end
  end

  defp truthy?(value), do: value in [true, "true", 1, "1"]

  defp type_first(entry) when is_map(entry) do
    case value(entry, :type) do
      nil -> entry
      type -> Map.put(Map.delete(Map.delete(entry, :type), "type"), "type", type)
    end
  end
end
