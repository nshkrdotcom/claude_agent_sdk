defmodule ClaudeAgentSDK.Process do
  @moduledoc """
  Handles spawning and communicating with the Claude Code CLI process using erlexec.

  This module manages the lifecycle of Claude CLI subprocess execution:
  - Starting the CLI process with proper arguments
  - Capturing and parsing JSON output from stdout/stderr
  - Converting the output into a stream of `ClaudeAgentSDK.Message` structs
  - Handling errors and cleanup

  The module uses erlexec's synchronous execution mode to capture all output
  at once, then converts it to a lazy stream for consumption.
  """

  require Logger

  alias ClaudeAgentSDK.{CLI, Message, Options}
  alias ClaudeAgentSDK.Transport.AgentsFile

  @doc """
  Streams messages from Claude Code CLI using erlexec.

  ## Parameters

  - `args` - List of command-line arguments for the Claude CLI
  - `options` - Configuration options (see `t:ClaudeAgentSDK.Options.t/0`)

  ## Returns

  A stream of `t:ClaudeAgentSDK.Message.t/0` structs.

  ## Examples

      ClaudeAgentSDK.Process.stream(["--print", "Hello"], %ClaudeAgentSDK.Options{})

  """
  @spec stream([String.t()], Options.t(), String.t() | nil) ::
          Enumerable.t(ClaudeAgentSDK.Message.t())
  def stream(args, %Options{} = options, stdin_input \\ nil) do
    # Check if we should use mock
    if use_mock?() do
      ClaudeAgentSDK.Mock.Process.stream(args, options, stdin_input)
    else
      stream_real(args, options, stdin_input)
    end
  end

  defp use_mock? do
    # Check LIVE_MODE environment variable first (set by mix run.live)
    # This overrides the Application config (even when MIX_ENV=test)
    case {System.get_env("LIVE_MODE"), System.get_env("LIVE_TESTS")} do
      {"true", _} -> false
      {_, "true"} -> false
      _ -> Application.get_env(:claude_agent_sdk, :use_mock, false)
    end
  end

  defp stream_real(args, options, stdin_input) do
    Stream.resource(
      fn -> start_claude_process(args, options, stdin_input) end,
      &receive_messages/1,
      &cleanup_process/1
    )
  end

  defp start_claude_process(args, options, stdin_input) do
    ensure_erlexec_started!()
    {cmd, temp_files} = build_claude_command(args, options, stdin_input)

    case validate_cwd(options.cwd, temp_files) do
      {:error, error_state} ->
        error_state

      :ok ->
        exec_options = build_exec_options(options)
        start_exec(cmd, exec_options, options, stdin_input, temp_files)
    end
  end

  defp ensure_erlexec_started! do
    case Application.ensure_all_started(:erlexec) do
      {:ok, _} -> :ok
      {:error, reason} -> raise "Failed to start erlexec application: #{inspect(reason)}"
    end
  end

  defp validate_cwd(cwd, temp_files) when is_binary(cwd) do
    if File.dir?(cwd) do
      :ok
    else
      {:error, cwd_not_found_state(cwd, temp_files)}
    end
  end

  defp validate_cwd(_cwd, _temp_files), do: :ok

  defp cwd_not_found_state(cwd, temp_files) do
    error =
      %ClaudeAgentSDK.Errors.CLIConnectionError{
        message: "Working directory does not exist: #{cwd}",
        cwd: cwd,
        reason: :cwd_not_found
      }

    error_msg = %Message{
      type: :result,
      subtype: :error_during_execution,
      data: %{
        error: Exception.message(error),
        error_struct: error,
        session_id: "error",
        is_error: true
      }
    }

    %{
      mode: :error,
      messages: [error_msg],
      current_index: 0,
      done: false,
      temp_files: temp_files
    }
  end

  defp start_exec(cmd, exec_options, options, nil, temp_files) do
    case :exec.run(cmd, exec_options) do
      {:ok, result} ->
        %{
          mode: :sync,
          result: result,
          messages: parse_sync_result(result),
          current_index: 0,
          done: false,
          temp_files: temp_files
        }

      {:error, reason} ->
        Logger.error("Failed to start Claude CLI (sync run)",
          cmd: cmd,
          reason: reason,
          env_keys: env_keys(exec_options)
        )

        formatted_error = format_error_message(reason, options)
        error_msg = process_error_message(formatted_error, reason)

        %{
          mode: :error,
          messages: [error_msg],
          current_index: 0,
          done: false,
          temp_files: temp_files
        }
    end
  end

  defp start_exec(cmd, exec_options, options, input, temp_files) when is_binary(input) do
    run_with_stdin_erlexec(cmd, input, exec_options, options, temp_files)
  end

  defp run_with_stdin_erlexec(cmd, input, _exec_options, options, temp_files) do
    # Add stdin to the exec options and use async execution
    # Build fresh options with env vars for async mode
    env_vars = build_env_vars(options)

    stdin_exec_options =
      [:stdin, :stdout, :stderr, :monitor]
      |> maybe_put_env_option(env_vars)
      |> maybe_put_user_option(options.user)
      |> maybe_put_cd_option(options.cwd)

    case :exec.run(cmd, stdin_exec_options) do
      {:ok, pid, os_pid} ->
        # Send the input to stdin
        :exec.send(pid, input)
        :exec.send(pid, :eof)

        # Get timeout from options (default: 75 minutes)
        timeout_ms = options.timeout_ms || 4_500_000

        Logger.debug("Using timeout for CLI run", timeout_ms: timeout_ms)

        # Collect output until process exits
        receive_exec_output(pid, os_pid, [], [], timeout_ms, temp_files)

      {:error, reason} ->
        Logger.error("Failed to start Claude CLI (stdin run)",
          cmd: cmd,
          reason: reason,
          env_keys: env_keys(stdin_exec_options)
        )

        formatted_error = format_error_message(reason, options)
        error_msg = process_error_message(formatted_error, reason)

        %{
          mode: :error,
          messages: [error_msg],
          current_index: 0,
          done: false,
          temp_files: temp_files
        }
    end
  end

  defp receive_exec_output(pid, os_pid, stdout_acc, stderr_acc, timeout_ms, temp_files) do
    receive do
      {:stdout, ^os_pid, data} ->
        # Check for challenge URL in the output
        combined_output = [data | stdout_acc] |> Enum.reverse() |> Enum.join()

        if challenge_url = detect_challenge_url(combined_output) do
          # Challenge URL detected - dump it and terminate
          IO.puts("\n🔐 Challenge URL detected:")
          IO.puts("#{challenge_url}")
          IO.puts("\nTerminating process...")

          # Stop the process
          :exec.stop(pid)

          # Return a special error message indicating challenge URL was detected
          error_msg = %Message{
            type: :result,
            subtype: :authentication_required,
            data: %{
              error: "Authentication challenge detected",
              challenge_url: challenge_url,
              session_id: "auth_challenge",
              is_error: true
            }
          }

          %{
            mode: :error,
            messages: [error_msg],
            current_index: 0,
            done: false,
            temp_files: temp_files
          }
        else
          receive_exec_output(
            pid,
            os_pid,
            [data | stdout_acc],
            stderr_acc,
            timeout_ms,
            temp_files
          )
        end

      {:stderr, ^os_pid, data} ->
        # Also check stderr for challenge URL
        combined_output = [data | stderr_acc] |> Enum.reverse() |> Enum.join()

        if challenge_url = detect_challenge_url(combined_output) do
          # Challenge URL detected - dump it and terminate
          IO.puts("\n🔐 Challenge URL detected:")
          IO.puts("#{challenge_url}")
          IO.puts("\nTerminating process...")

          # Stop the process
          :exec.stop(pid)

          # Return a special error message indicating challenge URL was detected
          error_msg = %Message{
            type: :result,
            subtype: :authentication_required,
            data: %{
              error: "Authentication challenge detected",
              challenge_url: challenge_url,
              session_id: "auth_challenge",
              is_error: true
            }
          }

          %{
            mode: :error,
            messages: [error_msg],
            current_index: 0,
            done: false,
            temp_files: temp_files
          }
        else
          receive_exec_output(
            pid,
            os_pid,
            stdout_acc,
            [data | stderr_acc],
            timeout_ms,
            temp_files
          )
        end

      {:DOWN, ^os_pid, :process, ^pid, _exit_status} ->
        # Process completed, parse the accumulated output
        stdout_output = stdout_acc |> Enum.reverse() |> Enum.join()
        stderr_output = stderr_acc |> Enum.reverse() |> Enum.join()

        stdout_lines = if stdout_output == "", do: [], else: [stdout_output]
        stderr_lines = if stderr_output == "", do: [], else: [stderr_output]

        result = %{stdout: stdout_lines, stderr: stderr_lines}

        %{
          mode: :sync,
          result: result,
          messages: parse_sync_result(result),
          current_index: 0,
          done: false,
          temp_files: temp_files
        }
    after
      timeout_ms ->
        # Timeout - use configured value
        :exec.stop(pid)

        timeout_seconds = div(timeout_ms, 1000)
        timeout_minutes = div(timeout_seconds, 60)

        timeout_display =
          if timeout_minutes > 0 do
            "#{timeout_minutes} minutes"
          else
            "#{timeout_seconds} seconds"
          end

        error_msg = %Message{
          type: :result,
          subtype: :error_during_execution,
          data: %{
            error: "Command timed out after #{timeout_display}",
            session_id: "error",
            is_error: true
          }
        }

        %{
          mode: :error,
          messages: [error_msg],
          current_index: 0,
          done: false,
          temp_files: temp_files
        }
    end
  end

  defp build_claude_command(args, _options, _stdin_input) do
    executable = CLI.find_executable!()
    _ = CLI.warn_if_outdated()

    # Ensure proper flags for JSON output
    final_args = ensure_json_flags(args)

    # Always return the command string format - erlexec handles both cases
    {final_args, temp_files} = AgentsFile.externalize_agents_if_needed(final_args)
    quoted_args = Enum.map(final_args, &shell_escape/1)
    {Enum.join([executable | quoted_args], " "), temp_files}
  end

  defp build_exec_options(options) do
    # Get timeout from options (default: 75 minutes)
    timeout_ms = options.timeout_ms || 4_500_000

    base_options = [:sync, :stdout, :stderr, {:timeout, timeout_ms}]

    # Add environment variables (critical for authentication!)
    env_options = build_env_vars(options)

    base_options
    |> maybe_put_env_option(env_options)
    |> maybe_put_user_option(options.user)
    |> maybe_put_cd_option(options.cwd)
  end

  defp build_env_vars(%Options{} = options) do
    base_env =
      ["CLAUDE_AGENT_OAUTH_TOKEN", "ANTHROPIC_API_KEY", "PATH", "HOME"]
      |> Enum.reduce(%{}, fn var, acc ->
        case System.get_env(var) do
          nil -> acc
          "" -> acc
          value -> Map.put(acc, var, value)
        end
      end)

    overrides =
      options.env
      |> Enum.reduce(%{}, fn {key, value}, acc ->
        env_key = to_string(key)
        Map.put(acc, env_key, value)
      end)

    merged =
      Enum.reduce(overrides, base_env, fn
        {key, nil}, acc -> Map.delete(acc, key)
        {key, value}, acc -> Map.put(acc, key, to_string(value))
      end)
      |> maybe_put_user_env(options.user)
      |> maybe_put_pwd_env(options.cwd)
      |> Map.put_new("CLAUDE_CODE_ENTRYPOINT", "sdk-elixir")
      |> Map.put_new("CLAUDE_AGENT_SDK_VERSION", version_string())
      |> maybe_put_file_checkpointing_env(options)

    Enum.map(merged, fn {k, v} -> {k, v} end)
  end

  @doc false
  @spec __env_vars__(Options.t()) :: map()
  def __env_vars__(%Options{} = options) do
    build_env_vars(options)
    |> Map.new()
  end

  defp maybe_put_file_checkpointing_env(env_map, %Options{enable_file_checkpointing: true}) do
    Map.put(env_map, "CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING", "true")
  end

  defp maybe_put_file_checkpointing_env(env_map, _options), do: env_map

  defp maybe_put_user_env(env_map, nil), do: env_map

  defp maybe_put_user_env(env_map, user) when is_binary(user) do
    env_map
    |> Map.put("USER", user)
    |> Map.put("LOGNAME", user)
  end

  defp maybe_put_pwd_env(env_map, nil), do: env_map

  defp maybe_put_pwd_env(env_map, cwd) when is_binary(cwd) do
    Map.put(env_map, "PWD", cwd)
  end

  defp shell_escape(""), do: "\"\""

  defp shell_escape(arg) do
    # Escape arguments that contain spaces or special characters
    if String.contains?(arg, [" ", "!", "\"", "'", "$", "`", "\\", "|", "&", ";", "(", ")"]) do
      "\"#{String.replace(arg, "\"", "\\\"")}\""
    else
      arg
    end
  end

  defp version_string do
    case Application.spec(:claude_agent_sdk, :vsn) do
      nil -> "unknown"
      version -> to_string(version)
    end
  end

  @doc false
  def __exec_options__(%Options{} = options), do: build_exec_options(options)

  @doc false
  def __shell_escape__(arg) when is_binary(arg), do: shell_escape(arg)

  @doc false
  @spec __parse_output__(String.t()) :: [Message.t()]
  def __parse_output__(output) when is_binary(output) do
    parse_sync_result(%{stdout: [output], stderr: []})
  end

  defp maybe_put_env_option(opts, []), do: opts
  defp maybe_put_env_option(opts, env) when is_list(env), do: [{:env, env} | opts]

  defp maybe_put_cd_option(opts, nil), do: opts

  defp maybe_put_cd_option(opts, cwd) when is_binary(cwd) do
    [{:cd, cwd} | opts]
  end

  defp maybe_put_cd_option(opts, _), do: opts

  defp maybe_put_user_option(opts, nil), do: opts

  defp maybe_put_user_option(opts, user) when is_binary(user) do
    [{:user, String.to_charlist(user)} | opts]
  end

  defp env_keys(opts) do
    opts
    |> Enum.find_value([], fn
      {:env, env} -> env
      _ -> nil
    end)
    |> Enum.map(fn
      {key, _} when is_binary(key) -> key
      {key, _} when is_atom(key) -> Atom.to_string(key)
      {key, _} -> to_string(key)
    end)
  end

  defp ensure_json_flags(args) do
    cond do
      "--output-format" not in args ->
        args ++ ["--output-format", "stream-json", "--verbose"]

      has_stream_json?(args) and "--verbose" not in args ->
        args ++ ["--verbose"]

      true ->
        args
    end
  end

  defp has_stream_json?(args) do
    case Enum.find_index(args, &(&1 == "--output-format")) do
      nil -> false
      idx -> Enum.at(args, idx + 1) == "stream-json"
    end
  end

  defp parse_sync_result(result) do
    stdout_data = get_in(result, [:stdout]) || []
    stderr_data = get_in(result, [:stderr]) || []

    # Combine all output
    all_output = stdout_data ++ stderr_data
    combined_text = Enum.join(all_output)

    # First check for challenge URL
    case detect_challenge_url(combined_text) do
      nil ->
        parse_sync_lines(combined_text)

      challenge_url ->
        IO.puts("\n🔐 Challenge URL detected:")
        IO.puts("#{challenge_url}")
        IO.puts("\nTerminating process...")

        [
          %Message{
            type: :result,
            subtype: :authentication_required,
            data: %{
              error: "Authentication challenge detected",
              challenge_url: challenge_url,
              session_id: "auth_challenge",
              is_error: true
            }
          }
        ]
    end
  end

  defp parse_sync_lines(combined_text) do
    combined_text
    |> String.split("\n", trim: true)
    |> Enum.reduce_while([], &parse_sync_line/2)
    |> case do
      {:error, error_message} -> [error_message]
      messages when is_list(messages) -> Enum.reverse(messages)
    end
  end

  defp parse_sync_line(line, acc) do
    case parse_json_line(line) do
      {:ok, message} -> {:cont, [message | acc]}
      {:error, error_message} -> {:halt, {:error, error_message}}
    end
  end

  defp parse_json_line(line) do
    result = ClaudeAgentSDK.JSON.decode(line)

    # Debug: Try with OTP :json directly to see actual error
    case result do
      {:error, _} ->
        try do
          :json.decode(line)
        rescue
          e ->
            Logger.error(
              "JSON parse failed. Line length: #{String.length(line)}, Error: #{inspect(e)}"
            )
        catch
          kind, error ->
            Logger.error("JSON parse caught #{kind}: #{inspect(error)}")
        end

      _ ->
        :ok
    end

    case result do
      {:ok, json_obj} when is_map(json_obj) ->
        case Message.from_json(line) do
          {:ok, message} ->
            {:ok, message}

          {:error, reason} ->
            {:error, message_parse_error_message(json_obj, reason)}
        end

      {:ok, _other} ->
        {:error, json_decode_error_message(line, :not_a_map)}

      {:error, reason} ->
        {:error, json_decode_error_message(line, reason)}
    end
  end

  defp json_decode_error_message(line, original_error) do
    error =
      %ClaudeAgentSDK.Errors.CLIJSONDecodeError{
        message: "Failed to decode JSON: #{String.slice(line, 0, 100)}...",
        line: line,
        original_error: original_error
      }

    %Message{
      type: :result,
      subtype: :error_during_execution,
      data: %{
        error: Exception.message(error),
        error_struct: error,
        session_id: "error",
        is_error: true
      }
    }
  end

  defp process_error_message(formatted_error, reason) do
    {exit_code, stderr} = extract_process_error_details(reason)

    error =
      %ClaudeAgentSDK.Errors.ProcessError{
        message: formatted_error,
        exit_code: exit_code,
        stderr: stderr
      }

    %Message{
      type: :result,
      subtype: :error_during_execution,
      data: %{
        error: Exception.message(error),
        error_struct: error,
        session_id: "error",
        is_error: true
      }
    }
  end

  defp extract_process_error_details(reason) when is_list(reason) do
    if Keyword.keyword?(reason) do
      exit_code =
        case Keyword.get(reason, :exit_status) do
          code when is_integer(code) -> code
          _ -> nil
        end

      stderr =
        case Keyword.get(reason, :stderr) do
          lines when is_list(lines) -> Enum.join(lines, "")
          other when is_binary(other) -> other
          _ -> nil
        end

      {exit_code, stderr}
    else
      {nil, nil}
    end
  end

  defp extract_process_error_details(_reason) do
    {nil, nil}
  end

  defp message_parse_error_message(data, reason) do
    error =
      %ClaudeAgentSDK.Errors.MessageParseError{
        message: "Failed to parse CLI message",
        data: data
      }

    %Message{
      type: :result,
      subtype: :error_during_execution,
      data: %{
        error: Exception.message(error) <> " (#{inspect(reason)})",
        error_struct: error,
        session_id: "error",
        is_error: true
      }
    }
  end

  defp receive_messages(%{done: true} = state) do
    {:halt, state}
  end

  defp receive_messages(%{mode: :error, messages: [msg], current_index: 0} = state) do
    {[msg], %{state | current_index: 1, done: true}}
  end

  defp receive_messages(%{mode: :sync, messages: messages, current_index: idx} = state) do
    if idx >= length(messages) do
      {:halt, %{state | done: true}}
    else
      message = Enum.at(messages, idx)
      new_state = %{state | current_index: idx + 1}

      # Check if this is the final message
      if Message.final?(message) do
        {[message], %{new_state | done: true}}
      else
        {[message], new_state}
      end
    end
  end

  defp cleanup_process(state) do
    _ = AgentsFile.cleanup_temp_files(Map.get(state, :temp_files, []))
    :ok
  end

  defp format_error_message(reason, options) do
    cwd_info = if options.cwd, do: " (cwd: #{options.cwd})", else: ""

    case reason do
      [exit_status: status, stdout: stdout_data] when is_list(stdout_data) ->
        # Extract and format JSON from stdout
        json_output = Enum.join(stdout_data, "")
        formatted_json = format_json_output(json_output)
        "Failed to execute claude#{cwd_info} (exit status: #{status}):\n#{formatted_json}"

      [exit_status: status, stdout: stdout_data, stderr: stderr_data]
      when is_list(stdout_data) ->
        # Extract and format JSON from stdout
        json_output = Enum.join(stdout_data, "")
        formatted_json = format_json_output(json_output)
        stderr_text = if is_list(stderr_data), do: Enum.join(stderr_data, ""), else: ""
        error_details = if stderr_text != "", do: "\nstderr: #{stderr_text}", else: ""

        "Failed to execute claude#{cwd_info} (exit status: #{status}):\n#{formatted_json}#{error_details}"

      [exit_status: status] ->
        "Failed to execute claude#{cwd_info} (exit status: #{status})"

      other ->
        "Failed to execute claude#{cwd_info}: #{inspect(other)}"
    end
  end

  defp format_json_output(json_string) do
    json_string
    |> String.split("\n")
    |> Enum.filter(&(&1 != ""))
    |> Enum.map_join("\n", &format_single_json_line/1)
  end

  defp format_single_json_line(line) do
    # Try to parse and pretty print the JSON
    case ClaudeAgentSDK.JSON.decode(line) do
      {:ok, _parsed} ->
        # Since we don't have a pretty print encoder, just return the line
        line

      {:error, _} ->
        # If parsing fails, return the original line
        line
    end
  end

  @doc false
  # Detects challenge URLs in CLI output
  # Common patterns:
  # - "Please visit: https://console.anthropic.com/..."
  # - "Open this URL in your browser: https://..."
  # - "Visit https://console.anthropic.com/challenge/..."
  # - URLs containing "challenge", "auth", "login", or "verify"
  defp detect_challenge_url(output) do
    # Define patterns to look for
    patterns = [
      # Direct URL patterns with common auth/challenge keywords
      ~r/https:\/\/[^\s]*(?:challenge|auth|login|verify|oauth|signin|authenticate)[^\s]*/i,
      # Console URLs that might be auth-related
      ~r/https:\/\/console\.anthropic\.com\/[^\s]+/i,
      # URLs preceded by common prompts
      ~r/(?:visit|open|go to|navigate to|click|access)[\s:]+?(https:\/\/[^\s]+)/i,
      # Any URL in a line containing auth-related keywords
      ~r/(?:authenticate|login|sign in|verify|challenge).*?(https:\/\/[^\s]+)/i,
      # URLs in JSON that might be auth URLs
      ~r/"(?:url|challenge_url|auth_url|login_url)"[\s:]+?"(https:\/\/[^\s"]+)"/i
    ]

    # Try each pattern
    Enum.find_value(patterns, fn pattern ->
      pattern
      |> Regex.run(output)
      |> process_regex_match()
    end)
  end

  # Process regex match result
  defp process_regex_match(nil), do: nil

  defp process_regex_match([full_match | _captures]) do
    url = extract_url_from_match(full_match)
    if valid_challenge_url?(url), do: url, else: nil
  end

  # Extract clean URL from a regex match
  defp extract_url_from_match(match) do
    # If the match contains an URL starting with https://, extract it
    case Regex.run(~r/https:\/\/[^\s"'>\]]+/, match) do
      [url] -> url
      _ -> match
    end
  end

  # Validate that the URL looks like an authentication challenge URL
  defp valid_challenge_url?(url) do
    String.starts_with?(url, "https://") and
      (String.contains?(url, "anthropic.com") or
         String.contains?(url, "challenge") or
         String.contains?(url, "auth") or
         String.contains?(url, "login") or
         String.contains?(url, "verify") or
         String.contains?(url, "oauth"))
  end
end
