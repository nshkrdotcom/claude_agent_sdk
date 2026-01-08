defmodule PhoenixChatWeb.UserSocket do
  @moduledoc """
  WebSocket endpoint for the chat application.

  This socket handles WebSocket connections and routes them to the
  appropriate channel handlers. It's analogous to the WebSocket
  server setup in the TypeScript reference demo.

  ## Connection

  Connect to `ws://localhost:4000/socket/websocket` to establish
  a WebSocket connection.

  ## Channels

    * `chat:lobby` - General chat lobby
    * `chat:<id>` - Specific chat room by ID

  """
  use Phoenix.Socket

  # Channel routes
  channel("chat:*", PhoenixChatWeb.ChatChannel)

  @impl true
  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
