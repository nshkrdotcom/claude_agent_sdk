defmodule PhoenixChatWeb.Router do
  @moduledoc """
  Router for the Phoenix Chat application.
  """
  use PhoenixChatWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {PhoenixChatWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", PhoenixChatWeb do
    pipe_through(:browser)

    live("/", ChatLive, :index)
  end

  # REST API for chat management
  scope "/api", PhoenixChatWeb do
    pipe_through(:api)

    get("/chats", ChatController, :index)
    post("/chats", ChatController, :create)
    get("/chats/:id", ChatController, :show)
    delete("/chats/:id", ChatController, :delete)
    get("/chats/:id/messages", ChatController, :messages)
  end
end
