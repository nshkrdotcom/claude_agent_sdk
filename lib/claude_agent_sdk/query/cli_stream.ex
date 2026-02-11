defmodule ClaudeAgentSDK.Query.CLIStream do
  @moduledoc """
  Streams CLI-only query responses over a transport.

  This module is used for unidirectional, non-control queries. It supports:
  - String prompts (sent as stream-json user messages via stdin)
  - Enumerable prompts (streamed via stdin)
  - Optional transport injection
  """

  alias ClaudeAgentSDK.{
    CLI,
    Errors,
    Message,
    Options,
    ProcessSupport,
    Runtime,
    TaskSupervisor,
    Transport
  }

  alias ClaudeAgentSDK.Config.{Buffers, Timeouts}
  alias ClaudeAgentSDK.Config.CLI, as: CLIConfig

  @type transport_spec :: module() | {module(), keyword()} | nil

  @doc """
  Streams messages for a single query prompt.
  """
  @spec stream(String.t() | Enumerable.t(), Options.t(), transport_spec()) ::
          Enumerable.t(Message.t())
  def stream(prompt, %Options{} = options, transport \\ nil) do
    {args, input} = build_prompt_args(prompt, options)

    if should_use_mock?(transport, options) do
      mock_prompt = mock_prompt_from(prompt)
      ClaudeAgentSDK.Mock.Process.stream(args, options, mock_prompt)
    else
      stream_args(args, options, transport, input)
    end
  end

  @doc false
  @spec stream_args([String.t()], Options.t(), transport_spec(), Enumerable.t() | nil) ::
          Enumerable.t(Message.t())
  def stream_args(args, %Options{} = options, transport \\ nil, input \\ nil) do
    if should_use_mock?(transport, options) do
      mock_prompt =
        cond do
          is_binary(input) -> input
          is_nil(input) -> nil
          true -> mock_prompt_from(input)
        end

      ClaudeAgentSDK.Mock.Process.stream(args, options, mock_prompt)
    else
      Stream.resource(
        fn -> start_transport(args, options, transport, input) end,
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

  defp start_transport(args, %Options{} = options, transport, input) do
    drain_stale_transport_messages()

    {module, transport_opts} = normalize_transport(transport, options, input)

    transport_opts =
      transport_opts
      |> Keyword.put_new(:args, args)
      |> Keyword.put_new(:options, options)

    transport_ref = make_ref()
    transport_opts = maybe_put_bootstrap_subscriber(module, transport_opts, transport_ref)

    with {:ok, transport_opts} <- maybe_put_cli_command(module, transport_opts, options),
         {:ok, transport_pid} <- module.start_link(transport_opts),
         :ok <- subscribe_transport(module, transport_pid, transport_ref),
         {:ok, input_task} <- maybe_stream_input(module, transport_pid, input) do
      %{
        module: module,
        transport: transport_pid,
        transport_ref: transport_ref,
        input_task: input_task,
        done?: false,
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

  defp maybe_put_cli_command(module, transport_opts, options) do
    if needs_cli_command?(module, transport_opts) do
      with {:ok, executable} <- CLI.resolve_executable(options) do
        _ = CLI.warn_if_outdated()
        {:ok, Keyword.put_new(transport_opts, :command, executable)}
      end
    else
      {:ok, transport_opts}
    end
  end

  defp needs_cli_command?(module, transport_opts) do
    module == ClaudeAgentSDK.Transport.Erlexec and
      Keyword.get(transport_opts, :command) == nil
  end

  defp normalize_transport(nil, _options, input) do
    module = ClaudeAgentSDK.Transport.Erlexec
    ensure_streaming_transport!(module, input)
    {module, []}
  end

  defp normalize_transport({module, opts}, _options, input) when is_atom(module) do
    ensure_streaming_transport!(module, input)
    {module, opts}
  end

  defp normalize_transport(module, _options, input) when is_atom(module) do
    ensure_streaming_transport!(module, input)
    {module, []}
  end

  defp normalize_transport(other, _options, _input) do
    raise ArgumentError, "Unsupported transport spec: #{inspect(other)}"
  end

  defp ensure_streaming_transport!(_module, nil), do: :ok

  defp ensure_streaming_transport!(module, _input) do
    _ = Code.ensure_loaded(module)

    unless function_exported?(module, :end_input, 1) do
      raise ArgumentError,
            "Streaming prompts require a transport with end_input/1. " <>
              "Use ClaudeAgentSDK.Transport.Erlexec or provide a compatible transport."
    end

    :ok
  end

  # For non-streaming queries (nil input), close stdin immediately so the CLI starts processing
  defp maybe_stream_input(module, transport, nil) do
    if function_exported?(module, :end_input, 1) do
      case module.end_input(transport) do
        :ok -> {:ok, nil}
        {:error, reason} -> {:error, {:end_input_failed, Transport.normalize_reason(reason)}}
      end
    else
      {:ok, nil}
    end
  end

  defp maybe_stream_input(module, transport, input) do
    with {:ok, pid} <-
           TaskSupervisor.start_child(fn -> stream_input_messages(module, transport, input) end) do
      {:ok, %{pid: pid, monitor_ref: Process.monitor(pid)}}
    end
  end

  defp stream_input_messages(module, transport, input) do
    send_result =
      Enum.reduce_while(input, :ok, fn message, _acc ->
        case module.send(transport, message) do
          :ok ->
            {:cont, :ok}

          {:error, reason} ->
            {:halt, {:error, {:send_failed, Transport.normalize_reason(reason)}}}
        end
      end)

    end_result =
      case module.end_input(transport) do
        :ok -> :ok
        {:error, reason} -> {:error, Transport.normalize_reason(reason)}
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

  defp receive_next(state) do
    receive do
      {:DOWN, monitor_ref, :process, _pid, reason} ->
        maybe_handle_input_task_down(state, monitor_ref, reason)

      {:claude_agent_sdk_transport, ref, {:message, line}}
      when ref == state.transport_ref and is_binary(line) ->
        handle_line(line, state)

      {:claude_agent_sdk_transport, ref, {:error, error}} when ref == state.transport_ref ->
        {[transport_error_message(error)], %{state | done?: true}}

      {:claude_agent_sdk_transport, ref, {:stderr, _data}} when ref == state.transport_ref ->
        receive_next(state)

      {:claude_agent_sdk_transport, ref, {:exit, _reason}} when ref == state.transport_ref ->
        if process_running?(state.transport) do
          receive_next(state)
        else
          {:halt, %{state | done?: true}}
        end

      {:transport_message, line} when is_binary(line) ->
        handle_line(line, state)

      {:transport_error, error} ->
        {[transport_error_message(error)], %{state | done?: true}}

      {:transport_exit, _reason} ->
        if process_running?(state.transport) do
          receive_next(state)
        else
          {:halt, %{state | done?: true}}
        end
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

      {:error, message} ->
        {[message], %{state | done?: true}}
    end
  end

  defp parse_message(line) do
    case Message.from_json(line) do
      {:ok, message} ->
        {:ok, message}

      {:error, reason} ->
        {:error, json_decode_error_message(line, reason)}
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

  defp transport_error_message(%Errors.CLIJSONDecodeError{} = error) do
    Message.error_result(Exception.message(error), error_struct: error)
  end

  defp transport_error_message(error) do
    Message.error_result("Transport error: #{inspect(error)}", error_struct: error)
  end

  defp input_task_error_message(reason) do
    Message.error_result("Input stream worker failed: #{inspect(reason)}", error_struct: reason)
  end

  defp maybe_handle_input_task_down(%{input_task: nil} = state, _monitor_ref, _reason) do
    receive_next(state)
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
         module: module,
         transport: transport,
         transport_ref: transport_ref,
         input_task: task
       }) do
    cleanup_input_task(task)
    close_transport_with_timeout(module, transport, Timeouts.transport_close_grace_ms())
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

  defp close_transport_with_timeout(module, transport, timeout_ms) when is_pid(transport) do
    ref = Process.monitor(transport)

    if module == ClaudeAgentSDK.Transport.Erlexec do
      case ProcessSupport.await_down(ref, transport, timeout_ms) do
        :down ->
          :ok

        :timeout ->
          _ = safe_force_close(module, transport)
          await_down_or_shutdown(ref, transport, 250)
      end
    else
      _ = safe_force_close(module, transport)
      await_down_or_shutdown(ref, transport, timeout_ms)
    end
  end

  defp close_transport_with_timeout(_module, _transport, _timeout_ms), do: :ok

  defp drain_stale_transport_messages do
    receive do
      {:claude_agent_sdk_transport, _ref, _event} ->
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
      {:claude_agent_sdk_transport, ^ref, _event} ->
        flush_transport_messages(ref)
    after
      0 ->
        :ok
    end
  end

  defp flush_transport_messages(_), do: :ok

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

  defp safe_force_close(module, transport) when is_pid(transport) do
    if function_exported?(module, :force_close, 1) do
      module.force_close(transport)
    else
      module.close(transport)
    end
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

  defp subscribe_transport(module, transport_pid, transport_ref) do
    cond do
      function_exported?(module, :subscribe, 3) ->
        module.subscribe(transport_pid, self(), transport_ref)

      function_exported?(module, :subscribe, 2) ->
        module.subscribe(transport_pid, self())

      true ->
        {:error, :subscribe_not_supported}
    end
  end

  defp maybe_put_bootstrap_subscriber(module, transport_opts, transport_ref) do
    if module == ClaudeAgentSDK.Transport.Erlexec do
      Keyword.put_new(transport_opts, :subscriber, {self(), transport_ref})
    else
      transport_opts
    end
  end

  defp process_running?(pid) when is_pid(pid), do: Process.info(pid, :status) != nil
  defp process_running?(_pid), do: false

  defp should_use_mock?(transport, %Options{} = options) do
    Runtime.use_mock?() and is_nil(transport) and not Runtime.force_real?(options)
  end

  defp mock_prompt_from(prompt) when is_binary(prompt), do: prompt

  defp mock_prompt_from(prompt) do
    Enum.find_value(prompt, fn
      %{"message" => %{"content" => content}} when is_binary(content) -> content
      _ -> nil
    end)
  end
end
