defmodule EmailAgent.EmailParser do
  @moduledoc """
  Parses raw RFC 5322 email messages into structured Email structs.

  Handles various email formats including:
  - Simple single-part text emails
  - Multipart MIME messages (text/html alternatives)
  - Emails with attachments
  - Various header encodings
  """

  alias ClaudeAgentSDK.StringScan
  alias EmailAgent.Email
  alias Mail.Parsers.RFC2822

  @typedoc """
  Email metadata extracted for search indexing.
  """
  @type metadata :: %{
          id: String.t(),
          from: String.t(),
          subject: String.t(),
          keywords: [String.t()],
          has_attachments: boolean(),
          likely_needs_response: boolean()
        }

  @doc """
  Parses a raw email string into an Email struct.

  ## Parameters

  - `raw_email` - Raw RFC 5322 formatted email string

  ## Returns

  - `{:ok, email}` - Successfully parsed email
  - `{:error, reason}` - Parsing failed

  ## Examples

      raw = "From: sender@example.com\\nTo: recipient@example.com\\nSubject: Test\\n\\nBody"
      {:ok, email} = EmailParser.parse_raw(raw)
  """
  @spec parse_raw(String.t()) :: {:ok, Email.t()} | {:error, term()}
  def parse_raw(raw_email) when is_binary(raw_email) do
    # Use Mail library for parsing
    parsed = RFC2822.parse(raw_email)
    email = convert_mail_to_email(parsed, raw_email)
    {:ok, email}
  rescue
    e ->
      {:error, {:parse_error, Exception.message(e)}}
  end

  @doc """
  Extracts searchable metadata from an email.

  Returns structured metadata useful for search indexing
  and AI-powered queries.
  """
  @spec extract_metadata(Email.t()) :: metadata()
  def extract_metadata(%Email{} = email) do
    keywords = extract_keywords(email)
    needs_response = likely_needs_response?(email)

    %{
      id: email.id,
      from: email.from,
      subject: email.subject,
      keywords: keywords,
      has_attachments: Email.has_attachments?(email),
      likely_needs_response: needs_response
    }
  end

  @doc """
  Parses a date string from email headers.

  Handles RFC 2822 date formats and common variations.
  """
  @spec parse_date(String.t()) :: {:ok, DateTime.t()} | {:error, term()}
  def parse_date(date_string) when is_binary(date_string) do
    date_string = String.trim(date_string)

    # ISO 8601 format
    if String.contains?(date_string, "T") do
      case DateTime.from_iso8601(date_string) do
        {:ok, datetime, _} -> {:ok, datetime}
        {:error, reason} -> {:error, reason}
      end
    else
      # RFC 2822 format
      parse_rfc2822_date(date_string)
    end
  end

  # Private functions

  defp convert_mail_to_email(parsed, raw) do
    headers = extract_headers(parsed)
    body = extract_body(parsed)
    attachments = extract_attachments(parsed)

    from_header = Map.get(headers, "from", "")
    {from_email, from_name} = parse_address(from_header)

    %Email{
      id: generate_id(),
      message_id: Map.get(headers, "message-id"),
      from: from_email,
      from_name: from_name,
      to: parse_address_list(Map.get(headers, "to", "")),
      cc: parse_address_list(Map.get(headers, "cc", "")),
      bcc: parse_address_list(Map.get(headers, "bcc", "")),
      reply_to: extract_email(Map.get(headers, "reply-to")),
      subject: Map.get(headers, "subject", "(No Subject)"),
      date: parse_date_header(Map.get(headers, "date")),
      body_text: body[:text],
      body_html: body[:html],
      attachments: attachments,
      labels: ["inbox"],
      is_read: false,
      is_starred: false,
      raw: raw
    }
  end

  defp extract_headers(%Mail.Message{headers: headers}) do
    headers
    |> Enum.map(fn {key, value} -> {String.downcase(to_string(key)), to_string(value)} end)
    |> Map.new()
  end

  defp extract_body(parsed) do
    case parsed do
      %Mail.Message{body: _body, multipart: true, parts: parts} when is_list(parts) ->
        extract_multipart_body(parts)

      %Mail.Message{body: body} when is_binary(body) ->
        %{text: body, html: nil}

      _ ->
        %{text: nil, html: nil}
    end
  end

  defp extract_multipart_body(parts) do
    Enum.reduce(parts, %{text: nil, html: nil}, fn part, acc ->
      content_type = get_content_type(part)

      cond do
        String.contains?(content_type, "text/plain") and is_nil(acc.text) ->
          %{acc | text: get_part_body(part)}

        String.contains?(content_type, "text/html") and is_nil(acc.html) ->
          %{acc | html: get_part_body(part)}

        String.contains?(content_type, "multipart/") ->
          # Recursively extract from nested multipart
          nested = extract_multipart_body(Map.get(part, :parts, []))
          %{text: acc.text || nested.text, html: acc.html || nested.html}

        true ->
          acc
      end
    end)
  end

  defp get_content_type(%Mail.Message{headers: headers}) do
    headers
    |> Enum.find(fn {k, _v} -> String.downcase(to_string(k)) == "content-type" end)
    |> case do
      {_, value} -> String.downcase(to_string(value))
      nil -> "text/plain"
    end
  end

  defp get_content_type(_), do: "text/plain"

  defp get_part_body(%Mail.Message{body: body}) when is_binary(body), do: body
  defp get_part_body(_), do: nil

  defp extract_attachments(parsed) do
    case parsed do
      %Mail.Message{multipart: true, parts: parts} ->
        parts
        |> Enum.filter(&attachment?/1)
        |> Enum.map(&parse_attachment/1)

      _ ->
        []
    end
  end

  defp attachment?(%Mail.Message{headers: headers}) do
    disposition =
      headers
      |> Enum.find(fn {k, _v} -> String.downcase(to_string(k)) == "content-disposition" end)

    case disposition do
      {_, value} -> String.contains?(String.downcase(to_string(value)), "attachment")
      nil -> false
    end
  end

  defp attachment?(_), do: false

  defp parse_attachment(%Mail.Message{headers: headers} = part) do
    content_type = get_content_type(part)

    filename =
      headers
      |> Enum.find(fn {k, _v} -> String.downcase(to_string(k)) == "content-disposition" end)
      |> extract_filename()

    %{
      filename: filename || "attachment",
      content_type: content_type,
      size: nil,
      content_id: nil
    }
  end

  defp extract_filename({_, value}) do
    to_string(value)
    |> String.split(";")
    |> Enum.find_value(fn part ->
      part = String.trim(part)

      if String.starts_with?(part, "filename=") do
        part
        |> String.replace_prefix("filename=", "")
        |> String.trim("\"")
      end
    end)
  end

  defp extract_filename(_), do: nil

  defp parse_address(address_string) when is_binary(address_string) do
    trimmed = String.trim(address_string)

    case bracketed_email(trimmed) do
      {:ok, name, email} ->
        {email, normalize_display_name(name)}

      :error ->
        email = extract_email(trimmed)
        {email || trimmed, nil}
    end
  end

  defp parse_address(nil), do: {"", nil}

  defp parse_address_list(nil), do: []
  defp parse_address_list(""), do: []

  defp parse_address_list(addresses) when is_binary(addresses) do
    addresses
    |> String.split(",")
    |> Enum.map(&parse_address/1)
    |> Enum.map(fn {email, _name} -> email end)
    |> Enum.reject(&(&1 == ""))
  end

  defp extract_email(nil), do: nil

  defp extract_email(string) when is_binary(string) do
    case bracketed_email(string) do
      {:ok, _name, email} -> email
      :error -> if String.contains?(string, "@"), do: String.trim(string), else: nil
    end
  end

  defp parse_date_header(nil), do: nil

  defp parse_date_header(date_string) do
    case parse_date(date_string) do
      {:ok, datetime} -> datetime
      {:error, _} -> nil
    end
  end

  defp parse_rfc2822_date(date_string) do
    date_string = remove_day_name(date_string)

    # Parse: "6 Jan 2025 10:30:00 -0500"
    case String.split(date_string, " ", trim: true) do
      [day, month, year, time | rest] ->
        [hour, min, sec] = parse_time(time)
        month_num = month_to_number(month)
        offset = parse_offset(List.first(rest))

        with {:ok, naive} <-
               NaiveDateTime.new(
                 String.to_integer(year),
                 month_num,
                 String.to_integer(day),
                 String.to_integer(hour),
                 String.to_integer(min),
                 String.to_integer(sec)
               ),
             {:ok, datetime} <- DateTime.from_naive(naive, "Etc/UTC") do
          {:ok, DateTime.add(datetime, -offset, :second)}
        end

      _ ->
        {:error, :invalid_date_format}
    end
  rescue
    _error -> {:error, :invalid_date_format}
  end

  defp month_to_number(month) do
    %{
      "jan" => 1,
      "feb" => 2,
      "mar" => 3,
      "apr" => 4,
      "may" => 5,
      "jun" => 6,
      "jul" => 7,
      "aug" => 8,
      "sep" => 9,
      "oct" => 10,
      "nov" => 11,
      "dec" => 12
    }[String.downcase(month)] || 1
  end

  defp parse_offset(nil), do: 0

  defp parse_offset(offset_str) do
    case String.trim(offset_str) do
      <<sign::binary-size(1), hours::binary-size(2), mins::binary-size(2)>>
      when sign in ["+", "-"] ->
        offset_seconds = String.to_integer(hours) * 3600 + String.to_integer(mins) * 60
        if sign == "-", do: -offset_seconds, else: offset_seconds

      _ ->
        0
    end
  end

  defp extract_keywords(%Email{subject: subject, body_text: body}) do
    text = "#{subject} #{body || ""}"

    # Extract significant words (longer than 3 chars, not common words)
    common_words =
      ~w(the and are was were been have has had that this with from your into they them)

    text
    |> String.downcase()
    |> StringScan.words_and_spaces()
    |> String.split()
    |> Enum.reject(fn word -> String.length(word) <= 3 or word in common_words end)
    |> Enum.uniq()
    |> Enum.take(20)
  end

  defp likely_needs_response?(%Email{body_text: nil}), do: false

  defp likely_needs_response?(%Email{body_text: body, subject: subject}) do
    text = String.downcase("#{subject} #{body}")

    question_indicators = ["?", "could you", "can you", "would you", "please", "let me know"]

    Enum.any?(question_indicators, &String.contains?(text, &1))
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  defp bracketed_email(string) do
    with {open, 1} <- :binary.match(string, "<"),
         after_open <- binary_part(string, open + 1, byte_size(string) - open - 1),
         {close, 1} <- :binary.match(after_open, ">") do
      name = string |> binary_part(0, open) |> String.trim()
      email = after_open |> binary_part(0, close) |> String.trim()

      if email == "", do: :error, else: {:ok, name, email}
    else
      _ -> :error
    end
  end

  defp normalize_display_name(""), do: nil

  defp normalize_display_name(name) do
    name
    |> String.trim()
    |> String.trim("\"")
  end

  defp remove_day_name(value) do
    trimmed = String.trim(value)

    case String.split(trimmed, " ", parts: 2, trim: true) do
      [first, rest] ->
        day = first |> String.trim_trailing(",") |> String.downcase() |> String.slice(0, 3)

        if day in ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] do
          String.trim(rest)
        else
          trimmed
        end

      _ ->
        trimmed
    end
  end

  defp parse_time(value) do
    case String.split(value, ":", parts: 3) do
      [hour, min, sec] -> [hour, min, sec]
      _ -> ["0", "0", "0"]
    end
  end
end
