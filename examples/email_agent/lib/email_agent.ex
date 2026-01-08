defmodule EmailAgent do
  @moduledoc """
  Email Agent - An AI-powered email management application.

  This application demonstrates integration between the Claude Agent SDK
  and email systems via IMAP. It provides:

  - IMAP connection management for fetching emails
  - Local SQLite storage for email indexing and search
  - AI-powered email search and query capabilities
  - File-based automation rules for email processing

  ## Architecture

  The application is structured around several key components:

  - `EmailAgent.IMAP.Connection` - GenServer managing IMAP connections
  - `EmailAgent.Storage` - SQLite-based email persistence
  - `EmailAgent.Agent` - Claude SDK integration for AI queries
  - `EmailAgent.Rules` - Automation rule processing
  - `EmailAgent.EmailParser` - RFC 5322 email parsing

  ## Usage

      # Start the application (in iex -S mix)
      EmailAgent.Application.start(:normal, [])

      # Sync emails from IMAP
      EmailAgent.sync_emails()

      # Search emails with AI
      EmailAgent.ask("Find emails from John about the project")

      # List recent emails
      EmailAgent.list_emails(limit: 10)

  ## Configuration

  Set environment variables in `.env` file:

      IMAP_HOST=imap.gmail.com
      IMAP_PORT=993
      EMAIL_ADDRESS=your-email@gmail.com
      EMAIL_PASSWORD=your-app-password
      ANTHROPIC_API_KEY=your-api-key
  """

  alias EmailAgent.Agent
  alias EmailAgent.IMAP.Connection
  alias EmailAgent.Storage

  @doc """
  Syncs emails from the configured IMAP server to local storage.

  ## Options

  - `:folder` - IMAP folder to sync (default: "INBOX")
  - `:limit` - Maximum number of emails to fetch (default: 50)
  - `:since` - Only fetch emails since this date

  ## Examples

      EmailAgent.sync_emails()
      EmailAgent.sync_emails(folder: "INBOX", limit: 100)
      EmailAgent.sync_emails(since: ~U[2025-01-01 00:00:00Z])
  """
  @spec sync_emails(keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def sync_emails(opts \\ []) do
    folder = Keyword.get(opts, :folder, "INBOX")
    limit = Keyword.get(opts, :limit, 50)
    since = Keyword.get(opts, :since)

    with {:ok, conn} <- get_imap_connection(),
         {:ok, emails} <- Connection.fetch_emails(conn, folder, limit: limit, since: since),
         {:ok, storage} <- get_storage() do
      stored_count =
        Enum.reduce(emails, 0, fn email, count ->
          case Storage.insert_email(storage, email) do
            {:ok, _id} -> count + 1
            {:error, _} -> count
          end
        end)

      {:ok, stored_count}
    end
  end

  @doc """
  Asks a natural language question about emails.

  Uses Claude AI to interpret the query and search through stored emails.

  ## Examples

      EmailAgent.ask("Find emails from John about the quarterly report")
      EmailAgent.ask("What are my unread emails about?")
      EmailAgent.ask("Summarize emails from last week")
  """
  @spec ask(String.t()) :: {:ok, String.t()} | {:error, term()}
  def ask(query) when is_binary(query) do
    with {:ok, storage} <- get_storage() do
      Agent.process_query(query, storage)
    end
  end

  @doc """
  Lists emails from local storage.

  ## Options

  - `:limit` - Maximum number of emails (default: 20)
  - `:offset` - Pagination offset (default: 0)
  - `:label` - Filter by label
  - `:unread_only` - Only show unread emails (default: false)

  ## Examples

      EmailAgent.list_emails()
      EmailAgent.list_emails(limit: 10, unread_only: true)
  """
  @spec list_emails(keyword()) :: {:ok, [EmailAgent.Email.t()]} | {:error, term()}
  def list_emails(opts \\ []) do
    with {:ok, storage} <- get_storage() do
      Storage.list_emails(storage, opts)
    end
  end

  @doc """
  Searches emails by text query.

  Searches in subject, body, and sender fields.

  ## Examples

      EmailAgent.search("quarterly report")
      EmailAgent.search("from:john urgent")
  """
  @spec search(String.t()) :: {:ok, [EmailAgent.Email.t()]} | {:error, term()}
  def search(query) when is_binary(query) do
    with {:ok, storage} <- get_storage() do
      Storage.search_emails(storage, query)
    end
  end

  @doc """
  Gets a single email by ID.
  """
  @spec get_email(String.t()) :: {:ok, EmailAgent.Email.t()} | {:error, term()}
  def get_email(id) when is_binary(id) do
    with {:ok, storage} <- get_storage() do
      Storage.get_email(storage, id)
    end
  end

  @doc """
  Marks an email as read.
  """
  @spec mark_as_read(String.t()) :: :ok | {:error, term()}
  def mark_as_read(id) when is_binary(id) do
    with {:ok, storage} <- get_storage(),
         {:ok, _} <- Storage.update_email(storage, id, %{is_read: true}) do
      :ok
    end
  end

  @doc """
  Applies automation rules to all unprocessed emails.
  """
  @spec apply_rules() :: {:ok, non_neg_integer()} | {:error, term()}
  def apply_rules do
    with {:ok, storage} <- get_storage(),
         {:ok, rules} <- EmailAgent.Rules.load_rules(),
         {:ok, emails} <- Storage.list_emails(storage, unread_only: true) do
      processed =
        Enum.reduce(emails, 0, fn email, count ->
          case EmailAgent.Rules.process_email(email, rules, storage) do
            {:ok, _updated, applied} when applied != [] -> count + 1
            _ -> count
          end
        end)

      {:ok, processed}
    end
  end

  # Private helpers

  defp get_imap_connection do
    case Process.whereis(EmailAgent.IMAP.Connection) do
      nil -> {:error, :not_connected}
      pid -> {:ok, pid}
    end
  end

  defp get_storage do
    case Process.whereis(EmailAgent.Storage) do
      nil -> {:error, :storage_not_started}
      pid -> {:ok, pid}
    end
  end
end
