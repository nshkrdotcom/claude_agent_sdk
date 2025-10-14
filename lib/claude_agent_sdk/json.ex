defmodule ClaudeAgentSDK.JSON do
  @moduledoc """
  Simple JSON parser for Claude Code SDK.

  This module provides a lightweight JSON decoder that doesn't require external
  dependencies. It first attempts to use Erlang's built-in :json module (OTP 27+),
  falling back to a manual parser for older versions.

  The manual parser handles the basic JSON structures needed for Claude Code messages:
  - Objects (maps)
  - Arrays (lists)
  - Strings
  - Numbers (integers and floats)
  - Booleans and null

  Note: The manual parser is simplified and may not handle all edge cases of the
  JSON specification, but it's sufficient for parsing Claude Code CLI output.
  """

  @doc """
  Decode a JSON string into an Elixir term.

  ## Parameters

  - `json_string` - A valid JSON string to decode

  ## Returns

  - `{:ok, term}` - Successfully decoded JSON as Elixir term
  - `{:error, :invalid_json}` - Failed to parse JSON

  ## Examples

      iex> ClaudeAgentSDK.JSON.decode(~s({"key": "value"}))
      {:ok, %{"key" => "value"}}

      iex> ClaudeAgentSDK.JSON.decode(~s([1, 2, 3]))
      {:ok, [1, 2, 3]}

      iex> ClaudeAgentSDK.JSON.decode("invalid")
      {:error, :invalid_json}

  """
  @spec decode(String.t()) :: {:ok, term()} | {:error, :invalid_json}
  def decode(json_string) when is_binary(json_string) do
    # Use Erlang's :json module if available (OTP 27+)
    if function_exported?(:json, :decode, 1) do
      try do
        # :json.decode returns the decoded value directly, not a tuple
        result = :json.decode(json_string)
        {:ok, result}
      rescue
        _ -> {:error, :invalid_json}
      end
    else
      # Fallback for older OTP versions
      decode_manual(json_string)
    end
  end

  # Manual JSON decoder for basic cases
  defp decode_manual(json_string) do
    json_string = String.trim(json_string)

    case identify_json_type(json_string) do
      :object -> decode_object(json_string)
      :array -> decode_array(json_string)
      :string -> decode_string(json_string)
      :literal -> decode_literal_value(json_string)
      :number -> decode_number(json_string)
      :invalid -> {:error, :invalid_json}
    end
  end

  defp identify_json_type(json_string) do
    case json_string do
      "{" <> _ -> check_ends_with(json_string, "}", :object)
      "[" <> _ -> check_ends_with(json_string, "]", :array)
      "\"" <> _ -> check_ends_with(json_string, "\"", :string)
      "true" -> :literal
      "false" -> :literal
      "null" -> :literal
      _ -> check_if_numeric(json_string)
    end
  end

  defp check_ends_with(string, suffix, type) do
    if String.ends_with?(string, suffix), do: type, else: :invalid
  end

  defp check_if_numeric(string) do
    if numeric?(string), do: :number, else: :invalid
  end

  defp numeric?(string) do
    case Float.parse(string) do
      {_, ""} -> true
      _ -> match?({_, ""}, Integer.parse(string))
    end
  end

  defp decode_string(json_string) do
    {:ok, String.slice(json_string, 1..-2//1)}
  end

  defp decode_literal_value("true"), do: {:ok, true}
  defp decode_literal_value("false"), do: {:ok, false}
  defp decode_literal_value("null"), do: {:ok, nil}

  defp decode_number(json_string) do
    case Float.parse(json_string) do
      {num, ""} ->
        {:ok, num}

      _ ->
        case Integer.parse(json_string) do
          {num, ""} -> {:ok, num}
          _ -> {:error, :invalid_json}
        end
    end
  end

  defp decode_object(json_string) do
    # Remove outer braces
    content = String.slice(json_string, 1..-2//1) |> String.trim()

    if content == "" do
      {:ok, %{}}
    else
      decode_object_content(content)
    end
  end

  defp decode_object_content(content) do
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

  defp decode_array(json_string) do
    # Remove outer brackets
    content = String.slice(json_string, 1..-2//1) |> String.trim()

    if content == "" do
      {:ok, []}
    else
      decode_array_content(content)
    end
  end

  defp decode_array_content(content) do
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

  defp split_object_pairs(content) do
    # Simple splitting - doesn't handle all edge cases but works for our use case
    split_by_comma_outside_strings(content)
  end

  defp split_array_items(content) do
    split_by_comma_outside_strings(content)
  end

  defp split_by_comma_outside_strings(content) do
    # Split by comma, but ignore commas inside strings or nested structures
    state = %{
      parts: [],
      current: "",
      in_string: false,
      brace_depth: 0,
      bracket_depth: 0
    }

    final_state = split_chars(content, state)

    if final_state.current != "" do
      [final_state.current | final_state.parts] |> Enum.reverse()
    else
      Enum.reverse(final_state.parts)
    end
  end

  defp split_chars("", state), do: state

  defp split_chars(<<char::utf8, rest::binary>>, state) do
    new_state = process_char(char, state)
    split_chars(rest, new_state)
  end

  defp process_char(char, state) do
    case {char, state.in_string} do
      {?", false} ->
        process_quote_start(state)

      {?", true} ->
        process_quote_end(state)

      {_, true} ->
        append_char(state, char)

      {char, false} ->
        process_non_string_char(char, state)
    end
  end

  defp process_quote_start(state) do
    %{state | current: state.current <> "\"", in_string: true}
  end

  defp process_quote_end(state) do
    %{state | current: state.current <> "\"", in_string: false}
  end

  defp process_non_string_char(char, state) do
    case char do
      ?{ -> %{state | current: state.current <> "{", brace_depth: state.brace_depth + 1}
      ?} -> %{state | current: state.current <> "}", brace_depth: state.brace_depth - 1}
      ?[ -> %{state | current: state.current <> "[", bracket_depth: state.bracket_depth + 1}
      ?] -> %{state | current: state.current <> "]", bracket_depth: state.bracket_depth - 1}
      ?, -> process_comma(state)
      _ -> append_char(state, char)
    end
  end

  defp process_comma(state) do
    if state.brace_depth == 0 && state.bracket_depth == 0 do
      new_parts =
        if state.current != "" do
          [String.trim(state.current) | state.parts]
        else
          state.parts
        end

      %{state | parts: new_parts, current: ""}
    else
      append_char(state, ?,)
    end
  end

  defp append_char(state, char) do
    %{state | current: state.current <> <<char::utf8>>}
  end

  defp parse_key_value(pair) do
    case String.split(pair, ":", parts: 2) do
      [key_part, value_part] -> parse_key_and_value(key_part, value_part)
      _ -> {:error, :invalid_pair}
    end
  end

  defp parse_key_and_value(key_part, value_part) do
    key_part = String.trim(key_part)
    value_part = String.trim(value_part)

    with {:ok, key} when is_binary(key) <- decode_manual(key_part),
         {:ok, value} <- decode_manual(value_part) do
      {:ok, {key, value}}
    else
      {:ok, _} -> {:error, :invalid_key}
      {:error, _} -> {:error, :invalid_value}
    end
  end
end
