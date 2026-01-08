defmodule EmailAgent.Storage do
  @moduledoc """
  SQLite-based storage for emails.

  Provides local persistence for fetched emails with full-text search
  capabilities. Uses exqlite for direct SQLite access without Ecto.

  ## Schema

  The storage creates the following tables:

  - `emails` - Main email storage with all fields
  - `email_metadata` - Search-optimized metadata
  - `sync_state` - IMAP sync state tracking

  ## Usage

      {:ok, conn} = Storage.init(database_path: "priv/emails.db")

      # Insert email
      {:ok, id} = Storage.insert_email(conn, email)

      # Search
      {:ok, results} = Storage.search_emails(conn, "quarterly report")

      # List with filters
      {:ok, emails} = Storage.list_emails(conn, unread_only: true, limit: 10)
  """

  use GenServer

  alias EmailAgent.Email

  # Exqlite.Sqlite3.open/1 returns a reference, not Exqlite.Connection.t()
  @type conn :: reference()

  # Client API

  @doc """
  Starts the Storage GenServer.

  ## Options

  - `:database_path` - Path to SQLite database file (default: "priv/emails.db")
  - `:name` - GenServer name (default: `EmailAgent.Storage`)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Initializes the database with required tables.

  Can be called directly for testing or when not using GenServer.
  """
  @spec init_db(keyword()) :: {:ok, conn()} | {:error, term()}
  def init_db(opts) do
    db_path = Keyword.get(opts, :database_path, "priv/emails.db")

    # Ensure directory exists
    db_path |> Path.dirname() |> File.mkdir_p!()

    case Exqlite.Sqlite3.open(db_path) do
      {:ok, conn} ->
        create_tables(conn)
        {:ok, conn}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Closes the database connection.
  """
  @spec close(conn()) :: :ok | {:error, term()}
  def close(conn) do
    Exqlite.Sqlite3.close(conn)
  end

  @doc """
  Executes a raw SQL query.
  """
  @spec query(conn() | pid(), String.t(), list()) :: {:ok, list()} | {:error, term()}
  def query(conn_or_pid, sql, params \\ [])

  def query(pid, sql, params) when is_pid(pid) do
    GenServer.call(pid, {:query, sql, params})
  end

  def query(conn, sql, params) do
    fetch_all(conn, sql, params)
  end

  @doc """
  Inserts or updates an email.

  If an email with the same message_id exists, it will be updated.
  Returns the email ID.
  """
  @spec insert_email(pid() | conn(), Email.t()) :: {:ok, String.t()} | {:error, term()}
  def insert_email(pid, email) when is_pid(pid) do
    GenServer.call(pid, {:insert_email, email})
  end

  def insert_email(conn, %Email{} = email) do
    id = email.id || generate_id()
    params = build_insert_params(id, email)

    sql = """
    INSERT INTO emails (
      id, message_id, from_address, from_name, to_addresses, cc_addresses,
      bcc_addresses, reply_to, subject, date, body_text, body_html,
      attachments, labels, is_read, is_starred, raw
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(message_id) DO UPDATE SET
      subject = excluded.subject,
      body_text = excluded.body_text,
      body_html = excluded.body_html,
      labels = excluded.labels,
      is_read = excluded.is_read,
      is_starred = excluded.is_starred
    """

    case execute(conn, sql, params) do
      :ok -> {:ok, id}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_insert_params(id, email) do
    [
      id,
      email.message_id,
      email.from,
      email.from_name,
      Jason.encode!(email.to || []),
      Jason.encode!(email.cc || []),
      Jason.encode!(email.bcc || []),
      email.reply_to,
      email.subject,
      format_datetime(email.date),
      email.body_text,
      email.body_html,
      Jason.encode!(email.attachments || []),
      Jason.encode!(email.labels || []),
      bool_to_int(email.is_read),
      bool_to_int(email.is_starred),
      email.raw
    ]
  end

  defp bool_to_int(true), do: 1
  defp bool_to_int(_), do: 0

  @doc """
  Gets an email by ID.
  """
  @spec get_email(pid() | conn(), String.t()) :: {:ok, Email.t()} | {:error, :not_found | term()}
  def get_email(pid, id) when is_pid(pid) do
    GenServer.call(pid, {:get_email, id})
  end

  def get_email(conn, id) do
    sql = "SELECT * FROM emails WHERE id = ?"

    case fetch_all(conn, sql, [id]) do
      {:ok, [row | _]} -> {:ok, row_to_email(row)}
      {:ok, []} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists emails with optional filters.

  ## Options

  - `:limit` - Maximum number of emails (default: 50)
  - `:offset` - Pagination offset (default: 0)
  - `:label` - Filter by label
  - `:unread_only` - Only return unread emails
  - `:order_by` - Field to order by (default: :date)
  - `:order_dir` - Order direction :asc or :desc (default: :desc)
  """
  @spec list_emails(pid() | conn(), keyword()) :: {:ok, [Email.t()]} | {:error, term()}
  def list_emails(pid, opts \\ [])

  def list_emails(pid, opts) when is_pid(pid) do
    GenServer.call(pid, {:list_emails, opts})
  end

  def list_emails(conn, opts) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    label = Keyword.get(opts, :label)
    unread_only = Keyword.get(opts, :unread_only, false)

    {where_clauses, params} = build_filters(label, unread_only)

    where_sql =
      if where_clauses == [], do: "", else: "WHERE " <> Enum.join(where_clauses, " AND ")

    sql = """
    SELECT * FROM emails
    #{where_sql}
    ORDER BY date DESC
    LIMIT ? OFFSET ?
    """

    case fetch_all(conn, sql, params ++ [limit, offset]) do
      {:ok, rows} -> {:ok, Enum.map(rows, &row_to_email/1)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Searches emails by text query.

  Searches in subject, body_text, and from_address fields.
  """
  @spec search_emails(pid() | conn(), String.t()) :: {:ok, [Email.t()]} | {:error, term()}
  def search_emails(pid, query) when is_pid(pid) do
    GenServer.call(pid, {:search_emails, query})
  end

  def search_emails(conn, query) do
    # Simple LIKE-based search (SQLite FTS could be added for performance)
    search_term = "%#{query}%"

    sql = """
    SELECT * FROM emails
    WHERE subject LIKE ? OR body_text LIKE ? OR from_address LIKE ?
    ORDER BY date DESC
    LIMIT 50
    """

    case fetch_all(conn, sql, [search_term, search_term, search_term]) do
      {:ok, rows} -> {:ok, Enum.map(rows, &row_to_email/1)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Updates an email's fields.
  """
  @spec update_email(pid() | conn(), String.t(), map()) ::
          {:ok, Email.t()} | {:error, :not_found | term()}
  def update_email(pid, id, changes) when is_pid(pid) do
    GenServer.call(pid, {:update_email, id, changes})
  end

  def update_email(conn, id, changes) when is_binary(id) and is_map(changes) do
    # Build SET clause dynamically
    {set_clauses, params} = build_update_clauses(changes)

    if set_clauses == [] do
      get_email(conn, id)
    else
      sql = """
      UPDATE emails SET #{Enum.join(set_clauses, ", ")}
      WHERE id = ?
      """

      case execute(conn, sql, params ++ [id]) do
        :ok -> get_email(conn, id)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Deletes an email by ID.
  """
  @spec delete_email(pid() | conn(), String.t()) :: :ok | {:error, term()}
  def delete_email(pid, id) when is_pid(pid) do
    GenServer.call(pid, {:delete_email, id})
  end

  def delete_email(conn, id) do
    sql = "DELETE FROM emails WHERE id = ?"

    case execute(conn, sql, [id]) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets the last sync timestamp for a folder.
  """
  @spec get_last_sync(pid() | conn(), String.t()) :: {:ok, DateTime.t() | nil} | {:error, term()}
  def get_last_sync(pid, folder) when is_pid(pid) do
    GenServer.call(pid, {:get_last_sync, folder})
  end

  def get_last_sync(conn, folder) do
    sql = "SELECT last_sync FROM sync_state WHERE folder = ?"

    case fetch_all(conn, sql, [folder]) do
      {:ok, [%{"last_sync" => timestamp} | _]} when not is_nil(timestamp) ->
        case DateTime.from_iso8601(timestamp) do
          {:ok, datetime, _} -> {:ok, datetime}
          _ -> {:ok, nil}
        end

      {:ok, _} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sets the last sync timestamp for a folder.
  """
  @spec set_last_sync(pid() | conn(), String.t(), DateTime.t()) :: :ok | {:error, term()}
  def set_last_sync(pid, folder, timestamp) when is_pid(pid) do
    GenServer.call(pid, {:set_last_sync, folder, timestamp})
  end

  def set_last_sync(conn, folder, timestamp) do
    sql = """
    INSERT INTO sync_state (folder, last_sync)
    VALUES (?, ?)
    ON CONFLICT(folder) DO UPDATE SET last_sync = excluded.last_sync
    """

    case execute(conn, sql, [folder, DateTime.to_iso8601(timestamp)]) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Counts emails with optional filters.
  """
  @spec email_count(pid() | conn(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def email_count(pid, opts \\ [])

  def email_count(pid, opts) when is_pid(pid) do
    GenServer.call(pid, {:email_count, opts})
  end

  def email_count(conn, opts) do
    unread_only = Keyword.get(opts, :unread_only, false)

    {sql, params} =
      if unread_only do
        {"SELECT COUNT(*) as count FROM emails WHERE is_read = 0", []}
      else
        {"SELECT COUNT(*) as count FROM emails", []}
      end

    case fetch_all(conn, sql, params) do
      {:ok, [%{"count" => count} | _]} -> {:ok, count}
      {:ok, _} -> {:ok, 0}
      {:error, reason} -> {:error, reason}
    end
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    case init_db(opts) do
      {:ok, conn} -> {:ok, %{conn: conn}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:query, sql, params}, _from, %{conn: conn} = state) do
    result = fetch_all(conn, sql, params)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:insert_email, email}, _from, %{conn: conn} = state) do
    result = insert_email(conn, email)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_email, id}, _from, %{conn: conn} = state) do
    result = get_email(conn, id)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:list_emails, opts}, _from, %{conn: conn} = state) do
    result = list_emails(conn, opts)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:search_emails, query}, _from, %{conn: conn} = state) do
    result = search_emails(conn, query)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:update_email, id, changes}, _from, %{conn: conn} = state) do
    result = update_email(conn, id, changes)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:delete_email, id}, _from, %{conn: conn} = state) do
    result = delete_email(conn, id)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_last_sync, folder}, _from, %{conn: conn} = state) do
    result = get_last_sync(conn, folder)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:set_last_sync, folder, timestamp}, _from, %{conn: conn} = state) do
    result = set_last_sync(conn, folder, timestamp)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:email_count, opts}, _from, %{conn: conn} = state) do
    result = email_count(conn, opts)
    {:reply, result, state}
  end

  @impl true
  def terminate(_reason, %{conn: conn}) do
    close(conn)
    :ok
  end

  # Private functions

  defp create_tables(conn) do
    # Main emails table
    execute(
      conn,
      """
      CREATE TABLE IF NOT EXISTS emails (
        id TEXT PRIMARY KEY,
        message_id TEXT UNIQUE,
        from_address TEXT,
        from_name TEXT,
        to_addresses TEXT,
        cc_addresses TEXT,
        bcc_addresses TEXT,
        reply_to TEXT,
        subject TEXT,
        date TEXT,
        body_text TEXT,
        body_html TEXT,
        attachments TEXT,
        labels TEXT,
        is_read INTEGER DEFAULT 0,
        is_starred INTEGER DEFAULT 0,
        raw TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
      """,
      []
    )

    # Sync state table
    execute(
      conn,
      """
      CREATE TABLE IF NOT EXISTS sync_state (
        folder TEXT PRIMARY KEY,
        last_sync TEXT,
        uid_validity INTEGER
      )
      """,
      []
    )

    # Email metadata for search (future FTS support)
    execute(
      conn,
      """
      CREATE TABLE IF NOT EXISTS email_metadata (
        email_id TEXT PRIMARY KEY,
        keywords TEXT,
        has_attachments INTEGER,
        needs_response INTEGER,
        FOREIGN KEY (email_id) REFERENCES emails(id)
      )
      """,
      []
    )

    # Create indexes
    execute(conn, "CREATE INDEX IF NOT EXISTS idx_emails_message_id ON emails(message_id)", [])
    execute(conn, "CREATE INDEX IF NOT EXISTS idx_emails_date ON emails(date)", [])
    execute(conn, "CREATE INDEX IF NOT EXISTS idx_emails_from ON emails(from_address)", [])
    execute(conn, "CREATE INDEX IF NOT EXISTS idx_emails_is_read ON emails(is_read)", [])

    :ok
  end

  defp execute(conn, sql, params) do
    if params == [] do
      case Exqlite.Sqlite3.execute(conn, sql) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      with {:ok, stmt} <- Exqlite.Sqlite3.prepare(conn, sql),
           :ok <- bind_params(conn, stmt, params) do
        result = step_until_done(conn, stmt)
        Exqlite.Sqlite3.release(conn, stmt)
        result
      end
    end
  end

  defp step_until_done(conn, stmt) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      :done -> :ok
      {:row, _} -> step_until_done(conn, stmt)
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_all(conn, sql, params) do
    with {:ok, stmt} <- Exqlite.Sqlite3.prepare(conn, sql),
         :ok <- bind_params(conn, stmt, params),
         {:ok, rows} <- fetch_rows(conn, stmt) do
      Exqlite.Sqlite3.release(conn, stmt)
      {:ok, rows}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp bind_params(_conn, stmt, params) do
    Exqlite.Sqlite3.bind(stmt, params)
  end

  defp fetch_rows(conn, stmt) do
    fetch_rows(conn, stmt, [])
  end

  defp fetch_rows(conn, stmt, acc) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, values} ->
        {:ok, columns} = Exqlite.Sqlite3.columns(conn, stmt)
        row = Enum.zip(columns, values) |> Map.new()
        fetch_rows(conn, stmt, [row | acc])

      :done ->
        {:ok, Enum.reverse(acc)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp row_to_email(row) do
    %Email{
      id: row["id"],
      message_id: row["message_id"],
      from: row["from_address"],
      from_name: row["from_name"],
      to: Jason.decode!(row["to_addresses"] || "[]"),
      cc: Jason.decode!(row["cc_addresses"] || "[]"),
      bcc: Jason.decode!(row["bcc_addresses"] || "[]"),
      reply_to: row["reply_to"],
      subject: row["subject"],
      date: parse_stored_date(row["date"]),
      body_text: row["body_text"],
      body_html: row["body_html"],
      attachments: Jason.decode!(row["attachments"] || "[]"),
      labels: Jason.decode!(row["labels"] || "[]"),
      is_read: row["is_read"] == 1,
      is_starred: row["is_starred"] == 1,
      raw: row["raw"]
    }
  end

  defp parse_stored_date(nil), do: nil

  defp parse_stored_date(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp build_filters(label, unread_only) do
    clauses = []
    params = []

    {clauses, params} =
      if label do
        {["labels LIKE ?" | clauses], ["%\"#{label}\"%" | params]}
      else
        {clauses, params}
      end

    {clauses, params} =
      if unread_only do
        {["is_read = 0" | clauses], params}
      else
        {clauses, params}
      end

    {Enum.reverse(clauses), Enum.reverse(params)}
  end

  defp build_update_clauses(changes) do
    field_mapping = %{
      is_read: "is_read",
      is_starred: "is_starred",
      labels: "labels",
      subject: "subject"
    }

    changes
    |> Enum.reduce({[], []}, &build_clause(&1, &2, field_mapping))
    |> then(fn {clauses, params} -> {Enum.reverse(clauses), Enum.reverse(params)} end)
  end

  defp build_clause({key, value}, {clauses, params}, field_mapping) do
    case Map.get(field_mapping, key) do
      nil -> {clauses, params}
      column -> {["#{column} = ?" | clauses], [format_update_value(key, value) | params]}
    end
  end

  defp format_update_value(:is_read, value), do: if(value, do: 1, else: 0)
  defp format_update_value(:is_starred, value), do: if(value, do: 1, else: 0)
  defp format_update_value(:labels, value), do: Jason.encode!(value)
  defp format_update_value(_key, value), do: value

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
