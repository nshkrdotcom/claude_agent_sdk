defmodule ClaudeAgentSDK.Process do
  @moduledoc """
  Claude CLI one-shot query surface backed by the shared command lane.

  The shared `cli_subprocess_core` command lane now owns subprocess execution.
  This module keeps the Claude SDK's environment shaping, stderr callback
  handling, and stream-json output parsing so existing callers still see the
  same message structs and helper functions.
  """

  alias ClaudeAgentSDK.{CLI, LineFraming, Message, Options, Runtime, Shell}
  alias ClaudeAgentSDK.Config.{Buffers, Env, Timeouts}
  alias ClaudeAgentSDK.Config.CLI, as: CLIConfig
  alias ClaudeAgentSDK.Errors
  alias CliSubprocessCore.Command, as: CoreCommand
  alias CliSubprocessCore.Command.Error, as: CoreCommandError
  alias CliSubprocessCore.Command.RunResult
  alias CliSubprocessCore.CommandSpec
  alias CliSubprocessCore.ExecutionSurface
  alias CliSubprocessCore.ProviderCLI
  alias ExternalRuntimeTransport.Transport.Error, as: CoreTransportError

  @doc """
  Streams messages from Claude Code CLI using the shared non-PTY command lane.
  """
  @spec stream([String.t()], Options.t(), String.t() | nil) ::
          Enumerable.t(ClaudeAgentSDK.Message.t())
  def stream(args, %Options{} = options, stdin_input \\ nil) do
    if Runtime.use_mock?() and not Runtime.force_real?(options) do
      ClaudeAgentSDK.Mock.Process.stream(args, options, stdin_input)
    else
      state = start_claude_process(args, options, stdin_input)
      Stream.resource(fn -> state end, &receive_messages/1, &cleanup_process/1)
    end
  end

  defp start_claude_process(args, options, stdin_input) do
    with :ok <- validate_cwd(options.cwd, options.execution_surface),
         {:ok, invocation} <- build_claude_invocation(args, options),
         {:ok, %RunResult{} = result} <- run_claude_invocation(invocation, stdin_input, options) do
      _ = dispatch_stderr_from_result(result, options)

      if RunResult.success?(result) do
        sync_state(parse_sync_result(result, options), result)
      else
        exit_result_state(result, options)
      end
    else
      {:error, %CoreCommandError{} = error} ->
        command_error_state(error, options)

      {:error, error_state} when is_map(error_state) ->
        error_state
    end
  end

  defp validate_cwd(cwd, execution_surface) when is_binary(cwd) do
    if ExecutionSurface.nonlocal_path_surface?(execution_surface) or File.dir?(cwd) do
      :ok
    else
      {:error, cwd_not_found_state(cwd)}
    end
  end

  defp validate_cwd(_cwd, _execution_surface), do: :ok

  defp cwd_not_found_state(cwd) do
    error =
      %Errors.CLIConnectionError{
        message: "Working directory does not exist: #{cwd}",
        cwd: cwd,
        reason: :cwd_not_found
      }

    error_state(Exception.message(error), error)
  end

  defp build_claude_invocation(args, %Options{} = options) do
    case CLI.resolve_command_spec(options) do
      {:ok, %CommandSpec{} = command_spec} ->
        _ = CLI.warn_if_outdated()

        {:ok,
         CoreCommand.new(command_spec, ensure_json_flags(args),
           cwd: options.cwd,
           env: __env_vars__(options),
           user: options.user
         )}

      {:error, :not_found} ->
        error =
          %Errors.CLINotFoundError{
            message: "Claude CLI not found. Please install with: #{CLIConfig.install_command()}"
          }

        {:error, error_state(Exception.message(error), error)}
    end
  end

  defp run_claude_invocation(%CoreCommand{} = invocation, stdin_input, %Options{} = options) do
    timeout_ms = options.timeout_ms || Timeouts.query_total_ms()

    run_opts =
      [timeout: timeout_ms, stderr: :separate]
      |> maybe_put_stdin(stdin_input)
      |> Kernel.++(Options.execution_surface_options(options))

    CoreCommand.run(invocation, run_opts)
  end

  defp maybe_put_stdin(run_opts, nil), do: run_opts

  defp maybe_put_stdin(run_opts, stdin_input) when is_binary(stdin_input),
    do: Keyword.put(run_opts, :stdin, stdin_input)

  defp command_error_state(
         %CoreCommandError{reason: {:transport, %CoreTransportError{} = error}},
         %Options{} = options
       ) do
    case normalize_transport_reason(error) do
      :timeout ->
        timeout_state(options)

      :cli_not_found ->
        not_found =
          %Errors.CLINotFoundError{
            message: "Claude CLI not found. Please install with: #{CLIConfig.install_command()}"
          }

        error_state(Exception.message(not_found), not_found)

      %Errors.CLIJSONDecodeError{} = normalized ->
        error_state(Exception.message(normalized), normalized)

      _normalized ->
        failure =
          ProviderCLI.runtime_failure(
            :claude,
            error,
            execution_surface: options.execution_surface,
            cwd: options.cwd
          )

        error = runtime_failure_error_struct(failure)

        error_state(Exception.message(error), error,
          error_details: runtime_failure_details(failure)
        )
    end
  end

  defp command_error_state(%CoreCommandError{} = error, _options) do
    sdk_error = %Errors.ClaudeSDKError{message: Exception.message(error), cause: error}
    error_state(Exception.message(sdk_error), sdk_error)
  end

  defp normalize_transport_reason(%CoreTransportError{
         reason: {:buffer_overflow, actual_size, max_size},
         context: context
       }) do
    %Errors.CLIJSONDecodeError{
      message: "JSON message exceeded maximum buffer size of #{max_size} bytes",
      line: Map.get(context, :preview, "") |> truncate_preview(),
      original_error: {:buffer_overflow, actual_size, max_size}
    }
  end

  defp normalize_transport_reason(%CoreTransportError{reason: {:command_not_found, command}})
       when command in ["claude", "claude-code"],
       do: :cli_not_found

  defp normalize_transport_reason(%CoreTransportError{reason: reason}),
    do: normalize_transport_reason(reason)

  defp normalize_transport_reason({:command_not_found, command})
       when command in ["claude", "claude-code"],
       do: :cli_not_found

  defp normalize_transport_reason(:noproc), do: :not_connected
  defp normalize_transport_reason({:call_exit, :noproc}), do: :not_connected
  defp normalize_transport_reason({:transport, :noproc}), do: :not_connected
  defp normalize_transport_reason(reason), do: reason

  defp truncate_preview(preview) when is_binary(preview) do
    if byte_size(preview) > Buffers.error_preview_length() do
      binary_part(preview, 0, Buffers.error_preview_length()) <> "..."
    else
      preview
    end
  end

  defp exit_result_state(%RunResult{} = result, %Options{} = options) do
    failure =
      ProviderCLI.runtime_failure(
        :claude,
        result.exit,
        execution_surface: options.execution_surface,
        cwd: options.cwd,
        stderr: result.stderr
      )

    error = runtime_failure_error_struct(failure)

    error_msg =
      Message.error_result(Exception.message(error),
        error_struct: error,
        error_details: runtime_failure_details(failure)
      )

    %{
      mode: :error,
      messages: [error_msg],
      current_index: 0,
      done: false
    }
  end

  defp timeout_state(%Options{} = options) do
    timeout_ms = options.timeout_ms || Timeouts.query_total_ms()
    timeout_seconds = div(timeout_ms, 1_000)
    timeout_minutes = div(timeout_seconds, 60)

    timeout_display =
      if timeout_minutes > 0 do
        "#{timeout_minutes} minutes"
      else
        "#{timeout_seconds} seconds"
      end

    error_msg = Message.error_result("Command timed out after #{timeout_display}")

    %{
      mode: :error,
      messages: [error_msg],
      current_index: 0,
      done: false
    }
  end

  defp sync_state(messages, result) when is_list(messages) do
    %{
      mode: :sync,
      result: result,
      messages: messages,
      current_index: 0,
      done: false
    }
  end

  defp error_state(message, error_struct, opts \\ []) do
    %{
      mode: :error,
      messages: [
        Message.error_result(message,
          error_struct: error_struct,
          error_details: Keyword.get(opts, :error_details)
        )
      ],
      current_index: 0,
      done: false
    }
  end

  defp dispatch_stderr_from_result(%RunResult{stderr: stderr}, %Options{stderr: callback})
       when is_function(callback, 1) do
    stderr
    |> LineFraming.finalize_trimmed_lines()
    |> dispatch_stderr_lines(callback)
  end

  defp dispatch_stderr_from_result(_result, _options), do: :ok

  defp dispatch_stderr_lines(lines, callback) when is_function(callback, 1) do
    Enum.each(lines, callback)
  end

  defp build_env_vars(%Options{} = options) do
    base_env =
      Env.passthrough_vars()
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

    payload_env =
      options
      |> model_payload_env_overrides()
      |> Enum.reduce(%{}, fn {key, value}, acc ->
        Map.put(acc, to_string(key), value)
      end)

    merged =
      overrides
      |> Enum.reduce(base_env, fn
        {key, nil}, acc -> Map.delete(acc, key)
        {key, value}, acc -> Map.put(acc, key, to_string(value))
      end)
      |> then(fn env ->
        Enum.reduce(payload_env, env, fn
          {key, nil}, acc -> Map.delete(acc, key)
          {key, value}, acc -> Map.put(acc, key, to_string(value))
        end)
      end)
      |> maybe_put_user_env(options.user)
      |> maybe_put_pwd_env(options.cwd)
      |> Map.put_new(Env.entrypoint(), "sdk-elixir")
      |> Map.put_new(Env.sdk_version(), version_string())
      |> maybe_put_file_checkpointing_env(options)

    Map.new(merged)
  end

  @doc false
  @spec __env_vars__(Options.t()) :: map()
  def __env_vars__(%Options{} = options), do: build_env_vars(options)

  defp model_payload_env_overrides(%Options{model_payload: payload}) when is_map(payload) do
    Map.get(payload, :env_overrides, Map.get(payload, "env_overrides", %{}))
  end

  defp model_payload_env_overrides(_options), do: %{}

  defp maybe_put_file_checkpointing_env(env_map, %Options{enable_file_checkpointing: true}) do
    Map.put(env_map, Env.file_checkpointing(), "true")
  end

  defp maybe_put_file_checkpointing_env(env_map, _options), do: env_map

  defp maybe_put_user_env(env_map, nil), do: env_map

  defp maybe_put_user_env(env_map, user) when is_binary(user) do
    env_map
    |> Map.put("USER", user)
    |> Map.put("LOGNAME", user)
  end

  defp maybe_put_pwd_env(env_map, nil), do: env_map
  defp maybe_put_pwd_env(env_map, cwd) when is_binary(cwd), do: Map.put(env_map, "PWD", cwd)

  defp shell_escape(arg), do: Shell.escape_arg(arg)

  defp version_string do
    case Application.spec(:claude_agent_sdk, :vsn) do
      nil -> "unknown"
      version -> to_string(version)
    end
  end

  @doc false
  def __shell_escape__(arg) when is_binary(arg), do: shell_escape(arg)

  @doc false
  @spec __parse_output__(String.t(), Options.t()) :: [Message.t()]
  def __parse_output__(output, %Options{} = options \\ %Options{}) when is_binary(output) do
    parse_sync_result(%{stdout: output, stderr: ""}, options)
  end

  defp ensure_json_flags(args) do
    args
    |> ensure_stream_json_output_format()
    |> ensure_verbose_for_stream_json()
  end

  defp has_stream_json?(args) do
    case Enum.find_index(args, &(&1 == "--output-format")) do
      nil -> false
      idx -> Enum.at(args, idx + 1) == "stream-json"
    end
  end

  defp ensure_stream_json_output_format(args) do
    case Enum.find_index(args, &(&1 == "--output-format")) do
      nil ->
        args ++ ["--output-format", "stream-json"]

      idx when idx == length(args) - 1 ->
        args ++ ["stream-json"]

      idx ->
        if Enum.at(args, idx + 1) == "stream-json" do
          args
        else
          List.replace_at(args, idx + 1, "stream-json")
        end
    end
  end

  defp ensure_verbose_for_stream_json(args) do
    if has_stream_json?(args) and "--verbose" not in args do
      args ++ ["--verbose"]
    else
      args
    end
  end

  defp parse_sync_result(%RunResult{} = result, %Options{} = options) do
    parse_sync_result(%{stdout: result.stdout, stderr: result.stderr}, options)
  end

  defp parse_sync_result(%{stdout: stdout_output, stderr: stderr_output}, %Options{} = options)
       when is_binary(stdout_output) and is_binary(stderr_output) do
    combined_text = stdout_output <> stderr_output

    case detect_challenge_url(combined_text) do
      nil ->
        output_to_parse = if stdout_output == "", do: stderr_output, else: stdout_output
        parse_sync_lines(output_to_parse, max_buffer_size(options))

      challenge_url ->
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

  defp parse_sync_lines(combined_text, max_buffer_size) do
    combined_text
    |> String.split("\n", trim: true)
    |> Enum.reduce_while([], fn line, acc ->
      if byte_size(line) > max_buffer_size do
        {:halt, {:error, buffer_overflow_error_message(line, max_buffer_size)}}
      else
        parse_sync_line(line, acc)
      end
    end)
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
    case Message.from_json(line) do
      {:ok, message} ->
        {:ok, message}

      {:error, reason} ->
        case ClaudeAgentSDK.JSON.decode(line) do
          {:ok, json_obj} when is_map(json_obj) ->
            {:error, message_parse_error_message(json_obj, reason)}

          {:ok, _other} ->
            {:error, json_decode_error_message(line, :not_a_map)}

          {:error, decode_reason} ->
            {:error, json_decode_error_message(line, decode_reason)}
        end
    end
  end

  defp json_decode_error_message(line, original_error) do
    error =
      %Errors.CLIJSONDecodeError{
        message:
          "Failed to decode JSON: #{String.slice(line, 0, Buffers.error_preview_length())}...",
        line: line,
        original_error: original_error
      }

    Message.error_result(Exception.message(error), error_struct: error)
  end

  defp buffer_overflow_error_message(line, max_buffer_size) do
    error =
      %Errors.CLIJSONDecodeError{
        message: "JSON message exceeded maximum buffer size of #{max_buffer_size} bytes",
        line: truncate_line(line),
        original_error: {:buffer_overflow, byte_size(line), max_buffer_size}
      }

    Message.error_result(Exception.message(error), error_struct: error)
  end

  defp truncate_line(line) when is_binary(line) do
    if byte_size(line) > Buffers.error_preview_length() do
      binary_part(line, 0, Buffers.error_preview_length()) <> "..."
    else
      line
    end
  end

  defp max_buffer_size(%Options{max_buffer_size: size}) when is_integer(size) and size > 0,
    do: size

  defp max_buffer_size(_), do: Buffers.max_stdout_buffer_bytes()

  defp runtime_failure_error_struct(
         %ProviderCLI.ErrorRuntimeFailure{kind: :cli_not_found} = failure
       ) do
    %Errors.CLINotFoundError{
      message: failure.message,
      cli_path: failure.context[:command]
    }
  end

  defp runtime_failure_error_struct(
         %ProviderCLI.ErrorRuntimeFailure{kind: :cwd_not_found} = failure
       ) do
    %Errors.CLIConnectionError{
      message: failure.message,
      cwd: failure.context[:cwd],
      reason: :cwd_not_found
    }
  end

  defp runtime_failure_error_struct(%ProviderCLI.ErrorRuntimeFailure{} = failure) do
    %Errors.ProcessError{
      message: failure.message,
      exit_code: failure.exit_code,
      stderr: blank_to_nil(failure.stderr)
    }
  end

  defp runtime_failure_details(%ProviderCLI.ErrorRuntimeFailure{} = failure) do
    %{}
    |> maybe_put_runtime_detail(:kind, failure.kind)
    |> maybe_put_runtime_detail(:exit_code, failure.exit_code)
    |> maybe_put_runtime_detail(:stderr, blank_to_nil(failure.stderr))
    |> maybe_put_runtime_detail(:cwd, failure.context[:cwd])
    |> maybe_put_runtime_detail(:destination, failure.context[:destination])
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(value) when is_binary(value), do: value

  defp maybe_put_runtime_detail(details, _key, nil), do: details
  defp maybe_put_runtime_detail(details, key, value), do: Map.put(details, key, value)

  defp message_parse_error_message(data, reason) do
    error =
      %Errors.MessageParseError{
        message: "Failed to parse CLI message",
        data: data
      }

    Message.error_result(Exception.message(error) <> " (#{inspect(reason)})", error_struct: error)
  end

  defp receive_messages(%{done: true} = state), do: {:halt, state}

  defp receive_messages(%{mode: :error, messages: [msg], current_index: 0} = state) do
    {[msg], %{state | current_index: 1, done: true}}
  end

  defp receive_messages(%{mode: :sync, messages: messages, current_index: idx} = state) do
    if idx >= length(messages) do
      {:halt, %{state | done: true}}
    else
      message = Enum.at(messages, idx)
      new_state = %{state | current_index: idx + 1}

      if Message.final?(message) do
        {[message], %{new_state | done: true}}
      else
        {[message], new_state}
      end
    end
  end

  defp cleanup_process(_state), do: :ok

  @doc false
  defp detect_challenge_url(output) do
    patterns = [
      ~r/https:\/\/[^\s]*(?:challenge|auth|login|verify|oauth|signin|authenticate)[^\s]*/i,
      ~r/https:\/\/console\.anthropic\.com\/[^\s]+/i,
      ~r/(?:visit|open|go to|navigate to|click|access)[\s:]+?(https:\/\/[^\s]+)/i,
      ~r/(?:authenticate|login|sign in|verify|challenge).*?(https:\/\/[^\s]+)/i,
      ~r/"(?:url|challenge_url|auth_url|login_url)"[\s:]+?"(https:\/\/[^\s"]+)"/i
    ]

    Enum.find_value(patterns, fn pattern ->
      pattern
      |> Regex.run(output)
      |> process_regex_match()
    end)
  end

  defp process_regex_match(nil), do: nil

  defp process_regex_match([full_match | _captures]) do
    url = extract_url_from_match(full_match)
    if valid_challenge_url?(url), do: url, else: nil
  end

  defp extract_url_from_match(match) do
    case Regex.run(~r/https:\/\/[^\s"'>\]]+/, match) do
      [url] -> url
      _ -> match
    end
  end

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
