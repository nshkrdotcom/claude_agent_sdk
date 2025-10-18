defmodule ClaudeAgentSDK.Query.ClientStream do
  @moduledoc """
  Wraps the Client GenServer to provide a Stream interface for SDK MCP support.

  This module enables `ClaudeAgentSDK.query/2` to work with SDK MCP servers
  by using the Client GenServer internally while maintaining the same Stream API.

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

  @doc """
  Creates a Stream backed by a Client GenServer.

  This function starts a Client, sends the prompt, and returns a Stream that
  wraps Client.stream_messages. The Client is automatically stopped after
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

  # Start Client and send initial message
  defp start_client_and_send(prompt, options) do
    Logger.debug("Starting Client for SDK MCP query", prompt_length: String.length(prompt))

    case Client.start_link(options) do
      {:ok, client_pid} ->
        # Send the initial message
        :ok = Client.send_message(client_pid, prompt)

        # Get the message stream
        message_stream = Client.stream_messages(client_pid)

        # Return state with stream wrapped in Enumerable.reduce
        {client_pid, message_stream}

      {:error, reason} ->
        # If Client fails to start, return error state
        Logger.error("Failed to start Client for SDK MCP query", error: inspect(reason))

        error_msg = %Message{
          type: :result,
          subtype: :error_during_execution,
          data: %{
            error: "Failed to start Client: #{inspect(reason)}",
            session_id: "error",
            is_error: true
          }
        }

        # Return a simple stream with just the error message
        {nil, [error_msg]}
    end
  end

  # Stream next element
  defp stream_next({nil, [msg | rest]}) do
    # Error state - emit buffered error messages
    {[msg], {nil, rest}}
  end

  defp stream_next({nil, []}) do
    # Error state - no more messages
    {:halt, {nil, []}}
  end

  defp stream_next({client_pid, stream}) do
    # Try to get next message from stream
    case Enum.take(stream, 1) do
      [msg] ->
        # Got a message
        if Message.final?(msg) do
          # Final message - halt after this
          {[msg], :done}
        else
          # More messages may follow
          {[msg], {client_pid, Stream.drop(stream, 1)}}
        end

      [] ->
        # No more messages
        {:halt, {client_pid, stream}}
    end
  end

  defp stream_next(:done) do
    {:halt, :done}
  end

  # Clean up the Client GenServer
  defp cleanup_client({nil, _}), do: :ok
  defp cleanup_client(:done), do: :ok

  defp cleanup_client({client_pid, _stream}) when is_pid(client_pid) do
    Logger.debug("Stopping Client for SDK MCP query", pid: inspect(client_pid))

    if Process.alive?(client_pid) do
      Client.stop(client_pid)
    end

    :ok
  end
end
