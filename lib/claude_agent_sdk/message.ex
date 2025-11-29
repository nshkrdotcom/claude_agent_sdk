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

  defstruct [:type, :subtype, :data, :raw]

  @type message_type :: :assistant | :user | :result | :system
  @type result_subtype :: :success | :error_max_turns | :error_during_execution
  @type system_subtype :: :init

  @type t :: %__MODULE__{
          type: message_type(),
          subtype: result_subtype() | system_subtype() | nil,
          data: map(),
          raw: map()
        }

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
          e -> {:error, e}
        end
    end
  end

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
          "session_id" => extract_string_field(str, "session_id")
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
    type = String.to_atom(raw["type"])

    message = %__MODULE__{
      type: type,
      raw: raw
    }

    parse_by_type(message, type, raw)
  end

  defp parse_by_type(message, :assistant, raw) do
    %{message | data: %{message: raw["message"], session_id: raw["session_id"]}}
  end

  defp parse_by_type(message, :user, raw) do
    %{message | data: %{message: raw["message"], session_id: raw["session_id"]}}
  end

  defp parse_by_type(message, :result, raw) do
    subtype = String.to_atom(raw["subtype"])
    data = build_result_data(subtype, raw)
    %{message | subtype: subtype, data: data}
  end

  defp parse_by_type(message, :system, raw) do
    subtype = String.to_atom(raw["subtype"])
    data = build_system_data(subtype, raw)
    %{message | subtype: subtype, data: data}
  end

  defp parse_by_type(message, _unknown_type, raw) do
    %{message | data: raw}
  end

  defp build_result_data(:success, raw) do
    %{
      result: raw["result"],
      session_id: raw["session_id"],
      structured_output: raw["structured_output"],
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
  """
  def error?(%__MODULE__{type: :result, subtype: subtype})
      when subtype in [:error_max_turns, :error_during_execution],
      do: true

  def error?(_), do: false

  @doc """
  Gets the session ID from a message.
  """
  def session_id(%__MODULE__{data: %{session_id: id}}), do: id
  def session_id(_), do: nil
end
