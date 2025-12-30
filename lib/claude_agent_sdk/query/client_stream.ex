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
  require Logger

  @default_receive_timeout_ms 30_000
  @default_query_timeout_ms 4_500_000

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
  @spec stream(String.t(), Options.t()) :: Enumerable.t(Message.t())
  def stream(prompt, %Options{} = options) do
    Stream.resource(
      fn -> start_client_and_send(prompt, options) end,
      &stream_next/1,
      &cleanup_client/1
    )
  end

  defp start_client_and_send(prompt, options) do
    Logger.debug("Starting control client for query", prompt_length: String.length(prompt))

    case Client.start_link(options) do
      {:ok, client_pid} ->
        {client_pid, ref} = Client.subscribe(client_pid)
        deadline_ms = System.monotonic_time(:millisecond) + query_timeout_ms(options)

        case await_initialized(client_pid, options) do
          :ok ->
            :ok = Client.send_message(client_pid, prompt)
            {:ok, %{client: client_pid, ref: ref, done?: false, deadline_ms: deadline_ms}}

          {:error, reason} ->
            safe_stop(client_pid)

            error_msg = %Message{
              type: :result,
              subtype: :error_during_execution,
              data: %{
                error: "Failed to initialize Client: #{inspect(reason)}",
                session_id: "error",
                is_error: true
              }
            }

            {:error, [error_msg]}
        end

      {:error, reason} ->
        Logger.error("Failed to start control client for query", error: inspect(reason))

        error_msg = %Message{
          type: :result,
          subtype: :error_during_execution,
          data: %{
            error: "Failed to start Client: #{inspect(reason)}",
            session_id: "error",
            is_error: true
          }
        }

        {:error, [error_msg]}
    end
  end

  defp await_initialized(client_pid, %Options{} = options) do
    await_initialized(client_pid, init_timeout_ms(options))
  end

  defp await_initialized(client_pid, timeout_ms)
       when is_pid(client_pid) and is_integer(timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_await_initialized(client_pid, deadline)
  end

  defp init_timeout_ms(%Options{} = options) do
    default_ms = (Client.init_timeout_seconds_from_env() * 1_000) |> trunc()

    case options.timeout_ms do
      timeout_ms when is_integer(timeout_ms) and timeout_ms > 0 -> min(timeout_ms, default_ms)
      _ -> default_ms
    end
  end

  defp do_await_initialized(client_pid, deadline_ms) do
    if System.monotonic_time(:millisecond) > deadline_ms do
      {:error, :timeout}
    else
      state = :sys.get_state(client_pid)

      if Map.get(state, :initialized) == true do
        :ok
      else
        Process.sleep(50)
        do_await_initialized(client_pid, deadline_ms)
      end
    end
  rescue
    e ->
      Logger.debug("Client state check failed: #{Exception.message(e)}")
      {:error, :client_not_alive}
  catch
    :exit, reason ->
      Logger.debug("Client exited during state check: #{inspect(reason)}")
      {:error, :client_not_alive}
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
        msg = %Message{type: :stream_event, subtype: nil, data: %{event: event}, raw: %{}}
        {[msg], {:ok, state}}
    after
      @default_receive_timeout_ms ->
        cond do
          query_timed_out?(state) ->
            safe_stop(client_pid)

            error_msg = %Message{
              type: :result,
              subtype: :error_during_execution,
              data: %{
                error: "Timed out waiting for Claude CLI response",
                session_id: "timeout",
                is_error: true
              }
            }

            {[error_msg], {:ok, %{state | done?: true}}}

          Process.alive?(client_pid) ->
            stream_next({:ok, state})

          true ->
            {:halt, {:ok, state}}
        end
    end
  end

  defp query_timeout_ms(%Options{timeout_ms: timeout_ms})
       when is_integer(timeout_ms) and timeout_ms > 0,
       do: timeout_ms

  defp query_timeout_ms(_), do: @default_query_timeout_ms

  defp query_timed_out?(%{deadline_ms: deadline_ms})
       when is_integer(deadline_ms) do
    System.monotonic_time(:millisecond) > deadline_ms
  end

  defp query_timed_out?(_), do: false

  defp safe_stop(client_pid) when is_pid(client_pid) do
    if Process.alive?(client_pid) do
      Client.stop(client_pid)
    end

    :ok
  end

  defp cleanup_client({:ok, %{client: client_pid, ref: ref}}) when is_pid(client_pid) do
    Logger.debug("Stopping control client for query", pid: inspect(client_pid))

    if is_reference(ref) and Process.alive?(client_pid) do
      GenServer.cast(client_pid, {:unsubscribe, ref})
    end

    safe_stop(client_pid)
  end

  defp cleanup_client(_), do: :ok
end
