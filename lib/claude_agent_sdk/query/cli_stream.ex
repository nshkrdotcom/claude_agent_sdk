defmodule ClaudeAgentSDK.Query.CLIStream do
  @moduledoc """
  Streams CLI-only query responses over a transport.

  This module is used for unidirectional, non-control queries. It supports:
  - String prompts (passed as CLI args)
  - Enumerable prompts (streamed via stdin)
  - Optional transport injection
  """

  alias ClaudeAgentSDK.{CLI, Errors, Message, Options, TaskSupervisor}

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
    {["--print"] ++ base_args ++ ["--", prompt], nil}
  end

  defp build_prompt_args(prompt, %Options{} = options) do
    base_args = base_stream_args(options)
    {["--print", "--input-format", "stream-json"] ++ base_args, prompt}
  end

  defp base_stream_args(%Options{} = options) do
    ["--output-format", "stream-json", "--verbose"] ++ Options.to_stream_json_args(options)
  end

  defp start_transport(args, %Options{} = options, transport, input) do
    {module, transport_opts} = normalize_transport(transport, options, input)

    transport_opts =
      transport_opts
      |> Keyword.put_new(:args, args)
      |> Keyword.put_new(:options, options)

    with {:ok, transport_opts} <- maybe_put_cli_command(module, transport_opts, options),
         {:ok, transport_pid} <- module.start_link(transport_opts),
         :ok <- module.subscribe(transport_pid, self()) do
      input_task = maybe_stream_input(module, transport_pid, input)

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
        error_msg = %Message{
          type: :result,
          subtype: :error_during_execution,
          data: %{
            error: "Failed to start CLI transport: #{inspect(reason)}",
            session_id: "error",
            is_error: true
          }
        }

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
    module in [ClaudeAgentSDK.Transport.Port, ClaudeAgentSDK.Transport.Erlexec] and
      Keyword.get(transport_opts, :command) == nil
  end

  defp normalize_transport(nil, %Options{user: user}, input) when is_binary(user) do
    module = ClaudeAgentSDK.Transport.Erlexec
    ensure_streaming_transport!(module, input)
    {module, []}
  end

  # Always use Erlexec - Port transport can't close stdin independently, and the
  # Claude CLI hangs if stdin isn't closed for non-streaming (--print) queries.
  defp normalize_transport(nil, _options, _input) do
    {ClaudeAgentSDK.Transport.Erlexec, []}
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
      module.end_input(transport)
    end

    nil
  end

  defp maybe_stream_input(module, transport, input) do
    {:ok, pid} =
      TaskSupervisor.start_child(fn -> stream_input_messages(module, transport, input) end)

    pid
  end

  defp stream_input_messages(module, transport, input) do
    Enum.each(input, fn message -> module.send(transport, message) end)
    module.end_input(transport)
  end

  defp receive_next({:error, [msg | rest]}), do: {[msg], {:error, rest}}
  defp receive_next({:error, []}), do: {:halt, {:error, []}}

  defp receive_next(%{done?: true} = state), do: {:halt, state}

  defp receive_next(state) do
    receive do
      {:transport_message, line} when is_binary(line) ->
        handle_line(line, state)

      {:transport_error, error} ->
        {[transport_error_message(error)], %{state | done?: true}}

      {:transport_exit, _reason} ->
        {:halt, %{state | done?: true}}
    after
      30_000 ->
        if Process.alive?(state.transport) do
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

  defp transport_error_message(%Errors.CLIJSONDecodeError{} = error) do
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

  defp transport_error_message(error) do
    %Message{
      type: :result,
      subtype: :error_during_execution,
      data: %{
        error: "Transport error: #{inspect(error)}",
        error_struct: error,
        session_id: "error",
        is_error: true
      }
    }
  end

  defp cleanup(%{module: module, transport: transport, input_task: task}) do
    if is_pid(task) do
      Process.exit(task, :kill)
    end

    _ = module.close(transport)
    :ok
  end

  defp cleanup(_), do: :ok

  defp should_use_mock?(transport, %Options{} = options) do
    use_mock?() and is_nil(transport) and not force_real?(options)
  end

  defp force_real?(%Options{executable: executable, path_to_claude_code_executable: path}) do
    is_binary(executable) or is_binary(path)
  end

  defp use_mock? do
    case {System.get_env("LIVE_MODE"), System.get_env("LIVE_TESTS")} do
      {"true", _} -> false
      {_, "true"} -> false
      _ -> Application.get_env(:claude_agent_sdk, :use_mock, false)
    end
  end

  defp mock_prompt_from(prompt) when is_binary(prompt), do: nil

  defp mock_prompt_from(prompt) do
    Enum.find_value(prompt, fn
      %{"message" => %{"content" => content}} when is_binary(content) -> content
      _ -> nil
    end)
  end
end
