defmodule ClaudeAgentSDK.Transport.AgentsFile do
  @moduledoc false

  alias ClaudeAgentSDK.Log, as: Logger

  @windows_cmd_length_limit 8_000
  @default_cmd_length_limit 100_000
  @temp_file_prefix "claude_agent_sdk_agents_"
  @default_temp_file_max_age_seconds 86_400

  @spec externalize_agents_if_needed([String.t()]) :: {[String.t()], [String.t()]}
  def externalize_agents_if_needed(args) when is_list(args) do
    externalize_agents_if_needed(args, [])
  end

  @spec externalize_agents_if_needed([String.t()], keyword()) :: {[String.t()], [String.t()]}
  def externalize_agents_if_needed(args, opts) when is_list(args) and is_list(opts) do
    cleanup_stale_temp_files(opts)

    cmd_length = args |> Enum.join(" ") |> String.length()

    if cmd_length > cmd_length_limit(opts) do
      maybe_externalize_agents_arg(args)
    else
      {args, []}
    end
  end

  @spec cleanup_temp_files([String.t()]) :: :ok
  def cleanup_temp_files(paths) when is_list(paths) do
    Enum.each(paths, fn path ->
      _ = File.rm(path)
    end)

    :ok
  end

  defp cmd_length_limit(opts) do
    case Keyword.get(opts, :agents_cmd_length_limit) do
      limit when is_integer(limit) and limit > 0 ->
        limit

      _ ->
        Application.get_env(:claude_agent_sdk, :agents_cmd_length_limit, default_limit())
    end
  end

  defp default_limit do
    if match?({:win32, _}, :os.type()) do
      @windows_cmd_length_limit
    else
      @default_cmd_length_limit
    end
  end

  defp maybe_externalize_agents_arg(args) do
    case Enum.find_index(args, &(&1 == "--agents")) do
      nil ->
        {args, []}

      agents_idx ->
        case Enum.at(args, agents_idx + 1) do
          "@" <> _path ->
            {args, []}

          value when is_binary(value) ->
            path = write_temp_agents_file(value)
            {List.replace_at(args, agents_idx + 1, "@#{path}"), [path]}

          _other ->
            {args, []}
        end
    end
  rescue
    e ->
      Logger.warning("Failed to externalize agents file: #{Exception.message(e)}")
      {args, []}
  end

  defp write_temp_agents_file(contents) when is_binary(contents) do
    filename = "#{@temp_file_prefix}#{System.unique_integer([:positive])}.json"
    path = Path.join(System.tmp_dir!(), filename)
    File.write!(path, contents)
    path
  end

  defp cleanup_stale_temp_files(opts) do
    tmp_dir = System.tmp_dir!()
    max_age_seconds = temp_file_max_age_seconds(opts)
    now = System.system_time(:second)

    with {:ok, entries} <- File.ls(tmp_dir) do
      entries
      |> Enum.filter(&String.starts_with?(&1, @temp_file_prefix))
      |> Enum.each(fn entry ->
        path = Path.join(tmp_dir, entry)
        maybe_cleanup_stale_file(path, now, max_age_seconds)
      end)
    end
  end

  defp maybe_cleanup_stale_file(path, now, max_age_seconds) do
    case File.stat(path, time: :posix) do
      {:ok, %{mtime: mtime}} when is_integer(mtime) ->
        if max_age_seconds <= 0 or now - mtime >= max_age_seconds do
          _ = File.rm(path)
        end

      _ ->
        :ok
    end
  end

  defp temp_file_max_age_seconds(opts) do
    case Keyword.get(opts, :agents_temp_file_max_age_seconds) do
      age when is_integer(age) and age >= 0 ->
        age

      _ ->
        Application.get_env(
          :claude_agent_sdk,
          :agents_temp_file_max_age_seconds,
          @default_temp_file_max_age_seconds
        )
    end
  end
end
