#!/usr/bin/env elixir

# Week 1-2 Features Showcase
# Demonstrates AuthManager, Model Selection, Agents, and Orchestrator

alias ClaudeCodeSDK.{OptionBuilder, Orchestrator, ContentExtractor, AuthManager}

# Enable mocking for demo
Application.put_env(:claude_code_sdk, :use_mock, true)
{:ok, _} = ClaudeCodeSDK.Mock.start_link()

# Start AuthManager
{:ok, _} = AuthManager.start_link()

IO.puts("""

╔══════════════════════════════════════════════════════════╗
║  Claude Code SDK v0.1.0 - Week 1-2 Features Showcase     ║
╚══════════════════════════════════════════════════════════╝

""")

# ============================================================================
# FEATURE 1: Authentication Manager
# ============================================================================

IO.puts("🔐 FEATURE 1: Authentication Manager")
IO.puts("─" |> String.duplicate(60))
IO.puts("")

# Check authentication status
status = AuthManager.status()
IO.puts("   Authentication Status:")
IO.puts("   • Authenticated: #{status.authenticated}")
IO.puts("   • Provider: #{status.provider}")
IO.puts("   • Token present: #{status.token_present}")

if status.expires_at do
  IO.puts("   • Expires: #{status.expires_at}")
  IO.puts("   • Hours remaining: #{status.time_until_expiry_hours}")
end

IO.puts("")
IO.puts("   💡 In production, run: mix claude.setup_token")
IO.puts("   💡 Or set: export CLAUDE_CODE_OAUTH_TOKEN=<your-token>")
IO.puts("")

# ============================================================================
# FEATURE 2: Model Selection
# ============================================================================

IO.puts("🎯 FEATURE 2: Model Selection")
IO.puts("─" |> String.duplicate(60))
IO.puts("")

# Demonstrate model options
models = [
  {"Opus", OptionBuilder.with_opus(), "Most capable, higher cost"},
  {"Sonnet", OptionBuilder.with_sonnet(), "Balanced, default"},
  {"Haiku", OptionBuilder.with_haiku(), "Fastest, lowest cost"}
]

Enum.each(models, fn {name, opts, desc} ->
  IO.puts("   • #{name}: #{desc}")
  IO.puts("     Model: #{opts.model}, Fallback: #{opts.fallback_model || "none"}")
end)

IO.puts("")

# ============================================================================
# FEATURE 3: Custom Agents
# ============================================================================

IO.puts("🤖 FEATURE 3: Custom Agents")
IO.puts("─" |> String.duplicate(60))
IO.puts("")

# Define specialized agents
agents = %{
  "security_reviewer" => %{
    description: "Security-focused code reviewer",
    prompt: "You are a security expert. Look for vulnerabilities."
  },
  "performance_optimizer" => %{
    description: "Performance optimization specialist",
    prompt: "You optimize code for speed and efficiency."
  },
  "test_generator" => %{
    description: "Comprehensive test generator",
    prompt: "You create thorough ExUnit tests."
  }
}

IO.puts("   Defined #{map_size(agents)} specialized agents:")

Enum.each(agents, fn {name, agent} ->
  IO.puts("   • #{name}: #{agent.description}")
end)

IO.puts("")

# ============================================================================
# FEATURE 4: Parallel Orchestration
# ============================================================================

IO.puts("⚡ FEATURE 4: Parallel Query Orchestration")
IO.puts("─" |> String.duplicate(60))
IO.puts("")

# Setup mock responses for demo
ClaudeCodeSDK.Mock.set_response("analyze", [
  %{
    "type" => "system",
    "subtype" => "init",
    "session_id" => "session-1",
    "model" => "claude-sonnet-4"
  },
  %{
    "type" => "assistant",
    "message" => %{"role" => "assistant", "content" => "Analysis complete"}
  },
  %{
    "type" => "result",
    "subtype" => "success",
    "total_cost_usd" => 0.001,
    "duration_ms" => 500,
    "num_turns" => 1
  }
])

# Execute parallel queries
queries = [
  {"Analyze file1.ex", %ClaudeCodeSDK.Options{}},
  {"Analyze file2.ex", %ClaudeCodeSDK.Options{}},
  {"Analyze file3.ex", %ClaudeCodeSDK.Options{}}
]

start_time = System.monotonic_time(:millisecond)
{:ok, results} = Orchestrator.query_parallel(queries, max_concurrent: 3)
duration = System.monotonic_time(:millisecond) - start_time

IO.puts("   ✅ Executed #{length(results)} queries in parallel")
IO.puts("   ⏱️  Total time: #{duration}ms")
IO.puts("   💰 Total cost: $#{Enum.sum(Enum.map(results, & &1.cost))}")
IO.puts("   ✓  Success rate: #{Enum.count(results, & &1.success)}/#{length(results)}")
IO.puts("")

# ============================================================================
# FEATURE 5: Pipeline Workflows
# ============================================================================

IO.puts("🔄 FEATURE 5: Pipeline Workflows")
IO.puts("─" |> String.duplicate(60))
IO.puts("")

steps = [
  {"Step 1: Analyze code", %ClaudeCodeSDK.Options{}},
  {"Step 2: Suggest improvements", %ClaudeCodeSDK.Options{}},
  {"Step 3: Generate tests", %ClaudeCodeSDK.Options{}}
]

{:ok, pipeline_result} = Orchestrator.query_pipeline(steps, use_context: true)

IO.puts("   ✅ Completed #{length(steps)}-step pipeline")
IO.puts("   💬 Final message count: #{length(pipeline_result)}")
IO.puts("")

# ============================================================================
# FEATURE 6: Retry with Backoff
# ============================================================================

IO.puts("🔁 FEATURE 6: Automatic Retry with Exponential Backoff")
IO.puts("─" |> String.duplicate(60))
IO.puts("")

{:ok, retry_result} =
  Orchestrator.query_with_retry(
    "Test query",
    %ClaudeCodeSDK.Options{},
    max_retries: 3,
    backoff_ms: 100
  )

IO.puts("   ✅ Query succeeded (with retry logic)")
IO.puts("   💬 Messages received: #{length(retry_result)}")
IO.puts("")

# ============================================================================
# COMBINED EXAMPLE: Real-World Workflow
# ============================================================================

IO.puts("🚀 COMBINED EXAMPLE: Multi-File Code Review Workflow")
IO.puts("─" |> String.duplicate(60))
IO.puts("")

# Step 1: Parallel analysis of multiple files
files = ["lib/auth.ex", "lib/user.ex", "lib/api.ex"]

review_queries =
  Enum.map(files, fn file ->
    {
      "Review #{file} for security issues",
      OptionBuilder.build_analysis_options()
      |> OptionBuilder.with_agents(%{
        "security_reviewer" => %{
          description: "Security expert",
          prompt: "Review for OWASP Top 10 vulnerabilities"
        }
      })
      # Use most capable model
      |> OptionBuilder.with_model("opus")
    }
  end)

{:ok, review_results} = Orchestrator.query_parallel(review_queries)

IO.puts("   Step 1: Parallel Security Review")
IO.puts("   • Analyzed #{length(files)} files concurrently")
IO.puts("   • Model: Opus (most capable)")
IO.puts("   • Agent: Security Reviewer")
IO.puts("")

# Step 2: Aggregate findings
summary_prompt = """
Summarize the security findings from all files.
Prioritize by severity.
"""

{:ok, summary} =
  Orchestrator.query_with_retry(
    summary_prompt,
    # Sonnet is fine for summarization
    OptionBuilder.with_sonnet(),
    max_retries: 2
  )

IO.puts("   Step 2: Aggregate Findings")
IO.puts("   • Summarized #{length(review_results)} reviews")
IO.puts("   • Model: Sonnet (cost-effective)")
IO.puts("")

IO.puts("✅ Complete workflow executed successfully!")
IO.puts("")

# ============================================================================
# STATISTICS
# ============================================================================

IO.puts("📊 EXECUTION STATISTICS")
IO.puts("─" |> String.duplicate(60))
IO.puts("")

total_queries = length(queries) + length(steps) + 1 + length(review_queries) + 1
total_cost = Enum.sum(Enum.map(results, & &1.cost))

IO.puts("   Total queries executed: #{total_queries}")
IO.puts("   Total cost: $#{Float.round(total_cost, 4)}")
IO.puts("   Average cost per query: $#{Float.round(total_cost / total_queries, 4)}")
IO.puts("")

IO.puts("""
╔══════════════════════════════════════════════════════════╗
║  Week 1-2 Implementation Complete! 🎉                    ║
║                                                          ║
║  ✅ AuthManager - Token management                       ║
║  ✅ Model Selection - Opus/Sonnet/Haiku                  ║
║  ✅ Custom Agents - Specialized workflows                ║
║  ✅ Parallel Orchestration - 3-5x faster                 ║
║  ✅ Pipeline Workflows - Multi-step automation           ║
║  ✅ Retry Logic - Fault tolerance                        ║
╚══════════════════════════════════════════════════════════╝
""")
