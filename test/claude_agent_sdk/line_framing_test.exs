defmodule ClaudeAgentSDK.LineFramingTest do
  @moduledoc """
  The NDJSON line reassembler must not lose or corrupt interior bytes when a
  single line exceeds a stream-buffer boundary (Python v0.2.111 fixed a bug
  where whitespace was dropped for lines over 64 KiB). The Elixir reassembler
  concatenates raw bytes, so it is lossless regardless of line length or how
  the bytes are chunked.
  """
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.LineFraming

  test "reassembles a >64 KiB single line with interior whitespace, byte-exact" do
    # A JSON line well over the 64 KiB stream buffer, with runs of interior
    # spaces/tabs inside a string value.
    inner = String.duplicate("a  b\tc   d\t\te ", 8_000)
    line = ~s({"type":"assistant","message":{"content":") <> inner <> ~s("}})
    assert byte_size(line) > 64 * 1024

    # Deliver the line in small chunks (no newline until the very end), the way
    # a stream reader would.
    chunks = chunk_binary(line <> "\n", 4096)

    {lines, rest} =
      Enum.reduce(chunks, {[], ""}, fn chunk, {acc, buffer} ->
        {new_lines, new_buffer} = LineFraming.consume_complete_lines(buffer, chunk)
        {acc ++ new_lines, new_buffer}
      end)

    assert rest == ""
    assert [reassembled] = lines
    assert reassembled == line
    assert byte_size(reassembled) == byte_size(line)
  end

  test "preserves multiple lines split across chunk boundaries" do
    data = "line one\nline  two\nline\tthree\n"
    chunks = chunk_binary(data, 3)

    {lines, rest} =
      Enum.reduce(chunks, {[], ""}, fn chunk, {acc, buffer} ->
        {new_lines, new_buffer} = LineFraming.consume_complete_lines(buffer, chunk)
        {acc ++ new_lines, new_buffer}
      end)

    assert rest == ""
    assert lines == ["line one", "line  two", "line\tthree"]
  end

  defp chunk_binary(binary, size) when is_binary(binary) and is_integer(size) do
    do_chunk(binary, size, [])
  end

  defp do_chunk(<<>>, _size, acc), do: Enum.reverse(acc)

  defp do_chunk(binary, size, acc) when byte_size(binary) <= size do
    Enum.reverse([binary | acc])
  end

  defp do_chunk(binary, size, acc) do
    <<chunk::binary-size(size), rest::binary>> = binary
    do_chunk(rest, size, [chunk | acc])
  end
end
