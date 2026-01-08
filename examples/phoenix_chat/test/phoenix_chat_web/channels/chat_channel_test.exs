defmodule PhoenixChatWeb.ChatChannelTest do
  @moduledoc """
  Tests for the ChatChannel WebSocket channel.
  """
  use PhoenixChatWeb.ChannelCase

  alias PhoenixChat.ChatStore
  alias PhoenixChatWeb.ChatChannel
  alias PhoenixChatWeb.UserSocket

  setup do
    # Start a ChatStore for tests
    store_name = :"store_#{:erlang.unique_integer([:positive])}"
    {:ok, _store_pid} = ChatStore.start_link(name: store_name)

    # Create a test chat
    {:ok, chat} = ChatStore.create_chat(store_name, "Test Chat")

    {:ok, store: store_name, chat: chat}
  end

  describe "join/3" do
    test "joins chat:lobby successfully" do
      {:ok, _, socket} =
        socket(UserSocket, "user_id", %{})
        |> subscribe_and_join(ChatChannel, "chat:lobby")

      assert socket.assigns.topic == "chat:lobby"
    end

    test "joins chat:<id> with valid chat_id", %{chat: chat} do
      {:ok, reply, socket} =
        socket(UserSocket, "user_id", %{})
        |> subscribe_and_join(ChatChannel, "chat:#{chat.id}")

      assert socket.assigns.chat_id == chat.id
      assert reply == %{}
    end
  end

  describe "handle_in subscribe" do
    test "subscribes to a chat and receives history", %{store: store, chat: chat} do
      # Add some messages first
      {:ok, _} = ChatStore.add_message(store, chat.id, "user", "Hello")
      {:ok, _} = ChatStore.add_message(store, chat.id, "assistant", "Hi there!")

      {:ok, _, socket} =
        socket(UserSocket, "user_id", %{store: store})
        |> subscribe_and_join(ChatChannel, "chat:lobby")

      ref = push(socket, "subscribe", %{"chat_id" => chat.id})
      assert_reply(ref, :ok, %{"messages" => messages})

      assert length(messages) == 2
      assert Enum.at(messages, 0)["role"] == "user"
      assert Enum.at(messages, 0)["content"] == "Hello"
      assert Enum.at(messages, 1)["role"] == "assistant"
    end
  end

  describe "handle_in chat" do
    test "broadcasts user message to channel", %{store: store, chat: chat} do
      {:ok, _, socket} =
        socket(UserSocket, "user_id", %{store: store})
        |> subscribe_and_join(ChatChannel, "chat:lobby")

      # Subscribe to the chat first
      push(socket, "subscribe", %{"chat_id" => chat.id})

      # Send a message
      push(socket, "chat", %{"chat_id" => chat.id, "content" => "Test message"})

      # Should receive confirmation of the message
      chat_id = chat.id
      assert_broadcast("user_message", %{content: "Test message", chat_id: ^chat_id})
    end

    test "returns error for missing chat_id", %{store: store} do
      {:ok, _, socket} =
        socket(UserSocket, "user_id", %{store: store})
        |> subscribe_and_join(ChatChannel, "chat:lobby")

      ref = push(socket, "chat", %{"content" => "Test"})
      assert_reply(ref, :error, %{reason: "chat_id required"})
    end

    test "returns error for missing content", %{store: store, chat: chat} do
      {:ok, _, socket} =
        socket(UserSocket, "user_id", %{store: store})
        |> subscribe_and_join(ChatChannel, "chat:lobby")

      ref = push(socket, "chat", %{"chat_id" => chat.id})
      assert_reply(ref, :error, %{reason: "content required"})
    end
  end
end
