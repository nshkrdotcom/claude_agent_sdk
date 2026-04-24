defmodule ClaudeAgentSDK.Query.CLIStream do
  @moduledoc """
  Streams CLI-only query responses over the shared core transport lane.

  This module is used for unidirectional, non-control queries. It supports:
  - String prompts (sent as stream-json user messages via stdin)
  - Enumerable prompts (streamed via stdin)
  - Execution-surface routing via `Options.execution_surface`
  """

  alias ClaudeAgentSDK.{
    CLI,
    Errors,
    Message,
    Options,
    ProcessSupport,
    Runtime,
    TaskSupervisor
  }

  alias ClaudeAgentSDK.Config.{Buffers, Timeouts}
  alias ClaudeAgentSDK.Config.CLI, as: CLIConfig
  alias ClaudeAgentSDK.SessionStore.{MirrorBatcher, Resume}
  alias CliSubprocessCore.Command, as: CoreCommand
  alias CliSubprocessCore.CommandSpec
  alias CliSubprocessCore.ProcessExit, as: CoreProcessExit
  alias CliSubprocessCore.ProviderCLI
  alias CliSubprocessCore.RawSession
  alias CliSubprocessCore.TransportError, as: CoreTransportError

  @transport_event_tag :claude_agent_sdk_transport

  @doc """
  Streams messages for a single query prompt.
  """
  @spec stream(String.t() | Enumerable.t(), Options.t(), term()) ::
          Enumerable.t(Message.t())
  def stream(prompt, %Options{} = options, transport \\ nil) do
    {args, input} = build_prompt_args(prompt, options)
    validate_no_transport_override!(transport)

    if should_use_mock?(options) do
      mock_prompt = mock_prompt_from(prompt)
      ClaudeAgentSDK.Mock.Process.stream(args, options, mock_prompt)
    else
      stream_args(args, options, nil, input)
    end
  end

  @doc false
  @spec stream_args([String.t()], Options.t(), term(), Enumerable.t() | nil) ::
          Enumerable.t(Message.t())
  def stream_args(args, %Options{} = options, transport \\ nil, input \\ nil) do
    validate_no_transport_override!(transport)

    if should_use_mock?(options) do
      mock_prompt =
        cond do
          is_binary(input) -> input
          is_nil(input) -> nil
          true -> mock_prompt_from(input)
        end

      ClaudeAgentSDK.Mock.Process.stream(args, options, mock_prompt)
    else
      Stream.resource(
        fn -> start_transport(args, options, input) end,
        &receive_next/1,
        &cleanup/1
      )
    end
  end

  @doc false
  def __build_args__(prompt, %Options{} = options) do
    {args, _input} = build_prompt_args(prompt, options)
    args
  end

  defp build_prompt_args(prompt, %Options{} = options) when is_binary(prompt) do
    base_args = base_stream_args(options)

    input = [
      %{
        "type" => "user",
        "message" => %{"role" => "user", "content" => prompt}
      }
    ]

    {["--input-format", "stream-json"] ++ base_args, input}
  end

  defp build_prompt_args(prompt, %Options{} = options) do
    base_args = base_stream_args(options)
    {["--input-format", "stream-json"] ++ base_args, prompt}
  end

  defp base_stream_args(%Options{} = options) do
    CLIConfig.streaming_output_args() ++ Options.to_stream_json_args(options)
  end

  defp start_transport(args, %Options{} = options, input) do
    drain_stale_transport_messages()

    with {:ok, materialized} <- Resume.materialize(options),
         options = Resume.apply_options(options, materialized),
         {:ok, mirror_batcher} <- start_mirror_batcher(options),
         {:ok, command} <- build_transport_command(options, args),
         {:ok, raw_session} <-
           RawSession.start_link(
             command,
             [
               receiver: self(),
               event_tag: @transport_event_tag,
               stderr_callback: nil,
               stdout_mode: :line,
               stdin_mode: :line
             ] ++
               Options.execution_surface_options(options)
           ),
         {:ok, input_task} <- maybe_stream_input(raw_session, input) do
      %{
        raw_session: raw_session,
        transport: raw_session.transport,
        transport_ref: raw_session.transport_ref,
        input_task: input_task,
        done?: false,
        command: command.command,
        cwd: command.cwd,
        execution_surface: options.execution_surface,
        transport_error_mode: transport_error_mode(options),
        materialized_resume: materialized,
        mirror_batcher: mirror_batcher,
        # Track if we've received at least one message for better error diagnostics
        received_first_message?: false,
        # Track if we've received the result for stream completion detection
        received_result?: false
      }
    else
      {:error, reason} ->
        error_msg =
          transport_error_message(reason, %{
            command: transport_command_name(options),
            cwd: options.cwd,
            execution_surface: options.execution_surface
          })

        {:error, [error_msg]}
    end
  end

  # For non-streaming queries (nil input), close stdin immediately so the CLI starts processing
  defp maybe_stream_input(raw_session, nil) do
    case RawSession.close_input(raw_session) do
      :ok -> {:ok, nil}
      {:error, reason} -> {:error, {:end_input_failed, normalize_transport_reason(reason)}}
    end
  end

  defp maybe_stream_input(raw_session, input) do
    with {:ok, pid} <-
           TaskSupervisor.start_child(fn -> stream_input_messages(raw_session, input) end) do
      {:ok, %{pid: pid, monitor_ref: Process.monitor(pid)}}
    end
  end

  defp stream_input_messages(raw_session, input) do
    send_result =
      Enum.reduce_while(input, :ok, fn message, _acc ->
        case RawSession.send_input(raw_session, message) do
          :ok ->
            {:cont, :ok}

          {:error, reason} ->
            {:halt, {:error, {:send_failed, normalize_transport_reason(reason)}}}
        end
      end)

    end_result =
      case RawSession.close_input(raw_session) do
        :ok -> :ok
        {:error, reason} -> {:error, normalize_transport_reason(reason)}
      end

    case {send_result, end_result} do
      {:ok, :ok} ->
        :ok

      {{:error, reason}, _} ->
        exit({:input_stream_failed, reason})

      {:ok, {:error, reason}} ->
        exit({:end_input_failed, reason})
    end
  end

  defp receive_next({:error, [msg | rest]}), do: {[msg], {:error, rest}}
  defp receive_next({:error, []}), do: {:halt, {:error, []}}

  defp receive_next(%{done?: true} = state), do: {:halt, state}

  defp receive_next(%{input_task: %{monitor_ref: monitor_ref}} = state) do
    receive do
      {:DOWN, ^monitor_ref, :process, _pid, reason} ->
        maybe_handle_input_task_down(state, monitor_ref, reason)

      {@transport_event_tag, ref, event} when ref == state.transport_ref ->
        handle_transport_event(event, state)

      {:transport_message, line} when is_binary(line) ->
        handle_line(line, state)

      {:transport_error, error} ->
        handle_transport_error(error, state)

      {:transport_stderr, _chunk} ->
        receive_next(state)

      {:transport_exit, reason} ->
        handle_transport_exit(reason, state)
    after
      Timeouts.stream_receive_ms() ->
        if process_running?(state.transport) do
          receive_next(state)
        else
          {:halt, %{state | done?: true}}
        end
    end
  end

  defp receive_next(state) do
    receive do
      {@transport_event_tag, ref, event} when ref == state.transport_ref ->
        handle_transport_event(event, state)

      {:transport_message, line} when is_binary(line) ->
        handle_line(line, state)

      {:transport_error, error} ->
        handle_transport_error(error, state)

      {:transport_stderr, _chunk} ->
        receive_next(state)

      {:transport_exit, reason} ->
        handle_transport_exit(reason, state)
    after
      Timeouts.stream_receive_ms() ->
        if process_running?(state.transport) do
          receive_next(state)
        else
          {:halt, %{state | done?: true}}
        end
    end
  end

  defp handle_line(line, state) do
    case parse_message(line) do
      {:ok, message} ->
        state = %{state | received_first_message?: true}

        if Message.final?(message) do
          mirror_errors = flush_mirror(state.mirror_batcher)
          {mirror_errors ++ [message], %{state | received_result?: true, done?: true}}
        else
          {[message], state}
        end

      {:mirror, file_path, entries} ->
        errors = enqueue_mirror(state.mirror_batcher, file_path, entries)
        if errors == [], do: receive_next(state), else: {errors, state}

      :skip ->
        receive_next(state)

      {:error, error} ->
        handle_transport_error(error, state)
    end
  end

  defp parse_message(line) do
    if json_candidate?(line) do
      case ClaudeAgentSDK.JSON.decode(line) do
        {:ok, %{"type" => "transcript_mirror"} = frame} ->
          {:mirror, frame["filePath"] || frame["file_path"], frame["entries"] || []}

        _other ->
          parse_regular_message(line)
      end
    else
      :skip
    end
  end

  defp parse_regular_message(line) do
    case Message.from_json(line) do
      {:ok, message} ->
        {:ok, message}

      {:error, reason} ->
        {:error, json_decode_error(line, reason)}
    end
  end

  defp json_candidate?(line) when is_binary(line) do
    line
    |> String.trim_leading()
    |> case do
      "{" <> _rest -> true
      "[" <> _rest -> true
      _other -> false
    end
  end

  defp json_decode_error(line, original_error) do
    %Errors.CLIJSONDecodeError{
      message:
        "Failed to decode JSON: #{String.slice(line, 0, Buffers.error_preview_length())}...",
      line: line,
      original_error: original_error
    }
  end

  defp handle_transport_error(error, %{transport_error_mode: :raise} = state) do
    raise transport_error_struct(error, state)
  end

  defp handle_transport_error(error, state) do
    {[transport_error_message(error, state)], %{state | done?: true}}
  end

  defp transport_error_message(error, state) do
    error_struct = transport_error_struct(error, state)

    Message.error_result(Exception.message(error_struct),
      error_struct: error_struct,
      error_details: transport_error_details(error, state)
    )
  end

  defp input_task_error_message(reason) do
    Message.error_result("Input stream worker failed: #{inspect(reason)}", error_struct: reason)
  end

  defp maybe_handle_input_task_down(
         %{input_task: %{monitor_ref: monitor_ref}} = state,
         monitor_ref,
         :normal
       ) do
    receive_next(%{state | input_task: nil})
  end

  defp maybe_handle_input_task_down(
         %{input_task: %{monitor_ref: monitor_ref}} = state,
         monitor_ref,
         reason
       ) do
    {[input_task_error_message(reason)], %{state | input_task: nil, done?: true}}
  end

  defp maybe_handle_input_task_down(state, _monitor_ref, _reason) do
    receive_next(state)
  end

  defp cleanup(%{
         raw_session: raw_session,
         transport_ref: transport_ref,
         input_task: task,
         materialized_resume: materialized,
         mirror_batcher: mirror_batcher
       }) do
    cleanup_input_task(task)
    _ = flush_mirror(mirror_batcher)
    close_transport_with_timeout(raw_session, Timeouts.transport_close_grace_ms())
    flush_transport_messages(transport_ref)
    Resume.cleanup(materialized)

    :ok
  end

  defp cleanup(_), do: :ok

  defp cleanup_input_task(%{pid: pid, monitor_ref: monitor_ref}) do
    Process.demonitor(monitor_ref, [:flush])
    Process.exit(pid, :kill)
    :ok
  end

  defp cleanup_input_task(_), do: :ok

  defp close_transport_with_timeout(%RawSession{transport: transport} = raw_session, timeout_ms) do
    ref = Process.monitor(transport)

    _ = safe_force_close(raw_session)
    await_down_or_shutdown(ref, transport, timeout_ms)
  end

  defp close_transport_with_timeout(_transport, _timeout_ms), do: :ok

  defp drain_stale_transport_messages do
    receive do
      {@transport_event_tag, _ref, _event} ->
        drain_stale_transport_messages()

      {:transport_stderr, _data} ->
        drain_stale_transport_messages()

      {:transport_message, _line} ->
        drain_stale_transport_messages()

      {:transport_error, _error} ->
        drain_stale_transport_messages()

      {:transport_exit, _reason} ->
        drain_stale_transport_messages()
    after
      0 ->
        :ok
    end
  end

  defp flush_transport_messages(ref) when is_reference(ref) do
    receive do
      {@transport_event_tag, ^ref, _event} ->
        flush_transport_messages(ref)
    after
      0 ->
        :ok
    end
  end

  defp flush_transport_messages(_), do: :ok

  defp handle_transport_event({:message, line}, state), do: handle_line(line, state)
  defp handle_transport_event({:error, error}, state), do: handle_transport_error(error, state)
  defp handle_transport_event({:stderr, _chunk}, state), do: receive_next(state)
  defp handle_transport_event({:data, _chunk}, state), do: receive_next(state)
  defp handle_transport_event({:exit, reason}, state), do: handle_transport_exit(reason, state)

  defp handle_transport_exit(_reason, %{received_result?: true} = state) do
    {:halt, %{state | done?: true}}
  end

  defp handle_transport_exit(reason, %{transport_error_mode: :raise} = state) do
    raise transport_error_struct(normalize_exit(reason), state)
  end

  defp handle_transport_exit(reason, state) do
    {[transport_error_message(normalize_exit(reason), state)], %{state | done?: true}}
  end

  defp start_mirror_batcher(%Options{session_store: nil}), do: {:ok, nil}

  defp start_mirror_batcher(%Options{} = options) do
    config_dir =
      options.env
      |> Map.get(
        "CLAUDE_CONFIG_DIR",
        System.get_env("CLAUDE_CONFIG_DIR") || Path.join(System.user_home!(), ".claude")
      )

    MirrorBatcher.start_link(options.session_store, Path.join(config_dir, "projects"))
  end

  defp enqueue_mirror(nil, _file_path, _entries), do: []

  defp enqueue_mirror(pid, file_path, entries)
       when is_pid(pid) and is_binary(file_path) and is_list(entries) do
    MirrorBatcher.enqueue(pid, file_path, entries)
  end

  defp enqueue_mirror(_pid, _file_path, _entries), do: []

  defp flush_mirror(nil), do: []
  defp flush_mirror(pid) when is_pid(pid), do: MirrorBatcher.flush(pid)

  defp await_down_or_shutdown(ref, transport, timeout_ms) do
    case ProcessSupport.await_down(ref, transport, timeout_ms) do
      :down ->
        :ok

      :timeout ->
        safe_shutdown(transport)
        await_down_or_kill(ref, transport, 250)
    end
  end

  defp await_down_or_kill(ref, transport, timeout_ms) do
    case ProcessSupport.await_down(ref, transport, timeout_ms) do
      :down ->
        :ok

      :timeout ->
        safe_kill(transport)
        await_down_or_demonitor(ref, transport, 250)
    end
  end

  defp await_down_or_demonitor(ref, transport, timeout_ms) do
    case ProcessSupport.await_down(ref, transport, timeout_ms) do
      :down ->
        :ok

      :timeout ->
        Process.demonitor(ref, [:flush])
        :ok
    end
  end

  defp safe_force_close(%RawSession{} = raw_session) do
    RawSession.force_close(raw_session)
  catch
    :exit, _ -> {:error, {:transport, :not_connected}}
  end

  defp safe_shutdown(transport) when is_pid(transport) do
    Process.exit(transport, :shutdown)
    :ok
  catch
    :exit, _ -> :ok
  end

  defp safe_kill(transport) when is_pid(transport) do
    Process.exit(transport, :kill)
    :ok
  catch
    :exit, _ -> :ok
  end

  defp process_running?(pid) when is_pid(pid), do: Process.info(pid, :status) != nil
  defp process_running?(_pid), do: false

  defp transport_error_struct(%Errors.CLIJSONDecodeError{} = error, _state), do: error
  defp transport_error_struct(%Errors.CLIConnectionError{} = error, _state), do: error
  defp transport_error_struct(%Errors.CLINotFoundError{} = error, _state), do: error
  defp transport_error_struct(%Errors.ProcessError{} = error, _state), do: error
  defp transport_error_struct(%Errors.ClaudeSDKError{} = error, _state), do: error

  defp transport_error_struct(:cli_not_found, state) do
    provider_runtime_failure(CoreProcessExit.from_reason({:exit_status, 127}), state)
    |> runtime_failure_error_struct()
  end

  defp transport_error_struct(error, state) when is_exception(error) do
    if CoreTransportError.match?(error) do
      transport_error_struct_from_core(error, state)
    else
      transport_error_struct_fallback(error)
    end
  end

  defp transport_error_struct(error, state) do
    cond do
      CoreTransportError.match?(error) ->
        transport_error_struct_from_core(error, state)

      CoreProcessExit.match?(error) ->
        error
        |> provider_runtime_failure(state)
        |> runtime_failure_error_struct()

      true ->
        transport_error_struct_fallback(error)
    end
  end

  defp transport_error_struct_from_core(error, state) do
    case normalize_transport_reason(error) do
      %Errors.CLIJSONDecodeError{} = normalized ->
        normalized

      _other ->
        error
        |> provider_runtime_failure(state)
        |> runtime_failure_error_struct()
    end
  end

  defp transport_error_struct_fallback(error) do
    %Errors.ClaudeSDKError{
      message: "Transport error: #{inspect(error)}",
      cause: error
    }
  end

  defp build_transport_command(%Options{} = options, args) when is_list(args) do
    case CLI.resolve_command_spec(options) do
      {:ok, %CommandSpec{} = command_spec} ->
        {:ok,
         CoreCommand.new(command_spec, args,
           cwd: options.cwd,
           env: ClaudeAgentSDK.Process.__env_vars__(options),
           user: options.user
         )}

      {:error, :not_found} ->
        {:error, :cli_not_found}
    end
  end

  defp transport_error_mode(%Options{transport_error_mode: :raise}), do: :raise
  defp transport_error_mode(_options), do: :result

  defp should_use_mock?(%Options{} = options) do
    Runtime.use_mock?() and not Runtime.force_real?(options)
  end

  defp validate_no_transport_override!(nil), do: :ok

  defp validate_no_transport_override!(other) do
    raise ArgumentError,
          "custom transport injection has been removed; use execution_surface instead: #{inspect(other)}"
  end

  defp normalize_transport_reason(error) do
    if CoreTransportError.match?(error) do
      normalize_transport_reason(
        CoreTransportError.reason(error),
        CoreTransportError.context(error)
      )
    else
      normalize_transport_reason(error, %{})
    end
  end

  defp normalize_transport_reason({:buffer_overflow, actual_size, max_size}, context) do
    %Errors.CLIJSONDecodeError{
      message: "JSON message exceeded maximum buffer size of #{max_size} bytes",
      line: Map.get(context, :preview, ""),
      original_error: {:buffer_overflow, actual_size, max_size}
    }
  end

  defp normalize_transport_reason({:command_not_found, command}, _context)
       when command in ["claude", "claude-code"],
       do: :cli_not_found

  defp normalize_transport_reason(:noproc, _context), do: :not_connected
  defp normalize_transport_reason({:call_exit, :noproc}, _context), do: :not_connected
  defp normalize_transport_reason({:transport, :noproc}, _context), do: :not_connected
  defp normalize_transport_reason(reason, _context), do: reason

  defp provider_runtime_failure(reason, state) do
    ProviderCLI.runtime_failure(
      :claude,
      reason,
      execution_surface: Map.get(state, :execution_surface),
      cwd: Map.get(state, :cwd),
      command: Map.get(state, :command)
    )
  end

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

  defp runtime_failure_error_struct(%ProviderCLI.ErrorRuntimeFailure{kind: :auth_error} = failure) do
    %Errors.ProcessError{
      message: failure.message,
      exit_code: failure.exit_code,
      stderr: blank_to_nil(failure.stderr)
    }
  end

  defp runtime_failure_error_struct(%ProviderCLI.ErrorRuntimeFailure{} = failure) do
    %Errors.ProcessError{
      message: failure.message,
      exit_code: failure.exit_code,
      stderr: blank_to_nil(failure.stderr)
    }
  end

  defp transport_error_details(:cli_not_found, state) do
    runtime_failure_details(
      provider_runtime_failure(CoreProcessExit.from_reason({:exit_status, 127}), state)
    )
  end

  defp transport_error_details(error, state) when is_exception(error) do
    if CoreTransportError.match?(error) do
      transport_error_details_from_core(error, state)
    end
  end

  defp transport_error_details(error, state) do
    cond do
      CoreTransportError.match?(error) ->
        transport_error_details_from_core(error, state)

      CoreProcessExit.match?(error) ->
        runtime_failure_details(provider_runtime_failure(error, state))

      true ->
        nil
    end
  end

  defp transport_error_details_from_core(error, state) do
    case normalize_transport_reason(error) do
      %Errors.CLIJSONDecodeError{} ->
        nil

      _other ->
        runtime_failure_details(provider_runtime_failure(error, state))
    end
  end

  defp runtime_failure_details(%ProviderCLI.ErrorRuntimeFailure{} = failure) do
    %{}
    |> maybe_put_detail(:kind, failure.kind)
    |> maybe_put_detail(:exit_code, failure.exit_code)
    |> maybe_put_detail(:stderr, blank_to_nil(failure.stderr))
    |> maybe_put_detail(:cwd, failure.context[:cwd])
    |> maybe_put_detail(:destination, failure.context[:destination])
  end

  defp transport_command_name(%Options{} = options) do
    options.executable || options.path_to_claude_code_executable || "claude-code"
  end

  defp normalize_exit(reason) do
    if CoreProcessExit.match?(reason), do: reason, else: CoreProcessExit.from_reason(reason)
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value) when is_binary(value), do: value

  defp maybe_put_detail(details, _key, nil), do: details
  defp maybe_put_detail(details, key, value), do: Map.put(details, key, value)

  defp mock_prompt_from(prompt) when is_binary(prompt), do: prompt

  defp mock_prompt_from(prompt) do
    Enum.find_value(prompt, fn
      %{"message" => %{"content" => content}} when is_binary(content) -> content
      _ -> nil
    end)
  end
end
