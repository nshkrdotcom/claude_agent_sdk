defmodule ClaudeCodeSDK.Message do
  @moduledoc """
  Represents a message from Claude Code.
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
  """
  def from_json(json_string) when is_binary(json_string) do
    case ClaudeCodeSDK.JSON.decode(json_string) do
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
          "is_error" => extract_boolean_field(str, "is_error")
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
      _ -> 0.0
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
        |> Enum.filter(& &1 != "")
      _ -> []
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
      _ -> ""
    end
  end

  defp parse_message(raw) do
    type = String.to_atom(raw["type"])

    message = %__MODULE__{
      type: type,
      raw: raw
    }

    case type do
      :assistant ->
        %{message | data: %{message: raw["message"], session_id: raw["session_id"]}}

      :user ->
        %{message | data: %{message: raw["message"], session_id: raw["session_id"]}}

      :result ->
        subtype = String.to_atom(raw["subtype"])

        data =
          case subtype do
            :success ->
              %{
                result: raw["result"],
                session_id: raw["session_id"],
                total_cost_usd: raw["total_cost_usd"],
                duration_ms: raw["duration_ms"],
                duration_api_ms: raw["duration_api_ms"],
                num_turns: raw["num_turns"],
                is_error: raw["is_error"]
              }

            error_type when error_type in [:error_max_turns, :error_during_execution] ->
              %{
                session_id: raw["session_id"],
                total_cost_usd: raw["total_cost_usd"] || 0.0,
                duration_ms: raw["duration_ms"] || 0,
                duration_api_ms: raw["duration_api_ms"] || 0,
                num_turns: raw["num_turns"] || 0,
                is_error: raw["is_error"] || true,
                error: raw["error"]
              }
          end

        %{message | subtype: subtype, data: data}

      :system ->
        subtype = String.to_atom(raw["subtype"])

        data =
          case subtype do
            :init ->
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

        %{message | subtype: subtype, data: data}

      _ ->
        # Unknown type, store raw data
        %{message | data: raw}
    end
  end

  @doc """
  Checks if the message is a final result message.
  """
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