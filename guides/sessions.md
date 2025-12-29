# Sessions Guide

This guide covers session management in the Claude Agent SDK for Elixir, including how to extract session IDs, continue conversations, persist sessions to disk, and search saved sessions.

## Table of Contents

1. [Understanding Sessions in Claude](#understanding-sessions-in-claude)
2. [Session IDs and Extraction](#session-ids-and-extraction)
3. [Continuing Conversations](#continuing-conversations)
4. [Resuming by Session ID](#resuming-by-session-id)
5. [Fork Session (Creating Branches)](#fork-session-creating-branches)
6. [SessionStore GenServer](#sessionstore-genserver)
7. [Saving and Loading Sessions](#saving-and-loading-sessions)
8. [Session Metadata and Tagging](#session-metadata-and-tagging)
9. [Searching Saved Sessions](#searching-saved-sessions)
10. [Best Practices](#best-practices)

---

## Understanding Sessions in Claude

A **session** in Claude represents a conversation context that preserves message history across multiple turns. Each session has a unique identifier (UUID) that allows you to:

- Continue a conversation where you left off
- Resume a specific conversation by its ID
- Fork a session to explore alternative conversation paths
- Persist and retrieve conversation history

Sessions are managed by the Claude CLI and are separate from your application's state. The SDK provides utilities to:

- Extract session IDs from query responses
- Continue or resume sessions
- Store session data persistently with `SessionStore`

### Key Concepts

| Term | Description |
|------|-------------|
| **Session ID** | A UUID that uniquely identifies a conversation |
| **Continue** | Resume the most recent conversation |
| **Resume** | Resume a specific conversation by session ID |
| **Fork** | Create a new session branching from an existing one |

---

## Session IDs and Extraction

Every query to Claude returns messages that contain a session ID. The `ClaudeAgentSDK.Session` module provides utilities to extract this and other metadata.

### Extracting Session ID

```elixir
alias ClaudeAgentSDK.Session

# Make a query
messages = ClaudeAgentSDK.query("Write a hello world function")
|> Enum.to_list()

# Extract the session ID
session_id = Session.extract_session_id(messages)
# => "550e8400-e29b-41d4-a716-446655440000"
```

The session ID is contained in the `:system` type message that is emitted at the start of each query.

### Other Session Utilities

The `Session` module provides additional helper functions:

```elixir
alias ClaudeAgentSDK.Session

messages = ClaudeAgentSDK.query("Analyze this code") |> Enum.to_list()

# Extract session ID
session_id = Session.extract_session_id(messages)

# Calculate total cost
cost = Session.calculate_cost(messages)
# => 0.025

# Count conversation turns (assistant messages)
turns = Session.count_turns(messages)
# => 3

# Extract the model used
model = Session.extract_model(messages)
# => "claude-sonnet-4-5-20250929"

# Get a summary (first 200 chars of first assistant response)
summary = Session.get_summary(messages)
# => "I'll help you analyze this code. First, let me..."
```

---

## Continuing Conversations

Use `ClaudeAgentSDK.continue/2` to continue the **most recent** conversation. This is useful when you want to build on the last interaction without specifying a session ID.

### Basic Continue

```elixir
# First query
ClaudeAgentSDK.query("My name is Alice")
|> Enum.to_list()

# Continue the conversation (uses most recent session)
ClaudeAgentSDK.continue("What is my name?")
|> Enum.to_list()
# Claude will remember the context and respond "Alice"
```

### Continue Without Additional Prompt

You can continue without providing a new prompt to have Claude continue where it left off:

```elixir
# Start a task
ClaudeAgentSDK.query("Write a Fibonacci function in Elixir")
|> Enum.to_list()

# Continue without additional prompt
ClaudeAgentSDK.continue()
|> Enum.to_list()
```

### Continue With Options

```elixir
alias ClaudeAgentSDK.Options

options = %Options{
  max_turns: 3,
  allowed_tools: ["Read", "Edit"]
}

ClaudeAgentSDK.continue("Now add error handling", options)
|> Enum.to_list()
```

---

## Resuming by Session ID

Use `ClaudeAgentSDK.resume/3` to resume a **specific** conversation by its session ID. This is essential for building applications that manage multiple concurrent conversations.

### Basic Resume

```elixir
# Initial query - save the session ID
messages = ClaudeAgentSDK.query("Help me design a database schema")
|> Enum.to_list()

session_id = ClaudeAgentSDK.Session.extract_session_id(messages)
# => "550e8400-e29b-41d4-a716-446655440000"

# ... later, resume the same conversation
ClaudeAgentSDK.resume(session_id, "Now add indexes for common queries")
|> Enum.to_list()
```

### Resume Without Additional Prompt

```elixir
# Resume to continue where the session left off
ClaudeAgentSDK.resume(session_id)
|> Enum.to_list()
```

### Resume With Options

```elixir
alias ClaudeAgentSDK.Options

# Resume with specific options
options = %Options{
  model: "opus",
  max_turns: 5,
  permission_mode: :accept_edits
}

ClaudeAgentSDK.resume(session_id, "Add validation logic", options)
|> Enum.to_list()
```

### Managing Multiple Sessions

```elixir
defmodule ConversationManager do
  @moduledoc """
  Manages multiple concurrent Claude conversations.
  """

  alias ClaudeAgentSDK.Session

  def start_conversation(user_id, initial_prompt) do
    messages = ClaudeAgentSDK.query(initial_prompt) |> Enum.to_list()
    session_id = Session.extract_session_id(messages)

    # Store the mapping in your application state
    store_session(user_id, session_id)

    {session_id, messages}
  end

  def continue_conversation(user_id, prompt) do
    session_id = get_session(user_id)

    ClaudeAgentSDK.resume(session_id, prompt)
    |> Enum.to_list()
  end

  # Implement store_session/2 and get_session/1 using your preferred storage
  defp store_session(user_id, session_id), do: :ok
  defp get_session(user_id), do: "session-id"
end
```

---

## Fork Session (Creating Branches)

The `fork_session` option creates a **new session** that branches from an existing one. This is useful for:

- Exploring alternative conversation paths
- Creating "what if" scenarios
- Preserving original conversation while experimenting

### Using Fork Session

```elixir
alias ClaudeAgentSDK.Options

# Get the original session ID
messages = ClaudeAgentSDK.query("Design a REST API for users")
|> Enum.to_list()

original_session_id = ClaudeAgentSDK.Session.extract_session_id(messages)

# Fork the session - creates a NEW session with the same context
fork_options = %Options{
  fork_session: true,
  max_turns: 5
}

forked_messages = ClaudeAgentSDK.resume(
  original_session_id,
  "Actually, let's use GraphQL instead",
  fork_options
)
|> Enum.to_list()

# The forked messages have a NEW session ID
forked_session_id = ClaudeAgentSDK.Session.extract_session_id(forked_messages)

# original_session_id != forked_session_id
# Both sessions now exist independently
```

### Fork Session Workflow

```elixir
defmodule ExperimentalWorkflow do
  alias ClaudeAgentSDK.{Options, Session}

  def explore_alternatives(session_id, alternatives) do
    base_options = %Options{fork_session: true, max_turns: 3}

    # Create a forked session for each alternative
    Enum.map(alternatives, fn alternative_prompt ->
      messages = ClaudeAgentSDK.resume(session_id, alternative_prompt, base_options)
      |> Enum.to_list()

      %{
        prompt: alternative_prompt,
        session_id: Session.extract_session_id(messages),
        response: Session.get_summary(messages)
      }
    end)
  end
end

# Usage
alternatives = [
  "Use PostgreSQL for the database",
  "Use MongoDB for the database",
  "Use a hybrid approach with both SQL and NoSQL"
]

results = ExperimentalWorkflow.explore_alternatives(original_session_id, alternatives)
# Each alternative now has its own session that can be continued independently
```

---

## SessionStore GenServer

The `ClaudeAgentSDK.SessionStore` is a GenServer that provides persistent storage for session data. It enables:

- Saving complete session message history
- Tagging sessions for organization
- Searching sessions by various criteria
- Automatic cleanup of old sessions

### Starting SessionStore

```elixir
# Start with default storage directory (~/.claude_sdk/sessions)
{:ok, _pid} = ClaudeAgentSDK.SessionStore.start_link()

# Start with custom storage directory
{:ok, _pid} = ClaudeAgentSDK.SessionStore.start_link(
  storage_dir: "/path/to/sessions"
)

# Handle already started case (useful in scripts)
case ClaudeAgentSDK.SessionStore.start_link(storage_dir: storage_dir) do
  {:ok, pid} -> {:ok, pid}
  {:error, {:already_started, pid}} -> {:ok, pid}
end
```

### Adding to Supervision Tree

For production applications, add SessionStore to your supervision tree:

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      {ClaudeAgentSDK.SessionStore, storage_dir: session_storage_path()}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp session_storage_path do
    Application.get_env(:my_app, :session_storage_dir, "priv/sessions")
  end
end
```

### Configuration

Configure the storage directory in your config:

```elixir
# config/config.exs
config :claude_agent_sdk,
  session_storage_dir: "/var/lib/myapp/claude_sessions"
```

---

## Saving and Loading Sessions

### Saving a Session

```elixir
alias ClaudeAgentSDK.{Session, SessionStore}

# Make a query
messages = ClaudeAgentSDK.query("Build a user authentication module")
|> Enum.to_list()

# Extract the session ID
session_id = Session.extract_session_id(messages)

# Save with tags and description
:ok = SessionStore.save_session(session_id, messages,
  tags: ["auth", "security", "important"],
  description: "User authentication implementation"
)
```

### Loading a Session

```elixir
alias ClaudeAgentSDK.SessionStore

# Load a saved session
case SessionStore.load_session(session_id) do
  {:ok, session_data} ->
    # session_data contains:
    # - :session_id - The session ID
    # - :messages - List of Message structs
    # - :metadata - Session metadata

    IO.puts("Loaded #{length(session_data.messages)} messages")
    IO.puts("Tags: #{inspect(session_data.metadata["tags"])}")

  {:error, :not_found} ->
    IO.puts("Session not found")
end
```

### Complete Save/Load Workflow

```elixir
alias ClaudeAgentSDK.{Options, Session, SessionStore}

defmodule PersistentWorkflow do
  def run_and_save(prompt, tags \\ []) do
    options = %Options{max_turns: 5, model: "sonnet"}

    # Run the query
    messages = ClaudeAgentSDK.query(prompt, options) |> Enum.to_list()
    session_id = Session.extract_session_id(messages)

    # Save for later
    :ok = SessionStore.save_session(session_id, messages,
      tags: tags,
      description: String.slice(prompt, 0, 100)
    )

    session_id
  end

  def resume_saved(session_id, prompt) do
    case SessionStore.load_session(session_id) do
      {:ok, _session_data} ->
        # Session exists, resume it
        ClaudeAgentSDK.resume(session_id, prompt)
        |> Enum.to_list()

      {:error, :not_found} ->
        {:error, "Session not found: #{session_id}"}
    end
  end
end
```

---

## Session Metadata and Tagging

Session metadata provides organization and searchability for your saved sessions.

### Metadata Structure

```elixir
@type session_metadata :: %{
  session_id: String.t(),
  created_at: DateTime.t(),
  updated_at: DateTime.t(),
  message_count: non_neg_integer(),
  total_cost: float(),
  tags: [String.t()],
  description: String.t() | nil,
  model: String.t() | nil
}
```

### Tagging Strategies

```elixir
alias ClaudeAgentSDK.SessionStore

# Organize by project
SessionStore.save_session(session_id, messages,
  tags: ["project:myapp", "feature:auth"],
  description: "Authentication implementation"
)

# Organize by priority/status
SessionStore.save_session(session_id, messages,
  tags: ["priority:high", "status:in-progress"],
  description: "Critical bug fix"
)

# Organize by type
SessionStore.save_session(session_id, messages,
  tags: ["type:code-review", "team:backend"],
  description: "API endpoint review"
)
```

### Listing All Sessions

```elixir
alias ClaudeAgentSDK.SessionStore

# Get all sessions (sorted by updated_at, newest first)
sessions = SessionStore.list_sessions()

Enum.each(sessions, fn meta ->
  # Handle both atom and string keys for compatibility
  session_id = meta[:session_id] || meta["session_id"]
  tags = meta[:tags] || meta["tags"] || []
  description = meta[:description] || meta["description"]
  cost = meta[:total_cost] || meta["total_cost"] || 0

  IO.puts("#{session_id}")
  IO.puts("  Tags: #{inspect(tags)}")
  IO.puts("  Description: #{description}")
  IO.puts("  Cost: $#{cost}")
  IO.puts("")
end)
```

### Using the Main Module Helper

```elixir
# ClaudeAgentSDK.list_sessions/1 auto-starts SessionStore
case ClaudeAgentSDK.list_sessions(storage_dir: "/custom/path") do
  {:ok, sessions} ->
    IO.puts("Found #{length(sessions)} sessions")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end
```

---

## Searching Saved Sessions

The SessionStore provides flexible search capabilities.

### Search by Tags

```elixir
alias ClaudeAgentSDK.SessionStore

# Find sessions with any of the specified tags
security_sessions = SessionStore.search(tags: ["security", "auth"])

# Process results
Enum.each(security_sessions, fn session ->
  IO.puts("Found: #{session[:session_id] || session["session_id"]}")
end)
```

### Search by Date Range

```elixir
alias ClaudeAgentSDK.SessionStore

# Sessions created after a specific date
recent = SessionStore.search(after: ~D[2025-01-01])

# Sessions created before a date
older = SessionStore.search(before: ~D[2025-06-01])

# Sessions within a date range
range = SessionStore.search(
  after: ~D[2025-01-01],
  before: ~D[2025-03-31]
)
```

### Search by Cost

```elixir
alias ClaudeAgentSDK.SessionStore

# Find expensive sessions (useful for cost analysis)
expensive = SessionStore.search(min_cost: 0.50)

# Find cheap sessions
cheap = SessionStore.search(max_cost: 0.01)

# Cost range
moderate = SessionStore.search(min_cost: 0.10, max_cost: 0.50)
```

### Combined Search Criteria

```elixir
alias ClaudeAgentSDK.SessionStore

# Complex search: recent, important, and expensive
results = SessionStore.search(
  tags: ["important", "production"],
  after: ~D[2025-10-01],
  min_cost: 0.25
)

IO.puts("Found #{length(results)} matching sessions")
```

### Search Example with Full Processing

```elixir
defmodule SessionAnalyzer do
  alias ClaudeAgentSDK.SessionStore

  def analyze_costs_by_tag(tag) do
    sessions = SessionStore.search(tags: [tag])

    total_cost = Enum.reduce(sessions, 0.0, fn session, acc ->
      cost = session[:total_cost] || session["total_cost"] || 0
      acc + cost
    end)

    avg_cost = if length(sessions) > 0 do
      total_cost / length(sessions)
    else
      0.0
    end

    %{
      tag: tag,
      session_count: length(sessions),
      total_cost: Float.round(total_cost, 4),
      average_cost: Float.round(avg_cost, 4)
    }
  end

  def find_expensive_sessions(threshold \\ 0.50) do
    SessionStore.search(min_cost: threshold)
    |> Enum.map(fn session ->
      %{
        session_id: session[:session_id] || session["session_id"],
        cost: session[:total_cost] || session["total_cost"],
        description: session[:description] || session["description"]
      }
    end)
    |> Enum.sort_by(& &1.cost, :desc)
  end
end
```

---

## Best Practices

### 1. Always Extract and Store Session IDs

```elixir
# Good: Always capture the session ID for potential future use
defmodule ChatHandler do
  alias ClaudeAgentSDK.Session

  def handle_query(user_id, prompt) do
    messages = ClaudeAgentSDK.query(prompt) |> Enum.to_list()
    session_id = Session.extract_session_id(messages)

    # Store the session_id for this user
    cache_session(user_id, session_id)

    messages
  end
end
```

### 2. Use Meaningful Tags

```elixir
# Good: Use structured, searchable tags
SessionStore.save_session(session_id, messages,
  tags: [
    "project:api-v2",
    "type:implementation",
    "priority:high",
    "sprint:23"
  ],
  description: "REST API v2 user endpoints"
)

# Avoid: Generic or inconsistent tags
# tags: ["stuff", "work", "code"]
```

### 3. Handle Session Store Startup Gracefully

```elixir
defmodule SessionHelper do
  def ensure_store_started(opts \\ []) do
    case Process.whereis(ClaudeAgentSDK.SessionStore) do
      nil ->
        case ClaudeAgentSDK.SessionStore.start_link(opts) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          error -> error
        end
      pid ->
        {:ok, pid}
    end
  end
end
```

### 4. Clean Up Old Sessions Periodically

```elixir
# SessionStore automatically cleans up sessions older than 30 days
# But you can trigger manual cleanup:

# Delete sessions older than 14 days
deleted_count = ClaudeAgentSDK.SessionStore.cleanup_old_sessions(max_age_days: 14)
IO.puts("Cleaned up #{deleted_count} old sessions")
```

### 5. Use Fork Session for Experiments

```elixir
# When exploring alternatives, fork instead of modifying the original
defmodule ExperimentRunner do
  alias ClaudeAgentSDK.{Options, Session}

  def try_variation(original_session_id, variation_prompt) do
    options = %Options{
      fork_session: true,  # Creates new session
      max_turns: 3
    }

    messages = ClaudeAgentSDK.resume(original_session_id, variation_prompt, options)
    |> Enum.to_list()

    # Original session remains unchanged
    # New session can be continued independently
    Session.extract_session_id(messages)
  end
end
```

### 6. Implement Proper Error Handling

```elixir
defmodule RobustSessionManager do
  alias ClaudeAgentSDK.{Session, SessionStore}

  def safe_resume(session_id, prompt, options \\ nil) do
    # First check if session exists in our store
    case SessionStore.load_session(session_id) do
      {:ok, _data} ->
        try do
          messages = ClaudeAgentSDK.resume(session_id, prompt, options)
          |> Enum.to_list()
          {:ok, messages}
        rescue
          e -> {:error, {:resume_failed, e}}
        end

      {:error, :not_found} ->
        {:error, :session_not_found}
    end
  end

  def safe_save(session_id, messages, opts) do
    if session_id && length(messages) > 0 do
      SessionStore.save_session(session_id, messages, opts)
    else
      {:error, :invalid_session_data}
    end
  end
end
```

### 7. Use Sessions for Multi-Step Workflows

```elixir
defmodule DocumentationWorkflow do
  alias ClaudeAgentSDK.{Options, Session, SessionStore}

  def generate_docs(module_path) do
    options = %Options{
      max_turns: 10,
      allowed_tools: ["Read", "Glob", "Grep"]
    }

    # Step 1: Analyze the code
    step1 = ClaudeAgentSDK.query(
      "Analyze the code in #{module_path} and identify public functions",
      options
    ) |> Enum.to_list()

    session_id = Session.extract_session_id(step1)

    # Step 2: Generate documentation (continues same session)
    step2 = ClaudeAgentSDK.resume(
      session_id,
      "Now generate @moduledoc and @doc for each function",
      options
    ) |> Enum.to_list()

    # Step 3: Review and finalize
    step3 = ClaudeAgentSDK.resume(
      session_id,
      "Review the documentation for completeness and add examples",
      options
    ) |> Enum.to_list()

    # Save the complete workflow
    all_messages = step1 ++ step2 ++ step3
    SessionStore.save_session(session_id, all_messages,
      tags: ["documentation", "automated"],
      description: "Auto-generated docs for #{module_path}"
    )

    {:ok, session_id, all_messages}
  end
end
```

---

## Summary

The Claude Agent SDK provides comprehensive session management through:

| Feature | Module/Function | Purpose |
|---------|-----------------|---------|
| Session ID extraction | `Session.extract_session_id/1` | Get session ID from messages |
| Continue conversation | `ClaudeAgentSDK.continue/2` | Resume most recent session |
| Resume by ID | `ClaudeAgentSDK.resume/3` | Resume specific session |
| Fork session | `Options.fork_session: true` | Branch from existing session |
| Persistent storage | `SessionStore` | Save/load sessions to disk |
| Tagging | `SessionStore.save_session/3` | Organize with tags |
| Search | `SessionStore.search/1` | Find sessions by criteria |
| Cleanup | `SessionStore.cleanup_old_sessions/1` | Remove old sessions |

Sessions enable building sophisticated conversational applications with context persistence, multi-step workflows, and proper conversation management.
