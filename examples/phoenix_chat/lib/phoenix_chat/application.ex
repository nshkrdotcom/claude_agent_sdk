defmodule PhoenixChat.Application do
  @moduledoc """
  Main application supervisor for the Phoenix Chat demo.

  This module starts all the required processes:
  - Phoenix Endpoint (web server)
  - PubSub for real-time messaging
  - ChatStore for in-memory chat storage
  - SessionRegistry for managing Claude agent sessions
  - Process registry for session naming
  """
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Phoenix endpoint
      PhoenixChatWeb.Telemetry,
      {Phoenix.PubSub, name: PhoenixChat.PubSub},
      # Registry for naming chat sessions
      {Registry, keys: :unique, name: PhoenixChat.SessionNames},
      # In-memory chat storage
      {PhoenixChat.ChatStore, name: PhoenixChat.ChatStore},
      # Dynamic supervisor for chat sessions
      {PhoenixChat.SessionRegistry, name: PhoenixChat.SessionRegistry},
      # Start the Endpoint (http/https)
      PhoenixChatWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: PhoenixChat.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    PhoenixChatWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
