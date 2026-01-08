defmodule EmailAgent.IMAP.ConnectionTest do
  use ExUnit.Case, async: false

  import Mox

  alias EmailAgent.IMAP.Connection

  # Allow mocks to be called from any process
  setup :set_mox_global
  setup :verify_on_exit!

  @base_config [
    host: "imap.example.com",
    port: 993,
    email: "test@example.com",
    password: "password123",
    ssl: true,
    imap_module: EmailAgent.IMAP.ConnectionMock
  ]

  describe "start_link/1" do
    test "starts the GenServer with valid config" do
      EmailAgent.IMAP.ConnectionMock
      |> expect(:connect, fn _host, _port, _opts -> {:ok, :mock_socket} end)
      |> expect(:login, fn _socket, _email, _password -> {:ok, :logged_in} end)
      |> expect(:logout, fn _socket -> :ok end)
      |> expect(:close, fn _socket -> :ok end)

      {:ok, pid} = Connection.start_link(@base_config)

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "returns error with invalid config" do
      config = [host: "imap.example.com"]
      assert {:error, _reason} = Connection.start_link(config)
    end
  end

  describe "list_folders/1" do
    test "returns list of folder names" do
      EmailAgent.IMAP.ConnectionMock
      |> expect(:connect, fn _host, _port, _opts -> {:ok, :mock_socket} end)
      |> expect(:login, fn _socket, _email, _password -> {:ok, :logged_in} end)
      |> expect(:list_mailboxes, fn _socket ->
        {:ok, ["INBOX", "Sent", "Drafts"]}
      end)
      |> expect(:logout, fn _socket -> :ok end)
      |> expect(:close, fn _socket -> :ok end)

      {:ok, pid} = Connection.start_link(@base_config)
      assert {:ok, folders} = Connection.list_folders(pid)
      assert "INBOX" in folders

      GenServer.stop(pid)
    end
  end

  describe "fetch_emails/3" do
    test "returns empty list for empty folder" do
      EmailAgent.IMAP.ConnectionMock
      |> expect(:connect, fn _host, _port, _opts -> {:ok, :mock_socket} end)
      |> expect(:login, fn _socket, _email, _password -> {:ok, :logged_in} end)
      |> expect(:select_mailbox, fn _socket, "INBOX" -> {:ok, %{exists: 0}} end)
      |> expect(:logout, fn _socket -> :ok end)
      |> expect(:close, fn _socket -> :ok end)

      {:ok, pid} = Connection.start_link(@base_config)
      assert {:ok, []} = Connection.fetch_emails(pid, "INBOX")

      GenServer.stop(pid)
    end
  end

  describe "disconnect/1" do
    test "gracefully disconnects from server" do
      EmailAgent.IMAP.ConnectionMock
      |> expect(:connect, fn _host, _port, _opts -> {:ok, :mock_socket} end)
      |> expect(:login, fn _socket, _email, _password -> {:ok, :logged_in} end)
      |> expect(:logout, fn _socket -> :ok end)
      |> expect(:close, fn _socket -> :ok end)

      {:ok, pid} = Connection.start_link(@base_config)
      assert :ok = Connection.disconnect(pid)
      refute Process.alive?(pid)
    end
  end

  describe "config validation" do
    test "requires host, port, email, and password" do
      missing_host = Keyword.delete(@base_config, :host)
      missing_port = Keyword.delete(@base_config, :port)
      missing_email = Keyword.delete(@base_config, :email)
      missing_pass = Keyword.delete(@base_config, :password)

      assert {:error, {:missing_config, [:host]}} = Connection.start_link(missing_host)
      assert {:error, {:missing_config, [:port]}} = Connection.start_link(missing_port)
      assert {:error, {:missing_config, [:email]}} = Connection.start_link(missing_email)
      assert {:error, {:missing_config, [:password]}} = Connection.start_link(missing_pass)
    end
  end
end
