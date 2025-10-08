# Implementation Plan: Session Persistence
## Priority: SHOULD-HAVE (Medium)
## Estimated Effort: 2 days
## Target Version: 0.2.0

---

## 🎯 Objective

Implement SDK-level session management for:
- Persistent session storage across restarts
- Session metadata and tagging
- Easy resumption of multi-step workflows
- Session search and discovery

---

## 📋 Architecture

```
┌──────────────────────────────────────────────────────┐
│ ClaudeCodeSDK.SessionStore (GenServer)               │
├──────────────────────────────────────────────────────┤
│ • In-memory cache (ETS)                              │
│ • Persistent storage (file/DB)                       │
│ • Session metadata indexing                          │
│ • Automatic cleanup of old sessions                  │
└──────────────────────────────────────────────────────┘
```

---

## 📁 Implementation

### SessionStore Module

```elixir
defmodule ClaudeCodeSDK.SessionStore do
  use GenServer

  @moduledoc """
  Persistent session storage and management.

  ## Features
  - Save/load session messages
  - Tag sessions for organization
  - Search sessions by tags, date, cost
  - Automatic cleanup of old sessions
  - Export/import session data

  ## Usage

      # Save a session
      SessionStore.save_session(session_id, messages, tags: ["code-review", "security"])

      # Load session
      {:ok, messages} = SessionStore.load_session(session_id)

      # Search sessions
      sessions = SessionStore.search(tags: ["security"], after: ~D[2025-01-01])

      # Resume session
      ClaudeCodeSDK.resume(session_id, "Continue from where we left off")
  """

  defstruct [
    :cache,              # ETS table
    :storage_backend,    # :file | :db | custom
    :cleanup_timer       # Periodic cleanup
  ]

  ## Public API

  @spec save_session(String.t(), [Message.t()], keyword()) :: :ok
  def save_session(session_id, messages, opts \\ []) do
    GenServer.call(__MODULE__, {:save_session, session_id, messages, opts})
  end

  @spec load_session(String.t()) :: {:ok, [Message.t()]} | {:error, :not_found}
  def load_session(session_id) do
    GenServer.call(__MODULE__, {:load_session, session_id})
  end

  @spec search(keyword()) :: [session_metadata()]
  def search(criteria) do
    GenServer.call(__MODULE__, {:search, criteria})
  end

  @spec list_sessions() :: [session_metadata()]
  def list_sessions do
    GenServer.call(__MODULE__, :list_sessions)
  end

  @spec delete_session(String.t()) :: :ok
  def delete_session(session_id) do
    GenServer.call(__MODULE__, {:delete_session, session_id})
  end

  ## Storage Backend

  defmodule FileBackend do
    @storage_dir Path.expand("~/.claude_sdk/sessions")

    def save(session_id, data) do
      path = session_path(session_id)
      File.mkdir_p!(Path.dirname(path))

      json = Jason.encode!(%{
        session_id: session_id,
        messages: data.messages,
        metadata: data.metadata,
        created_at: data.created_at,
        updated_at: DateTime.utc_now()
      })

      File.write!(path, json)
      :ok
    end

    def load(session_id) do
      path = session_path(session_id)

      case File.read(path) do
        {:ok, json} ->
          {:ok, data} = Jason.decode(json, keys: :atoms)
          {:ok, data}

        {:error, :enoent} ->
          {:error, :not_found}
      end
    end

    def list do
      File.ls!(@storage_dir)
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Enum.map(&Path.basename(&1, ".json"))
    end

    defp session_path(session_id) do
      Path.join(@storage_dir, "#{session_id}.json")
    end
  end
end
```

### Helper Functions

```elixir
defmodule ClaudeCodeSDK.Session do
  @moduledoc """
  Session helper functions.
  """

  @spec extract_session_id([Message.t()]) :: String.t() | nil
  def extract_session_id(messages) do
    messages
    |> Enum.find(&(&1.type == :system))
    |> case do
      %{data: %{session_id: id}} -> id
      _ -> nil
    end
  end

  @spec calculate_cost([Message.t()]) :: float()
  def calculate_cost(messages) do
    messages
    |> Enum.find(&(&1.type == :result))
    |> case do
      %{data: %{total_cost_usd: cost}} -> cost
      _ -> 0.0
    end
  end

  @spec count_turns([Message.t()]) :: integer()
  def count_turns(messages) do
    messages
    |> Enum.count(&(&1.type == :assistant))
  end
end
```

---

## 📊 Session Metadata

```elixir
@type session_metadata :: %{
  session_id: String.t(),
  created_at: DateTime.t(),
  updated_at: DateTime.t(),
  message_count: integer(),
  total_cost: float(),
  tags: [String.t()],
  summary: String.t() | nil
}
```

---

## 🧪 Testing

```elixir
defmodule ClaudeCodeSDK.SessionStoreTest do
  use ExUnit.Case

  setup do
    start_supervised!(ClaudeCodeSDK.SessionStore)
    :ok
  end

  test "saves and loads session" do
    messages = [
      %Message{type: :system, data: %{session_id: "test-123"}},
      %Message{type: :assistant, data: %{message: %{"content" => "Hello"}}}
    ]

    :ok = SessionStore.save_session("test-123", messages, tags: ["test"])

    assert {:ok, loaded} = SessionStore.load_session("test-123")
    assert length(loaded.messages) == 2
  end

  test "searches sessions by tags" do
    SessionStore.save_session("s1", messages1, tags: ["review"])
    SessionStore.save_session("s2", messages2, tags: ["test"])

    results = SessionStore.search(tags: ["review"])

    assert length(results) == 1
    assert hd(results).session_id == "s1"
  end

  test "cleans up old sessions" do
    # Create old session (> 30 days)
    old_session = create_old_session()

    # Trigger cleanup
    SessionStore.cleanup_old_sessions(max_age_days: 30)

    # Verify deleted
    assert {:error, :not_found} = SessionStore.load_session(old_session.id)
  end
end
```

---

## ⏱️ Timeline

- Day 1: Core SessionStore (7h)
- Day 2: Testing + Integration (5h)

**Total**: 12 hours (1.5 days)

---

**Status**: Ready for Implementation
