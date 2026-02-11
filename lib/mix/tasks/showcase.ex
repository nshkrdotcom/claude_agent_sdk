defmodule Mix.Tasks.Showcase do
  @moduledoc """
  Run the Claude Code SDK comprehensive showcase.

  ## Usage

      # Run with mocks (safe, no API costs)
      mix showcase

      # Run with live API calls (requires authentication)
      mix showcase --live

  ## Examples

      mix showcase              # Safe demo with mocks
      mix showcase --live       # Live demo with real API calls
  """

  use Mix.Task

  @shortdoc "Run Claude Code SDK comprehensive showcase"
  @impl Mix.Task

  def run(args) do
    # Start the application
    Application.ensure_all_started(:claude_agent_sdk)

    live_mode = "--live" in args

    if live_mode do
      IO.puts("🔴 LIVE MODE - Will make real API calls and incur costs!")
      IO.puts("Press Enter to continue or Ctrl+C to cancel...")
      IO.read(:line)
      # Disable mocking
      Application.put_env(:claude_agent_sdk, :use_mock, false)
      IO.puts("✅ Live mode enabled - using real Claude CLI")
    else
      # Enable mocking (default)
      Application.put_env(:claude_agent_sdk, :use_mock, true)
      {:ok, _} = ClaudeAgentSDK.Mock.start_link()
      IO.puts("✅ Mock mode enabled - no API calls will be made")
    end

    # Run the showcase
    run_showcase(live_mode)
  end

  defp run_showcase(live_mode) do
    mode_indicator = if live_mode, do: "🔴 LIVE", else: "🎭 MOCK"
    IO.puts("\n🎯 Claude Code SDK - Comprehensive Feature Showcase (#{mode_indicator})")
    IO.puts(String.duplicate("=", 70))

    # Setup mock responses if in mock mode
    if not live_mode do
      setup_mock_responses()
    end

    # Import all modules for showcase
    alias ClaudeAgentSDK.{AuthChecker, ContentExtractor, DebugMode, Mock, OptionBuilder}

    # Run all showcase sections
    run_option_builder_demo()
    run_auth_checker_demo()
    run_basic_sdk_demo()
    run_content_extractor_demo()
    run_debug_mode_demo()
    run_performance_demo()
    run_mock_system_demo(live_mode)

    # Final summary
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("🎉 SHOWCASE COMPLETE - All Features Demonstrated!")
    IO.puts("")
    IO.puts("💡 Key Benefits Shown:")
    IO.puts("   ✅ Zero-config smart defaults with OptionBuilder")
    IO.puts("   ✅ Automatic environment validation with AuthChecker")
    IO.puts("   ✅ Effortless content extraction from any message format")
    IO.puts("   ✅ Comprehensive debugging tools for troubleshooting")
    IO.puts("   ✅ Complete mock system for testing without API costs")
    IO.puts("   ✅ Production-ready configuration management")
    IO.puts("")
    IO.puts("🚀 Ready for production use!")
    IO.puts("📖 See README.md for detailed usage examples")
  end

  defp setup_mock_responses do
    alias ClaudeAgentSDK.Mock

    # Set up realistic mock responses
    Mock.set_response("hello", [
      %{
        "type" => "system",
        "subtype" => "init",
        "session_id" => "showcase-123",
        "model" => ClaudeAgentSDK.Model.default_model(),
        "tools" => ["Read", "Write"],
        "cwd" => "/showcase/project"
      },
      %{
        "type" => "assistant",
        "message" => %{
          "content" => [
            %{"type" => "text", "text" => "Hello! I'm Claude, ready to help you with your code."},
            %{
              "type" => "text",
              "text" => " I can analyze, review, and assist with development tasks."
            }
          ]
        },
        "session_id" => "showcase-123"
      },
      %{
        "type" => "result",
        "subtype" => "success",
        "session_id" => "showcase-123",
        "total_cost_usd" => 0.015,
        "duration_ms" => 1250,
        "num_turns" => 1,
        "is_error" => false
      }
    ])

    Mock.set_response("analyze", [
      %{
        "type" => "assistant",
        "message" => %{
          "content" =>
            "Code analysis complete: Found 3 potential improvements and 1 security consideration."
        }
      },
      %{
        "type" => "result",
        "subtype" => "success",
        "total_cost_usd" => 0.025,
        "duration_ms" => 2100
      }
    ])

    Mock.set_response("custom test", [
      %{"type" => "assistant", "message" => %{"content" => "Custom mock response!"}}
    ])
  end

  defp run_option_builder_demo do
    alias ClaudeAgentSDK.OptionBuilder
    IO.puts("\n🔧 1. OPTION BUILDER - Smart Configuration")
    IO.puts(String.duplicate("-", 50))

    # Demonstrate OptionBuilder
    dev_options = OptionBuilder.build_development_options()

    IO.puts(
      "✅ Development options: #{dev_options.max_turns} turns, verbose: #{dev_options.verbose}"
    )

    prod_options = OptionBuilder.build_production_options()

    IO.puts(
      "✅ Production options: #{prod_options.max_turns} turns, mode: #{prod_options.permission_mode}"
    )

    env_options = OptionBuilder.for_environment()
    IO.puts("✅ Auto-detected environment options for dev: #{env_options.max_turns} turns")

    custom_options = OptionBuilder.merge(:development, %{max_turns: 15, cwd: "/my/project"})
    IO.puts("✅ Custom merged options: #{custom_options.max_turns} turns in #{custom_options.cwd}")

    sandbox_options = OptionBuilder.sandboxed("/tmp/safe", ["Read"])
    IO.puts("✅ Sandboxed options: #{length(sandbox_options.allowed_tools)} allowed tools")
  end

  defp run_auth_checker_demo do
    alias ClaudeAgentSDK.AuthChecker
    IO.puts("\n🔍 2. AUTH CHECKER - Environment Validation")
    IO.puts(String.duplicate("-", 50))

    IO.puts("📊 Running authentication diagnostics...")
    diagnosis = AuthChecker.diagnose()
    IO.puts("✅ CLI installed: #{diagnosis.cli_installed}")
    IO.puts("✅ Status: #{diagnosis.status}")

    unless Enum.empty?(diagnosis.recommendations) do
      IO.puts("💡 Recommendations:")
      Enum.each(diagnosis.recommendations, fn rec -> IO.puts("   - #{rec}") end)
    end
  end

  defp run_basic_sdk_demo do
    alias ClaudeAgentSDK.OptionBuilder
    IO.puts("\n🎯 3. BASIC SDK USAGE - Core Functionality")
    IO.puts(String.duplicate("-", 50))

    IO.puts("🚀 Making query with development options...")
    dev_options = OptionBuilder.build_development_options()
    messages = ClaudeAgentSDK.query("hello", dev_options) |> Enum.to_list()

    IO.puts("✅ Received #{length(messages)} messages")

    Enum.each(messages, fn msg ->
      IO.puts("   📝 #{msg.type}: #{if msg.subtype, do: "#{msg.subtype}", else: "no subtype"}")
    end)
  end

  defp run_content_extractor_demo do
    alias ClaudeAgentSDK.{ContentExtractor, DebugMode, OptionBuilder}
    IO.puts("\n📜 4. CONTENT EXTRACTOR - Message Processing")
    IO.puts(String.duplicate("-", 50))

    dev_options = OptionBuilder.build_development_options()
    messages = ClaudeAgentSDK.query("hello", dev_options) |> Enum.to_list()
    assistant_messages = Enum.filter(messages, &(&1.type == :assistant))

    if assistant_messages != [] do
      assistant_msg = hd(assistant_messages)
      content = ContentExtractor.extract_text(assistant_msg)

      IO.puts(
        "✅ Extracted content: \"#{String.slice(content, 0, 80)}#{if String.length(content) > 80, do: "...", else: ""}\""
      )

      IO.puts("✅ Has text content: #{ContentExtractor.has_text?(assistant_msg)}")
      IO.puts("✅ Content length: #{String.length(content)} characters")
    end

    # Show statistics from all messages
    IO.puts("\n📊 Message Analysis:")
    stats = DebugMode.analyze_messages(messages)
    IO.puts("   • Total messages: #{stats.total_messages}")
    IO.puts("   • Message types: #{inspect(stats.message_types)}")
    IO.puts("   • Session ID: #{stats.session_id}")
    IO.puts("   • Total cost: $#{stats.total_cost_usd}")
    IO.puts("   • Duration: #{stats.duration_ms}ms")
    IO.puts("   • Content length: #{stats.content_length} chars")
  end

  defp run_debug_mode_demo do
    alias ClaudeAgentSDK.{DebugMode, OptionBuilder}
    IO.puts("\n🔬 5. DEBUG MODE - Troubleshooting Tools")
    IO.puts(String.duplicate("-", 50))

    dev_options = OptionBuilder.build_development_options()
    messages = ClaudeAgentSDK.query("hello", dev_options) |> Enum.to_list()
    assistant_messages = Enum.filter(messages, &(&1.type == :assistant))

    IO.puts("🔍 Message Inspection:")

    if assistant_messages != [] do
      inspection = DebugMode.inspect_message(hd(assistant_messages))
      IO.puts("   #{inspection}")
    end

    IO.puts("\n🏥 Environment Status:")
    IO.puts("   • Mock enabled: #{Application.get_env(:claude_agent_sdk, :use_mock, false)}")
    IO.puts("   • Mix environment: dev")
    IO.puts("   • SDK version: 0.1.0")
  end

  defp run_performance_demo do
    alias ClaudeAgentSDK.DebugMode
    IO.puts("\n⚡ 6. PERFORMANCE FEATURES - Benchmarking")
    IO.puts(String.duplicate("-", 50))

    IO.puts("📊 Running mini benchmark...")
    benchmark_results = DebugMode.benchmark("hello", nil, 2)
    IO.puts("✅ Benchmark complete:")
    IO.puts("   • Runs: #{benchmark_results.runs}")
    IO.puts("   • Avg duration: #{benchmark_results.avg_duration_ms}ms")
    IO.puts("   • Avg cost: $#{benchmark_results.avg_cost_usd}")
  end

  defp run_mock_system_demo(live_mode) do
    alias ClaudeAgentSDK.{ContentExtractor, Mock}
    IO.puts("\n🎮 7. MOCK SYSTEM - Testing Infrastructure")
    IO.puts(String.duplicate("-", 50))

    if live_mode do
      IO.puts("🔴 Live Mode Status:")
      IO.puts("   ✅ Using real Claude CLI")
      IO.puts("   ⚠️  API calls will incur costs")
      IO.puts("   ⚠️  Responses depend on actual API")
      IO.puts("   ✅ Full end-to-end testing")
    else
      IO.puts("🎭 Mock System Status:")
      IO.puts("   ✅ Mock server running: #{Process.whereis(Mock) != nil}")
      IO.puts("   ✅ Using mocked responses for all queries")
      IO.puts("   ✅ Zero API costs during testing")
      IO.puts("   ✅ Predictable, fast responses")

      # Show custom mock capability
      Mock.set_response("custom", [
        %{"type" => "assistant", "message" => %{"content" => "Custom mock response!"}}
      ])

      custom_result = ClaudeAgentSDK.query("custom test") |> Enum.to_list()

      custom_content =
        custom_result
        |> Enum.filter(&(&1.type == :assistant))
        |> Enum.map(&ContentExtractor.extract_text/1)
        |> hd()

      IO.puts("   ✅ Custom mock works: \"#{custom_content}\"")
    end
  end
end
