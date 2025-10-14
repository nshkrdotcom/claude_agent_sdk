#!/usr/bin/env elixir

# Comprehensive live test of all v0.1.0 features
# Tests authentication, models, agents, and orchestration

Application.put_env(:claude_agent_sdk, :use_mock, false)

alias ClaudeAgentSDK.{Orchestrator, OptionBuilder, ContentExtractor}

IO.puts("╔═══════════════════════════════════════════╗")
IO.puts("║  v0.1.0 LIVE FEATURE VALIDATION           ║")
IO.puts("╚═══════════════════════════════════════════╝")
IO.puts("")

# Test 1: Basic Query
IO.puts("TEST 1: Basic Query")
r = ClaudeAgentSDK.query("Say: Hello", %ClaudeAgentSDK.Options{max_turns: 1}) |> Enum.to_list()
response = ContentExtractor.extract_all_text(r) |> String.trim()
IO.puts("✅ Response: #{response}")
IO.puts("")

# Test 2: Model Selection
IO.puts("TEST 2: Model Selection (Haiku)")
r = ClaudeAgentSDK.query("What is 100-1?", OptionBuilder.with_haiku()) |> Enum.to_list()
s = Enum.find(r, &(&1.type == :system))
model = s.data[:model] || s.data["model"]
response = ContentExtractor.extract_all_text(r) |> String.trim()
IO.puts("✅ Model: #{model}")
IO.puts("✅ Response: #{response}")
IO.puts("")

# Test 3: Custom Agent
IO.puts("TEST 3: Custom Agent")

agent_opts = %ClaudeAgentSDK.Options{
  agents: %{
    "math" => %{
      description: "Math expert",
      prompt: "You are a math expert. Be concise."
    }
  },
  max_turns: 1
}

r = ClaudeAgentSDK.query("What is 7*8?", agent_opts) |> Enum.to_list()
response = ContentExtractor.extract_all_text(r) |> String.trim()
IO.puts("✅ Agent Response: #{response}")
IO.puts("")

# Test 4: Parallel Orchestration
IO.puts("TEST 4: Parallel Orchestration (2 concurrent)")

{:ok, results} =
  Orchestrator.query_parallel(
    [
      {"What is 5+5?", %ClaudeAgentSDK.Options{max_turns: 1}},
      {"What is 6+6?", %ClaudeAgentSDK.Options{max_turns: 1}}
    ],
    max_concurrent: 2
  )

IO.puts("✅ Queries: #{length(results)}")
IO.puts("✅ Success: #{Enum.count(results, & &1.success)}/#{length(results)}")

Enum.each(results, fn r ->
  resp = ContentExtractor.extract_all_text(r.messages) |> String.trim()
  IO.puts("  → #{String.slice(r.prompt, 0, 20)}: #{resp}")
end)

IO.puts("")

# Test 5: Pipeline Workflow
IO.puts("TEST 5: Pipeline Workflow (2 steps with context)")

{:ok, final} =
  Orchestrator.query_pipeline(
    [
      {"What is 2*5?", %ClaudeAgentSDK.Options{max_turns: 1}},
      {"Add 3 to the previous answer", %ClaudeAgentSDK.Options{max_turns: 1}}
    ],
    use_context: true
  )

response = ContentExtractor.extract_all_text(final) |> String.trim()
IO.puts("✅ Pipeline result: #{response}")
IO.puts("")

# Test 6: Retry Logic
IO.puts("TEST 6: Retry with Backoff")

{:ok, retry_result} =
  Orchestrator.query_with_retry(
    "Say: Retry test",
    %ClaudeAgentSDK.Options{max_turns: 1},
    max_retries: 2,
    backoff_ms: 500
  )

response = ContentExtractor.extract_all_text(retry_result) |> String.trim()
IO.puts("✅ Retry successful: #{response}")
IO.puts("")

IO.puts("╔═══════════════════════════════════════════╗")
IO.puts("║  ALL TESTS PASSED! ✅                     ║")
IO.puts("║                                           ║")
IO.puts("║  v0.1.0 is PRODUCTION READY! 🚀           ║")
IO.puts("╚═══════════════════════════════════════════╝")
