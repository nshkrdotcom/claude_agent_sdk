defmodule ClaudeAgentSDK.ControlProtocol.Protocol do
  @moduledoc """
  Control protocol message encoding and decoding.

  Handles bidirectional communication with Claude CLI via control messages:
  - Initialize requests with hooks configuration
  - Hook callback requests/responses
  - Control requests/responses

  Messages are exchanged as JSON over stdin/stdout.

  ## Message Types

  ### SDK → CLI
  - `control_request` with `initialize` subtype
  - `control_response` for hook callbacks

  ### CLI → SDK
  - `control_request` with `hook_callback` subtype
  - `control_response` for initialize

  See: https://docs.anthropic.com/en/docs/claude-code/sdk
  """

  @typedoc """
  Request ID for tracking control protocol requests.
  """
  @type request_id :: String.t()

  @typedoc """
  Message type classifier.
  """
  @type message_type ::
          :control_request
          | :control_response
          | :control_cancel_request
          | :sdk_message
          | :stream_event

  @doc """
  Encodes an initialize request with hooks configuration and SDK MCP servers.

  Sends hooks configuration and SDK MCP server info to CLI during initialization
  so it knows which callbacks to invoke and which SDK servers are available.

  ## Parameters

  - `hooks_config` - Hooks configuration map (from build_hooks_config)
  - `sdk_mcp_servers` - Map of server_name => server_info for SDK servers (optional)
  - `request_id` - Optional request ID (generated if nil)

  ## Returns

  `{request_id, json_string}` tuple

  ## Examples

      hooks = %{
        "PreToolUse" => [
          %{"matcher" => "Bash", "hookCallbackIds" => ["hook_0"]}
        ]
      }

      sdk_servers = %{
        "math-tools" => %{"name" => "math-tools", "version" => "1.0.0"}
      }

      {id, json} = Protocol.encode_initialize_request(hooks, sdk_servers, nil)
  """
  @spec encode_initialize_request(map() | nil, map() | nil, request_id() | nil, map() | nil) ::
          {request_id(), String.t()}
  def encode_initialize_request(
        hooks_config,
        sdk_mcp_servers \\ nil,
        request_id \\ nil,
        agents \\ nil
      ) do
    req_id = request_id || generate_request_id()

    request_data = %{
      "subtype" => "initialize",
      "hooks" => hooks_config
    }

    # Add SDK MCP servers if provided
    request_data =
      if sdk_mcp_servers && map_size(sdk_mcp_servers) > 0 do
        Map.put(request_data, "sdkMcpServers", sdk_mcp_servers)
      else
        request_data
      end

    # Add agents if provided (Python SDK parity: agents sent via initialize, not CLI args)
    request_data =
      if agents && map_size(agents) > 0 do
        Map.put(request_data, "agents", agents)
      else
        request_data
      end

    request = %{
      "type" => "control_request",
      "request_id" => req_id,
      "request" => request_data
    }

    json = Jason.encode!(request)
    {req_id, json}
  end

  @doc """
  Encodes an MCP status control request.

  Returns `{request_id, json}`.

  ## Examples

      {id, json} = Protocol.encode_mcp_status_request()
  """
  @spec encode_mcp_status_request(request_id() | nil) :: {request_id(), String.t()}
  def encode_mcp_status_request(request_id \\ nil) do
    req_id = request_id || generate_request_id()

    request = %{
      "type" => "control_request",
      "request_id" => req_id,
      "request" => %{
        "subtype" => "mcp_status"
      }
    }

    {req_id, Jason.encode!(request)}
  end

  @doc """
  Encodes a set_model control request.

  Returns `{request_id, json}`.
  """
  @spec encode_set_model_request(String.t(), request_id() | nil) :: {request_id(), String.t()}
  def encode_set_model_request(model, request_id \\ nil) do
    model = to_string(model)
    req_id = request_id || generate_request_id()

    request = %{
      "type" => "control_request",
      "request_id" => req_id,
      "request" => %{
        "subtype" => "set_model",
        "model" => model
      }
    }

    {req_id, Jason.encode!(request)}
  end

  @doc """
  Encodes a rewind_files control request.

  Returns `{request_id, json}`.
  """
  @spec encode_rewind_files_request(String.t(), request_id() | nil) :: {request_id(), String.t()}
  def encode_rewind_files_request(user_message_id, request_id \\ nil)
      when is_binary(user_message_id) do
    req_id = request_id || generate_request_id()

    request = %{
      "type" => "control_request",
      "request_id" => req_id,
      "request" => %{
        "subtype" => "rewind_files",
        "user_message_id" => user_message_id
      }
    }

    {req_id, Jason.encode!(request)}
  end

  @doc """
  Encodes an interrupt control request.
  """
  @spec encode_interrupt_request(request_id() | nil) :: {request_id(), String.t()}
  def encode_interrupt_request(request_id \\ nil) do
    req_id = request_id || generate_request_id()

    request = %{
      "type" => "control_request",
      "request_id" => req_id,
      "request" => %{
        "subtype" => "interrupt"
      }
    }

    {req_id, Jason.encode!(request)}
  end

  @doc """
  Encodes a set_permission_mode control request.

  Returns `{request_id, json}`.
  """
  @spec encode_set_permission_mode_request(String.t(), request_id() | nil) ::
          {request_id(), String.t()}
  def encode_set_permission_mode_request(mode, request_id \\ nil) when is_binary(mode) do
    req_id = request_id || generate_request_id()

    request = %{
      "type" => "control_request",
      "request_id" => req_id,
      "request" => %{
        "subtype" => "set_permission_mode",
        "mode" => mode
      }
    }

    {req_id, Jason.encode!(request)}
  end

  @doc """
  Encodes a hook callback response.

  Sends the result of a hook callback execution back to CLI.

  ## Parameters

  - `request_id` - Request ID from CLI's hook_callback request
  - `output_or_error` - Hook output map or error string
  - `status` - `:success` or `:error`

  ## Returns

  JSON string ready to send to CLI

  ## Examples

      # Success
      output = %{hookSpecificOutput: %{permissionDecision: "allow"}}
      json = Protocol.encode_hook_response("req_123", output, :success)

      # Error
      json = Protocol.encode_hook_response("req_456", "Timeout", :error)
  """
  @spec encode_hook_response(request_id(), map() | String.t(), :success | :error) :: String.t()
  def encode_hook_response(request_id, output, :success) when is_map(output) do
    response = %{
      "type" => "control_response",
      "response" => %{
        "subtype" => "success",
        "request_id" => request_id,
        "response" => output
      }
    }

    Jason.encode!(response)
  end

  def encode_hook_response(request_id, error_message, :error) when is_binary(error_message) do
    response = %{
      "type" => "control_response",
      "response" => %{
        "subtype" => "error",
        "request_id" => request_id,
        "error" => error_message
      }
    }

    Jason.encode!(response)
  end

  @doc """
  Decodes a set_model control response.
  """
  @spec decode_set_model_response(map()) :: {:ok, String.t()} | {:error, term()}
  def decode_set_model_response(%{"response" => %{"subtype" => "success"} = response}) do
    model =
      response
      |> extract_model_from_response()

    if is_binary(model) do
      {:ok, model}
    else
      {:error, :invalid_response}
    end
  end

  def decode_set_model_response(%{"response" => %{"subtype" => "error", "error" => error}}) do
    {:error, error}
  end

  def decode_set_model_response(_), do: {:error, :invalid_response}

  defp extract_model_from_response(response) do
    model_from_result(response) || model_from_inner_response(response) ||
      model_from_direct_field(response)
  end

  defp model_from_result(response) do
    case Map.get(response, "result") || Map.get(response, :result) do
      %{} = result -> Map.get(result, "model") || Map.get(result, :model)
      _ -> nil
    end
  end

  defp model_from_inner_response(response) do
    case Map.get(response, "response") || Map.get(response, :response) do
      %{} = inner -> Map.get(inner, "model") || Map.get(inner, :model)
      _ -> nil
    end
  end

  defp model_from_direct_field(response) do
    Map.get(response, "model") || Map.get(response, :model)
  end

  @doc """
  Decodes a message from CLI.

  Parses JSON and classifies message type.

  ## Parameters

  - `json_string` - JSON message from CLI

  ## Returns

  - `{:ok, {message_type, data}}` - Successfully decoded
  - `{:error, reason}` - Failed to decode

  ## Examples

      iex> json = ~s({"type":"control_request","request_id":"req_1","request":{}})
      iex> {:ok, {type, _data}} = Protocol.decode_message(json)
      iex> type
      :control_request
  """
  @spec decode_message(String.t()) ::
          {:ok, {message_type(), map()}} | {:error, term()}
  def decode_message(""), do: {:error, :empty_message}
  def decode_message("\n"), do: {:error, :empty_message}

  def decode_message(json_string) when is_binary(json_string) do
    case Jason.decode(json_string) do
      {:ok, data} when is_map(data) ->
        type = classify_message(data)
        {:ok, {type, data}}

      {:ok, _non_map} ->
        {:error, :invalid_message_format}

      {:error, reason} ->
        {:error, {:json_decode_error, reason}}
    end
  end

  @doc """
  Generates a unique request ID.

  Format: `req_{counter}_{random_hex}`

  ## Examples

      iex> id = Protocol.generate_request_id()
      iex> String.starts_with?(id, "req_")
      true
  """
  @spec generate_request_id() :: request_id()
  def generate_request_id do
    counter = System.unique_integer([:positive])
    random_hex = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "req_#{counter}_#{random_hex}"
  end

  @doc """
  Checks if a message is a control protocol message.

  ## Parameters

  - `message` - Decoded message map

  ## Returns

  `true` if control message, `false` otherwise

  ## Examples

      iex> Protocol.control_message?(%{"type" => "control_request"})
      true

      iex> Protocol.control_message?(%{"type" => "assistant"})
      false
  """
  @spec control_message?(map()) :: boolean()
  def control_message?(%{"type" => type})
      when type in ["control_request", "control_response", "control_cancel_request"] do
    true
  end

  def control_message?(_), do: false

  ## Private Functions

  defp classify_message(%{"type" => "control_request"} = _data), do: :control_request
  defp classify_message(%{"type" => "control_response"} = _data), do: :control_response

  defp classify_message(%{"type" => "control_cancel_request"} = _data),
    do: :control_cancel_request

  # Streaming events (v0.6.0) - CLI wraps Anthropic streaming events in stream_event wrapper
  defp classify_message(%{"type" => "stream_event"} = _data), do: :stream_event

  # Streaming events - unwrapped format (from tests/MockTransport)
  defp classify_message(%{"type" => type} = _data)
       when type in [
              "message_start",
              "message_stop",
              "message_delta",
              "content_block_start",
              "content_block_delta",
              "content_block_stop"
            ],
       do: :stream_event

  defp classify_message(_data), do: :sdk_message
end
