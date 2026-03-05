defmodule ClaudeAgentSDK.Session.History do
  @moduledoc """
  Read Claude Code session history from on-disk JSONL files.

  Claude Code stores conversation history in `~/.claude/projects/<sanitized-cwd>/<uuid>.jsonl`.
  This module reads those files for session listing and message retrieval.
  """

  alias ClaudeAgentSDK.Session.SessionInfo

  @uuid_pattern ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
  @max_path_length 200

  @doc """
  Sanitizes a filesystem path for use as a directory name.

  Replaces non-alphanumeric characters with hyphens.
  Truncates long paths and appends a hash suffix.
  """
  @spec sanitize_path(String.t()) :: String.t()
  def sanitize_path(path) do
    sanitized = String.replace(path, ~r/[^a-zA-Z0-9]/, "-")

    if String.length(sanitized) > @max_path_length do
      truncated = String.slice(sanitized, 0, @max_path_length)
      "#{truncated}-#{simple_hash(path)}"
    else
      sanitized
    end
  end

  @doc """
  Produces a simple base-36 hash of a string.

  Used for generating deterministic short suffixes for truncated paths.
  """
  @spec simple_hash(String.t()) :: String.t()
  def simple_hash(input) do
    input
    |> String.to_charlist()
    |> Enum.reduce(0, fn char, acc -> rem(acc * 33 + char, 2_147_483_647) end)
    |> abs()
    |> Integer.to_string(36)
    |> String.downcase()
  end

  @doc """
  Lists sessions across all project directories.

  ## Options

  - `:projects_dir` - Base directory (default: `~/.claude/projects`)
  - `:directory` - Filter to a specific project directory name (or nil for all)
  - `:limit` - Maximum number of sessions to return
  """
  @spec list_sessions(keyword()) :: [SessionInfo.t()]
  def list_sessions(opts \\ []) do
    projects_dir = Keyword.get(opts, :projects_dir, default_projects_dir())
    limit = Keyword.get(opts, :limit)

    sessions =
      projects_dir
      |> find_jsonl_files()
      |> Enum.map(&parse_session_file/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(& &1.last_modified, :desc)

    if limit, do: Enum.take(sessions, limit), else: sessions
  end

  @doc """
  Gets parsed messages from a session file.

  ## Options

  - `:projects_dir` - Base directory (default: `~/.claude/projects`)
  - `:limit` - Maximum messages to return
  - `:offset` - Number of messages to skip
  """
  @spec get_session_messages(String.t(), keyword()) :: [map()]
  def get_session_messages(session_id, opts \\ [])

  def get_session_messages(session_id, _opts) when not is_binary(session_id), do: []

  def get_session_messages(session_id, opts) do
    if Regex.match?(@uuid_pattern, session_id) do
      do_get_session_messages(session_id, opts)
    else
      []
    end
  end

  defp do_get_session_messages(session_id, opts) do
    projects_dir = Keyword.get(opts, :projects_dir, default_projects_dir())
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)

    case find_session_file(projects_dir, session_id) do
      nil ->
        []

      path ->
        path
        |> read_jsonl_messages()
        |> Enum.reject(&filtered_message?/1)
        |> apply_pagination(offset, limit)
    end
  end

  defp default_projects_dir do
    Path.join([System.user_home!(), ".claude", "projects"])
  end

  defp find_jsonl_files(projects_dir) do
    projects_dir
    |> list_dir()
    |> Enum.flat_map(&list_jsonl_in_dir(projects_dir, &1))
  end

  defp list_jsonl_in_dir(base, entry) do
    dir = Path.join(base, entry)

    dir
    |> list_dir()
    |> Enum.filter(&String.ends_with?(&1, ".jsonl"))
    |> Enum.map(&Path.join(dir, &1))
  end

  defp list_dir(path) do
    case File.ls(path) do
      {:ok, entries} -> entries
      _ -> []
    end
  end

  defp parse_session_file(path) do
    filename = Path.basename(path, ".jsonl")

    if Regex.match?(@uuid_pattern, filename) do
      build_session_info(path, filename)
    end
  end

  defp build_session_info(path, session_id) do
    with {:ok, stat} <- File.stat(path),
         {:ok, metadata} <- read_session_metadata(path) do
      %SessionInfo{
        session_id: session_id,
        project_path: Path.dirname(path),
        first_prompt: metadata.first_prompt,
        custom_title: metadata.custom_title,
        summary: metadata.custom_title || metadata.first_prompt,
        file_size: stat.size,
        last_modified: to_unix_seconds(stat.mtime)
      }
    else
      _ -> nil
    end
  end

  defp read_session_metadata(path) do
    with {:ok, content} <- File.read(path),
         lines <- content |> String.split("\n") |> Enum.filter(&(&1 != "")),
         true <- lines != [],
         {:ok, first} <- Jason.decode(hd(lines)),
         false <- first["isSidechain"] == true do
      first_prompt = extract_first_prompt(first)
      custom_title = extract_custom_title(List.last(lines))
      {:ok, %{first_prompt: first_prompt, custom_title: custom_title}}
    else
      _ -> :skip
    end
  end

  defp extract_first_prompt(%{"message" => %{"content" => content}}) when is_binary(content) do
    content
  end

  defp extract_first_prompt(%{"message" => %{"content" => [%{"text" => text} | _]}}) do
    text
  end

  defp extract_first_prompt(_), do: nil

  defp extract_custom_title(line) do
    case Jason.decode(line) do
      {:ok, %{"customTitle" => title}} when is_binary(title) -> title
      _ -> nil
    end
  end

  defp find_session_file(projects_dir, session_id) do
    filename = "#{session_id}.jsonl"

    projects_dir
    |> list_dir()
    |> Enum.find_value(fn entry ->
      path = Path.join([projects_dir, entry, filename])
      if File.exists?(path), do: path
    end)
  end

  defp read_jsonl_messages(path) do
    case File.read(path) do
      {:ok, content} -> parse_jsonl_content(content)
      _ -> []
    end
  end

  defp parse_jsonl_content(content) do
    content
    |> String.split("\n")
    |> Enum.filter(&(&1 != ""))
    |> Enum.flat_map(&decode_jsonl_line/1)
  end

  defp decode_jsonl_line(line) do
    case Jason.decode(line) do
      {:ok, parsed} -> [struct_from_raw(parsed)]
      _ -> []
    end
  end

  defp struct_from_raw(raw) do
    %{
      type: raw["type"],
      uuid: raw["uuid"],
      session_id: raw["sessionId"],
      parent_uuid: raw["parentUuid"],
      message: raw["message"],
      is_meta: raw["isMeta"],
      is_sidechain: raw["isSidechain"]
    }
  end

  defp filtered_message?(%{is_meta: true}), do: true
  defp filtered_message?(%{is_sidechain: true}), do: true
  defp filtered_message?(_), do: false

  defp apply_pagination(messages, offset, nil), do: Enum.drop(messages, offset)

  defp apply_pagination(messages, offset, limit) do
    messages |> Enum.drop(offset) |> Enum.take(limit)
  end

  defp to_unix_seconds({{y, mo, d}, {h, mi, s}}) do
    NaiveDateTime.new!(y, mo, d, h, mi, s)
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_unix()
  end
end
