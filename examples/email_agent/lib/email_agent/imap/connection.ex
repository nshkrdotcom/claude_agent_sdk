defmodule EmailAgent.IMAP.Connection do
  @moduledoc """
  GenServer managing IMAP connections.

  Provides a reliable connection to IMAP servers with automatic
  reconnection on failures. Handles email fetching, folder operations,
  and flag management.

  ## Features

  - Automatic reconnection on connection loss
  - Configurable retry intervals
  - Email fetching with date filtering
  - Folder (mailbox) management
  - Flag operations (read/unread, star, etc.)

  ## Configuration

  Required options:

  - `:host` - IMAP server hostname
  - `:port` - IMAP server port (usually 993 for SSL)
  - `:email` - Email address for authentication
  - `:password` - Password or app password

  Optional options:

  - `:ssl` - Use SSL/TLS (default: true)
  - `:imap_module` - Module implementing ConnectionBehaviour (for testing)
  - `:reconnect_interval` - Milliseconds between reconnect attempts (default: 5000)

  ## Examples

      config = [
        host: "imap.gmail.com",
        port: 993,
        email: "user@gmail.com",
        password: "app-password"
      ]

      {:ok, pid} = Connection.start_link(config)

      # Fetch recent emails
      {:ok, emails} = Connection.fetch_emails(pid, "INBOX", limit: 10)

      # List folders
      {:ok, folders} = Connection.list_folders(pid)
  """

  use GenServer

  require Logger

  alias EmailAgent.{Email, EmailParser}

  @type state :: %{
          host: String.t(),
          port: non_neg_integer(),
          email: String.t(),
          password: String.t(),
          ssl: boolean(),
          socket: term() | nil,
          imap_module: module(),
          reconnect_interval: non_neg_integer(),
          connected: boolean()
        }

  # Client API

  @doc """
  Starts the IMAP connection GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    with :ok <- validate_config(opts) do
      name = Keyword.get(opts, :name, __MODULE__)
      GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @doc """
  Lists all available folders (mailboxes).
  """
  @spec list_folders(pid()) :: {:ok, [String.t()]} | {:error, term()}
  def list_folders(pid) do
    GenServer.call(pid, :list_folders)
  end

  @doc """
  Fetches emails from a folder.

  ## Options

  - `:limit` - Maximum number of emails to fetch (default: 50)
  - `:since` - Only fetch emails since this DateTime
  """
  @spec fetch_emails(pid(), String.t(), keyword()) :: {:ok, [Email.t()]} | {:error, term()}
  def fetch_emails(pid, folder, opts \\ []) do
    GenServer.call(pid, {:fetch_emails, folder, opts}, 60_000)
  end

  @doc """
  Fetches a single email by UID.
  """
  @spec fetch_email(pid(), non_neg_integer()) :: {:ok, Email.t()} | {:error, term()}
  def fetch_email(pid, uid) do
    GenServer.call(pid, {:fetch_email, uid})
  end

  @doc """
  Marks an email as read.
  """
  @spec mark_as_read(pid(), non_neg_integer()) :: :ok | {:error, term()}
  def mark_as_read(pid, uid) do
    GenServer.call(pid, {:mark_as_read, uid})
  end

  @doc """
  Moves an email to a different folder.
  """
  @spec move_to_folder(pid(), non_neg_integer(), String.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def move_to_folder(pid, uid, destination) do
    GenServer.call(pid, {:move_to_folder, uid, destination})
  end

  @doc """
  Disconnects from the IMAP server.
  """
  @spec disconnect(pid()) :: :ok
  def disconnect(pid) do
    GenServer.stop(pid, :normal)
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    state = %{
      host: Keyword.fetch!(opts, :host),
      port: Keyword.fetch!(opts, :port),
      email: Keyword.fetch!(opts, :email),
      password: Keyword.fetch!(opts, :password),
      ssl: Keyword.get(opts, :ssl, true),
      socket: nil,
      imap_module: Keyword.get(opts, :imap_module, EmailAgent.IMAP.Client),
      reconnect_interval: Keyword.get(opts, :reconnect_interval, 5_000),
      connected: false
    }

    # Connect immediately
    case connect(state) do
      {:ok, new_state} ->
        {:ok, new_state}

      {:error, reason} ->
        Logger.error("Failed to connect to IMAP server: #{inspect(reason)}")
        # Schedule reconnection attempt
        Process.send_after(self(), :reconnect, state.reconnect_interval)
        {:ok, state}
    end
  end

  @impl true
  def handle_call(:list_folders, _from, state) do
    case ensure_connected(state) do
      {:ok, state} ->
        result = state.imap_module.list_mailboxes(state.socket)
        {:reply, result, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:fetch_emails, folder, opts}, _from, state) do
    case ensure_connected(state) do
      {:ok, state} ->
        result = do_fetch_emails(state, folder, opts)
        {:reply, result, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:fetch_email, uid}, _from, state) do
    case ensure_connected(state) do
      {:ok, state} ->
        case state.imap_module.fetch_by_uid(state.socket, uid, []) do
          {:ok, raw_email} ->
            result = EmailParser.parse_raw(raw_email)
            {:reply, result, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:mark_as_read, uid}, _from, state) do
    case ensure_connected(state) do
      {:ok, state} ->
        result = state.imap_module.store_flags(state.socket, uid, :add, [:seen])
        {:reply, result, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:move_to_folder, uid, destination}, _from, state) do
    case ensure_connected(state) do
      {:ok, state} ->
        with {:ok, new_uid} <- state.imap_module.copy(state.socket, uid, destination),
             :ok <- state.imap_module.store_flags(state.socket, uid, :add, [:deleted]),
             :ok <- state.imap_module.expunge(state.socket) do
          {:reply, {:ok, new_uid}, state}
        else
          {:error, reason} -> {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(:reconnect, state) do
    case connect(state) do
      {:ok, new_state} ->
        Logger.info("Reconnected to IMAP server")
        {:noreply, new_state}

      {:error, reason} ->
        Logger.warning("Reconnection failed: #{inspect(reason)}, retrying...")
        Process.send_after(self(), :reconnect, state.reconnect_interval)
        {:noreply, state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    if state.connected and state.socket do
      state.imap_module.logout(state.socket)
      state.imap_module.close(state.socket)
    end

    :ok
  end

  # Private functions

  defp validate_config(opts) do
    required = [:host, :port, :email, :password]

    missing =
      Enum.filter(required, fn key ->
        not Keyword.has_key?(opts, key)
      end)

    if missing == [] do
      :ok
    else
      {:error, {:missing_config, missing}}
    end
  end

  defp connect(state) do
    ssl_opts = if state.ssl, do: [ssl: true], else: []

    with {:ok, socket} <- state.imap_module.connect(state.host, state.port, ssl_opts),
         {:ok, _} <- state.imap_module.login(socket, state.email, state.password) do
      {:ok, %{state | socket: socket, connected: true}}
    end
  end

  defp ensure_connected(%{connected: true} = state), do: {:ok, state}

  defp ensure_connected(state) do
    case connect(state) do
      {:ok, new_state} -> {:ok, new_state}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_fetch_emails(state, folder, opts) do
    limit = Keyword.get(opts, :limit, 50)
    since = Keyword.get(opts, :since)

    with {:ok, mailbox_info} <- state.imap_module.select_mailbox(state.socket, folder) do
      exists = Map.get(mailbox_info, :exists, 0)
      fetch_emails_from_mailbox(state, exists, limit, since)
    end
  end

  defp fetch_emails_from_mailbox(_state, 0, _limit, _since), do: {:ok, []}

  defp fetch_emails_from_mailbox(state, exists, limit, since) do
    uids = get_email_uids(state, exists, limit, since)
    fetch_emails_by_uids(state, uids)
  end

  defp get_email_uids(state, _exists, limit, since) when not is_nil(since) do
    case state.imap_module.search(state.socket, {:since, since}) do
      {:ok, found_uids} -> Enum.take(found_uids, limit)
      {:error, _} -> []
    end
  end

  defp get_email_uids(_state, exists, limit, nil) do
    start = max(1, exists - limit + 1)
    Enum.to_list(start..exists)
  end

  defp fetch_emails_by_uids(_state, []), do: {:ok, []}

  defp fetch_emails_by_uids(state, uids) do
    case state.imap_module.fetch_messages(state.socket, uids, []) do
      {:ok, raw_emails} ->
        emails =
          raw_emails
          |> Enum.map(&EmailParser.parse_raw/1)
          |> Enum.filter(&match?({:ok, _}, &1))
          |> Enum.map(fn {:ok, email} -> email end)

        {:ok, emails}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
