defmodule ClaudeAgentSDK.Query.CLIStream do
  @moduledoc """
  Streams CLI-only query responses over a transport.

  This module is used for unidirectional, non-control queries. It supports:
  - String prompts (passed as CLI args)
  - Enumerable prompts (streamed via stdin)
  - Optional transport injection
  """

  alias ClaudeAgentSDK.{CLI, Errors, Message, Options, Runtime, TaskSupervisor, Transport}

  @type transport_spec :: module() | {module(), keyword()} | nil
  @transport_close_grace_ms 2_000

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
    {base_args ++ ["--", prompt], nil}
  end

  defp build_prompt_args(prompt, %Options{} = options) do
    base_args = base_stream_args(options)
    {["--input-format", "stream-json"] ++ base_args, prompt}
  end

  defp base_stream_args(%Options{} = options) do
    ["--output-format", "stream-json", "--verbose"] ++ Options.to_stream_json_args(options)
  end

  defp start_transport(args, %Options{} = options, transport, input) do
    drain_stale_transport_messages()

    {module, transport_opts} = normalize_transport(transport, options, input)

    transport_opts =
      transport_opts
      |> Keyword.put_new(:args, args)
      |> Keyword.put_new(:options, options)

    with {:ok, transport_opts} <- maybe_put_cli_command(module, transport_opts, options),
         {:ok, transport_pid} <- module.start_link(transport_opts),
         :ok <- module.subscribe(transport_pid, self()),
         {:ok, input_task} <- maybe_stream_input(module, transport_pid, input) do
      %{
        module: module,
        transport: transport_pid,
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
      30_000 ->
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
        message: "Failed to decode JSON: #{String.slice(line, 0, 100)}...",
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

  defp cleanup(%{module: module, transport: transport, input_task: task}) do
    cleanup_input_task(task)

    if graceful_close?(module) do
      wait_for_transport_exit(transport, @transport_close_grace_ms)
    end

    safe_close_transport(module, transport)

    :ok
  end

  defp cleanup(_), do: :ok

  defp cleanup_input_task(%{pid: pid, monitor_ref: monitor_ref}) do
    Process.demonitor(monitor_ref, [:flush])
    Process.exit(pid, :kill)
    :ok
  end

  defp cleanup_input_task(_), do: :ok

  defp safe_close_transport(module, transport) when is_pid(transport) do
    _ = module.close(transport)
    :ok
  catch
    :exit, {:noproc, _} -> :ok
    :exit, :noproc -> :ok
  end

  defp safe_close_transport(_module, _transport), do: :ok

  defp drain_stale_transport_messages do
    receive do
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

  defp wait_for_transport_exit(transport, timeout_ms)
       when is_pid(transport) and is_integer(timeout_ms) and timeout_ms > 0 do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_transport_exit(transport, deadline)
  end

  defp wait_for_transport_exit(_transport, _timeout_ms), do: :ok

  defp do_wait_for_transport_exit(transport, deadline_ms) do
    cond do
      not process_running?(transport) ->
        :ok

      System.monotonic_time(:millisecond) >= deadline_ms ->
        :ok

      true ->
        Process.sleep(20)
        do_wait_for_transport_exit(transport, deadline_ms)
    end
  end

  defp graceful_close?(module) do
    module == ClaudeAgentSDK.Transport.Erlexec
  end

  defp process_running?(pid) when is_pid(pid), do: Process.info(pid, :status) != nil
  defp process_running?(_pid), do: false

  defp should_use_mock?(transport, %Options{} = options) do
    Runtime.use_mock?() and is_nil(transport) and not Runtime.force_real?(options)
  end

  defp mock_prompt_from(prompt) when is_binary(prompt), do: nil

  defp mock_prompt_from(prompt) do
    Enum.find_value(prompt, fn
      %{"message" => %{"content" => content}} when is_binary(content) -> content
      _ -> nil
    end)
  end
end
