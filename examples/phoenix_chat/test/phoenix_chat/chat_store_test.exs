defmodule PhoenixChat.ChatStoreTest do
  @moduledoc """
  Tests for the ChatStore GenServer.
  """
  use ExUnit.Case, async: true

  alias PhoenixChat.ChatStore

  setup do
    # Start a new ChatStore for each test with a unique name
    name = :"chat_store_#{:erlang.unique_integer([:positive])}"
    {:ok, pid} = ChatStore.start_link(name: name)
    {:ok, store: pid, name: name}
  end

  describe "create_chat/2" do
    test "creates a chat with a generated ID", %{name: name} do
      {:ok, chat} = ChatStore.create_chat(name)

      assert is_binary(chat.id)
      assert chat.title == "New Chat"
      assert is_binary(chat.created_at)
      assert is_binary(chat.updated_at)
    end

    test "creates a chat with a custom title", %{name: name} do
      {:ok, chat} = ChatStore.create_chat(name, "My Chat")

      assert chat.title == "My Chat"
    end
  end

  describe "get_chat/2" do
    test "returns a chat by ID", %{name: name} do
      {:ok, chat} = ChatStore.create_chat(name, "Test")

      assert {:ok, found} = ChatStore.get_chat(name, chat.id)
      assert found.id == chat.id
      assert found.title == "Test"
    end

    test "returns error for non-existent chat", %{name: name} do
      assert {:error, :not_found} = ChatStore.get_chat(name, "nonexistent")
    end
  end

  describe "list_chats/1" do
    test "returns empty list when no chats exist", %{name: name} do
      assert [] = ChatStore.list_chats(name)
    end

    test "returns all chats sorted by updated_at descending", %{name: name} do
      {:ok, chat1} = ChatStore.create_chat(name, "First")
      Process.sleep(10)
      {:ok, chat2} = ChatStore.create_chat(name, "Second")
      Process.sleep(10)
      {:ok, chat3} = ChatStore.create_chat(name, "Third")

      chats = ChatStore.list_chats(name)

      assert length(chats) == 3
      # Most recent first
      assert Enum.at(chats, 0).id == chat3.id
      assert Enum.at(chats, 1).id == chat2.id
      assert Enum.at(chats, 2).id == chat1.id
    end
  end

  describe "delete_chat/2" do
    test "deletes an existing chat", %{name: name} do
      {:ok, chat} = ChatStore.create_chat(name)

      assert :ok = ChatStore.delete_chat(name, chat.id)
      assert {:error, :not_found} = ChatStore.get_chat(name, chat.id)
    end

    test "returns error for non-existent chat", %{name: name} do
      assert {:error, :not_found} = ChatStore.delete_chat(name, "nonexistent")
    end

    test "also deletes associated messages", %{name: name} do
      {:ok, chat} = ChatStore.create_chat(name)
      {:ok, _msg} = ChatStore.add_message(name, chat.id, "user", "Hello")

      :ok = ChatStore.delete_chat(name, chat.id)

      # After delete, getting messages should return empty (chat doesn't exist)
      assert [] = ChatStore.get_messages(name, chat.id)
    end
  end

  describe "add_message/4" do
    test "adds a message to a chat", %{name: name} do
      {:ok, chat} = ChatStore.create_chat(name)

      {:ok, message} = ChatStore.add_message(name, chat.id, "user", "Hello!")

      assert is_binary(message.id)
      assert message.chat_id == chat.id
      assert message.role == "user"
      assert message.content == "Hello!"
      assert is_binary(message.timestamp)
    end

    test "updates chat title from first user message if still 'New Chat'", %{name: name} do
      {:ok, chat} = ChatStore.create_chat(name)

      {:ok, _msg} = ChatStore.add_message(name, chat.id, "user", "What is Elixir?")

      {:ok, updated_chat} = ChatStore.get_chat(name, chat.id)
      assert updated_chat.title == "What is Elixir?"
    end

    test "truncates long messages for title", %{name: name} do
      {:ok, chat} = ChatStore.create_chat(name)
      long_message = String.duplicate("a", 100)

      {:ok, _msg} = ChatStore.add_message(name, chat.id, "user", long_message)

      {:ok, updated_chat} = ChatStore.get_chat(name, chat.id)
      assert String.length(updated_chat.title) <= 53
      assert String.ends_with?(updated_chat.title, "...")
    end

    test "does not update title from assistant messages", %{name: name} do
      {:ok, chat} = ChatStore.create_chat(name)

      {:ok, _msg} = ChatStore.add_message(name, chat.id, "assistant", "I can help!")

      {:ok, updated_chat} = ChatStore.get_chat(name, chat.id)
      assert updated_chat.title == "New Chat"
    end

    test "does not update title if already customized", %{name: name} do
      {:ok, chat} = ChatStore.create_chat(name, "My Custom Title")

      {:ok, _msg} = ChatStore.add_message(name, chat.id, "user", "Hello!")

      {:ok, updated_chat} = ChatStore.get_chat(name, chat.id)
      assert updated_chat.title == "My Custom Title"
    end

    test "returns error for non-existent chat", %{name: name} do
      assert {:error, :not_found} = ChatStore.add_message(name, "nonexistent", "user", "Hello")
    end
  end

  describe "get_messages/2" do
    test "returns empty list for a new chat", %{name: name} do
      {:ok, chat} = ChatStore.create_chat(name)

      assert [] = ChatStore.get_messages(name, chat.id)
    end

    test "returns messages in order", %{name: name} do
      {:ok, chat} = ChatStore.create_chat(name)
      {:ok, msg1} = ChatStore.add_message(name, chat.id, "user", "Hello")
      {:ok, msg2} = ChatStore.add_message(name, chat.id, "assistant", "Hi there!")
      {:ok, msg3} = ChatStore.add_message(name, chat.id, "user", "How are you?")

      messages = ChatStore.get_messages(name, chat.id)

      assert length(messages) == 3
      assert Enum.at(messages, 0).id == msg1.id
      assert Enum.at(messages, 1).id == msg2.id
      assert Enum.at(messages, 2).id == msg3.id
    end

    test "returns empty list for non-existent chat", %{name: name} do
      assert [] = ChatStore.get_messages(name, "nonexistent")
    end
  end

  describe "update_chat_timestamp/2" do
    test "updates the updated_at timestamp", %{name: name} do
      {:ok, chat} = ChatStore.create_chat(name)
      original_updated_at = chat.updated_at

      Process.sleep(10)
      :ok = ChatStore.update_chat_timestamp(name, chat.id)

      {:ok, updated_chat} = ChatStore.get_chat(name, chat.id)
      assert updated_chat.updated_at > original_updated_at
    end
  end
end
