defmodule EmailAgent.StorageTest do
  use ExUnit.Case

  alias EmailAgent.Email
  alias EmailAgent.Storage

  @test_db_path "priv/test_storage_emails.db"

  setup do
    # Clean up before each test
    File.rm(@test_db_path)

    # Initialize fresh database
    {:ok, conn} = Storage.init_db(database_path: @test_db_path)

    on_exit(fn ->
      Storage.close(conn)
      File.rm(@test_db_path)
    end)

    {:ok, conn: conn}
  end

  describe "init/1" do
    test "creates database and tables", %{conn: conn} do
      # Verify tables exist
      {:ok, tables} =
        Storage.query(conn, "SELECT name FROM sqlite_master WHERE type='table'")

      table_names = Enum.map(tables, & &1["name"])

      assert "emails" in table_names
      assert "email_metadata" in table_names
      assert "sync_state" in table_names
    end

    test "creates necessary indexes", %{conn: conn} do
      {:ok, indexes} =
        Storage.query(conn, "SELECT name FROM sqlite_master WHERE type='index'")

      index_names = Enum.map(indexes, & &1["name"])

      assert Enum.any?(index_names, &String.contains?(&1, "message_id"))
      assert Enum.any?(index_names, &String.contains?(&1, "date"))
    end
  end

  describe "insert_email/2" do
    test "inserts a new email", %{conn: conn} do
      email = build_test_email()

      assert {:ok, id} = Storage.insert_email(conn, email)
      assert is_binary(id)
    end

    test "updates existing email on duplicate message_id", %{conn: conn} do
      email = build_test_email(id: "fixed-id-123")

      {:ok, id1} = Storage.insert_email(conn, email)

      # Insert same email again with same ID (should update)
      updated_email = %{email | subject: "Updated Subject"}
      {:ok, id2} = Storage.insert_email(conn, updated_email)

      assert id1 == id2
      assert id1 == "fixed-id-123"

      # Verify update
      {:ok, fetched} = Storage.get_email(conn, id1)
      assert fetched.subject == "Updated Subject"
    end

    test "generates ID when not provided", %{conn: conn} do
      email = %{build_test_email() | id: nil}

      {:ok, id} = Storage.insert_email(conn, email)

      assert is_binary(id)
      assert String.length(id) > 0
    end
  end

  describe "get_email/2" do
    test "returns email by ID", %{conn: conn} do
      email = build_test_email()
      {:ok, id} = Storage.insert_email(conn, email)

      {:ok, fetched} = Storage.get_email(conn, id)

      assert fetched.id == id
      assert fetched.from == email.from
      assert fetched.subject == email.subject
    end

    test "returns error for non-existent email", %{conn: conn} do
      assert {:error, :not_found} = Storage.get_email(conn, "nonexistent-id")
    end
  end

  describe "list_emails/2" do
    test "returns all emails with default options", %{conn: conn} do
      email1 = build_test_email(subject: "First Email")
      email2 = build_test_email(subject: "Second Email", message_id: "<second@example.com>")

      {:ok, _} = Storage.insert_email(conn, email1)
      {:ok, _} = Storage.insert_email(conn, email2)

      {:ok, emails} = Storage.list_emails(conn)

      assert length(emails) == 2
    end

    test "supports pagination with limit and offset", %{conn: conn} do
      for i <- 1..5 do
        email =
          build_test_email(
            subject: "Email #{i}",
            message_id: "<email#{i}@example.com>"
          )

        Storage.insert_email(conn, email)
      end

      {:ok, page1} = Storage.list_emails(conn, limit: 2, offset: 0)
      {:ok, page2} = Storage.list_emails(conn, limit: 2, offset: 2)

      assert length(page1) == 2
      assert length(page2) == 2

      # Pages should be different
      page1_ids = Enum.map(page1, & &1.id)
      page2_ids = Enum.map(page2, & &1.id)
      assert MapSet.disjoint?(MapSet.new(page1_ids), MapSet.new(page2_ids))
    end

    test "filters by label", %{conn: conn} do
      email1 = build_test_email(labels: ["inbox"], message_id: "<inbox@example.com>")
      email2 = build_test_email(labels: ["archive"], message_id: "<archive@example.com>")

      {:ok, _} = Storage.insert_email(conn, email1)
      {:ok, _} = Storage.insert_email(conn, email2)

      {:ok, inbox_emails} = Storage.list_emails(conn, label: "inbox")

      assert length(inbox_emails) == 1
      assert hd(inbox_emails).labels == ["inbox"]
    end

    test "filters by unread status", %{conn: conn} do
      email1 = build_test_email(is_read: false, message_id: "<unread@example.com>")
      email2 = build_test_email(is_read: true, message_id: "<read@example.com>")

      {:ok, _} = Storage.insert_email(conn, email1)
      {:ok, _} = Storage.insert_email(conn, email2)

      {:ok, unread_emails} = Storage.list_emails(conn, unread_only: true)

      assert length(unread_emails) == 1
      assert hd(unread_emails).is_read == false
    end

    test "orders by date descending by default", %{conn: conn} do
      old_email =
        build_test_email(
          date: ~U[2025-01-01 10:00:00Z],
          message_id: "<old@example.com>"
        )

      new_email =
        build_test_email(
          date: ~U[2025-01-06 10:00:00Z],
          message_id: "<new@example.com>"
        )

      {:ok, _} = Storage.insert_email(conn, old_email)
      {:ok, _} = Storage.insert_email(conn, new_email)

      {:ok, emails} = Storage.list_emails(conn)

      assert hd(emails).message_id == "<new@example.com>"
    end
  end

  describe "search_emails/2" do
    test "searches in subject", %{conn: conn} do
      email1 = build_test_email(subject: "Meeting Tomorrow", message_id: "<m1@example.com>")
      email2 = build_test_email(subject: "Invoice Attached", message_id: "<m2@example.com>")

      {:ok, _} = Storage.insert_email(conn, email1)
      {:ok, _} = Storage.insert_email(conn, email2)

      {:ok, results} = Storage.search_emails(conn, "meeting")

      assert length(results) == 1
      assert hd(results).subject =~ "Meeting"
    end

    test "searches in body text", %{conn: conn} do
      email =
        build_test_email(
          body_text: "Please review the quarterly report attached.",
          message_id: "<body@example.com>"
        )

      {:ok, _} = Storage.insert_email(conn, email)

      {:ok, results} = Storage.search_emails(conn, "quarterly report")

      assert length(results) == 1
    end

    test "searches in sender address", %{conn: conn} do
      email = build_test_email(from: "boss@company.com", message_id: "<boss@example.com>")

      {:ok, _} = Storage.insert_email(conn, email)

      {:ok, results} = Storage.search_emails(conn, "boss@company")

      assert length(results) == 1
    end

    test "returns empty list for no matches", %{conn: conn} do
      email = build_test_email()
      {:ok, _} = Storage.insert_email(conn, email)

      {:ok, results} = Storage.search_emails(conn, "nonexistent-term-xyz")

      assert results == []
    end
  end

  describe "update_email/3" do
    test "updates email fields", %{conn: conn} do
      email = build_test_email(is_read: false, is_starred: false)
      {:ok, id} = Storage.insert_email(conn, email)

      {:ok, updated} = Storage.update_email(conn, id, %{is_read: true, is_starred: true})

      assert updated.is_read == true
      assert updated.is_starred == true
    end

    test "updates labels", %{conn: conn} do
      email = build_test_email(labels: ["inbox"])
      {:ok, id} = Storage.insert_email(conn, email)

      {:ok, updated} = Storage.update_email(conn, id, %{labels: ["inbox", "important"]})

      assert "important" in updated.labels
    end

    test "returns error for non-existent email", %{conn: conn} do
      assert {:error, :not_found} = Storage.update_email(conn, "nonexistent", %{is_read: true})
    end
  end

  describe "delete_email/2" do
    test "deletes email by ID", %{conn: conn} do
      email = build_test_email()
      {:ok, id} = Storage.insert_email(conn, email)

      assert :ok = Storage.delete_email(conn, id)
      assert {:error, :not_found} = Storage.get_email(conn, id)
    end

    test "returns ok for non-existent email", %{conn: conn} do
      # Idempotent deletion
      assert :ok = Storage.delete_email(conn, "nonexistent")
    end
  end

  describe "sync state" do
    test "stores and retrieves last sync timestamp", %{conn: conn} do
      timestamp = DateTime.utc_now()

      :ok = Storage.set_last_sync(conn, "INBOX", timestamp)
      {:ok, retrieved} = Storage.get_last_sync(conn, "INBOX")

      # Compare with 1 second tolerance
      assert DateTime.diff(timestamp, retrieved, :second) == 0
    end

    test "returns nil for folder never synced", %{conn: conn} do
      assert {:ok, nil} = Storage.get_last_sync(conn, "NEVER_SYNCED")
    end

    test "updates existing sync timestamp", %{conn: conn} do
      old_time = ~U[2025-01-01 00:00:00Z]
      new_time = ~U[2025-01-06 12:00:00Z]

      :ok = Storage.set_last_sync(conn, "INBOX", old_time)
      :ok = Storage.set_last_sync(conn, "INBOX", new_time)

      {:ok, retrieved} = Storage.get_last_sync(conn, "INBOX")
      assert DateTime.compare(retrieved, new_time) == :eq
    end
  end

  describe "email_count/2" do
    test "counts all emails", %{conn: conn} do
      for i <- 1..3 do
        email = build_test_email(message_id: "<count#{i}@example.com>")
        Storage.insert_email(conn, email)
      end

      assert {:ok, 3} = Storage.email_count(conn)
    end

    test "counts unread emails", %{conn: conn} do
      read = build_test_email(is_read: true, message_id: "<read@example.com>")
      unread = build_test_email(is_read: false, message_id: "<unread@example.com>")

      Storage.insert_email(conn, read)
      Storage.insert_email(conn, unread)

      assert {:ok, 1} = Storage.email_count(conn, unread_only: true)
    end
  end

  # Helper function to build test emails
  defp build_test_email(overrides \\ []) do
    defaults = [
      id: nil,
      message_id: "<test123@example.com>",
      from: "sender@example.com",
      from_name: "Sender Name",
      to: ["recipient@example.com"],
      cc: [],
      bcc: [],
      subject: "Test Subject",
      date: ~U[2025-01-06 10:00:00Z],
      body_text: "This is the email body.",
      body_html: nil,
      attachments: [],
      labels: ["inbox"],
      is_read: false,
      is_starred: false,
      raw: nil
    ]

    struct(Email, Keyword.merge(defaults, overrides))
  end
end
