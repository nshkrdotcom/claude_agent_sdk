defmodule PhoenixChat.ChatSessionTest do
  @moduledoc """
  Tests for the ChatSession GenServer.
  """
  use ExUnit.Case, async: true

  alias PhoenixChat.ChatSession

  describe "start_link/1" do
    test "starts a session with the given chat_id" do
      {:ok, pid} = ChatSession.start_link(chat_id: "test-chat-123")

      assert Process.alive?(pid)
      assert ChatSession.get_chat_id(pid) == "test-chat-123"
    end

    test "can be registered with a name" do
      name = :"session_#{:erlang.unique_integer([:positive])}"
      {:ok, _pid} = ChatSession.start_link(chat_id: "test-chat", name: name)

      assert ChatSession.get_chat_id(name) == "test-chat"
    end
  end

  describe "subscribe/2" do
    test "adds a subscriber to the session" do
      {:ok, pid} = ChatSession.start_link(chat_id: "test-chat")
      subscriber = self()

      :ok = ChatSession.subscribe(pid, subscriber)

      assert ChatSession.has_subscriber?(pid, subscriber)
    end

    test "allows multiple subscribers" do
      {:ok, pid} = ChatSession.start_link(chat_id: "test-chat")

      pid1 = spawn(fn -> Process.sleep(5000) end)
      pid2 = spawn(fn -> Process.sleep(5000) end)

      :ok = ChatSession.subscribe(pid, pid1)
      :ok = ChatSession.subscribe(pid, pid2)

      assert ChatSession.subscriber_count(pid) == 2
    end
  end

  describe "unsubscribe/2" do
    test "removes a subscriber from the session" do
      {:ok, pid} = ChatSession.start_link(chat_id: "test-chat")
      subscriber = self()

      :ok = ChatSession.subscribe(pid, subscriber)
      :ok = ChatSession.unsubscribe(pid, subscriber)

      refute ChatSession.has_subscriber?(pid, subscriber)
    end

    test "does nothing if subscriber doesn't exist" do
      {:ok, pid} = ChatSession.start_link(chat_id: "test-chat")

      assert :ok = ChatSession.unsubscribe(pid, self())
    end
  end

  describe "broadcast/2" do
    test "sends message to all subscribers" do
      {:ok, pid} = ChatSession.start_link(chat_id: "test-chat")

      :ok = ChatSession.subscribe(pid, self())
      :ok = ChatSession.broadcast(pid, {:test_message, "hello"})

      assert_receive {:test_message, "hello"}, 1000
    end

    test "does not crash when subscribers disconnect" do
      {:ok, pid} = ChatSession.start_link(chat_id: "test-chat")

      dead_pid = spawn(fn -> :ok end)
      Process.sleep(10)

      :ok = ChatSession.subscribe(pid, dead_pid)
      # Should not crash
      :ok = ChatSession.broadcast(pid, {:test_message, "hello"})
    end
  end

  describe "state management" do
    test "tracks streaming state" do
      {:ok, pid} = ChatSession.start_link(chat_id: "test-chat")

      refute ChatSession.is_streaming?(pid)

      :ok = ChatSession.set_streaming(pid, true)
      assert ChatSession.is_streaming?(pid)

      :ok = ChatSession.set_streaming(pid, false)
      refute ChatSession.is_streaming?(pid)
    end

    test "stores session metadata" do
      {:ok, pid} = ChatSession.start_link(chat_id: "test-chat")

      :ok = ChatSession.set_metadata(pid, :sdk_session_id, "sdk-123")
      assert ChatSession.get_metadata(pid, :sdk_session_id) == "sdk-123"
    end
  end
end
