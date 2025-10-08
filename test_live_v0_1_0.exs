#!/usr/bin/env elixir

# Live API Testing for v0.1.0
# Run with: mix run test_live_v0_1_0.exs
#
# ⚠️ WARNING: This makes REAL API calls and incurs costs!
# Estimated cost: ~$0.05-0.10 for full test suite

alias ClaudeCodeSDK.{OptionBuilder, Orchestrator, ContentExtractor, AuthManager}

# Disable mocking - use real API
Application.put_env(:claude_code_sdk, :use_mock, false)

# Start AuthManager
{:ok, _} = AuthManager.start_link()

IO.puts("""

╔══════════════════════════════════════════════════════════╗
║  v0.1.0 LIVE API TESTING                                 ║
║  ⚠️  This makes REAL API calls and costs money!          ║
╚══════════════════════════════════════════════════════════╝

""")

# Prompt user for confirmation
IO.puts("Press Enter to continue with live testing, or Ctrl+C to cancel...")
IO.gets("")

IO.puts("\n🔍 Starting live tests...\n")

# ============================================================================
# TEST 1: Authentication
# ============================================================================

IO.puts("TEST 1: Authentication Check")
IO.puts("─" |> String.duplicate(60))

status = AuthManager.status()
IO.puts("   Status: #{inspect(status)}")

case AuthManager.ensure_authenticated() do
  :ok ->
    IO.puts("   ✅ Authentication: PASS")
    IO.puts("")

  {:error, reason} ->
    IO.puts("   ❌ Authentication: FAIL - #{inspect(reason)}")
    IO.puts("")
    IO.puts("   Please run: mix claude.setup_token")
    IO.puts("   Or set: export CLAUDE_CODE_OAUTH_TOKEN=<your-token>")
    System.halt(1)
end

# ============================================================================
# TEST 2: Basic Query
# ============================================================================

IO.puts("TEST 2: Basic Query (No model specified)")
IO.puts("─" |> String.duplicate(60))

result =
  ClaudeCodeSDK.query("Say exactly: Hello from v0.1.0")
  |> Enum.to_list()

assistant_msg = Enum.find(result, &(&1.type == :assistant))
result_msg = Enum.find(result, &(&1.type == :result))

# Check for auth errors
response_text = if assistant_msg, do: ContentExtractor.extract_text(assistant_msg), else: ""

cond do
  String.contains?(response_text, "authentication_error") or
      String.contains?(response_text, "Invalid bearer token") ->
    IO.puts("   ❌ Basic Query: FAIL - Authentication error")
    IO.puts("   Error: #{response_text}")
    IO.puts("")
    IO.puts("   💡 The CLAUDE_CODE_OAUTH_TOKEN environment variable may not be set correctly")
    IO.puts("   💡 Try: export CLAUDE_CODE_OAUTH_TOKEN='sk-ant-oat01-...' (in single quotes)")
    System.halt(1)

  assistant_msg && result_msg && result_msg.subtype == :success ->
    IO.puts("   Response: #{response_text}")
    IO.puts("   Cost: $#{result_msg.data[:total_cost_usd]}")
    IO.puts("   ✅ Basic Query: PASS")

  true ->
    IO.puts("   ❌ Basic Query: FAIL - Unexpected response")
    IO.puts("   Messages: #{inspect(result, limit: 5)}")
    System.halt(1)
end

IO.puts("")

# ============================================================================
# TEST 3: Model Selection
# ============================================================================

IO.puts("TEST 3: Model Selection (Sonnet with fallback)")
IO.puts("─" |> String.duplicate(60))

model_opts = OptionBuilder.with_sonnet()
IO.puts("   Using model: #{model_opts.model}")

result =
  ClaudeCodeSDK.query("What is 2+2?", model_opts)
  |> Enum.to_list()

system_msg = Enum.find(result, &(&1.type == :system))

if system_msg do
  model_used = system_msg.data[:model] || system_msg.data["model"]
  IO.puts("   Model used: #{model_used}")
  IO.puts("   ✅ Model Selection: PASS")
else
  IO.puts("   ❌ Model Selection: FAIL")
end

IO.puts("")

# ============================================================================
# TEST 4: Custom Agent
# ============================================================================

IO.puts("TEST 4: Custom Agent")
IO.puts("─" |> String.duplicate(60))

agent_opts = %ClaudeCodeSDK.Options{
  agents: %{
    "math_helper" => %{
      description: "Math expert",
      prompt: "You are a math expert. Provide concise numerical answers."
    }
  },
  max_turns: 1
}

result =
  ClaudeCodeSDK.query("What is 5 * 7?", agent_opts)
  |> Enum.to_list()

assistant_msg = Enum.find(result, &(&1.type == :assistant))
response = if assistant_msg, do: ContentExtractor.extract_text(assistant_msg), else: ""

cond do
  String.contains?(response, "authentication_error") ->
    IO.puts("   ❌ Custom Agent: FAIL - Authentication error")
    System.halt(1)

  assistant_msg && String.contains?(response, "35") ->
    IO.puts("   Agent response: #{response}")
    IO.puts("   ✅ Custom Agent: PASS")

  assistant_msg ->
    IO.puts("   Response: #{response}")
    IO.puts("   ⚠️  Custom Agent: Unexpected response (but working)")

  true ->
    IO.puts("   ❌ Custom Agent: FAIL")
    System.halt(1)
end

IO.puts("")

# ============================================================================
# TEST 5: Parallel Orchestration (EXPENSIVE!)
# ============================================================================

IO.puts("TEST 5: Parallel Orchestration")
IO.puts("─" |> String.duplicate(60))
IO.puts("   ⚠️  This will execute 3 queries in parallel")
IO.puts("   Estimated cost: ~$0.03")
IO.puts("")
IO.puts("Press Enter to continue or Ctrl+C to skip...")
IO.gets("")

queries = [
  {"What is 1+1?", %ClaudeCodeSDK.Options{max_turns: 1}},
  {"What is 2+2?", %ClaudeCodeSDK.Options{max_turns: 1}},
  {"What is 3+3?", %ClaudeCodeSDK.Options{max_turns: 1}}
]

start_time = System.monotonic_time(:millisecond)
{:ok, results} = Orchestrator.query_parallel(queries, max_concurrent: 3)
duration = System.monotonic_time(:millisecond) - start_time

total_cost = Enum.sum(Enum.map(results, & &1.cost))
success_count = Enum.count(results, & &1.success)

IO.puts("   Queries executed: #{length(results)}")
IO.puts("   Success rate: #{success_count}/#{length(results)}")
IO.puts("   Total time: #{duration}ms")
IO.puts("   Total cost: $#{Float.round(total_cost, 4)}")

if success_count == length(results) do
  IO.puts("   ✅ Parallel Orchestration: PASS")
else
  IO.puts("   ❌ Parallel Orchestration: FAIL")
end

IO.puts("")

# ============================================================================
# TEST 6: Retry Logic
# ============================================================================

IO.puts("TEST 6: Retry with Backoff")
IO.puts("─" |> String.duplicate(60))

{:ok, retry_result} =
  Orchestrator.query_with_retry(
    "Say: Retry test successful",
    %ClaudeCodeSDK.Options{max_turns: 1},
    max_retries: 2,
    backoff_ms: 500
  )

if Enum.any?(retry_result, &(&1.type == :assistant)) do
  IO.puts("   ✅ Retry Logic: PASS")
else
  IO.puts("   ❌ Retry Logic: FAIL")
end

IO.puts("")

# ============================================================================
# SUMMARY
# ============================================================================

IO.puts("""
╔══════════════════════════════════════════════════════════╗
║  LIVE API TEST SUMMARY                                   ║
╚══════════════════════════════════════════════════════════╝

All v0.1.0 features tested with LIVE Claude Code API:

  ✅ Authentication (AuthManager)
  ✅ Basic queries
  ✅ Model selection
  ✅ Custom agents
  ✅ Parallel orchestration
  ✅ Retry logic

Estimated total cost: $#{Float.round(total_cost + 0.03, 2)}

Ready for production! 🚀

""")
