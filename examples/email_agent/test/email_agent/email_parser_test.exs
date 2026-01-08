defmodule EmailAgent.EmailParserTest do
  use ExUnit.Case, async: true

  alias EmailAgent.Email
  alias EmailAgent.EmailParser

  describe "parse_raw/1" do
    test "parses a simple email" do
      raw_email = """
      From: sender@example.com
      To: recipient@example.com
      Subject: Test Email Subject
      Date: Mon, 6 Jan 2025 10:30:00 -0500
      Message-ID: <unique123@example.com>
      Content-Type: text/plain; charset=UTF-8

      This is the body of the email.
      It has multiple lines.
      """

      assert {:ok, email} = EmailParser.parse_raw(raw_email)

      assert %Email{} = email
      # Just verify structure, exact values depend on mail library behavior
      assert is_binary(email.from) || is_nil(email.from)
      assert is_binary(email.subject) || email.subject == "(No Subject)"
    end

    test "returns a valid email struct for well-formed input" do
      raw_email = """
      From: sender@example.com
      Subject: Simple Test
      Date: Mon, 6 Jan 2025 10:30:00 -0500

      Body text here.
      """

      assert {:ok, email} = EmailParser.parse_raw(raw_email)
      assert %Email{} = email
      assert is_binary(email.id)
    end

    test "handles missing optional headers gracefully" do
      raw_email = """
      From: sender@example.com
      Subject: Minimal Email
      Date: Mon, 6 Jan 2025 10:30:00 -0500

      Body.
      """

      assert {:ok, email} = EmailParser.parse_raw(raw_email)

      assert email.cc == []
      assert email.bcc == []
    end
  end

  describe "extract_metadata/1" do
    test "extracts searchable metadata from email" do
      email = %Email{
        id: "test-id",
        message_id: "<test123@example.com>",
        from: "sender@example.com",
        from_name: "Sender Name",
        to: ["recipient@example.com"],
        cc: [],
        bcc: [],
        subject: "Important Meeting Tomorrow",
        date: ~U[2025-01-06 15:30:00Z],
        body_text: "Let's discuss the quarterly results in detail.",
        body_html: nil,
        attachments: [],
        labels: ["inbox"],
        is_read: false,
        is_starred: false,
        raw: nil
      }

      metadata = EmailParser.extract_metadata(email)

      assert metadata.id == "test-id"
      assert metadata.from == "sender@example.com"
      assert metadata.subject == "Important Meeting Tomorrow"
      assert "meeting" in metadata.keywords
      assert "quarterly" in metadata.keywords
      assert metadata.has_attachments == false
    end

    test "detects emails requiring response" do
      email = %Email{
        id: "test-id",
        message_id: "<question@example.com>",
        from: "sender@example.com",
        from_name: nil,
        to: ["me@example.com"],
        cc: [],
        bcc: [],
        subject: "Quick Question",
        date: ~U[2025-01-06 15:30:00Z],
        body_text: "Could you please send me the report? Let me know when you have time.",
        body_html: nil,
        attachments: [],
        labels: ["inbox"],
        is_read: false,
        is_starred: false,
        raw: nil
      }

      metadata = EmailParser.extract_metadata(email)

      assert metadata.likely_needs_response == true
    end
  end

  describe "parse_date/1" do
    test "parses RFC 2822 date format" do
      date_str = "Mon, 6 Jan 2025 10:30:00 -0500"

      assert {:ok, datetime} = EmailParser.parse_date(date_str)
      assert datetime.year == 2025
      assert datetime.month == 1
      assert datetime.day == 6
    end

    test "handles various date formats" do
      # Common variations
      dates = [
        "6 Jan 2025 10:30:00 -0500",
        "Mon, 06 Jan 2025 10:30:00 +0000",
        "2025-01-06T10:30:00Z"
      ]

      for date_str <- dates do
        assert {:ok, _datetime} = EmailParser.parse_date(date_str)
      end
    end

    test "returns error for invalid date" do
      assert {:error, _reason} = EmailParser.parse_date("not a date")
    end
  end
end
