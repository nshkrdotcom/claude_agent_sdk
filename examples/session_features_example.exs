#!/usr/bin/env elixir

# Example: Session features (fork-session, add-dir, session persistence)
# Demonstrates new v0.2.0 session management capabilities

alias ClaudeAgentSDK.{SessionStore, Session, OptionBuilder}

Application.put_env(:claude_agent_sdk, :use_mock, true)
{:ok, _} = ClaudeAgentSDK.Mock.start_link()
{:ok, _} = SessionStore.start_link()

IO.puts("📚 Session Features Example")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# Feature 1: Session Persistence
IO.puts("FEATURE 1: Session Persistence")
IO.puts("─" |> String.duplicate(60))

ClaudeAgentSDK.Mock.set_response("first", [
  %{
    "type" => "system",
    "subtype" => "init",
    "session_id" => "session-123",
    "model" => "claude-sonnet-4"
  },
  %{"type" => "assistant", "message" => %{"content" => "I'll help with that feature"}},
  %{"type" => "result", "subtype" => "success", "total_cost_usd" => 0.05}
])

messages = ClaudeAgentSDK.query("Build a feature") |> Enum.to_list()
session_id = Session.extract_session_id(messages)

IO.puts("   Original session: #{session_id}")

# Save with tags
:ok =
  SessionStore.save_session(session_id, messages,
    tags: ["feature-dev", "important"],
    description: "Building user authentication"
  )

IO.puts("   ✅ Session saved with tags: [feature-dev, important]")
IO.puts("")

# Feature 2: Session Forking
IO.puts("FEATURE 2: Session Forking (Experimentation)")
IO.puts("─" |> String.duplicate(60))

# Fork the session to try a different approach
fork_opts = %ClaudeAgentSDK.Options{
  # ← New in v0.2.0
  fork_session: true,
  max_turns: 1
}

IO.puts("   Forking session to try different approach...")
IO.puts("   Options: fork_session = true")

IO.puts(
  "   CLI args: #{inspect(ClaudeAgentSDK.Options.to_args(fork_opts) |> Enum.filter(&(&1 == "--fork-session")))}"
)

IO.puts("   ✅ Fork creates new session while preserving original context")
IO.puts("")

# Feature 3: Additional Directories
IO.puts("FEATURE 3: Additional Directories")
IO.puts("─" |> String.duplicate(60))

multi_dir_opts = %ClaudeAgentSDK.Options{
  # ← New in v0.2.0
  add_dir: ["/tmp/project1", "/tmp/project2"],
  allowed_tools: ["Read", "Write"]
}

IO.puts("   Working across multiple directories:")
IO.puts("   • /tmp/project1")
IO.puts("   • /tmp/project2")

IO.puts(
  "   CLI args: #{inspect(ClaudeAgentSDK.Options.to_args(multi_dir_opts) |> Enum.filter(&(String.starts_with?(&1, "/tmp") or &1 == "--add-dir")))}"
)

IO.puts("   ✅ Tools can access both directories")
IO.puts("")

# Feature 4: Session Search
IO.puts("FEATURE 4: Session Search & Discovery")
IO.puts("─" |> String.duplicate(60))

# Search by tags
results = SessionStore.search(tags: ["feature-dev"])
IO.puts("   Found #{length(results)} sessions with tag 'feature-dev'")

# List all sessions
all_sessions = SessionStore.list_sessions()
IO.puts("   Total sessions: #{length(all_sessions)}")

Enum.each(all_sessions, fn meta ->
  # Handle both atom and string keys for backward compatibility
  session_id = meta[:session_id] || meta["session_id"]
  tags = meta[:tags] || meta["tags"]
  total_cost = meta[:total_cost] || meta["total_cost"]
  description = meta[:description] || meta["description"]

  IO.puts("   • #{session_id |> String.slice(0, 12)}...")
  IO.puts("     Tags: #{inspect(tags)}")
  IO.puts("     Cost: $#{total_cost}")
  IO.puts("     Description: #{description}")
end)

IO.puts("")

# Feature 5: Strict MCP Config
IO.puts("FEATURE 5: Strict MCP Configuration")
IO.puts("─" |> String.duplicate(60))

mcp_opts = %ClaudeAgentSDK.Options{
  mcp_config: "mcp_config.json",
  # ← New in v0.2.0
  strict_mcp_config: true
}

IO.puts("   MCP config file: mcp_config.json")
IO.puts("   Strict mode: true (ignores other MCP configs)")

IO.puts(
  "   CLI args: #{inspect(ClaudeAgentSDK.Options.to_args(mcp_opts) |> Enum.filter(&String.contains?(&1, "mcp")))}"
)

IO.puts("   ✅ Only uses specified MCP servers")
IO.puts("")

IO.puts("=" |> String.duplicate(60))
IO.puts("✅ All Session Features Demonstrated!")
IO.puts("")
IO.puts("New in v0.2.0:")
IO.puts("  • Session Persistence (save/load/search)")
IO.puts("  • Session Forking (--fork-session)")
IO.puts("  • Multiple Directories (--add-dir)")
IO.puts("  • Strict MCP Config (--strict-mcp-config)")
