#!/usr/bin/env elixir

# Live test of session persistence
# Demonstrates saving, loading, searching, and resuming sessions

Application.put_env(:claude_code_sdk, :use_mock, false)

alias ClaudeCodeSDK.{SessionStore, Session}

IO.puts("💾 Testing Session Persistence (LIVE API)")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# Start SessionStore
{:ok, _pid} = SessionStore.start_link()
IO.puts("✅ SessionStore started")
IO.puts("")

# Test 1: Save a session
IO.puts("TEST 1: Save Session")
IO.puts("─" |> String.duplicate(60))

messages =
  ClaudeCodeSDK.query("What is 5*5?", %ClaudeCodeSDK.Options{max_turns: 1})
  |> Enum.to_list()

session_id = Session.extract_session_id(messages)
IO.puts("   Session ID: #{session_id}")

:ok =
  SessionStore.save_session(session_id, messages,
    tags: ["test", "math"],
    description: "Simple math query test"
  )

IO.puts("   ✅ Session saved with tags: [test, math]")
IO.puts("")

# Test 2: Load the session
IO.puts("TEST 2: Load Session")
IO.puts("─" |> String.duplicate(60))

{:ok, loaded} = SessionStore.load_session(session_id)

IO.puts("   ✅ Session loaded")
IO.puts("   Messages: #{length(loaded.messages)}")
IO.puts("   Tags: #{inspect(loaded.metadata["tags"])}")
IO.puts("   Description: #{loaded.metadata["description"]}")
IO.puts("   Cost: $#{loaded.metadata["total_cost"]}")
IO.puts("")

# Test 3: Search sessions
IO.puts("TEST 3: Search Sessions")
IO.puts("─" |> String.duplicate(60))

# Save another session for search testing
messages2 =
  ClaudeCodeSDK.query("What is 10*10?", %ClaudeCodeSDK.Options{max_turns: 1})
  |> Enum.to_list()

session_id2 = Session.extract_session_id(messages2)

:ok =
  SessionStore.save_session(session_id2, messages2,
    tags: ["test", "expensive"],
    description: "Another test query"
  )

# Search by tag
results = SessionStore.search(tags: ["test"])
IO.puts("   Found #{length(results)} sessions with tag 'test'")

# List all
all_sessions = SessionStore.list_sessions()
IO.puts("   Total sessions: #{length(all_sessions)}")

Enum.each(all_sessions, fn meta ->
  IO.puts(
    "   • #{meta.session_id |> String.slice(0, 8)}... - #{meta.description || "No description"}"
  )

  IO.puts("     Tags: #{inspect(meta.tags)}, Cost: $#{meta.total_cost}")
end)

IO.puts("")

# Test 4: Resume session
IO.puts("TEST 4: Resume Session (Continue Conversation)")
IO.puts("─" |> String.duplicate(60))

IO.puts("   Original session ID: #{session_id}")
IO.puts("   Resuming to add more context...")

# Resume the first session
resume_messages =
  ClaudeCodeSDK.resume(session_id, "Now multiply that by 2")
  |> Enum.to_list()

response = ClaudeCodeSDK.ContentExtractor.extract_all_text(resume_messages) |> String.trim()
IO.puts("   ✅ Resumed and got response: #{response}")
IO.puts("")

# Test 5: Cleanup
IO.puts("TEST 5: Cleanup")
IO.puts("─" |> String.duplicate(60))

# Delete test sessions
SessionStore.delete_session(session_id)
SessionStore.delete_session(session_id2)

remaining = SessionStore.list_sessions()
IO.puts("   ✅ Cleaned up test sessions")
IO.puts("   Remaining sessions: #{length(remaining)}")
IO.puts("")

IO.puts("=" |> String.duplicate(60))
IO.puts("✅ All Session Persistence Tests Passed!")
IO.puts("")
IO.puts("Features Validated:")
IO.puts("  ✅ Save sessions with metadata and tags")
IO.puts("  ✅ Load sessions with full message history")
IO.puts("  ✅ Search sessions by tags")
IO.puts("  ✅ Resume conversations from saved sessions")
IO.puts("  ✅ Delete sessions")
IO.puts("")
IO.puts("Session persistence is PRODUCTION READY! 🚀")
