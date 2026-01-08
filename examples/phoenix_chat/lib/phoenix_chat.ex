defmodule PhoenixChat do
  @moduledoc """
  Phoenix Chat - A Claude Agent SDK Demo Application.

  This application demonstrates how to integrate the Claude Agent SDK
  with Phoenix LiveView and Channels for real-time chat functionality.

  ## Features

  - Real-time chat interface using Phoenix LiveView
  - WebSocket streaming via Phoenix Channels
  - Claude Agent SDK integration for AI responses
  - In-memory chat storage
  - Tool usage visualization

  ## Architecture

  ```
  +----------------+     +------------------+     +----------------+
  |   Browser      |<--->|  Phoenix Server  |<--->| Claude Agent   |
  | (LiveView/JS)  |     |  (Channels/LV)   |     |    SDK         |
  +----------------+     +------------------+     +----------------+
                               |
                               v
                        +-------------+
                        | ChatStore   |
                        | (GenServer) |
                        +-------------+
  ```

  ## Modules

  - `PhoenixChat.ChatStore` - In-memory storage for chats and messages
  - `PhoenixChat.ChatSession` - GenServer managing Claude agent sessions
  - `PhoenixChat.SessionRegistry` - Dynamic supervisor for sessions
  - `PhoenixChatWeb.ChatChannel` - WebSocket channel for streaming
  - `PhoenixChatWeb.ChatLive` - LiveView for the chat UI

  """
end
