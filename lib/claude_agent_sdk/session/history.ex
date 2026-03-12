defmodule ClaudeAgentSDK.Session.History do
  @moduledoc """
  Read Claude CLI transcript history from on-disk JSONL files.

  This module mirrors the upstream Agent SDK session-history behavior:
  it reads `~/.claude/projects/<sanitized-cwd>/<session-id>.jsonl`,
  reconstructs the canonical conversation chain, and returns history metadata
  or visible user/assistant messages.
  """

  import Bitwise

  alias ClaudeAgentSDK.Session.{SessionInfo, SessionMessage}

  @lite_read_buf_size 65_536
  @max_sanitized_length 200
  @uuid_pattern ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
  @transcript_entry_types ["user", "assistant", "progress", "system", "attachment"]
  @skip_first_prompt_pattern ~r/^(?:<local-command-stdout>|<session-start-hook>|<tick>|<goal>|\[Request interrupted by user[^\]]*\]|\s*<ide_opened_file>[\s\S]*<\/ide_opened_file>\s*$|\s*<ide_selection>[\s\S]*<\/ide_selection>\s*$)/
  @command_name_pattern ~r/<command-name>(.*?)<\/command-name>/

  @typedoc false
  @type transcript_entry :: map()

  @doc """
  Sanitizes a project path to the directory format used by Claude CLI.
  """
  @spec sanitize_path(String.t()) :: String.t()
  def sanitize_path(path) when is_binary(path) do
    sanitized = String.replace(path, ~r/[^a-zA-Z0-9]/, "-")

    if String.length(sanitized) <= @max_sanitized_length do
      sanitized
    else
      "#{String.slice(sanitized, 0, @max_sanitized_length)}-#{simple_hash(path)}"
    end
  end

  @doc """
  Produces the same base-36 hash used by the upstream session-storage logic.
  """
  @spec simple_hash(String.t()) :: String.t()
  def simple_hash(input) when is_binary(input) do
    input
    |> String.to_charlist()
    |> Enum.reduce(0, fn char, acc ->
      hash = band(bsl(acc, 5) - acc + char, 0xFFFFFFFF)
      if hash >= 0x80000000, do: hash - 0x100000000, else: hash
    end)
    |> abs()
    |> Integer.to_string(36)
    |> String.downcase()
  end

  @doc """
  Lists CLI transcript sessions.

  Options:
  - `:directory` - project path to scan
  - `:limit` - max number of sessions to return
  - `:include_worktrees` - include git worktree transcript directories (default: `true`)
  - `:projects_dir` - override the Claude projects directory (primarily for tests)
  """
  @spec list_sessions(keyword()) :: [SessionInfo.t()]
  def list_sessions(opts \\ []) do
    directory = Keyword.get(opts, :directory)
    limit = Keyword.get(opts, :limit)
    include_worktrees = Keyword.get(opts, :include_worktrees, true)
    projects_dir = Keyword.get(opts, :projects_dir, default_projects_dir())

    if is_binary(directory) and directory != "" do
      list_sessions_for_project(directory, limit, include_worktrees, projects_dir)
    else
      list_all_sessions(limit, projects_dir)
    end
  end

  @doc """
  Reads visible conversation messages from a CLI transcript.

  Options:
  - `:directory` - project path to search in
  - `:limit` - max number of messages to return
  - `:offset` - number of messages to skip from the start
  - `:projects_dir` - override the Claude projects directory (primarily for tests)
  """
  @spec get_session_messages(String.t(), keyword()) :: [SessionMessage.t()]
  def get_session_messages(session_id, opts \\ [])

  def get_session_messages(session_id, _opts) when not is_binary(session_id), do: []

  def get_session_messages(session_id, opts) do
    if valid_uuid?(session_id) do
      directory = Keyword.get(opts, :directory)
      projects_dir = Keyword.get(opts, :projects_dir, default_projects_dir())
      limit = Keyword.get(opts, :limit)
      offset = Keyword.get(opts, :offset, 0)

      session_id
      |> read_session_file(directory, projects_dir)
      |> parse_visible_session_messages()
      |> apply_pagination(limit, offset)
    else
      []
    end
  end

  defp list_sessions_for_project(directory, limit, include_worktrees, projects_dir) do
    canonical_dir = canonicalize_path(directory)

    worktree_paths =
      if include_worktrees do
        get_worktree_paths(canonical_dir)
      else
        []
      end

    if length(worktree_paths) <= 1 do
      canonical_dir
      |> find_project_dir(projects_dir)
      |> read_sessions_from_project_dir(canonical_dir)
      |> apply_sort_and_limit(limit)
    else
      read_worktree_sessions(canonical_dir, worktree_paths, projects_dir, limit)
    end
  end

  defp read_worktree_sessions(canonical_dir, worktree_paths, projects_dir, limit) do
    case_insensitive? = windows?()
    indexed_worktrees = index_worktrees(worktree_paths, case_insensitive?)

    project_dirs = list_subdirs(projects_dir)
    seen_dirs = %{}

    {all_sessions, seen_dirs} =
      case find_project_dir(canonical_dir, projects_dir) do
        nil ->
          {[], seen_dirs}

        project_dir ->
          dir_name = maybe_downcase(Path.basename(project_dir), case_insensitive?)
          sessions = read_sessions_from_project_dir(project_dir, canonical_dir)
          {sessions, Map.put(seen_dirs, dir_name, true)}
      end

    sessions =
      Enum.reduce(project_dirs, all_sessions, fn project_dir, acc ->
        dir_name = maybe_downcase(Path.basename(project_dir), case_insensitive?)

        if Map.has_key?(seen_dirs, dir_name) do
          acc
        else
          maybe_read_worktree_sessions(project_dir, indexed_worktrees, case_insensitive?) ++ acc
        end
      end)

    sessions
    |> deduplicate_by_session_id()
    |> apply_sort_and_limit(limit)
  end

  defp list_all_sessions(limit, projects_dir) do
    projects_dir
    |> list_subdirs()
    |> Enum.flat_map(&read_sessions_from_dir/1)
    |> deduplicate_by_session_id()
    |> apply_sort_and_limit(limit)
  end

  defp read_sessions_from_project_dir(nil, _project_path), do: []

  defp read_sessions_from_project_dir(project_dir, project_path),
    do: read_sessions_from_dir(project_dir, project_path)

  defp read_sessions_from_dir(project_dir, project_path \\ nil) do
    project_dir
    |> list_files()
    |> Enum.flat_map(fn file_path ->
      file_path
      |> session_file_id()
      |> maybe_read_session_info(file_path, project_path)
    end)
  end

  defp maybe_build_session_info(session_id, %{head: head} = lite, project_path)
       when is_binary(head) do
    first_line = first_line(head)

    if String.contains?(first_line, "\"isSidechain\":true") or
         String.contains?(first_line, "\"isSidechain\": true") do
      []
    else
      custom_title = extract_last_json_string_field(lite.tail, "customTitle")
      first_prompt = blank_to_nil(extract_first_prompt_from_head(lite.head))

      summary =
        custom_title || extract_last_json_string_field(lite.tail, "summary") || first_prompt

      if is_binary(summary) and summary != "" do
        git_branch =
          extract_last_json_string_field(lite.tail, "gitBranch") ||
            extract_json_string_field(lite.head, "gitBranch")

        cwd = extract_json_string_field(lite.head, "cwd") || project_path

        [
          %SessionInfo{
            session_id: session_id,
            summary: summary,
            last_modified: lite.mtime,
            file_size: lite.size,
            custom_title: blank_to_nil(custom_title),
            first_prompt: first_prompt,
            git_branch: blank_to_nil(git_branch),
            cwd: blank_to_nil(cwd),
            project_path: blank_to_nil(cwd)
          }
        ]
      else
        []
      end
    end
  end

  defp read_session_lite(file_path) do
    case File.open(file_path, [:read, :binary]) do
      {:ok, file} ->
        try do
          build_session_lite(file_path, file)
        after
          File.close(file)
        end

      _ ->
        nil
    end
  end

  defp read_session_file(session_id, directory, projects_dir) do
    file_name = "#{session_id}.jsonl"

    if is_binary(directory) and directory != "" do
      read_session_file_for_directory(directory, file_name, projects_dir)
    else
      projects_dir
      |> list_subdirs()
      |> Enum.find_value(&try_read_session_file(&1, file_name))
    end
  end

  defp read_session_file_from_worktrees(canonical_dir, file_name, projects_dir) do
    canonical_dir
    |> get_worktree_paths()
    |> Enum.reject(&(&1 == canonical_dir))
    |> Enum.find_value(fn worktree_path ->
      worktree_path
      |> find_project_dir(projects_dir)
      |> try_read_session_file(file_name)
    end)
  end

  defp try_read_session_file(nil, _file_name), do: nil

  defp try_read_session_file(project_dir, file_name) do
    case File.read(Path.join(project_dir, file_name)) do
      {:ok, content} -> content
      _ -> nil
    end
  end

  defp parse_visible_session_messages(nil), do: []
  defp parse_visible_session_messages(""), do: []

  defp parse_visible_session_messages(content) do
    content
    |> parse_transcript_entries()
    |> build_conversation_chain()
    |> Enum.filter(&visible_message?/1)
    |> Enum.map(&to_session_message/1)
  end

  defp parse_transcript_entries(content) do
    content
    |> String.split("\n", trim: true)
    |> Enum.reduce([], fn line, acc ->
      case decode_transcript_entry(line) do
        nil -> acc
        entry -> [entry | acc]
      end
    end)
    |> Enum.reverse()
  end

  @doc false
  @spec build_conversation_chain([transcript_entry()]) :: [transcript_entry()]
  def build_conversation_chain([]), do: []

  def build_conversation_chain(entries) do
    by_uuid = Map.new(entries, &{&1["uuid"], &1})

    entry_index =
      entries |> Enum.with_index() |> Map.new(fn {entry, index} -> {entry["uuid"], index} end)

    parent_uuids =
      entries
      |> Enum.reduce(%{}, fn entry, acc ->
        case entry["parentUuid"] do
          parent when is_binary(parent) and parent != "" -> Map.put(acc, parent, true)
          _ -> acc
        end
      end)

    terminals = Enum.reject(entries, &Map.has_key?(parent_uuids, &1["uuid"]))

    leaves =
      terminals
      |> Enum.reduce([], fn terminal, acc ->
        case nearest_visible_leaf(terminal, by_uuid) do
          nil -> acc
          leaf -> [leaf | acc]
        end
      end)
      |> Enum.reverse()

    case pick_chain_leaf(leaves, entry_index) do
      nil -> []
      leaf -> build_chain_from_leaf(leaf, by_uuid)
    end
  end

  defp nearest_visible_leaf(start_entry, by_uuid) do
    walk_to_leaf(start_entry, by_uuid, %{})
  end

  defp walk_to_leaf(nil, _by_uuid, _seen), do: nil

  defp walk_to_leaf(%{"uuid" => uuid} = entry, by_uuid, seen) do
    cond do
      Map.has_key?(seen, uuid) ->
        nil

      entry["type"] in ["user", "assistant"] ->
        entry

      true ->
        parent = entry["parentUuid"]
        next = if is_binary(parent) and parent != "", do: Map.get(by_uuid, parent), else: nil
        walk_to_leaf(next, by_uuid, Map.put(seen, uuid, true))
    end
  end

  defp pick_chain_leaf([], _entry_index), do: nil

  defp pick_chain_leaf(leaves, entry_index) do
    main_leaves =
      Enum.reject(leaves, fn leaf ->
        truthy?(leaf["isSidechain"]) or truthy?(leaf["teamName"]) or truthy?(leaf["isMeta"])
      end)

    candidates = if main_leaves == [], do: leaves, else: main_leaves

    Enum.max_by(candidates, fn leaf -> Map.get(entry_index, leaf["uuid"], -1) end)
  end

  defp build_chain_from_leaf(leaf, by_uuid) do
    walk_chain(leaf, by_uuid, %{}, [])
  end

  defp walk_chain(nil, _by_uuid, _seen, acc), do: acc

  defp walk_chain(%{"uuid" => uuid} = entry, by_uuid, seen, acc) do
    if Map.has_key?(seen, uuid) do
      acc
    else
      parent = entry["parentUuid"]
      next = if is_binary(parent) and parent != "", do: Map.get(by_uuid, parent), else: nil
      walk_chain(next, by_uuid, Map.put(seen, uuid, true), [entry | acc])
    end
  end

  defp visible_message?(entry) do
    entry["type"] in ["user", "assistant"] and
      not truthy?(entry["isMeta"]) and
      not truthy?(entry["isSidechain"]) and
      not truthy?(entry["teamName"])
  end

  defp to_session_message(entry) do
    %SessionMessage{
      type: entry["type"],
      uuid: entry["uuid"] || "",
      session_id: entry["sessionId"] || entry["session_id"] || "",
      message: entry["message"],
      parent_tool_use_id: nil
    }
  end

  defp apply_pagination(messages, limit, offset) when is_integer(limit) and limit > 0 do
    messages |> Enum.drop(offset) |> Enum.take(limit)
  end

  defp apply_pagination(messages, _limit, offset) when is_integer(offset) and offset > 0 do
    Enum.drop(messages, offset)
  end

  defp apply_pagination(messages, _limit, _offset), do: messages

  defp deduplicate_by_session_id(sessions) do
    sessions
    |> Enum.reduce(%{}, fn session, acc ->
      case Map.get(acc, session.session_id) do
        nil ->
          Map.put(acc, session.session_id, session)

        existing when existing.last_modified < session.last_modified ->
          Map.put(acc, session.session_id, session)

        _existing ->
          acc
      end
    end)
    |> Map.values()
  end

  defp apply_sort_and_limit(sessions, limit) do
    sorted = Enum.sort_by(sessions, & &1.last_modified, :desc)

    if is_integer(limit) and limit > 0 do
      Enum.take(sorted, limit)
    else
      sorted
    end
  end

  defp extract_first_prompt_from_head(head) when is_binary(head) do
    {result, fallback} =
      head
      |> String.split("\n", trim: true)
      |> Enum.reduce_while({nil, ""}, &next_first_prompt_state/2)

    result || fallback || ""
  end

  defp extract_prompt_candidate(%{"content" => content}, fallback) do
    texts = content_texts(content)

    Enum.reduce_while(texts, {nil, fallback}, fn raw, {result, command_fallback} ->
      raw
      |> normalize_prompt_text()
      |> next_prompt_candidate(result, command_fallback)
    end)
  end

  defp extract_prompt_candidate(_message, fallback), do: {nil, fallback}

  defp truncate_prompt(prompt) when byte_size(prompt) > 200 do
    String.slice(prompt, 0, 200) |> String.trim_trailing() |> Kernel.<>("…")
  end

  defp truncate_prompt(prompt), do: prompt

  defp extract_json_string_field(text, key) do
    Enum.find_value(["\"#{key}\":\"", "\"#{key}\": \""], fn pattern ->
      case String.split(text, pattern, parts: 2) do
        [_prefix, suffix] -> extract_json_string_value(suffix)
        _ -> nil
      end
    end)
  end

  defp extract_last_json_string_field(text, key) do
    Enum.reduce(["\"#{key}\":\"", "\"#{key}\": \""], nil, fn pattern, last_value ->
      text
      |> String.split(pattern)
      |> tl_or_empty()
      |> Enum.reduce(last_value, fn suffix, acc ->
        extract_json_string_value(suffix) || acc
      end)
    end)
  end

  defp extract_json_string_value(suffix) do
    suffix
    |> String.to_charlist()
    |> extract_json_string_chars([])
    |> case do
      nil ->
        nil

      chars ->
        chars
        |> Enum.reverse()
        |> List.to_string()
        |> unescape_json_string()
    end
  end

  defp extract_json_string_chars([], _acc), do: nil

  defp extract_json_string_chars([?\\, char | rest], acc) do
    extract_json_string_chars(rest, [char, ?\\ | acc])
  end

  defp extract_json_string_chars([?" | _rest], acc), do: acc

  defp extract_json_string_chars([char | rest], acc),
    do: extract_json_string_chars(rest, [char | acc])

  defp unescape_json_string(value) do
    case Jason.decode("\"#{value}\"") do
      {:ok, decoded} when is_binary(decoded) -> decoded
      _ -> value
    end
  end

  defp tl_or_empty([]), do: []
  defp tl_or_empty([_head | tail]), do: tail

  defp find_project_dir(project_path, projects_dir) when is_binary(project_path) do
    exact = Path.join(projects_dir, sanitize_path(project_path))

    if File.dir?(exact) do
      exact
    else
      find_truncated_project_dir(project_path, projects_dir)
    end
  end

  defp find_project_dir(_project_path, _projects_dir), do: nil

  defp maybe_read_worktree_sessions(project_dir, indexed_worktrees, case_insensitive?) do
    case matching_worktree(project_dir, indexed_worktrees, case_insensitive?) do
      nil -> []
      {worktree_path, _prefix} -> read_sessions_from_dir(project_dir, worktree_path)
    end
  end

  defp session_file_id(file_path) do
    session_id = Path.basename(file_path, ".jsonl")

    if Path.extname(file_path) == ".jsonl" and valid_uuid?(session_id) do
      session_id
    end
  end

  defp maybe_read_session_info(nil, _file_path, _project_path), do: []

  defp maybe_read_session_info(session_id, file_path, project_path) do
    case read_session_lite(file_path) do
      nil -> []
      lite -> maybe_build_session_info(session_id, lite, project_path)
    end
  end

  defp build_session_lite(file_path, file) do
    with {:ok, %File.Stat{size: size, mtime: mtime}} <- File.stat(file_path, time: :posix),
         head when is_binary(head) and head != "" <- IO.binread(file, @lite_read_buf_size) do
      case read_session_tail(file, size, head) do
        tail when is_binary(tail) ->
          %{
            size: size,
            mtime: mtime * 1_000,
            head: head,
            tail: tail
          }

        _ ->
          nil
      end
    else
      _ -> nil
    end
  end

  defp read_session_tail(_file, size, head) when size <= @lite_read_buf_size, do: head

  defp read_session_tail(file, size, _head) do
    {:ok, _position} = :file.position(file, {:bof, max(size - @lite_read_buf_size, 0)})
    IO.binread(file, @lite_read_buf_size)
  end

  defp read_session_file_for_directory(directory, file_name, projects_dir) do
    canonical_dir = canonicalize_path(directory)

    try_read_session_file(find_project_dir(canonical_dir, projects_dir), file_name) ||
      read_session_file_from_worktrees(canonical_dir, file_name, projects_dir)
  end

  defp decode_transcript_entry(line) do
    case Jason.decode(line) do
      {:ok, %{} = entry} -> maybe_transcript_entry(entry)
      _ -> nil
    end
  end

  defp maybe_transcript_entry(%{"type" => type, "uuid" => uuid} = entry)
       when is_binary(uuid) do
    if type in @transcript_entry_types do
      entry
    end
  end

  defp maybe_transcript_entry(_entry), do: nil

  defp next_first_prompt_state(line, state) do
    if skip_prompt_line?(line) do
      {:cont, state}
    else
      {_result, fallback} = state

      line
      |> decode_prompt_message(fallback)
      |> merge_prompt_state(state)
    end
  end

  defp skip_prompt_line?(line) do
    not user_prompt_line?(line) or
      String.contains?(line, "\"tool_result\"") or
      String.contains?(line, "\"isMeta\":true") or
      String.contains?(line, "\"isMeta\": true") or
      String.contains?(line, "\"isCompactSummary\":true") or
      String.contains?(line, "\"isCompactSummary\": true")
  end

  defp user_prompt_line?(line) do
    String.contains?(line, "\"type\":\"user\"") or
      String.contains?(line, "\"type\": \"user\"")
  end

  defp decode_prompt_message(line, fallback) do
    case Jason.decode(line) do
      {:ok, %{"type" => "user", "message" => %{} = message}} ->
        extract_prompt_candidate(message, fallback)

      _ ->
        nil
    end
  end

  defp merge_prompt_state(nil, {result, fallback}), do: {:cont, {result, fallback}}

  defp merge_prompt_state({maybe_result, maybe_fallback}, {result, fallback}) do
    if is_binary(maybe_result) and maybe_result != "" do
      {:halt, {maybe_result, maybe_fallback}}
    else
      {:cont, {result, maybe_fallback || fallback}}
    end
  end

  defp content_texts(content) when is_binary(content), do: [content]

  defp content_texts(content) when is_list(content) do
    Enum.flat_map(content, fn
      %{"type" => "text", "text" => text} when is_binary(text) -> [text]
      _ -> []
    end)
  end

  defp content_texts(_content), do: []

  defp normalize_prompt_text(raw) do
    raw
    |> String.replace("\n", " ")
    |> String.trim()
  end

  defp next_prompt_candidate("", result, command_fallback),
    do: {:cont, {result, command_fallback}}

  defp next_prompt_candidate(cleaned, result, command_fallback) do
    case classify_prompt_text(cleaned) do
      {:command_name, command} ->
        {:cont, {result, update_command_fallback(command_fallback, command)}}

      :skip ->
        {:cont, {result, command_fallback}}

      :prompt ->
        {:halt, {truncate_prompt(cleaned), command_fallback}}
    end
  end

  defp classify_prompt_text(cleaned) do
    case Regex.run(@command_name_pattern, cleaned, capture: :all_but_first) do
      [command] -> {:command_name, command}
      _ -> maybe_prompt_text(cleaned)
    end
  end

  defp maybe_prompt_text(cleaned) do
    if Regex.match?(@skip_first_prompt_pattern, cleaned) do
      :skip
    else
      :prompt
    end
  end

  defp update_command_fallback("", command), do: command
  defp update_command_fallback(command_fallback, _command), do: command_fallback

  defp find_truncated_project_dir(project_path, projects_dir) do
    sanitized = sanitize_path(project_path)

    if String.length(sanitized) <= @max_sanitized_length do
      nil
    else
      prefix = String.slice(sanitized, 0, @max_sanitized_length)
      find_project_dir_by_prefix(projects_dir, prefix)
    end
  end

  defp find_project_dir_by_prefix(projects_dir, prefix) do
    projects_dir
    |> list_subdirs()
    |> Enum.find(&String.starts_with?(Path.basename(&1), prefix <> "-"))
  end

  defp matching_worktree(project_dir, indexed_worktrees, case_insensitive?) do
    dir_name = maybe_downcase(Path.basename(project_dir), case_insensitive?)

    Enum.find(indexed_worktrees, fn {_worktree_path, prefix} ->
      dir_name == prefix or
        (String.length(prefix) >= @max_sanitized_length and
           String.starts_with?(dir_name, prefix <> "-"))
    end)
  end

  defp index_worktrees(worktree_paths, case_insensitive?) do
    worktree_paths
    |> Enum.map(fn worktree_path ->
      sanitized = worktree_path |> sanitize_path() |> maybe_downcase(case_insensitive?)
      {worktree_path, sanitized}
    end)
    |> Enum.sort_by(fn {_worktree_path, prefix} -> String.length(prefix) end, :desc)
  end

  defp get_worktree_paths(cwd) do
    case System.cmd("git", ["worktree", "list", "--porcelain"],
           cd: cwd,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.flat_map(fn
          "worktree " <> path -> [normalize_nfc(path)]
          _ -> []
        end)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  defp default_projects_dir do
    Path.join(claude_config_home_dir(), "projects")
  end

  defp claude_config_home_dir do
    case System.get_env("CLAUDE_CONFIG_DIR") do
      nil -> Path.join(System.user_home!(), ".claude") |> normalize_nfc()
      config_dir -> normalize_nfc(config_dir)
    end
  end

  defp canonicalize_path(directory) do
    directory
    |> Path.expand()
    |> normalize_nfc()
  end

  defp normalize_nfc(value) when is_binary(value), do: String.normalize(value, :nfc)

  defp list_subdirs(path) do
    path
    |> list_entries()
    |> Enum.map(&Path.join(path, &1))
    |> Enum.filter(&File.dir?/1)
  end

  defp list_files(path) do
    path
    |> list_entries()
    |> Enum.map(&Path.join(path, &1))
    |> Enum.filter(&File.regular?/1)
  end

  defp list_entries(path) do
    case File.ls(path) do
      {:ok, entries} -> entries
      _ -> []
    end
  end

  defp first_line(text) do
    case String.split(text, "\n", parts: 2) do
      [line | _] -> line
      _ -> text
    end
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp maybe_downcase(value, true), do: String.downcase(value)
  defp maybe_downcase(value, false), do: value

  defp valid_uuid?(value) when is_binary(value), do: Regex.match?(@uuid_pattern, value)
  defp valid_uuid?(_value), do: false

  defp truthy?(value), do: not is_nil(value) and value != false
  defp windows?, do: match?({:win32, _}, :os.type())
end
