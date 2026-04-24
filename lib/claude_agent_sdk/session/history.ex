defmodule ClaudeAgentSDK.Session.History do
  @moduledoc """
  Read Claude CLI transcript history from on-disk JSONL files.

  This module mirrors the upstream Agent SDK session-history behavior:
  it reads `~/.claude/projects/<sanitized-cwd>/<session-id>.jsonl`,
  reconstructs the canonical conversation chain, and returns history metadata
  or visible user/assistant messages.
  """

  import Bitwise

  alias ClaudeAgentSDK.Config.Timeouts
  alias ClaudeAgentSDK.Session.{ForkResult, SessionInfo, SessionMessage}

  @lite_read_buf_size 65_536
  @max_sanitized_length 200
  @git_worktree_args ["worktree", "list", "--porcelain"]
  @git_worktree_env [{"GIT_PAGER", "cat"}, {"GIT_TERMINAL_PROMPT", "0"}]
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
    offset = Keyword.get(opts, :offset, 0)
    include_worktrees = Keyword.get(opts, :include_worktrees, true)
    projects_dir = Keyword.get(opts, :projects_dir, default_projects_dir())

    if is_binary(directory) and directory != "" do
      list_sessions_for_project(directory, limit, offset, include_worktrees, projects_dir)
    else
      list_all_sessions(limit, offset, projects_dir)
    end
  end

  @doc """
  Looks up metadata for a single CLI transcript session.
  """
  @spec get_session_info(String.t(), keyword()) :: SessionInfo.t() | nil
  def get_session_info(session_id, opts \\ [])

  def get_session_info(session_id, _opts) when not is_binary(session_id), do: nil

  def get_session_info(session_id, opts) do
    if valid_uuid?(session_id) do
      opts
      |> Keyword.put(:limit, nil)
      |> list_sessions()
      |> Enum.find(&(&1.session_id == session_id))
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

  @doc """
  Appends a custom title entry to a transcript.
  """
  @spec rename_session(String.t(), String.t(), keyword()) :: :ok
  def rename_session(session_id, title, opts \\ []) when is_binary(title) do
    title = title |> String.trim()

    if title == "" do
      raise ArgumentError, "title must be non-empty"
    end

    append_session_entry!(
      session_id,
      %{
        "type" => "custom-title",
        "customTitle" => title,
        "sessionId" => session_id
      },
      opts
    )
  end

  @doc """
  Appends a tag entry to a transcript. Passing `nil` clears the tag.
  """
  @spec tag_session(String.t(), String.t() | nil, keyword()) :: :ok
  def tag_session(session_id, tag, opts \\ [])

  def tag_session(session_id, nil, opts) do
    append_session_entry!(
      session_id,
      %{
        "type" => "tag",
        "tag" => "",
        "sessionId" => session_id
      },
      opts
    )
  end

  def tag_session(session_id, tag, opts) when is_binary(tag) do
    tag =
      tag
      |> sanitize_unicode()
      |> String.trim()

    if tag == "" do
      raise ArgumentError, "tag must be non-empty"
    end

    append_session_entry!(
      session_id,
      %{
        "type" => "tag",
        "tag" => tag,
        "sessionId" => session_id
      },
      opts
    )
  end

  @doc """
  Deletes a transcript and its sibling subagent transcript directory.
  """
  @spec delete_session(String.t(), keyword()) :: :ok
  def delete_session(session_id, opts \\ []) do
    file_path = find_existing_session_file!(session_id, opts)
    File.rm!(file_path)
    File.rm_rf!(Path.join(Path.dirname(file_path), session_id))
    :ok
  end

  @doc """
  Forks a transcript into a new session file.
  """
  @spec fork_session(String.t(), keyword()) :: ForkResult.t()
  def fork_session(session_id, opts \\ []) do
    file_path = find_existing_session_file!(session_id, opts)
    up_to_message_id = Keyword.get(opts, :up_to_message_id)

    if is_binary(up_to_message_id) and not valid_uuid?(up_to_message_id) do
      raise ArgumentError, "Invalid up_to_message_id"
    end

    entries =
      file_path
      |> File.read!()
      |> parse_transcript_entries()
      |> slice_entries_for_fork(up_to_message_id)

    new_session_id = Keyword.get(opts, :new_session_id, generate_uuid_v4())
    title = Keyword.get(opts, :title) || default_fork_title(session_id, opts)
    remapped_entries = remap_fork_entries(entries, session_id, new_session_id)

    new_file_path = Path.join(Path.dirname(file_path), "#{new_session_id}.jsonl")

    content =
      remapped_entries
      |> Kernel.++([
        %{
          "type" => "custom-title",
          "customTitle" => title,
          "sessionId" => new_session_id
        }
      ])
      |> Enum.map_join("\n", &Jason.encode!/1)
      |> Kernel.<>("\n")

    File.write!(new_file_path, content)

    %ForkResult{
      source_session_id: session_id,
      session_id: new_session_id,
      file_path: new_file_path
    }
  end

  @doc """
  Lists subagent IDs for a session.
  """
  @spec list_subagents(String.t(), keyword()) :: [String.t()]
  def list_subagents(session_id, opts \\ [])

  def list_subagents(session_id, _opts) when not is_binary(session_id), do: []

  def list_subagents(session_id, opts) do
    with true <- valid_uuid?(session_id),
         file_path when is_binary(file_path) <- find_session_file(session_id, opts),
         subagents_dir = Path.join([Path.dirname(file_path), session_id, "subagents"]),
         true <- File.dir?(subagents_dir) do
      subagents_dir
      |> agent_jsonl_files()
      |> Enum.map(&agent_id_from_path/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort()
    else
      _ -> []
    end
  end

  @doc """
  Reads visible messages from a subagent transcript.
  """
  @spec get_subagent_messages(String.t(), String.t(), keyword()) :: [SessionMessage.t()]
  def get_subagent_messages(session_id, agent_id, opts \\ [])

  def get_subagent_messages(session_id, agent_id, _opts)
      when not is_binary(session_id) or not is_binary(agent_id),
      do: []

  def get_subagent_messages(session_id, agent_id, opts) do
    with true <- valid_uuid?(session_id),
         true <- String.trim(agent_id) != "",
         file_path when is_binary(file_path) <- find_subagent_file(session_id, agent_id, opts),
         {:ok, content} <- File.read(file_path) do
      content
      |> parse_visible_session_messages()
      |> apply_pagination(Keyword.get(opts, :limit), Keyword.get(opts, :offset, 0))
    else
      _ -> []
    end
  end

  defp list_sessions_for_project(directory, limit, offset, include_worktrees, projects_dir) do
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
      |> apply_sort_and_limit(limit, offset)
    else
      read_worktree_sessions(canonical_dir, worktree_paths, projects_dir, limit, offset)
    end
  end

  defp read_worktree_sessions(canonical_dir, worktree_paths, projects_dir, limit, offset) do
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
    |> apply_sort_and_limit(limit, offset)
  end

  defp list_all_sessions(limit, offset, projects_dir) do
    projects_dir
    |> list_subdirs()
    |> Enum.flat_map(&read_sessions_from_dir/1)
    |> deduplicate_by_session_id()
    |> apply_sort_and_limit(limit, offset)
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

  defp append_session_entry!(session_id, entry, opts) do
    file_path = find_existing_session_file!(session_id, opts)
    File.write!(file_path, Jason.encode!(entry) <> "\n", [:append])
  end

  defp find_existing_session_file!(session_id, opts) do
    if not valid_uuid?(session_id) do
      raise ArgumentError, "Invalid session_id"
    end

    case find_session_file(session_id, opts) do
      path when is_binary(path) ->
        path

      nil ->
        raise File.Error,
          action: "find",
          path: "#{session_id}.jsonl",
          reason: :enoent
    end
  end

  defp find_session_file(session_id, opts) do
    directory = Keyword.get(opts, :directory)
    projects_dir = Keyword.get(opts, :projects_dir, default_projects_dir())
    file_name = "#{session_id}.jsonl"

    candidate_project_dirs(directory, projects_dir)
    |> Enum.find_value(fn project_dir ->
      path = Path.join(project_dir, file_name)

      if regular_nonempty_file?(path), do: path
    end)
  end

  defp candidate_project_dirs(directory, projects_dir)
       when is_binary(directory) and directory != "" do
    canonical_dir = canonicalize_path(directory)

    canonical_candidates =
      [find_project_dir(canonical_dir, projects_dir)] ++
        (canonical_dir
         |> get_worktree_paths()
         |> Enum.reject(&(&1 == canonical_dir))
         |> Enum.map(&find_project_dir(&1, projects_dir)))

    Enum.reject(canonical_candidates, &is_nil/1)
  end

  defp candidate_project_dirs(_directory, projects_dir), do: list_subdirs(projects_dir)

  defp regular_nonempty_file?(path) when is_binary(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular, size: size}} when size > 0 -> true
      _ -> false
    end
  end

  defp slice_entries_for_fork(entries, nil), do: entries

  defp slice_entries_for_fork(entries, up_to_message_id) when is_binary(up_to_message_id) do
    index = Enum.find_index(entries, &(&1["uuid"] == up_to_message_id))

    if is_nil(index) do
      raise ArgumentError, "up_to_message_id not found in session"
    else
      Enum.take(entries, index + 1)
    end
  end

  defp default_fork_title(session_id, opts) do
    case get_session_info(session_id, opts) do
      %SessionInfo{summary: summary} when is_binary(summary) and summary != "" ->
        "#{summary} (fork)"

      _ ->
        "Fork of #{session_id}"
    end
  end

  defp remap_fork_entries(entries, source_session_id, new_session_id) do
    uuid_map =
      entries
      |> Enum.filter(&(is_binary(&1["uuid"]) and &1["uuid"] != ""))
      |> Map.new(fn entry -> {entry["uuid"], generate_uuid_v4()} end)

    Enum.map(entries, fn entry ->
      original_uuid = entry["uuid"]

      entry
      |> Map.put("sessionId", new_session_id)
      |> Map.delete("session_id")
      |> maybe_remap_uuid("uuid", uuid_map)
      |> maybe_remap_uuid("parentUuid", uuid_map)
      |> Map.drop(["teamName", "agentName", "slug"])
      |> maybe_put_forked_from(source_session_id, original_uuid)
    end)
  end

  defp maybe_remap_uuid(entry, key, uuid_map) do
    case Map.get(entry, key) do
      uuid when is_binary(uuid) -> Map.put(entry, key, Map.get(uuid_map, uuid, uuid))
      _ -> entry
    end
  end

  defp maybe_put_forked_from(entry, source_session_id, original_uuid)
       when is_binary(original_uuid) do
    if entry["type"] in ["user", "assistant"] do
      Map.put(entry, "forkedFrom", %{"sessionId" => source_session_id, "uuid" => original_uuid})
    else
      entry
    end
  end

  defp maybe_put_forked_from(entry, _source_session_id, _original_uuid), do: entry

  defp find_subagent_file(session_id, agent_id, opts) do
    with file_path when is_binary(file_path) <- find_session_file(session_id, opts),
         subagents_dir = Path.join([Path.dirname(file_path), session_id, "subagents"]),
         true <- File.dir?(subagents_dir) do
      subagents_dir
      |> agent_jsonl_files()
      |> Enum.find(&(agent_id_from_path(&1) == agent_id))
    else
      _ -> nil
    end
  end

  defp agent_jsonl_files(subagents_dir) do
    Path.wildcard(Path.join([subagents_dir, "**", "agent-*.jsonl"]))
  end

  defp agent_id_from_path(path) do
    basename = Path.basename(path)

    if String.starts_with?(basename, "agent-") and String.ends_with?(basename, ".jsonl") do
      basename
      |> String.replace_prefix("agent-", "")
      |> String.replace_suffix(".jsonl", "")
      |> case do
        "" -> nil
        id -> id
      end
    else
      nil
    end
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
        tag = extract_last_json_string_field(lite.tail, "tag")
        created_at = extract_created_at(lite.head)

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
            tag: blank_to_nil(tag),
            created_at: created_at,
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
    opts = [directory: directory, projects_dir: projects_dir]

    case find_session_file(session_id, opts) do
      path when is_binary(path) -> File.read!(path)
      nil -> nil
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

  defp apply_sort_and_limit(sessions, limit, offset) do
    sorted = Enum.sort_by(sessions, & &1.last_modified, :desc)
    offset = if is_integer(offset) and offset > 0, do: offset, else: 0
    sorted = Enum.drop(sorted, offset)

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

  defp extract_created_at(head) when is_binary(head) do
    head
    |> first_line()
    |> decode_timestamp_ms()
  end

  defp decode_timestamp_ms(line) when is_binary(line) do
    with {:ok, %{"timestamp" => timestamp}} when is_binary(timestamp) <- Jason.decode(line),
         {:ok, datetime, _offset} <- DateTime.from_iso8601(normalize_iso8601(timestamp)) do
      DateTime.to_unix(datetime, :millisecond)
    else
      _ -> nil
    end
  end

  defp normalize_iso8601(timestamp) do
    if Regex.match?(~r/(Z|[+-]\d\d:\d\d)$/, timestamp) do
      timestamp
    else
      timestamp <> "Z"
    end
  end

  @doc false
  @spec sanitize_unicode(String.t()) :: String.t()
  def sanitize_unicode(value) when is_binary(value) do
    value
    |> String.normalize(:nfkc)
    |> String.replace(
      ~r/[\x{200B}-\x{200D}\x{FEFF}\x{202A}-\x{202E}\x{2066}-\x{2069}\x{E000}-\x{F8FF}]/u,
      ""
    )
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

  defp generate_uuid_v4 do
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)
    c = bor(band(c, 0x0FFF), 0x4000)
    d = bor(band(d, 0x3FFF), 0x8000)

    [
      Base.encode16(<<a::32>>, case: :lower),
      Base.encode16(<<b::16>>, case: :lower),
      Base.encode16(<<c::16>>, case: :lower),
      Base.encode16(<<d::16>>, case: :lower),
      Base.encode16(<<e::48>>, case: :lower)
    ]
    |> Enum.join("-")
  end

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
    case system_cmd_with_timeout(
           "git",
           @git_worktree_args,
           cd: cwd,
           env: @git_worktree_env,
           stderr_to_stdout: true
         ) do
      {:ok, {output, 0}} ->
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

  defp system_cmd_with_timeout(command, args, opts)
       when is_binary(command) and is_list(args) and is_list(opts) do
    caller = self()
    ref = make_ref()
    timeout_ms = Timeouts.session_git_worktree_ms()

    {:ok, pid} =
      Task.start(fn ->
        result =
          try do
            {:ok, System.cmd(command, args, opts)}
          rescue
            error -> {:error, error}
          catch
            kind, reason -> {kind, reason}
          end

        send(caller, {ref, result})
      end)

    receive do
      {^ref, {:ok, result}} ->
        {:ok, result}

      {^ref, _other} ->
        {:error, :command_failed}
    after
      timeout_ms ->
        Process.exit(pid, :kill)
        {:error, :timeout}
    end
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
