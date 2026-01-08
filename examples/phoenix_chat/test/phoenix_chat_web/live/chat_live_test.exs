defmodule PhoenixChatWeb.ChatLiveTest do
  @moduledoc """
  Tests for the ChatLive LiveView.

  Note: These tests use the application-started services (ChatStore, SessionRegistry)
  rather than starting isolated instances.
  """
  use PhoenixChatWeb.ConnCase

  import Phoenix.LiveViewTest

  alias PhoenixChat.ChatStore

  # Clear chat store before each test
  setup do
    # Get all existing chats and delete them
    chats = ChatStore.list_chats(PhoenixChat.ChatStore)

    for chat <- chats do
      ChatStore.delete_chat(PhoenixChat.ChatStore, chat.id)
    end

    {:ok, store: PhoenixChat.ChatStore}
  end

  describe "mount/3" do
    test "renders chat interface", %{conn: conn} do
      {:ok, view, html} = live(conn, "/")

      assert html =~ "Phoenix Chat"
      assert html =~ "New Chat"
      assert has_element?(view, "[data-role=new-chat-button]")
    end

    test "shows empty state when no chats exist", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      assert html =~ "No chats yet"
    end
  end

  describe "create chat" do
    test "creates a new chat when clicking New Chat button", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      view |> element("[data-role=new-chat-button]") |> render_click()

      # Should now have one chat in the list
      assert has_element?(view, "[data-role=chat-item]")
    end
  end

  describe "select chat" do
    test "selects a chat and shows welcome message", %{conn: conn, store: store} do
      # Create a chat first
      {:ok, chat} = ChatStore.create_chat(store, "Test Chat")

      {:ok, view, _html} = live(conn, "/")

      # Click on the chat item (first one since we cleared store)
      view |> element("[data-role='chat-item']") |> render_click()

      # Should show the chat window
      assert has_element?(view, "[data-role='chat-window']")
      assert has_element?(view, "[data-role='message-input']")

      # Cleanup
      ChatStore.delete_chat(store, chat.id)
    end
  end

  describe "delete chat" do
    test "deletes a chat from the list", %{conn: conn, store: store} do
      # Create a chat first
      {:ok, chat} = ChatStore.create_chat(store, "Test Chat")

      {:ok, view, _html} = live(conn, "/")

      # Verify chat exists
      assert has_element?(view, "[data-role='chat-item']")

      # Click delete button
      view
      |> element("[data-role='delete-chat-button']")
      |> render_click()

      # Chat should be removed
      refute has_element?(view, "[data-role='chat-item']")

      # Ensure cleanup (in case test failed before delete)
      ChatStore.delete_chat(store, chat.id)
    end
  end

  describe "message display" do
    test "displays existing messages when selecting a chat", %{conn: conn, store: store} do
      # Create a chat with messages
      {:ok, chat} = ChatStore.create_chat(store, "Test Chat")
      {:ok, _} = ChatStore.add_message(store, chat.id, "user", "Hello!")
      {:ok, _} = ChatStore.add_message(store, chat.id, "assistant", "Hi there!")

      {:ok, view, _html} = live(conn, "/")

      # Select the chat
      view |> element("[data-role='chat-item']") |> render_click()

      html = render(view)
      assert html =~ "Hello!"
      assert html =~ "Hi there!"

      # Cleanup
      ChatStore.delete_chat(store, chat.id)
    end
  end
end
