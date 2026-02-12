defmodule ClaudeAgentSDK.Message do
  @moduledoc """
  Represents a message from Claude Code CLI.

  Messages are the core data structure returned by the Claude Code SDK. They represent
  different types of communication during a conversation with Claude, including system
  initialization, user inputs, assistant responses, and final results.

  ## Message Types

  - `:system` - Session initialization messages with metadata
  - `:user` - User input messages (echoed back from CLI)
  - `:assistant` - Claude's response messages containing the actual AI output
  - `:result` - Final result messages with cost, duration, and completion status

  Assistant messages may optionally include an `error` code when the CLI surfaces
  an issue (e.g., `:rate_limit` or `:authentication_failed`).

  ## Result Subtypes

  - `:success` - Successful completion
  - `:error_max_turns` - Terminated due to max turns limit
  - `:error_during_execution` - Error occurred during execution

  ## System Subtypes

  - `:init` - Initial system message with session setup

  ## Examples

      # Assistant message
      %ClaudeAgentSDK.Message{
        type: :assistant,
        subtype: nil,
        data: %{
          message: %{"content" => "Hello! How can I help?"},
          session_id: "session-123"
        }
      }

      # Assistant message with error metadata
      %ClaudeAgentSDK.Message{
        type: :assistant,
        subtype: nil,
        data: %{
          message: %{"content" => "Please try again later."},
          session_id: "session-123",
          error: :rate_limit
        }
      }

      # Result message
      %ClaudeAgentSDK.Message{
        type: :result,
        subtype: :success,
        data: %{
          total_cost_usd: 0.001,
          duration_ms: 1500,
          num_turns: 2,
          session_id: "session-123"
        }
      }

  """

  alias ClaudeAgentSDK.AssistantError

  defstruct [:type, :subtype, :data, :raw]

  @type message_type ::
          :assistant | :user | :result | :system | :stream_event | :unknown | String.t()
  @type result_subtype :: :success | :error_max_turns | :error_during_execution | String.t()
  @type system_subtype :: :init | String.t()
  @type assistant_error :: AssistantError.t()
  @type assistant_data :: %{
          required(:message) => map(),
          required(:session_id) => String.t() | nil,
          optional(:parent_tool_use_id) => String.t() | nil,
          optional(:error) => assistant_error() | nil
        }

  @type t :: %__MODULE__{
          type: message_type(),
          subtype: result_subtype() | system_subtype() | nil,
          data: assistant_data() | map(),
          raw: map()
        }

  @doc false
  def __safe_type__(type), do: safe_type(type)

  @doc false
  def __safe_subtype__(type, subtype), do: safe_subtype(type, subtype)

  @doc """
  Parses a JSON message from Claude Code into a Message struct.

  ## Parameters

  - `json_string` - Raw JSON string from Claude CLI

  ## Returns

  - `{:ok, message}` - Successfully parsed message
  - `{:error, reason}` - Parsing failed

  ## Examples

      iex> ClaudeAgentSDK.Message.from_json(~s({"type":"assistant","message":{"content":"Hello"}}))
      {:ok, %ClaudeAgentSDK.Message{type: :assistant, ...}}

  """
  @spec from_json(String.t()) :: {:ok, t()} | {:error, term()}
  def from_json(json_string) when is_binary(json_string) do
    case ClaudeAgentSDK.JSON.decode(json_string) do
      {:ok, raw} ->
        {:ok, parse_message(raw)}

      {:error, _} ->
        # Fallback to manual parsing for our known message types
        try do
          raw = parse_json_manual(String.trim(json_string))
          {:ok, parse_message(raw)}
        rescue
          e -> {:error, {:parse_error, Exception.message(e)}}
        end
    end
  end

  @doc """
  Returns parsed content blocks for `:user` and `:assistant` messages.

  This is an ergonomic alternative to the Python SDK's typed content-block objects.
  """
  @spec content_blocks(t()) :: [map()]
  def content_blocks(%__MODULE__{type: type, data: %{message: %{"content" => content}}})
      when type in [:user, :assistant] do
    cond do
      is_list(content) ->
        Enum.map(content, &parse_content_block/1)

      is_binary(content) ->
        [%{type: :text, text: content}]

      true ->
        []
    end
  end

  def content_blocks(_message), do: []

  @doc false
  @spec error_result(String.t(), keyword()) :: t()
  def error_result(error_message, opts \\ []) when is_binary(error_message) and is_list(opts) do
    session_id = Keyword.get(opts, :session_id, "error")
    error_struct = Keyword.get(opts, :error_struct)
    error_details = Keyword.get(opts, :error_details)

    data =
      %{
        error: error_message,
        session_id: session_id,
        is_error: true
      }
      |> maybe_put_error_struct(error_struct)
      |> maybe_put_error_details(error_details, error_struct)

    %__MODULE__{
      type: :result,
      subtype: :error_during_execution,
      data: data,
      raw: %{}
    }
  end

  defp maybe_put_error_struct(data, nil), do: data
  defp maybe_put_error_struct(data, error_struct), do: Map.put(data, :error_struct, error_struct)

  defp maybe_put_error_details(data, error_details, _error_struct) when is_map(error_details) do
    Map.put(data, :error_details, error_details)
  end

  defp maybe_put_error_details(data, nil, %ClaudeAgentSDK.Errors.ProcessError{} = error_struct) do
    Map.put(data, :error_details, %{
      kind: :process_error,
      exit_code: error_struct.exit_code,
      stderr: error_struct.stderr
    })
  end

  defp maybe_put_error_details(data, nil, _error_struct), do: data

  # Manual JSON parsing for our specific message formats
  defp parse_json_manual(str) do
    cond do
      String.contains?(str, ~s("type":"system")) ->
        %{
          "type" => "system",
          "subtype" => extract_string_field(str, "subtype"),
          "session_id" => extract_string_field(str, "session_id"),
          "cwd" => extract_string_field(str, "cwd"),
          "tools" => extract_array_field(str, "tools"),
          "mcp_servers" => [],
          "model" => extract_string_field(str, "model"),
          "permissionMode" => extract_string_field(str, "permissionMode"),
          "apiKeySource" => extract_string_field(str, "apiKeySource")
        }

      String.contains?(str, ~s("type":"assistant")) ->
        content = extract_nested_field(str, ["message", "content"], "text")

        %{
          "type" => "assistant",
          "message" => %{
            "role" => "assistant",
            "content" => content
          },
          "session_id" => extract_string_field(str, "session_id"),
          "error" => extract_string_field(str, "error")
        }

      String.contains?(str, ~s("type":"result")) ->
        %{
          "type" => "result",
          "subtype" => extract_string_field(str, "subtype"),
          "session_id" => extract_string_field(str, "session_id"),
          "result" => extract_string_field(str, "result"),
          "total_cost_usd" => extract_number_field(str, "total_cost_usd"),
          "duration_ms" => extract_integer_field(str, "duration_ms"),
          "duration_api_ms" => extract_integer_field(str, "duration_api_ms"),
          "num_turns" => extract_integer_field(str, "num_turns"),
          "is_error" => extract_boolean_field(str, "is_error"),
          "error" => extract_string_field(str, "error")
        }

      true ->
        %{"type" => "unknown", "content" => str}
    end
  end

  defp extract_string_field(str, field) do
    case Regex.run(~r/"#{field}":"([^"]*)"/, str) do
      [_, value] -> value
      _ -> nil
    end
  end

  defp extract_number_field(str, field) do
    case Regex.run(~r/"#{field}":([\d.]+)/, str) do
      [_, value] ->
        if String.contains?(value, ".") do
          String.to_float(value)
        else
          String.to_integer(value) * 1.0
        end

      _ ->
        0.0
    end
  end

  defp extract_integer_field(str, field) do
    case Regex.run(~r/"#{field}":(\d+)/, str) do
      [_, value] -> String.to_integer(value)
      _ -> 0
    end
  end

  defp extract_boolean_field(str, field) do
    case Regex.run(~r/"#{field}":(true|false)/, str) do
      [_, "true"] -> true
      [_, "false"] -> false
      _ -> false
    end
  end

  defp extract_array_field(str, field) do
    case Regex.run(~r/"#{field}":\[([^\]]*)\]/, str) do
      [_, content] ->
        content
        |> String.split(",")
        |> Enum.map(fn item ->
          item
          |> String.trim()
          |> String.trim("\"")
        end)
        |> Enum.filter(&(&1 != ""))

      _ ->
        []
    end
  end

  defp extract_nested_field(str, path, final_field) do
    # Extract nested content like message.content[0].text
    case path do
      ["message", "content"] ->
        case Regex.run(~r/"content":\[.*?"#{final_field}":"([^"]*)"/, str) do
          [_, value] -> value
          _ -> ""
        end

      _ ->
        ""
    end
  end

  defp parse_message(raw) do
    type = safe_type(raw["type"])

    message = %__MODULE__{
      type: type,
      raw: raw
    }

    parse_by_type(message, type, raw)
  end

  defp parse_by_type(message, :assistant, raw) do
    %{message | data: build_assistant_data(raw)}
  end

  defp parse_by_type(message, :user, raw) do
    data =
      %{
        message: raw["message"],
        session_id: raw["session_id"],
        parent_tool_use_id: raw["parent_tool_use_id"],
        tool_use_result: raw["tool_use_result"]
      }
      |> maybe_put_uuid(raw)

    %{message | data: data}
  end

  defp parse_by_type(message, :result, raw) do
    subtype = safe_subtype(:result, raw["subtype"])

    data =
      case subtype do
        :success -> build_result_data(:success, raw)
        :error_max_turns -> build_result_data(:error_max_turns, raw)
        :error_during_execution -> build_result_data(:error_during_execution, raw)
        _ -> raw
      end

    %{message | subtype: subtype, data: data}
  end

  defp parse_by_type(message, :system, raw) do
    subtype = safe_subtype(:system, raw["subtype"])
    data = if subtype == :init, do: build_system_data(:init, raw), else: raw
    %{message | subtype: subtype, data: data}
  end

  defp parse_by_type(message, :stream_event, raw) do
    data = %{
      uuid: Map.fetch!(raw, "uuid"),
      session_id: Map.fetch!(raw, "session_id"),
      event: Map.fetch!(raw, "event"),
      parent_tool_use_id: raw["parent_tool_use_id"]
    }

    %{message | data: data}
  end

  defp parse_by_type(message, _unknown_type, raw) do
    %{message | data: raw}
  end

  defp safe_type(type) when is_binary(type) do
    case type do
      "assistant" -> :assistant
      "user" -> :user
      "result" -> :result
      "system" -> :system
      "stream_event" -> :stream_event
      other -> other
    end
  end

  defp safe_type(_), do: :unknown

  defp safe_subtype(:result, subtype) when is_binary(subtype) do
    case subtype do
      "success" -> :success
      "error_max_turns" -> :error_max_turns
      "error_during_execution" -> :error_during_execution
      other -> other
    end
  end

  defp safe_subtype(:system, subtype) when is_binary(subtype) do
    case subtype do
      "init" -> :init
      other -> other
    end
  end

  defp safe_subtype(_type, subtype) when is_binary(subtype), do: subtype
  defp safe_subtype(_type, _subtype), do: nil

  defp parse_content_block(%{"type" => "text", "text" => text}) when is_binary(text),
    do: %{type: :text, text: text}

  defp parse_content_block(%{"type" => "thinking"} = block) do
    %{
      type: :thinking,
      thinking: block["thinking"],
      signature: block["signature"]
    }
  end

  defp parse_content_block(%{"type" => "tool_use"} = block) do
    %{
      type: :tool_use,
      id: block["id"],
      name: block["name"],
      input: block["input"] || %{}
    }
  end

  defp parse_content_block(%{"type" => "tool_result"} = block) do
    %{
      type: :tool_result,
      tool_use_id: block["tool_use_id"],
      content: block["content"],
      is_error: block["is_error"]
    }
  end

  defp parse_content_block(block) when is_map(block), do: %{type: :unknown, raw: block}
  defp parse_content_block(other), do: %{type: :unknown, raw: other}

  # Extract uuid from user messages for file checkpointing support
  defp maybe_put_uuid(data, %{"uuid" => uuid}) when is_binary(uuid) and uuid != "" do
    Map.put(data, :uuid, uuid)
  end

  defp maybe_put_uuid(data, _raw), do: data

  defp build_assistant_data(raw) do
    error_value = get_in(raw, ["message", "error"]) || raw["error"]

    %{
      message: raw["message"],
      session_id: raw["session_id"],
      parent_tool_use_id: raw["parent_tool_use_id"]
    }
    |> maybe_put_assistant_error(error_value)
  end

  defp maybe_put_assistant_error(data, error_value) do
    case AssistantError.cast(error_value) do
      nil -> data
      parsed_error -> Map.put(data, :error, parsed_error)
    end
  end

  defp build_result_data(:success, raw) do
    %{
      result: raw["result"],
      session_id: raw["session_id"],
      structured_output: raw["structured_output"],
      usage: raw["usage"],
      total_cost_usd: raw["total_cost_usd"],
      duration_ms: raw["duration_ms"],
      duration_api_ms: raw["duration_api_ms"],
      num_turns: raw["num_turns"],
      is_error: raw["is_error"]
    }
  end

  defp build_result_data(error_type, raw)
       when error_type in [:error_max_turns, :error_during_execution] do
    error_message = get_error_message(error_type, raw["error"])

    %{
      session_id: raw["session_id"],
      structured_output: raw["structured_output"],
      usage: raw["usage"],
      total_cost_usd: raw["total_cost_usd"] || 0.0,
      duration_ms: raw["duration_ms"] || 0,
      duration_api_ms: raw["duration_api_ms"] || 0,
      num_turns: raw["num_turns"] || 0,
      is_error: raw["is_error"] || true,
      error: error_message
    }
  end

  defp get_error_message(:error_max_turns, nil) do
    "The task exceeded the maximum number of turns allowed. Consider increasing max_turns option for complex tasks."
  end

  defp get_error_message(:error_max_turns, "") do
    "The task exceeded the maximum number of turns allowed. Consider increasing max_turns option for complex tasks."
  end

  defp get_error_message(:error_during_execution, nil) do
    "An error occurred during task execution."
  end

  defp get_error_message(:error_during_execution, "") do
    "An error occurred during task execution."
  end

  defp get_error_message(_error_type, error_message) when is_binary(error_message) do
    error_message
  end

  defp get_error_message(_error_type, _) do
    "An unknown error occurred."
  end

  defp build_system_data(:init, raw) do
    %{
      api_key_source: raw["apiKeySource"],
      cwd: raw["cwd"],
      session_id: raw["session_id"],
      tools: raw["tools"] || [],
      mcp_servers: raw["mcp_servers"] || [],
      model: raw["model"],
      permission_mode: raw["permissionMode"]
    }
  end

  @doc """
  Checks if the message is a final result message.

  Final messages indicate the end of a conversation or query.

  ## Parameters

  - `message` - The message to check

  ## Returns

  `true` if the message is a final result, `false` otherwise.

  ## Examples

      iex> ClaudeAgentSDK.Message.final?(%ClaudeAgentSDK.Message{type: :result})
      true

      iex> ClaudeAgentSDK.Message.final?(%ClaudeAgentSDK.Message{type: :assistant})
      false

  """
  @spec final?(t()) :: boolean()
  def final?(%__MODULE__{type: :result}), do: true
  def final?(_), do: false

  @doc """
  Checks if the message indicates an error.

  Returns `true` for result messages with error subtypes
  (`:error_max_turns` or `:error_during_execution`).
  """
  @spec error?(t()) :: boolean()
  def error?(%__MODULE__{type: :result, subtype: subtype})
      when subtype in [:error_max_turns, :error_during_execution],
      do: true

  def error?(_), do: false

  @doc """
  Gets the session ID from a message.

  Returns `nil` if the message does not contain a session ID.
  """
  @spec session_id(t()) :: String.t() | nil
  def session_id(%__MODULE__{data: %{session_id: id}}), do: id
  def session_id(_), do: nil

  @doc """
  Returns the checkpoint UUID from a user message, or nil.

  Used with file checkpointing to identify rewind targets.
  """
  @spec user_uuid(t()) :: String.t() | nil
  def user_uuid(%__MODULE__{type: :user, data: %{uuid: uuid}})
      when is_binary(uuid) and uuid != "",
      do: uuid

  def user_uuid(%__MODULE__{type: :user, raw: %{"uuid" => uuid}})
      when is_binary(uuid) and uuid != "",
      do: uuid

  def user_uuid(_), do: nil
end
