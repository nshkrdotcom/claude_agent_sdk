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
  alias CliSubprocessCore.Command, as: CoreCommand
  alias CliSubprocessCore.CommandSpec
  alias CliSubprocessCore.Transport, as: CoreTransport
  alias CliSubprocessCore.Transport.Error, as: CoreTransportError

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
    transport_ref = make_ref()

    with {:ok, command} <- build_transport_command(options, args),
         {:ok, transport_pid} <-
           CoreTransport.start_link(
             [
               command: command,
               subscriber: {self(), transport_ref},
               event_tag: @transport_event_tag,
               stderr_callback: nil
             ] ++
               Options.execution_surface_options(options)
           ),
         :ok <- CoreTransport.subscribe(transport_pid, self(), transport_ref),
         {:ok, input_task} <- maybe_stream_input(transport_pid, input) do
      %{
        transport: transport_pid,
        transport_ref: transport_ref,
        input_task: input_task,
        done?: false,
        transport_error_mode: transport_error_mode(options),
        # Track if we've received at least one message for better error diagnostics
        received_first_message?: false,
        # Track if we've received the result for stream completion detection
        received_result?: false
      }
    else
      {:error, reason} ->
        error_msg = Message.error_result("Failed to start CLI transport: #{inspect(reason)}")

        {:error, [error_msg]}
    end
  end

  # For non-streaming queries (nil input), close stdin immediately so the CLI starts processing
  defp maybe_stream_input(transport, nil) do
    case CoreTransport.end_input(transport) do
      :ok -> {:ok, nil}
      {:error, reason} -> {:error, {:end_input_failed, normalize_transport_reason(reason)}}
    end
  end

  defp maybe_stream_input(transport, input) do
    with {:ok, pid} <-
           TaskSupervisor.start_child(fn -> stream_input_messages(transport, input) end) do
      {:ok, %{pid: pid, monitor_ref: Process.monitor(pid)}}
    end
  end

  defp stream_input_messages(transport, input) do
    send_result =
      Enum.reduce_while(input, :ok, fn message, _acc ->
        case CoreTransport.send(transport, message) do
          :ok ->
            {:cont, :ok}

          {:error, reason} ->
            {:halt, {:error, {:send_failed, normalize_transport_reason(reason)}}}
        end
      end)

    end_result =
      case CoreTransport.end_input(transport) do
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

      {:transport_exit, _reason} ->
        maybe_halt_after_transport_exit(state)
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

      {:transport_exit, _reason} ->
        maybe_halt_after_transport_exit(state)
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

        state =
          if Message.final?(message),
            do: %{state | received_result?: true, done?: true},
            else: state

        {[message], state}

      {:error, error} ->
        handle_transport_error(error, state)
    end
  end

  defp parse_message(line) do
    case Message.from_json(line) do
      {:ok, message} ->
        {:ok, message}

      {:error, reason} ->
        {:error, json_decode_error(line, reason)}
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

  defp handle_transport_error(error, %{transport_error_mode: :raise}) do
    raise transport_error_struct(error)
  end

  defp handle_transport_error(error, state) do
    {[transport_error_message(error)], %{state | done?: true}}
  end

  defp transport_error_message(error) do
    error_struct = transport_error_struct(error)
    Message.error_result(Exception.message(error_struct), error_struct: error_struct)
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

  defp cleanup(%{transport: transport, transport_ref: transport_ref, input_task: task}) do
    cleanup_input_task(task)
    close_transport_with_timeout(transport, Timeouts.transport_close_grace_ms())
    flush_transport_messages(transport_ref)

    :ok
  end

  defp cleanup(_), do: :ok

  defp cleanup_input_task(%{pid: pid, monitor_ref: monitor_ref}) do
    Process.demonitor(monitor_ref, [:flush])
    Process.exit(pid, :kill)
    :ok
  end

  defp cleanup_input_task(_), do: :ok

  defp close_transport_with_timeout(transport, timeout_ms) when is_pid(transport) do
    ref = Process.monitor(transport)

    _ = safe_force_close(transport)
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
  defp handle_transport_event({:exit, _reason}, state), do: maybe_halt_after_transport_exit(state)

  defp maybe_halt_after_transport_exit(state) do
    if process_running?(state.transport) do
      receive_next(state)
    else
      {:halt, %{state | done?: true}}
    end
  end

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

  defp safe_force_close(transport) when is_pid(transport) do
    CoreTransport.force_close(transport)
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

  defp transport_error_struct(%Errors.CLIJSONDecodeError{} = error), do: error
  defp transport_error_struct(%Errors.CLIConnectionError{} = error), do: error
  defp transport_error_struct(%Errors.CLINotFoundError{} = error), do: error
  defp transport_error_struct(%Errors.ProcessError{} = error), do: error
  defp transport_error_struct(%Errors.ClaudeSDKError{} = error), do: error

  defp transport_error_struct(%CoreTransportError{} = error) do
    case normalize_transport_reason(error) do
      %Errors.CLIJSONDecodeError{} = normalized ->
        normalized

      :cli_not_found ->
        %Errors.CLINotFoundError{
          message:
            "Claude CLI not found. Please install with: #{ClaudeAgentSDK.Config.CLI.install_command()}"
        }

      normalized ->
        %Errors.ClaudeSDKError{
          message: "Transport error: #{inspect(normalized)}",
          cause: error
        }
    end
  end

  defp transport_error_struct(error) do
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

  defp normalize_transport_reason(%CoreTransportError{
         reason: {:buffer_overflow, actual_size, max_size},
         context: context
       }) do
    %Errors.CLIJSONDecodeError{
      message: "JSON message exceeded maximum buffer size of #{max_size} bytes",
      line: Map.get(context, :preview, ""),
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

  defp mock_prompt_from(prompt) when is_binary(prompt), do: prompt

  defp mock_prompt_from(prompt) do
    Enum.find_value(prompt, fn
      %{"message" => %{"content" => content}} when is_binary(content) -> content
      _ -> nil
    end)
  end
end
