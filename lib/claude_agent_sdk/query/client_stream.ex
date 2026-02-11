defmodule ClaudeAgentSDK.Query.ClientStream do
  @moduledoc """
  Wraps the `ClaudeAgentSDK.Client` GenServer to provide a Stream interface.

  This module enables `ClaudeAgentSDK.query/2` to work with SDK MCP servers
  (and other control-protocol features like hooks and permission callbacks)
  by using the control client internally while maintaining the same Stream API.

  ## Why This Exists

  SDK MCP servers require bidirectional communication (control protocol) to work.
  The simple `Process.stream` approach is unidirectional and cannot handle
  `control_request` messages from the CLI. This module bridges the gap by:

  1. Starting a Client GenServer (which handles control protocol)
  2. Sending the query message
  3. Wrapping Client.stream_messages as a Stream
  4. Cleaning up the Client when done

  ## Usage

  This module is used internally by `ClaudeAgentSDK.Query` and should not
  be called directly. Use `ClaudeAgentSDK.query/2` as normal.
  """

  alias ClaudeAgentSDK.{Client, Message, Options}
  alias ClaudeAgentSDK.Config.Timeouts
  alias ClaudeAgentSDK.Log, as: Logger

  @doc """
  Creates a Stream backed by a Client GenServer.

  This function starts a Client, sends the prompt, and returns a Stream that
  yields `ClaudeAgentSDK.Message` structs from the client's mailbox. The Client is
  automatically stopped after
  the stream is exhausted.

  ## Parameters

  - `prompt` - The prompt to send to Claude
  - `options` - Configuration options (must contain SDK MCP servers)

  ## Returns

  A Stream of `ClaudeAgentSDK.Message` structs.
  """
  @spec stream(String.t() | Enumerable.t(), Options.t(), term() | nil) ::
          Enumerable.t(Message.t())
  def stream(prompt, %Options{} = options, transport \\ nil) do
    Stream.resource(
      fn -> start_client_and_send(prompt, options, transport) end,
      &stream_next/1,
      &cleanup_client/1
    )
  end

  defp start_client_and_send(prompt, options, transport) do
    Logger.debug("Starting control client for query", prompt_type: prompt_type(prompt))

    start_opts = client_start_opts(transport)

    case Client.start_link(options, start_opts) do
      {:ok, client_pid} ->
        initialize_and_send(client_pid, prompt, options)

      {:error, reason} ->
        Logger.error("Failed to start control client for query", error: inspect(reason))
        make_error_result("Failed to start Client: #{inspect(reason)}")
    end
  end

  defp initialize_and_send(client_pid, prompt, options) do
    {client_pid, ref} = Client.subscribe(client_pid)
    deadline_ms = System.monotonic_time(:millisecond) + query_timeout_ms(options)

    with :ok <- await_initialized(client_pid, options),
         :ok <- send_prompt(client_pid, prompt) do
      {:ok, %{client: client_pid, ref: ref, done?: false, deadline_ms: deadline_ms}}
    else
      {:error, reason} ->
        safe_stop(client_pid)
        make_error_result("Failed to initialize or send prompt: #{inspect(reason)}")
    end
  end

  defp await_initialized(client_pid, %Options{} = options) do
    await_initialized(client_pid, init_timeout_ms(options))
  end

  defp await_initialized(client_pid, timeout_ms)
       when is_pid(client_pid) and is_integer(timeout_ms) do
    Client.await_initialized(client_pid, timeout_ms)
  end

  defp init_timeout_ms(%Options{} = options) do
    default_ms = (Client.init_timeout_seconds_from_env() * 1_000) |> trunc()

    case options.timeout_ms do
      timeout_ms when is_integer(timeout_ms) and timeout_ms > 0 -> min(timeout_ms, default_ms)
      _ -> default_ms
    end
  end

  defp stream_next({:error, [msg | rest]}), do: {[msg], {:error, rest}}
  defp stream_next({:error, []}), do: {:halt, {:error, []}}

  defp stream_next({:ok, %{done?: true} = state}), do: {:halt, {:ok, state}}

  defp stream_next({:ok, %{client: client_pid, ref: ref} = state}) do
    receive do
      {:claude_message, %Message{} = message} ->
        if Message.final?(message) do
          {[message], {:ok, %{state | done?: true}}}
        else
          {[message], {:ok, state}}
        end

      {:stream_event, ^ref, event} ->
        msg = %Message{
          type: :stream_event,
          subtype: nil,
          data: stream_event_data(event),
          raw: %{}
        }

        {[msg], {:ok, state}}
    after
      Timeouts.stream_receive_ms() ->
        cond do
          query_timed_out?(state) ->
            safe_stop(client_pid)

            error_msg =
              Message.error_result("Timed out waiting for Claude CLI response",
                session_id: "timeout"
              )

            {[error_msg], {:ok, %{state | done?: true}}}

          process_running?(client_pid) ->
            stream_next({:ok, state})

          true ->
            {:halt, {:ok, state}}
        end
    end
  end

  defp stream_event_data(event) when is_map(event) do
    raw_event = Map.get(event, :raw_event, event)

    %{
      event: raw_event,
      uuid: Map.get(event, :uuid),
      session_id: Map.get(event, :session_id),
      parent_tool_use_id: Map.get(event, :parent_tool_use_id)
    }
  end

  defp query_timeout_ms(%Options{timeout_ms: timeout_ms})
       when is_integer(timeout_ms) and timeout_ms > 0,
       do: timeout_ms

  defp query_timeout_ms(_), do: Timeouts.query_total_ms()

  defp query_timed_out?(%{deadline_ms: deadline_ms})
       when is_integer(deadline_ms) do
    System.monotonic_time(:millisecond) > deadline_ms
  end

  defp query_timed_out?(_), do: false

  defp safe_stop(client_pid) when is_pid(client_pid) do
    Client.stop(client_pid)
  catch
    :exit, {:noproc, _} -> :ok
    :exit, :noproc -> :ok
  else
    _ -> :ok
  after
    :ok
  end

  defp cleanup_client({:ok, %{client: client_pid, ref: ref}}) when is_pid(client_pid) do
    Logger.debug("Stopping control client for query", pid: inspect(client_pid))

    maybe_unsubscribe(client_pid, ref)
    close_client_with_timeout(client_pid, Timeouts.client_close_grace_ms())
  end

  defp cleanup_client(_), do: :ok

  defp client_start_opts(nil), do: []

  defp client_start_opts({module, opts}) when is_atom(module) and is_list(opts) do
    [transport: module, transport_opts: opts]
  end

  defp client_start_opts(module) when is_atom(module) do
    [transport: module]
  end

  defp client_start_opts(other) do
    raise ArgumentError, "Unsupported transport spec: #{inspect(other)}"
  end

  defp send_prompt(client_pid, prompt) when is_binary(prompt) do
    Client.send_message(client_pid, prompt)
  end

  defp send_prompt(client_pid, prompt) do
    Client.query(client_pid, prompt)
  end

  defp prompt_type(prompt) when is_binary(prompt), do: :string
  defp prompt_type(_prompt), do: :stream

  defp make_error_result(error_message) do
    error_msg = Message.error_result(error_message)

    {:error, [error_msg]}
  end

  defp maybe_unsubscribe(client_pid, ref) when is_pid(client_pid) and is_reference(ref) do
    GenServer.cast(client_pid, {:unsubscribe, ref})
  catch
    :exit, {:noproc, _} -> :ok
    :exit, :noproc -> :ok
  end

  defp maybe_unsubscribe(_client_pid, _ref), do: :ok

  defp process_running?(pid) when is_pid(pid), do: Process.info(pid, :status) != nil

  defp close_client_with_timeout(client_pid, timeout_ms)
       when is_pid(client_pid) and is_integer(timeout_ms) and timeout_ms >= 0 do
    ref = Process.monitor(client_pid)

    case await_client_down(ref, client_pid, timeout_ms) do
      :down ->
        :ok

      :timeout ->
        safe_stop(client_pid)
        _ = await_client_down(ref, client_pid, 250)
        Process.demonitor(ref, [:flush])
        :ok
    end
  end

  defp await_client_down(ref, client_pid, timeout_ms)
       when is_reference(ref) and is_pid(client_pid) and is_integer(timeout_ms) and
              timeout_ms >= 0 do
    receive do
      {:DOWN, ^ref, :process, ^client_pid, _reason} ->
        :down
    after
      timeout_ms ->
        :timeout
    end
  end
end
