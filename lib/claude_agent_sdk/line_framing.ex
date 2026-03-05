defmodule ClaudeAgentSDK.LineFraming do
  @moduledoc false

  @spec split_complete_lines(binary()) :: {[binary()], binary()}
  def split_complete_lines(""), do: {[], ""}

  def split_complete_lines(buffer) when is_binary(buffer) do
    case :binary.split(buffer, "\n", [:global]) do
      [single] ->
        {[], single}

      parts ->
        {complete, [rest]} = Enum.split(parts, length(parts) - 1)
        {Enum.map(complete, &strip_trailing_cr/1), rest}
    end
  end

  @spec consume_complete_lines(binary(), iodata()) :: {[binary()], binary()}
  def consume_complete_lines(buffer, data) when is_binary(buffer) do
    split_complete_lines(buffer <> IO.iodata_to_binary(data))
  end

  @spec consume_trimmed_lines(binary(), iodata()) :: {[binary()], binary()}
  def consume_trimmed_lines(buffer, data) when is_binary(buffer) do
    {lines, rest} = consume_complete_lines(buffer, data)
    {trim_nonempty_lines(lines), rest}
  end

  @spec finalize_trimmed_lines(binary()) :: [binary()]
  def finalize_trimmed_lines(buffer) when is_binary(buffer) do
    {lines, rest} = split_complete_lines(buffer)
    trim_nonempty_lines(lines ++ [rest])
  end

  @spec trim_nonempty_lines([binary()]) :: [binary()]
  def trim_nonempty_lines(lines) when is_list(lines) do
    lines
    |> Enum.map(&trim_ascii/1)
    |> Enum.reject(&(&1 == ""))
  end

  @spec trim_ascii(binary()) :: binary()
  def trim_ascii(binary) when is_binary(binary) do
    binary
    |> trim_ascii_leading()
    |> trim_ascii_trailing()
  end

  defp strip_trailing_cr(line) do
    size = byte_size(line)

    if size > 0 and :binary.at(line, size - 1) == 13 do
      :binary.part(line, 0, size - 1)
    else
      line
    end
  end

  defp trim_ascii_leading(<<char, rest::binary>>) when char in [9, 10, 13, 32],
    do: trim_ascii_leading(rest)

  defp trim_ascii_leading(binary), do: binary

  defp trim_ascii_trailing(binary), do: do_trim_ascii_trailing(binary, byte_size(binary))

  defp do_trim_ascii_trailing(_binary, 0), do: ""

  defp do_trim_ascii_trailing(binary, size) when size > 0 do
    last = :binary.at(binary, size - 1)

    if last in [9, 10, 13, 32] do
      do_trim_ascii_trailing(binary, size - 1)
    else
      :binary.part(binary, 0, size)
    end
  end
end
