#!/usr/bin/env elixir

# Example: Using different Claude models
# Demonstrates model selection and fallback features

alias ClaudeCodeSDK.{OptionBuilder, ContentExtractor}

# Enable mocking for this example (no API costs)
Application.put_env(:claude_code_sdk, :use_mock, true)
{:ok, _} = ClaudeCodeSDK.Mock.start_link()

IO.puts("🤖 Claude Model Selection Example")
IO.puts("=" |> String.duplicate(50))
IO.puts("")

# Example 1: Using Opus (most capable)
IO.puts("📊 Example 1: Using Opus Model")
IO.puts("   Best for: Complex reasoning, multi-step tasks")
IO.puts("")

opus_options = OptionBuilder.with_opus()
IO.puts("   Model: #{opus_options.model}")
IO.puts("   Fallback: #{opus_options.fallback_model}")
IO.puts("")

# Example 2: Using Sonnet (balanced)
IO.puts("📊 Example 2: Using Sonnet Model (default)")
IO.puts("   Best for: General tasks, cost-effective")
IO.puts("")

sonnet_options = OptionBuilder.with_sonnet()
IO.puts("   Model: #{sonnet_options.model}")
IO.puts("")

# Example 3: Using Haiku (fastest)
IO.puts("📊 Example 3: Using Haiku Model")
IO.puts("   Best for: Simple queries, high volume")
IO.puts("")

haiku_options = OptionBuilder.with_haiku()
IO.puts("   Model: #{haiku_options.model}")
IO.puts("")

# Example 4: Custom model with fallback
IO.puts("📊 Example 4: Custom Model Configuration")
IO.puts("")

custom_options =
  OptionBuilder.build_development_options()
  |> OptionBuilder.with_model("claude-sonnet-4-5-20250929", "sonnet")

IO.puts("   Model: #{custom_options.model}")
IO.puts("   Fallback: #{custom_options.fallback_model}")
IO.puts("")

# Example 5: Query with specific model
IO.puts("📊 Example 5: Actual Query with Model Selection")
IO.puts("")

# Set up a mock response
ClaudeCodeSDK.Mock.set_response("hello", [
  %{
    "type" => "system",
    "subtype" => "init",
    "session_id" => "example-session",
    # Would be actual model used
    "model" => "claude-opus-4-20250514"
  },
  %{
    "type" => "assistant",
    "message" => %{
      "role" => "assistant",
      "content" => "Hello! I'm Claude Opus, the most capable model."
    }
  },
  %{
    "type" => "result",
    "subtype" => "success",
    # Opus costs more
    "total_cost_usd" => 0.025,
    "num_turns" => 1
  }
])

result =
  ClaudeCodeSDK.query("Say hello", opus_options)
  |> Enum.to_list()

# Extract model info
system_msg = Enum.find(result, &(&1.type == :system))
result_msg = Enum.find(result, &(&1.type == :result))
assistant_msg = Enum.find(result, &(&1.type == :assistant))

IO.puts("   Model used: #{system_msg.data[:model] || system_msg.data["model"]}")
IO.puts("   Response: #{ContentExtractor.extract_text(assistant_msg)}")
IO.puts("   Cost: $#{result_msg.data[:total_cost_usd]}")
IO.puts("")

IO.puts("✅ Model selection example complete!")
