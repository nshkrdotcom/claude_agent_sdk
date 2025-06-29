defmodule ClaudeCodeSDK.DebugModeTest do
  use ExUnit.Case

  alias ClaudeCodeSDK.{DebugMode, Message, Mock}

  setup do
    # Ensure mock is enabled for tests
    Application.put_env(:claude_code_sdk, :use_mock, true)
    Mock.clear_responses()

    # Set up a standard mock response
    Mock.set_response("test", [
      %{
        "type" => "system",
        "subtype" => "init",
        "session_id" => "test-123",
        "model" => "claude-test",
        "cwd" => "/test"
      },
      %{
        "type" => "assistant",
        "message" => %{"content" => "Test response"}
      },
      %{
        "type" => "result",
        "subtype" => "success",
        "total_cost_usd" => 0.001,
        "duration_ms" => 100,
        "num_turns" => 1
      }
    ])

    :ok
  end

  describe "debug_query/2" do
    @tag :skip
    test "executes query with debug output (skipped - calls AuthChecker)" do
      # Capture IO to verify debug output
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          messages = DebugMode.debug_query("test")
          assert length(messages) == 3
          assert Enum.any?(messages, &(&1.type == :assistant))
        end)

      assert String.contains?(output, "DEBUG MODE ENABLED")
      assert String.contains?(output, "Prompt: \"test\"")
      assert String.contains?(output, "Debug completed")
    end

    @tag :skip
    test "shows timing information (skipped - calls AuthChecker)" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          DebugMode.debug_query("test")
        end)

      # Should show elapsed time in brackets
      assert Regex.match?(~r/\[\d+ms\]/, output)
    end

    @tag :skip
    test "handles errors gracefully (skipped - calls AuthChecker)" do
      Mock.set_response("error", [
        %{
          "type" => "result",
          "subtype" => "error_during_execution",
          "error" => "Test error"
        }
      ])

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          messages = DebugMode.debug_query("error")
          assert length(messages) == 1
        end)

      assert String.contains?(output, "result:error_during_execution")
    end
  end

  describe "analyze_messages/1" do
    test "analyzes message statistics" do
      messages = [
        %Message{type: :system, data: %{session_id: "123"}},
        %Message{type: :assistant, data: %{message: %{"content" => "Hello world"}}},
        %Message{type: :assistant, data: %{message: %{"content" => "More content here"}}},
        %Message{
          type: :result,
          subtype: :success,
          data: %{
            total_cost_usd: 0.025,
            duration_ms: 1500,
            num_turns: 2
          }
        }
      ]

      stats = DebugMode.analyze_messages(messages)

      assert stats.total_messages == 4
      assert stats.message_types == %{system: 1, assistant: 2, result: 1}
      assert stats.total_cost_usd == 0.025
      assert stats.duration_ms == 1500
      assert stats.session_id == "123"

      assert stats.content_length ==
               String.length("Hello world") + String.length("More content here")

      assert stats.errors == []
    end

    test "tracks errors in messages" do
      messages = [
        %Message{type: :result, subtype: :error_max_turns, data: %{}}
      ]

      stats = DebugMode.analyze_messages(messages)
      assert stats.errors == [:error_max_turns]
    end

    test "handles empty message list" do
      stats = DebugMode.analyze_messages([])

      assert stats.total_messages == 0
      assert stats.message_types == %{}
      assert stats.total_cost_usd == nil
    end
  end

  describe "run_diagnostics/0" do
    @tag :skip
    test "runs diagnostic checks (skipped in test env)" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          assert DebugMode.run_diagnostics() == :ok
        end)

      assert String.contains?(output, "Running Claude Code SDK Diagnostics")
      assert String.contains?(output, "CLI Status:")
      assert String.contains?(output, "Authentication:")
      assert String.contains?(output, "Environment:")
      assert String.contains?(output, "Mix env:")
      assert String.contains?(output, "Testing basic connectivity")
    end

    @tag :skip
    test "shows mock status in diagnostics (skipped in test env)" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          DebugMode.run_diagnostics()
        end)

      assert String.contains?(output, "Mock enabled: true")
    end
  end

  describe "inspect_message/1" do
    test "formats system message" do
      message = %Message{
        type: :system,
        subtype: :init,
        data: %{session_id: "123", model: "claude-3"}
      }

      result = DebugMode.inspect_message(message)
      # Keys might be in different order
      assert String.starts_with?(result, "Message[system:init]: keys(")
      assert String.contains?(result, "model")
      assert String.contains?(result, "session_id")
    end

    test "formats assistant message with content" do
      message = %Message{
        type: :assistant,
        data: %{message: %{"content" => "Hello, this is a test message"}}
      }

      result = DebugMode.inspect_message(message)
      assert result == "Message[assistant]: \"Hello, this is a test message\" (29 chars)"
    end

    test "truncates long assistant messages" do
      long_content = String.duplicate("a", 150)

      message = %Message{
        type: :assistant,
        data: %{message: %{"content" => long_content}}
      }

      result = DebugMode.inspect_message(message)
      assert String.contains?(result, "...")
      assert String.contains?(result, "(150 chars)")
    end

    test "formats result message" do
      message = %Message{
        type: :result,
        subtype: :success,
        data: %{total_cost_usd: 0.025, duration_ms: 1234}
      }

      result = DebugMode.inspect_message(message)
      assert result == "Message[result:success]: cost=$0.025, duration=1234ms"
    end

    test "handles messages without text content" do
      message = %Message{
        type: :user,
        data: %{other_field: "value"}
      }

      result = DebugMode.inspect_message(message)
      assert String.contains?(result, "Message[user]:")
    end
  end

  describe "benchmark/3" do
    test "runs single benchmark" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          results = DebugMode.benchmark("test", nil, 1)

          assert results.runs == 1
          assert is_number(results.avg_duration_ms)
          # Can be 0 for fast mocks
          assert results.avg_duration_ms >= 0
          assert results.min_duration_ms == results.max_duration_ms
          assert is_number(results.avg_cost_usd)
        end)

      assert String.contains?(output, "Benchmarking 1 run(s)")
      assert String.contains?(output, "Benchmark Results:")
    end

    test "runs multiple benchmarks" do
      # Use a specific mock response with known cost
      Mock.set_response("test", [
        %{"type" => "assistant", "message" => %{"content" => "Response"}},
        %{
          "type" => "result",
          "subtype" => "success",
          "total_cost_usd" => 0.002,
          "duration_ms" => 50
        }
      ])

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          results = DebugMode.benchmark("test", nil, 3)

          assert results.runs == 3
          assert length(results.results) == 3
          assert results.total_cost_usd == results.avg_cost_usd * 3

          # Check individual run results
          Enum.each(results.results, fn run ->
            assert run.cost_usd == 0.002 or run.cost_usd == 0.001 or run.cost_usd == 0
            assert run.message_count > 0
          end)
        end)

      assert String.contains?(output, "Run 1/3")
      assert String.contains?(output, "Run 2/3")
      assert String.contains?(output, "Run 3/3")
    end

    test "handles benchmark with options" do
      options = %ClaudeCodeSDK.Options{max_turns: 1}

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          results = DebugMode.benchmark("test", options, 1)
          assert results.runs == 1
        end)

      assert String.contains?(output, "Benchmarking")
    end
  end

  describe "edge cases" do
    @tag :skip
    test "debug_query handles nil options (skipped - calls AuthChecker)" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          messages = DebugMode.debug_query("test", nil)
          assert is_list(messages)
        end)

      assert String.contains?(output, "Options: nil")
    end

    test "analyze_messages handles mixed content formats" do
      messages = [
        %Message{
          type: :assistant,
          data: %{message: %{"content" => [%{"text" => "Array format"}]}}
        },
        %Message{
          type: :assistant,
          data: %{message: %{"content" => "String format"}}
        }
      ]

      stats = DebugMode.analyze_messages(messages)
      assert stats.content_length > 0
    end
  end
end
