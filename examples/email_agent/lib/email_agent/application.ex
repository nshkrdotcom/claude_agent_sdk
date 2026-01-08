defmodule EmailAgent.Application do
  @moduledoc """
  OTP Application for the Email Agent.

  Supervises the core processes:
  - Storage GenServer for SQLite access
  - IMAP Connection GenServer (when configured)

  ## Configuration

  The application reads configuration from environment variables
  or application config. See `.env.example` for required variables.

  ## Starting

  The application can be started in different modes:

  1. Full mode (with IMAP connection):

         # With all environment variables set
         iex -S mix

  2. Storage-only mode (for testing or offline use):

         # Without IMAP credentials
         iex -S mix

  In storage-only mode, only the SQLite storage is started.
  """

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    # Load environment variables from .env file
    load_env()

    children = build_children()

    opts = [strategy: :one_for_one, name: EmailAgent.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("Email Agent started successfully")
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start Email Agent: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def stop(_state) do
    Logger.info("Email Agent stopping")
    :ok
  end

  # Private functions

  defp load_env do
    # Try to load .env file if dotenvy is available
    if Code.ensure_loaded?(Dotenvy) do
      Dotenvy.source([".env", ".env.local"])
    end
  rescue
    _ -> :ok
  end

  defp build_children do
    children = []

    # Always start storage
    storage_opts = [
      database_path: get_config(:database_path, "priv/emails.db"),
      name: EmailAgent.Storage
    ]

    children = [{EmailAgent.Storage, storage_opts} | children]

    # Optionally start IMAP connection if configured
    children =
      case build_imap_config() do
        {:ok, imap_config} ->
          [{EmailAgent.IMAP.Connection, imap_config} | children]

        {:error, _reason} ->
          Logger.warning("IMAP not configured - running in storage-only mode")
          children
      end

    Enum.reverse(children)
  end

  defp build_imap_config do
    host = get_env("IMAP_HOST")
    port = get_env("IMAP_PORT")
    email = get_env("EMAIL_ADDRESS")
    password = get_env("EMAIL_PASSWORD")

    if host && port && email && password do
      {:ok,
       [
         host: host,
         port: String.to_integer(port),
         email: email,
         password: password,
         ssl: true,
         name: EmailAgent.IMAP.Connection
       ]}
    else
      {:error, :incomplete_imap_config}
    end
  end

  defp get_env(key) do
    System.get_env(key)
  end

  defp get_config(key, default) do
    Application.get_env(:email_agent, key, default)
  end
end
