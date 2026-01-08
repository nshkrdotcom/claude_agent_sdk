defmodule PhoenixChatWeb.ChatController do
  @moduledoc """
  REST API controller for chat operations.

  Provides endpoints for managing chats and messages, similar to
  the Express routes in the TypeScript reference demo.

  ## Endpoints

    * `GET /api/chats` - List all chats
    * `POST /api/chats` - Create a new chat
    * `GET /api/chats/:id` - Get a specific chat
    * `DELETE /api/chats/:id` - Delete a chat
    * `GET /api/chats/:id/messages` - Get messages for a chat

  """
  use PhoenixChatWeb, :controller

  alias PhoenixChat.{ChatStore, SessionRegistry}

  @doc """
  Lists all chats.
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    chats = ChatStore.list_chats(PhoenixChat.ChatStore)
    json(conn, chats)
  end

  @doc """
  Creates a new chat.
  """
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, params) do
    title = params["title"]
    {:ok, chat} = ChatStore.create_chat(PhoenixChat.ChatStore, title)

    conn
    |> put_status(:created)
    |> json(chat)
  end

  @doc """
  Shows a specific chat.
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id}) do
    case ChatStore.get_chat(PhoenixChat.ChatStore, id) do
      {:ok, chat} ->
        json(conn, chat)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Chat not found"})
    end
  end

  @doc """
  Deletes a chat.
  """
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, %{"id" => id}) do
    case ChatStore.delete_chat(PhoenixChat.ChatStore, id) do
      :ok ->
        # Also close the session
        SessionRegistry.close_session(id)
        json(conn, %{success: true})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Chat not found"})
    end
  end

  @doc """
  Gets messages for a chat.
  """
  @spec messages(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def messages(conn, %{"id" => id}) do
    messages = ChatStore.get_messages(PhoenixChat.ChatStore, id)
    json(conn, messages)
  end
end
