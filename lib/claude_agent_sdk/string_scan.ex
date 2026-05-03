defmodule ClaudeAgentSDK.StringScan do
  @moduledoc false

  @uuid_hyphen_positions [8, 13, 18, 23]
  @skip_prompt_prefixes [
    "<local-command-stdout>",
    "<session-start-hook>",
    "<tick>",
    "<goal>",
    "[Request interrupted by user"
  ]

  @doc false
  @spec first_semver(String.t()) :: String.t() | nil
  def first_semver(text) when is_binary(text) do
    text
    |> String.to_charlist()
    |> scan_first_semver()
  end

  @doc false
  @spec first_url(String.t()) :: String.t() | nil
  def first_url(text) when is_binary(text) do
    case :binary.match(text, "https://") do
      {start, _size} ->
        text
        |> binary_part(start, byte_size(text) - start)
        |> take_until_url_boundary()

      :nomatch ->
        nil
    end
  end

  @doc false
  @spec challenge_url(String.t()) :: String.t() | nil
  def challenge_url(text) when is_binary(text) do
    text
    |> all_urls()
    |> Enum.find(&challenge_url?/1)
  end

  @doc false
  @spec all_urls(String.t()) :: [String.t()]
  def all_urls(text) when is_binary(text), do: do_all_urls(text, [])

  @doc false
  @spec valid_uuid?(term()) :: boolean()
  def valid_uuid?(value) when is_binary(value) do
    String.length(value) == 36 and
      value
      |> String.graphemes()
      |> Enum.with_index()
      |> Enum.all?(fn {char, index} -> uuid_char?(char, index) end)
  end

  def valid_uuid?(_value), do: false

  @doc false
  @spec has_iso8601_zone_suffix?(String.t()) :: boolean()
  def has_iso8601_zone_suffix?(value) when is_binary(value) do
    String.ends_with?(value, "Z") or offset_suffix?(value)
  end

  @doc false
  @spec sanitize_path_chars(String.t(), String.t()) :: String.t()
  def sanitize_path_chars(value, replacement) when is_binary(value) and is_binary(replacement) do
    value
    |> String.graphemes()
    |> Enum.map_join(fn char ->
      if alnum?(char), do: char, else: replacement
    end)
  end

  @doc false
  @spec strip_control_chars(String.t()) :: String.t()
  def strip_control_chars(value) when is_binary(value) do
    value
    |> String.to_charlist()
    |> Enum.reject(&control_char?/1)
    |> List.to_string()
  end

  @doc false
  @spec strip_invisible_chars(String.t()) :: String.t()
  def strip_invisible_chars(value) when is_binary(value) do
    value
    |> String.to_charlist()
    |> Enum.reject(&invisible_char?/1)
    |> List.to_string()
  end

  @doc false
  @spec extract_tag(String.t(), String.t()) :: String.t() | nil
  def extract_tag(value, tag) when is_binary(value) and is_binary(tag) do
    start_tag = "<#{tag}>"
    end_tag = "</#{tag}>"

    with {:ok, after_start} <- after_marker(value, start_tag),
         {:ok, inside} <- before_marker(after_start, end_tag) do
      inside
    else
      :error -> nil
    end
  end

  @doc false
  @spec skip_first_prompt?(String.t()) :: boolean()
  def skip_first_prompt?(value) when is_binary(value) do
    trimmed = String.trim(value)

    String.starts_with?(trimmed, @skip_prompt_prefixes) or
      wrapped_tag?(trimmed, "ide_opened_file") or
      wrapped_tag?(trimmed, "ide_selection")
  end

  @doc false
  @spec words_and_spaces(String.t()) :: String.t()
  def words_and_spaces(value) when is_binary(value) do
    value
    |> String.graphemes()
    |> Enum.map_join(fn char ->
      if word_or_space?(char), do: char, else: " "
    end)
  end

  @doc false
  @spec lowercase_slug(String.t()) :: String.t()
  def lowercase_slug(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.graphemes()
    |> Enum.map_join(fn char ->
      cond do
        alnum?(char) or char == "-" -> char
        char == " " -> " "
        true -> ""
      end
    end)
    |> collapse_spaces()
  end

  @doc false
  @spec collapse_spaces(String.t()) :: String.t()
  def collapse_spaces(value) when is_binary(value) do
    value
    |> String.split([" ", "\t", "\n", "\r"], trim: true)
    |> Enum.join("_")
  end

  @doc false
  @spec grouped_number(number()) :: String.t()
  def grouped_number(num) when is_number(num) do
    num
    |> round()
    |> Integer.to_string()
    |> String.reverse()
    |> group_reversed_digits([])
    |> Enum.join(",")
    |> String.reverse()
  end

  @doc false
  @spec numeric_token?(String.t()) :: boolean()
  def numeric_token?(value) when is_binary(value) do
    value != "" and
      value
      |> String.to_charlist()
      |> Enum.all?(&digit?/1)
  end

  def numeric_token?(_value), do: false

  defp scan_first_semver([]), do: nil

  defp scan_first_semver([char | rest] = chars) do
    if digit?(char) do
      case take_semver(chars) do
        {:ok, version} -> version
        :error -> scan_first_semver(rest)
      end
    else
      scan_first_semver(rest)
    end
  end

  defp take_semver(chars) do
    with {major, [?. | after_major]} <- take_digits(chars),
         {minor, [?. | after_minor]} <- take_digits(after_major),
         {patch, _rest} when patch != [] <- take_digits(after_minor) do
      {:ok, List.to_string(major ++ [?.] ++ minor ++ [?.] ++ patch)}
    else
      _ -> :error
    end
  end

  defp take_digits(chars), do: Enum.split_while(chars, &digit?/1)

  defp take_until_url_boundary(text) do
    text
    |> String.graphemes()
    |> Enum.take_while(&(not url_boundary?(&1)))
    |> Enum.join()
    |> trim_url_suffix()
  end

  defp do_all_urls("", acc), do: Enum.reverse(acc)

  defp do_all_urls(text, acc) do
    case :binary.match(text, "https://") do
      {start, _size} ->
        before_size = start
        after_start = binary_part(text, start, byte_size(text) - start)
        url = take_until_url_boundary(after_start)
        next_start = before_size + max(byte_size(url), 1)
        next_text = binary_part(text, next_start, byte_size(text) - next_start)
        do_all_urls(next_text, [url | acc])

      :nomatch ->
        Enum.reverse(acc)
    end
  end

  defp challenge_url?(url) when is_binary(url) do
    lower = String.downcase(url)

    String.starts_with?(lower, "https://") and
      Enum.any?(
        ["anthropic.com", "challenge", "auth", "login", "verify", "oauth", "signin"],
        &String.contains?(lower, &1)
      )
  end

  defp trim_url_suffix(url) do
    url
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 in [".", ";", ",", ")"]))
    |> Enum.reverse()
    |> Enum.join()
  end

  defp url_boundary?(char), do: char in [" ", "\t", "\n", "\r", "\"", "'", ">", "<", "]"]

  defp uuid_char?("-", index), do: index in @uuid_hyphen_positions

  defp uuid_char?(char, index) do
    index not in @uuid_hyphen_positions and hex?(char)
  end

  defp offset_suffix?(value) do
    if String.length(value) >= 6 do
      suffix = String.slice(value, -6, 6)
      offset_suffix_shape?(suffix)
    else
      false
    end
  end

  defp offset_suffix_shape?(
         <<sign::binary-size(1), h1::binary-size(1), h2::binary-size(1), ":", m1::binary-size(1),
           m2::binary-size(1)>>
       ) do
    sign in ["+", "-"] and digit_string?(h1) and digit_string?(h2) and digit_string?(m1) and
      digit_string?(m2)
  end

  defp offset_suffix_shape?(_suffix), do: false

  defp after_marker(value, marker) do
    case :binary.match(value, marker) do
      {start, size} -> {:ok, binary_part(value, start + size, byte_size(value) - start - size)}
      :nomatch -> :error
    end
  end

  defp before_marker(value, marker) do
    case :binary.match(value, marker) do
      {start, _size} -> {:ok, binary_part(value, 0, start)}
      :nomatch -> :error
    end
  end

  defp wrapped_tag?(value, tag) do
    String.starts_with?(value, "<#{tag}>") and String.ends_with?(value, "</#{tag}>")
  end

  defp digit?(char) when is_integer(char), do: char >= ?0 and char <= ?9
  defp digit?(_char), do: false

  defp digit_string?(<<char::utf8>>), do: digit?(char)
  defp digit_string?(_char), do: false

  defp hex?(<<char::utf8>>) do
    digit?(char) or (char >= ?a and char <= ?f) or (char >= ?A and char <= ?F)
  end

  defp hex?(_char), do: false

  defp alnum?(<<char::utf8>>) do
    digit?(char) or (char >= ?a and char <= ?z) or (char >= ?A and char <= ?Z)
  end

  defp alnum?(_char), do: false

  defp word_or_space?(<<char::utf8>>) do
    alnum?(<<char::utf8>>) or char in [?\s, ?\t, ?\n, ?\r, ?_]
  end

  defp word_or_space?(_char), do: false

  defp group_reversed_digits("", acc), do: Enum.reverse(acc)

  defp group_reversed_digits(value, acc) do
    {group, rest} = String.split_at(value, 3)
    group_reversed_digits(rest, [group | acc])
  end

  defp control_char?(char), do: char in 0..8 or char in [11, 12, 127] or char in 14..31

  defp invisible_char?(char) do
    char in [0x200B, 0x200C, 0x200D, 0xFEFF] or
      char in 0x202A..0x202E or
      char in 0x2066..0x2069 or
      char in 0xE000..0xF8FF
  end
end
