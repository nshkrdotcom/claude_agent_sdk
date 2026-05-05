defmodule PhoenixChat.ChatStoreTest do
  @moduledoc """
  Tests for the ChatStore GenServer.
  """
  use ExUnit.Case, async: true

  alias PhoenixChat.ChatStore

  setup do
    {:ok, store} = ChatStore.start_link(name: nil)
    {:ok, store: store}
  end

  describe "create_chat/2" do
    test "creates a chat with a generated ID", %{store: store} do
      {:ok, chat} = ChatStore.create_chat(store)

      assert is_binary(chat.id)
      assert chat.title == "New Chat"
      assert is_binary(chat.created_at)
      assert is_binary(chat.updated_at)
    end

    test "creates a chat with a custom title", %{store: store} do
      {:ok, chat} = ChatStore.create_chat(store, "My Chat")

      assert chat.title == "My Chat"
    end
  end

  describe "get_chat/2" do
    test "returns a chat by ID", %{store: store} do
      {:ok, chat} = ChatStore.create_chat(store, "Test")

      assert {:ok, found} = ChatStore.get_chat(store, chat.id)
      assert found.id == chat.id
      assert found.title == "Test"
    end

    test "returns error for non-existent chat", %{store: store} do
      assert {:error, :not_found} = ChatStore.get_chat(store, "nonexistent")
    end
  end

  describe "list_chats/1" do
    test "returns empty list when no chats exist", %{store: store} do
      assert [] = ChatStore.list_chats(store)
    end

    test "returns all chats sorted by updated_at descending", %{store: store} do
      {:ok, chat1} = ChatStore.create_chat(store, "First")
      Process.sleep(10)
      {:ok, chat2} = ChatStore.create_chat(store, "Second")
      Process.sleep(10)
      {:ok, chat3} = ChatStore.create_chat(store, "Third")

      chats = ChatStore.list_chats(store)

      assert length(chats) == 3
      # Most recent first
      assert Enum.at(chats, 0).id == chat3.id
      assert Enum.at(chats, 1).id == chat2.id
      assert Enum.at(chats, 2).id == chat1.id
    end
  end

  describe "delete_chat/2" do
    test "deletes an existing chat", %{store: store} do
      {:ok, chat} = ChatStore.create_chat(store)

      assert :ok = ChatStore.delete_chat(store, chat.id)
      assert {:error, :not_found} = ChatStore.get_chat(store, chat.id)
    end

    test "returns error for non-existent chat", %{store: store} do
      assert {:error, :not_found} = ChatStore.delete_chat(store, "nonexistent")
    end

    test "also deletes associated messages", %{store: store} do
      {:ok, chat} = ChatStore.create_chat(store)
      {:ok, _msg} = ChatStore.add_message(store, chat.id, "user", "Hello")

      :ok = ChatStore.delete_chat(store, chat.id)

      # After delete, getting messages should return empty (chat doesn't exist)
      assert [] = ChatStore.get_messages(store, chat.id)
    end
  end

  describe "add_message/4" do
    test "adds a message to a chat", %{store: store} do
      {:ok, chat} = ChatStore.create_chat(store)

      {:ok, message} = ChatStore.add_message(store, chat.id, "user", "Hello!")

      assert is_binary(message.id)
      assert message.chat_id == chat.id
      assert message.role == "user"
      assert message.content == "Hello!"
      assert is_binary(message.timestamp)
    end

    test "updates chat title from first user message if still 'New Chat'", %{store: store} do
      {:ok, chat} = ChatStore.create_chat(store)

      {:ok, _msg} = ChatStore.add_message(store, chat.id, "user", "What is Elixir?")

      {:ok, updated_chat} = ChatStore.get_chat(store, chat.id)
      assert updated_chat.title == "What is Elixir?"
    end

    test "truncates long messages for title", %{store: store} do
      {:ok, chat} = ChatStore.create_chat(store)
      long_message = String.duplicate("a", 100)

      {:ok, _msg} = ChatStore.add_message(store, chat.id, "user", long_message)

      {:ok, updated_chat} = ChatStore.get_chat(store, chat.id)
      assert String.length(updated_chat.title) <= 53
      assert String.ends_with?(updated_chat.title, "...")
    end

    test "does not update title from assistant messages", %{store: store} do
      {:ok, chat} = ChatStore.create_chat(store)

      {:ok, _msg} = ChatStore.add_message(store, chat.id, "assistant", "I can help!")

      {:ok, updated_chat} = ChatStore.get_chat(store, chat.id)
      assert updated_chat.title == "New Chat"
    end

    test "does not update title if already customized", %{store: store} do
      {:ok, chat} = ChatStore.create_chat(store, "My Custom Title")

      {:ok, _msg} = ChatStore.add_message(store, chat.id, "user", "Hello!")

      {:ok, updated_chat} = ChatStore.get_chat(store, chat.id)
      assert updated_chat.title == "My Custom Title"
    end

    test "returns error for non-existent chat", %{store: store} do
      assert {:error, :not_found} = ChatStore.add_message(store, "nonexistent", "user", "Hello")
    end
  end

  describe "get_messages/2" do
    test "returns empty list for a new chat", %{store: store} do
      {:ok, chat} = ChatStore.create_chat(store)

      assert [] = ChatStore.get_messages(store, chat.id)
    end

    test "returns messages in order", %{store: store} do
      {:ok, chat} = ChatStore.create_chat(store)
      {:ok, msg1} = ChatStore.add_message(store, chat.id, "user", "Hello")
      {:ok, msg2} = ChatStore.add_message(store, chat.id, "assistant", "Hi there!")
      {:ok, msg3} = ChatStore.add_message(store, chat.id, "user", "How are you?")

      messages = ChatStore.get_messages(store, chat.id)

      assert length(messages) == 3
      assert Enum.at(messages, 0).id == msg1.id
      assert Enum.at(messages, 1).id == msg2.id
      assert Enum.at(messages, 2).id == msg3.id
    end

    test "returns empty list for non-existent chat", %{store: store} do
      assert [] = ChatStore.get_messages(store, "nonexistent")
    end
  end

  describe "update_chat_timestamp/2" do
    test "updates the updated_at timestamp", %{store: store} do
      {:ok, chat} = ChatStore.create_chat(store)
      original_updated_at = chat.updated_at

      Process.sleep(10)
      :ok = ChatStore.update_chat_timestamp(store, chat.id)

      {:ok, updated_chat} = ChatStore.get_chat(store, chat.id)
      assert updated_chat.updated_at > original_updated_at
    end
  end
end
