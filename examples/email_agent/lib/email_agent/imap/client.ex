defmodule EmailAgent.IMAP.Client do
  @moduledoc """
  Real IMAP client implementation using the mail library.

  This module provides the actual IMAP operations for production use.
  Tests can replace the ConnectionBehaviour implementation.

  ## Note

  This is a simplified IMAP client. For production use with high volume,
  consider using a more robust IMAP library or implementing connection pooling.
  """

  @behaviour EmailAgent.IMAP.ConnectionBehaviour

  require Logger

  @impl true
  def connect(host, port, opts) do
    ssl = Keyword.get(opts, :ssl, true)

    ssl_opts = [
      verify: :verify_none,
      versions: [:"tlsv1.2", :"tlsv1.3"]
    ]

    socket_opts = [
      :binary,
      active: false,
      packet: :line
    ]

    try do
      if ssl do
        case :ssl.connect(String.to_charlist(host), port, ssl_opts ++ socket_opts, 30_000) do
          {:ok, socket} ->
            # Read greeting
            case :ssl.recv(socket, 0, 10_000) do
              {:ok, greeting} ->
                Logger.debug("IMAP greeting: #{greeting}")
                {:ok, {:ssl, socket}}

              {:error, reason} ->
                {:error, {:greeting_failed, reason}}
            end

          {:error, reason} ->
            {:error, {:connect_failed, reason}}
        end
      else
        case :gen_tcp.connect(String.to_charlist(host), port, socket_opts, 30_000) do
          {:ok, socket} ->
            {:ok, greeting} = :gen_tcp.recv(socket, 0, 10_000)
            Logger.debug("IMAP greeting: #{greeting}")
            {:ok, {:tcp, socket}}

          {:error, reason} ->
            {:error, {:connect_failed, reason}}
        end
      end
    rescue
      e -> {:error, {:connect_error, Exception.message(e)}}
    end
  end

  @impl true
  def login({transport, socket}, email, password) do
    command = "A001 LOGIN #{quote_string(email)} #{quote_string(password)}\r\n"

    case send_command({transport, socket}, command) do
      {:ok, response} ->
        if String.contains?(response, "OK") do
          {:ok, :logged_in}
        else
          {:error, {:login_failed, response}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def logout({transport, socket}) do
    send_command({transport, socket}, "A999 LOGOUT\r\n")
    :ok
  end

  @impl true
  def close({:ssl, socket}) do
    :ssl.close(socket)
    :ok
  end

  def close({:tcp, socket}) do
    :gen_tcp.close(socket)
    :ok
  end

  @impl true
  def list_mailboxes({transport, socket}) do
    command = "A002 LIST \"\" \"*\"\r\n"

    case send_command({transport, socket}, command) do
      {:ok, response} ->
        mailboxes =
          response
          |> String.split("\r\n")
          |> Enum.filter(&String.contains?(&1, "* LIST"))
          |> Enum.map(&extract_mailbox_name/1)
          |> Enum.reject(&is_nil/1)

        {:ok, mailboxes}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def select_mailbox({transport, socket}, mailbox) do
    command = "A003 SELECT #{quote_string(mailbox)}\r\n"

    case send_command({transport, socket}, command) do
      {:ok, response} ->
        if String.contains?(response, "OK") do
          exists = extract_exists_count(response)
          {:ok, %{exists: exists}}
        else
          {:error, {:select_failed, response}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def search({transport, socket}, {:since, %DateTime{} = date}) do
    date_str = Calendar.strftime(date, "%d-%b-%Y")
    command = "A004 SEARCH SINCE #{date_str}\r\n"

    case send_command({transport, socket}, command) do
      {:ok, response} ->
        uids =
          response
          |> String.split("\r\n")
          |> Enum.find(&String.starts_with?(&1, "* SEARCH"))
          |> case do
            nil ->
              []

            line ->
              line
              |> String.replace("* SEARCH", "")
              |> String.split()
              |> Enum.map(&String.to_integer/1)
          end

        {:ok, uids}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def fetch_messages({transport, socket}, uids, _opts) when is_list(uids) do
    if uids == [] do
      {:ok, []}
    else
      uid_range = Enum.join(uids, ",")
      command = "A005 FETCH #{uid_range} (BODY[])\r\n"

      case send_command_multiline({transport, socket}, command) do
        {:ok, response} ->
          messages = parse_fetch_response(response)
          {:ok, messages}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl true
  def fetch_by_uid({transport, socket}, uid, _opts) do
    command = "A006 UID FETCH #{uid} (BODY[])\r\n"

    case send_command_multiline({transport, socket}, command) do
      {:ok, response} ->
        case parse_fetch_response(response) do
          [message | _] -> {:ok, message}
          [] -> {:error, :not_found}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def store_flags({transport, socket}, uid, operation, flags) do
    flag_str = Enum.map_join(flags, " ", &flag_to_string/1)
    op_str = if operation == :add, do: "+FLAGS", else: "-FLAGS"
    command = "A007 UID STORE #{uid} #{op_str} (#{flag_str})\r\n"

    case send_command({transport, socket}, command) do
      {:ok, response} ->
        if String.contains?(response, "OK"), do: :ok, else: {:error, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def copy({transport, socket}, uid, destination) do
    command = "A008 UID COPY #{uid} #{quote_string(destination)}\r\n"

    case send_command({transport, socket}, command) do
      {:ok, response} ->
        {:ok, extract_copy_uid(response)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def expunge({transport, socket}) do
    command = "A009 EXPUNGE\r\n"

    case send_command({transport, socket}, command) do
      {:ok, _response} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Private helpers

  defp send_command({:ssl, socket}, command) do
    with :ok <- :ssl.send(socket, command) do
      recv_response({:ssl, socket})
    end
  end

  defp send_command({:tcp, socket}, command) do
    with :ok <- :gen_tcp.send(socket, command) do
      recv_response({:tcp, socket})
    end
  end

  defp send_command_multiline({transport, socket}, command) do
    case send_raw({transport, socket}, command) do
      :ok -> recv_multiline_response({transport, socket})
      {:error, reason} -> {:error, reason}
    end
  end

  defp send_raw({:ssl, socket}, data), do: :ssl.send(socket, data)
  defp send_raw({:tcp, socket}, data), do: :gen_tcp.send(socket, data)

  defp recv_response({:ssl, socket}) do
    recv_until_complete({:ssl, socket}, "")
  end

  defp recv_response({:tcp, socket}) do
    recv_until_complete({:tcp, socket}, "")
  end

  defp recv_until_complete({transport, socket}, acc) do
    case recv_line({transport, socket}) do
      {:ok, line} ->
        new_acc = acc <> line

        if line_is_complete?(line) do
          {:ok, new_acc}
        else
          recv_until_complete({transport, socket}, new_acc)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp recv_line({:ssl, socket}) do
    :ssl.recv(socket, 0, 30_000)
  end

  defp recv_line({:tcp, socket}) do
    :gen_tcp.recv(socket, 0, 30_000)
  end

  defp recv_multiline_response({transport, socket}) do
    recv_multiline_response({transport, socket}, "", 0)
  end

  defp recv_multiline_response({transport, socket}, acc, depth) do
    case recv_line({transport, socket}) do
      {:ok, line} ->
        new_acc = acc <> line

        cond do
          # End of command response
          line_is_complete?(line) ->
            {:ok, new_acc}

          # Literal follows - need to read more
          line_has_literal_size?(line) ->
            recv_multiline_response({transport, socket}, new_acc, depth + 1)

          true ->
            recv_multiline_response({transport, socket}, new_acc, depth)
        end

      {:error, :timeout} when depth > 0 ->
        # Allow partial responses for multiline
        {:ok, acc}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp line_is_complete?(line) do
    # A tagged response line starting with the command tag
    case String.trim_leading(line) |> String.split(" ", parts: 3) do
      [tag, status | _rest] ->
        command_tag?(tag) and status in ["OK", "NO", "BAD"]

      _ ->
        false
    end
  end

  defp quote_string(str) do
    "\"#{String.replace(str, "\"", "\\\"")}\""
  end

  defp extract_mailbox_name(line) do
    parts = String.split(line, "\"")

    cond do
      length(parts) >= 4 ->
        Enum.at(parts, 3)

      String.contains?(line, ")") ->
        line
        |> String.split(")", parts: 2)
        |> List.last()
        |> String.trim()
        |> String.trim("\"")

      true ->
        nil
    end
  end

  defp extract_exists_count(response) do
    response
    |> String.split([" ", "\r", "\n", "\t"], trim: true)
    |> Enum.chunk_every(3, 1, :discard)
    |> Enum.find_value(0, fn
      ["*", count, "EXISTS"] -> if numeric?(count), do: String.to_integer(count), else: nil
      _other -> nil
    end)
  end

  defp parse_fetch_response(response) do
    # Simple extraction of message bodies from FETCH response
    # This is a simplified parser - a production version would need more robust parsing
    response
    |> fetch_blocks()
    |> Enum.map(&extract_body/1)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_body(fetch_data) do
    # Extract content between BODY[] { } markers
    with {:ok, after_body} <- after_marker(fetch_data, "BODY[]"),
         {:ok, after_literal} <- after_literal_header(after_body) do
      after_literal
      |> trim_fetch_body()
      |> String.trim()
    else
      :error -> nil
    end
  end

  defp extract_copy_uid(response) do
    tokens = String.split(response, [" ", "\r", "\n", "\t", "[", "]"], trim: true)

    tokens
    |> Enum.with_index()
    |> Enum.find_value(0, fn
      {"COPYUID", index} ->
        tokens
        |> Enum.at(index + 3, "0")
        |> digits_prefix()
        |> parse_or_zero()

      _other ->
        nil
    end)
  end

  defp command_tag?(<<"A", digits::binary>>), do: numeric?(digits)
  defp command_tag?(_tag), do: false

  defp line_has_literal_size?(line) do
    trimmed = String.trim(line)

    with true <- String.ends_with?(trimmed, "}"),
         [_before, value] <- String.split(trimmed, "{") |> Enum.take(-2),
         size <- String.trim_trailing(value, "}") do
      numeric?(size)
    else
      _ -> false
    end
  end

  defp fetch_blocks(response) do
    response
    |> String.split("* ", trim: true)
    |> Enum.flat_map(fn segment ->
      case String.split(segment, " ", parts: 3) do
        [number, "FETCH", rest] when number != "" ->
          if numeric?(number), do: [rest], else: []

        _other ->
          []
      end
    end)
  end

  defp after_marker(value, marker) do
    case :binary.match(value, marker) do
      {start, size} -> {:ok, binary_part(value, start + size, byte_size(value) - start - size)}
      :nomatch -> :error
    end
  end

  defp after_literal_header(value) do
    case :binary.match(value, "}") do
      {start, size} ->
        rest = binary_part(value, start + size, byte_size(value) - start - size)

        cond do
          String.starts_with?(rest, "\r\n") -> {:ok, binary_part(rest, 2, byte_size(rest) - 2)}
          String.starts_with?(rest, "\n") -> {:ok, binary_part(rest, 1, byte_size(rest) - 1)}
          true -> {:ok, rest}
        end

      :nomatch ->
        :error
    end
  end

  defp trim_fetch_body(body) do
    body
    |> String.trim()
    |> trim_single_trailing_paren()
  end

  defp trim_single_trailing_paren(value) do
    if String.ends_with?(value, ")") do
      value
      |> String.slice(0, String.length(value) - 1)
      |> String.trim()
    else
      value
    end
  end

  defp digits_prefix(value) do
    value
    |> String.to_charlist()
    |> Enum.take_while(&(&1 in ?0..?9))
    |> List.to_string()
  end

  defp parse_or_zero(""), do: 0
  defp parse_or_zero(value), do: String.to_integer(value)

  defp numeric?(value) when is_binary(value), do: value != "" and digits_prefix(value) == value
  defp numeric?(_value), do: false

  defp flag_to_string(:seen), do: "\\Seen"
  defp flag_to_string(:deleted), do: "\\Deleted"
  defp flag_to_string(:flagged), do: "\\Flagged"
  defp flag_to_string(:answered), do: "\\Answered"
  defp flag_to_string(:draft), do: "\\Draft"
  defp flag_to_string(other), do: to_string(other)
end
