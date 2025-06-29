defmodule ClaudeCodeSDK.JSON do
  @moduledoc """
  Simple JSON parser for Claude Code SDK.
  """

  @doc """
  Decode a JSON string into an Elixir term.
  """
  def decode(json_string) when is_binary(json_string) do
    try do
      # Use Erlang's :json module if available (OTP 27+)
      if function_exported?(:json, :decode, 1) do
        {:ok, :json.decode(json_string)}
      else
        # Fallback for older OTP versions
        decode_manual(json_string)
      end
    rescue
      _ -> {:error, :invalid_json}
    end
  end

  # Manual JSON decoder for basic cases
  defp decode_manual(json_string) do
    json_string = String.trim(json_string)
    
    cond do
      String.starts_with?(json_string, "{") && String.ends_with?(json_string, "}") ->
        decode_object(json_string)
        
      String.starts_with?(json_string, "[") && String.ends_with?(json_string, "]") ->
        decode_array(json_string)
        
      String.starts_with?(json_string, "\"") && String.ends_with?(json_string, "\"") ->
        {:ok, String.slice(json_string, 1..-2//1)}
        
      json_string in ["true", "false", "null"] ->
        {:ok, decode_literal(json_string)}
        
      true ->
        case Float.parse(json_string) do
          {num, ""} -> {:ok, num}
          _ -> 
            case Integer.parse(json_string) do
              {num, ""} -> {:ok, num}
              _ -> {:error, :invalid_json}
            end
        end
    end
  end

  defp decode_object(json_string) do
    # Remove outer braces
    content = String.slice(json_string, 1..-2//1) |> String.trim()
    
    if content == "" do
      {:ok, %{}}
    else
      # Split by commas (but not inside strings or nested objects)
      pairs = split_object_pairs(content)
      
      result = 
        Enum.reduce_while(pairs, %{}, fn pair, acc ->
          case parse_key_value(pair) do
            {:ok, {key, value}} -> {:cont, Map.put(acc, key, value)}
            {:error, _} -> {:halt, :error}
          end
        end)
      
      if result == :error do
        {:error, :invalid_json}
      else
        {:ok, result}
      end
    end
  end

  defp decode_array(json_string) do
    # Remove outer brackets
    content = String.slice(json_string, 1..-2//1) |> String.trim()
    
    if content == "" do
      {:ok, []}
    else
      # Split by commas (but not inside strings or nested structures)
      items = split_array_items(content)
      
      result = 
        Enum.reduce_while(items, [], fn item, acc ->
          case decode_manual(String.trim(item)) do
            {:ok, value} -> {:cont, [value | acc]}
            {:error, _} -> {:halt, :error}
          end
        end)
      
      if result == :error do
        {:error, :invalid_json}
      else
        {:ok, Enum.reverse(result)}
      end
    end
  end

  defp split_object_pairs(content) do
    # Simple splitting - doesn't handle all edge cases but works for our use case
    split_by_comma_outside_strings(content)
  end

  defp split_array_items(content) do
    split_by_comma_outside_strings(content)
  end

  defp split_by_comma_outside_strings(content) do
    # Split by comma, but ignore commas inside strings or nested structures
    parts = []
    current = ""
    in_string = false
    brace_depth = 0
    bracket_depth = 0
    
    split_chars(content, current, parts, in_string, brace_depth, bracket_depth)
  end

  defp split_chars("", current, parts, _in_string, _brace_depth, _bracket_depth) do
    if current != "" do
      [current | parts] |> Enum.reverse()
    else
      Enum.reverse(parts)
    end
  end

  defp split_chars(<<char::utf8, rest::binary>>, current, parts, in_string, brace_depth, bracket_depth) do
    case char do
      ?" when not in_string ->
        split_chars(rest, current <> "\"", parts, true, brace_depth, bracket_depth)
        
      ?" when in_string ->
        split_chars(rest, current <> "\"", parts, false, brace_depth, bracket_depth)
        
      ?{ when not in_string ->
        split_chars(rest, current <> "{", parts, in_string, brace_depth + 1, bracket_depth)
        
      ?} when not in_string ->
        split_chars(rest, current <> "}", parts, in_string, brace_depth - 1, bracket_depth)
        
      ?[ when not in_string ->
        split_chars(rest, current <> "[", parts, in_string, brace_depth, bracket_depth + 1)
        
      ?] when not in_string ->
        split_chars(rest, current <> "]", parts, in_string, brace_depth, bracket_depth - 1)
        
      ?, when not in_string and brace_depth == 0 and bracket_depth == 0 ->
        # Split here
        new_parts = if current != "", do: [String.trim(current) | parts], else: parts
        split_chars(rest, "", new_parts, in_string, brace_depth, bracket_depth)
        
      _ ->
        split_chars(rest, current <> <<char::utf8>>, parts, in_string, brace_depth, bracket_depth)
    end
  end

  defp parse_key_value(pair) do
    case String.split(pair, ":", parts: 2) do
      [key_part, value_part] ->
        key_part = String.trim(key_part)
        value_part = String.trim(value_part)
        
        # Parse key (should be a string)
        case decode_manual(key_part) do
          {:ok, key} when is_binary(key) ->
            case decode_manual(value_part) do
              {:ok, value} -> {:ok, {key, value}}
              {:error, _} -> {:error, :invalid_value}
            end
          _ -> {:error, :invalid_key}
        end
        
      _ -> {:error, :invalid_pair}
    end
  end

  defp decode_literal("true"), do: true
  defp decode_literal("false"), do: false
  defp decode_literal("null"), do: nil
end