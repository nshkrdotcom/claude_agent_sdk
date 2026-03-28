defmodule ClaudeAgentSDK.ControlProtocol.Adapter do
  @moduledoc false

  @behaviour CliSubprocessCore.ProtocolAdapter

  alias ClaudeAgentSDK.ControlProtocol.Protocol

  defstruct peer_request_types: %{}

  @type t :: %__MODULE__{
          peer_request_types: %{optional(String.t()) => String.t() | nil}
        }

  @impl true
  def init(_opts), do: {:ok, %__MODULE__{}, []}

  @impl true
  def encode_request(%{request_id: request_id, frame: frame}, %__MODULE__{} = state)
      when is_binary(request_id) and is_binary(frame) do
    {:ok, request_id, ensure_newline(frame), state}
  end

  def encode_request(%{"request_id" => request_id, "frame" => frame}, %__MODULE__{} = state)
      when is_binary(request_id) and is_binary(frame) do
    {:ok, request_id, ensure_newline(frame), state}
  end

  def encode_request({request_id, frame}, %__MODULE__{} = state)
      when is_binary(request_id) and is_binary(frame) do
    {:ok, request_id, ensure_newline(frame), state}
  end

  def encode_request(other, %__MODULE__{} = _state), do: {:error, {:invalid_request, other}}

  @impl true
  def encode_notification(%{frame: frame}, %__MODULE__{} = state) when is_binary(frame) do
    {:ok, ensure_newline(frame), state}
  end

  def encode_notification(%{"frame" => frame}, %__MODULE__{} = state) when is_binary(frame) do
    {:ok, ensure_newline(frame), state}
  end

  def encode_notification(frame, %__MODULE__{} = state) when is_binary(frame) do
    {:ok, ensure_newline(frame), state}
  end

  def encode_notification(%{} = message, %__MODULE__{} = state) do
    {:ok, message |> Jason.encode!() |> ensure_newline(), state}
  end

  def encode_notification(other, %__MODULE__{} = _state),
    do: {:error, {:invalid_notification, other}}

  @impl true
  def handle_inbound(frame, %__MODULE__{} = state) when is_binary(frame) do
    case Protocol.decode_message(frame) do
      {:ok, {:control_request, %{"request_id" => request_id, "request" => request}}} ->
        request = Map.put(request, "request_id", request_id)
        subtype = Map.get(request, "subtype")

        {:ok, [{:peer_request, request_id, request}],
         put_in(state.peer_request_types[request_id], subtype)}

      {:ok, {:control_response, %{"response" => response}}} ->
        request_id = Map.get(response, "request_id")
        {:ok, [{:response, request_id, {:ok, response}}], state}

      {:ok, {:control_cancel_request, data}} ->
        {:ok, [{:notification, {:control_cancel_request, data}}], state}

      {:ok, {:stream_event, data}} ->
        {:ok, [{:notification, {:stream_event, data}}], state}

      {:ok, {:sdk_message, data}} ->
        {:ok, [{:notification, {:sdk_message, data}}], state}

      {:error, :empty_message} ->
        {:ok, [:ignore], state}

      {:error, reason} ->
        {:ok, [{:protocol_error, reason}], state}
    end
  end

  @impl true
  def encode_peer_reply(correlation_key, result, %__MODULE__{} = state) do
    subtype = Map.get(state.peer_request_types, correlation_key)

    next_state = %{
      state
      | peer_request_types: Map.delete(state.peer_request_types, correlation_key)
    }

    with {:ok, frame} <- encode_peer_reply_frame(subtype, correlation_key, result) do
      {:ok, ensure_newline(frame), next_state}
    end
  end

  defp encode_peer_reply_frame(_subtype, _request_id, {:ok, {:raw_frame, frame}})
       when is_binary(frame) do
    {:ok, frame}
  end

  defp encode_peer_reply_frame("hook_callback", request_id, {:ok, {:hook_success, output}}) do
    {:ok, Protocol.encode_hook_response(request_id, output, :success)}
  end

  defp encode_peer_reply_frame("hook_callback", request_id, {:error, reason}) do
    {:ok, Protocol.encode_hook_response(request_id, error_message(reason), :error)}
  end

  defp encode_peer_reply_frame(
         "can_use_tool",
         request_id,
         {:ok, {:permission_response, decision, permission_result, original_input}}
       ) do
    {:ok,
     Protocol.encode_permission_response(request_id, decision, permission_result, original_input)}
  end

  defp encode_peer_reply_frame("can_use_tool", request_id, {:error, reason}) do
    {:ok, Protocol.encode_permission_error_response(request_id, error_message(reason))}
  end

  defp encode_peer_reply_frame(
         subtype,
         request_id,
         {:ok, {:sdk_mcp_response, jsonrpc_response}}
       )
       when subtype in ["sdk_mcp_request", "mcp_message"] do
    {:ok, Protocol.encode_sdk_mcp_response(request_id, jsonrpc_response)}
  end

  defp encode_peer_reply_frame(_subtype, request_id, {:ok, response}) when is_map(response) do
    {:ok, encode_control_success_response(request_id, response)}
  end

  defp encode_peer_reply_frame(_subtype, request_id, {:ok, response}) do
    {:ok, encode_control_success_response(request_id, %{"result" => response})}
  end

  defp encode_peer_reply_frame(_subtype, request_id, {:error, reason}) do
    {:ok, encode_control_error_response(request_id, error_message(reason))}
  end

  defp encode_control_success_response(request_id, response) when is_binary(request_id) do
    %{
      "type" => "control_response",
      "response" => %{
        "request_id" => request_id,
        "subtype" => "success",
        "response" => response
      }
    }
    |> Jason.encode!()
  end

  defp encode_control_error_response(request_id, error_message) when is_binary(request_id) do
    %{
      "type" => "control_response",
      "response" => %{
        "request_id" => request_id,
        "subtype" => "error",
        "error" => error_message
      }
    }
    |> Jason.encode!()
  end

  defp error_message(:timeout), do: "Callback timed out"

  defp error_message({:handler_exit, reason}) do
    "Callback crashed: #{Exception.format_exit(reason) |> String.replace("\n", " ") |> String.trim()}"
  end

  defp error_message({:handler_start_failed, reason}),
    do: "Callback unavailable: #{inspect(reason)}"

  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(reason), do: inspect(reason)

  defp ensure_newline(frame) when is_binary(frame) do
    if String.ends_with?(frame, "\n"), do: frame, else: frame <> "\n"
  end
end
