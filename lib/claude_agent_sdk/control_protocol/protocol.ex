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

  require Logger

  @typedoc """
  Request ID for tracking control protocol requests.
  """
  @type request_id :: String.t()

  @typedoc """
  Message type classifier.
  """
  @type message_type :: :control_request | :control_response | :sdk_message

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
  @spec encode_initialize_request(map() | nil, map() | nil, request_id() | nil) ::
          {request_id(), String.t()}
  def encode_initialize_request(hooks_config, sdk_mcp_servers \\ nil, request_id \\ nil) do
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

    request = %{
      "type" => "control_request",
      "request_id" => req_id,
      "request" => request_data
    }

    json = Jason.encode!(request)
    {req_id, json}
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

      iex> Protocol.is_control_message?(%{"type" => "control_request"})
      true

      iex> Protocol.is_control_message?(%{"type" => "assistant"})
      false
  """
  @spec is_control_message?(map()) :: boolean()
  def is_control_message?(%{"type" => type})
      when type in ["control_request", "control_response"] do
    true
  end

  def is_control_message?(_), do: false

  ## Private Functions

  defp classify_message(%{"type" => "control_request"} = _data), do: :control_request
  defp classify_message(%{"type" => "control_response"} = _data), do: :control_response
  defp classify_message(_data), do: :sdk_message
end
