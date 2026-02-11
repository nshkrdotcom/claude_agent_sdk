defmodule ClaudeAgentSDK.DebugMode do
  @moduledoc """
  Comprehensive debugging and diagnostics for Claude Code SDK.

  This module provides tools for troubleshooting queries, analyzing performance,
  and diagnosing environment issues. Essential for development, testing, and
  production monitoring of Claude Code SDK usage.

  ## Features

  - **Query Debugging**: Detailed execution logging with timing
  - **Environment Diagnostics**: CLI installation and auth status checks
  - **Performance Benchmarking**: Multi-run performance analysis
  - **Message Analysis**: Content statistics and error detection
  - **Connectivity Testing**: Basic health checks and validation

  ## Basic Usage

      # Debug a specific query
      messages = ClaudeAgentSDK.DebugMode.debug_query("Hello, Claude!")
      
      # Run full environment diagnostics
      ClaudeAgentSDK.DebugMode.run_diagnostics()
      
      # Benchmark query performance
      results = ClaudeAgentSDK.DebugMode.benchmark("Analyze this code", nil, 3)
      
      # Analyze message statistics
      stats = ClaudeAgentSDK.DebugMode.analyze_messages(messages)

  ## Debug Output Example

      🐛 DEBUG MODE ENABLED
         Prompt: "Hello, Claude!"
         Options: %ClaudeAgentSDK.Options{verbose: true, max_turns: 1}
         ✅ Auth: Authenticated as user@example.com
         [0ms] system:init: session_id=abc123, model=opus
         [1250ms] assistant: "Hello! How can I help you today?" (35 chars)
         [1680ms] result:success: cost=$0.003, turns=1
      🏁 Debug completed in 1680ms with 3 messages

  ## Environment Diagnostics

      🔍 Running Claude Code SDK Diagnostics...
      ✅ CLI Status: Installed at /usr/local/bin/claude
         Version: 1.2.3
      ✅ Authentication: Authenticated as user@example.com
      📋 Environment:
         Build env: dev
         Mock enabled: false
         Elixir: 1.15.0
         OTP: 26
      🔌 Testing basic connectivity...
         ✅ Basic connectivity OK
      ✅ All systems operational!

  """

  alias ClaudeAgentSDK.{AuthChecker, BuildEnv, ContentExtractor, Message, Options, Runtime}
  alias ClaudeAgentSDK.Config.Buffers
  alias ClaudeAgentSDK.Config.CLI, as: CLIConfig

  @doc """
  Executes a query in debug mode with detailed logging and timing.

  Provides comprehensive debug output including authentication status,
  timing information for each message, and final statistics. Automatically
  enables verbose mode and catches/reports any errors.

  ## Parameters

  - `prompt` - The query prompt to debug
  - `options` - Optional `ClaudeAgentSDK.Options` (verbose will be auto-enabled)

  ## Returns

  - List of messages with complete debug trace

  ## Examples

      # Basic debug query
      messages = ClaudeAgentSDK.DebugMode.debug_query("Hello")
      
      # Debug with custom options
      options = %ClaudeAgentSDK.Options{max_turns: 3}
      messages = ClaudeAgentSDK.DebugMode.debug_query("Complex task", options)

  ## Output Format

      🐛 DEBUG MODE ENABLED
         Prompt: "Hello, Claude!"
         Options: %ClaudeAgentSDK.Options{verbose: true, max_turns: 1}
         ✅ Auth: Authenticated as user@example.com
         [0ms] system:init: session_id=abc123, model=opus
         [1250ms] assistant: "Hello! How can I help you today?" (35 chars)
         [1680ms] result:success: cost=$0.003, turns=1
      🏁 Debug completed in 1680ms with 3 messages

  """
  @spec debug_query(String.t(), Options.t() | nil) :: [Message.t()]
  def debug_query(prompt, options \\ nil) do
    IO.puts("\n🐛 DEBUG MODE ENABLED")
    IO.puts("   Prompt: #{inspect(prompt, limit: 200)}")

    # Build debug options
    debug_options = build_debug_options(options)
    IO.puts("   Options: #{format_options_summary(debug_options)}")

    # Pre-flight checks
    auth_status = check_authentication()
    environment_info = check_environment()

    IO.puts("   #{auth_status}")
    IO.puts("   Environment: #{environment_info}")
    IO.puts("   Starting query execution...")

    # Execute with timing and error handling
    start_time = System.monotonic_time(:millisecond)

    try do
      result = execute_debug_query(prompt, debug_options, start_time)

      total_time = System.monotonic_time(:millisecond) - start_time
      IO.puts("🏁 Debug completed in #{total_time}ms with #{length(result)} messages")

      print_final_summary(result, total_time)

      result
    rescue
      e ->
        elapsed = System.monotonic_time(:millisecond) - start_time
        IO.puts("\n❌ QUERY FAILED after #{elapsed}ms")
        IO.puts("   Error: #{Exception.message(e)}")
        IO.puts("   Type: #{e.__struct__}")
        print_error_suggestions(e)
        reraise e, __STACKTRACE__
    end
  end

  @doc """
  Executes a query with performance profiling.

  Similar to `debug_query/2` but focuses on performance metrics,
  memory usage, and execution timing rather than detailed content logging.

  ## Parameters

  - `prompt` - The query prompt
  - `options` - Optional `ClaudeAgentSDK.Options`

  ## Returns

  - `{messages, profile}` where profile contains performance data

  ## Examples

      {messages, profile} = ClaudeAgentSDK.DebugMode.profile_query("Complex task")
      IO.puts("Peak memory: \#{profile.peak_memory_mb}MB")
      IO.puts("Execution time: \#{profile.execution_time_ms}ms")

  """
  @spec profile_query(String.t(), Options.t() | nil) :: {[Message.t()], map()}
  def profile_query(prompt, options \\ nil) do
    IO.puts("📊 PERFORMANCE PROFILING ENABLED")

    # Start profiling
    start_time = System.monotonic_time(:millisecond)
    start_memory = :erlang.memory(:total)

    # Execute query
    messages = ClaudeAgentSDK.query(prompt, options) |> Enum.to_list()

    # Calculate metrics
    end_time = System.monotonic_time(:millisecond)
    end_memory = :erlang.memory(:total)

    profile = %{
      execution_time_ms: end_time - start_time,
      memory_delta_bytes: end_memory - start_memory,
      peak_memory_mb: Float.round(:erlang.memory(:total) / 1_048_576, 2),
      message_count: length(messages),
      process_count: :erlang.system_info(:process_count)
    }

    IO.puts("📊 Profile Results:")
    IO.puts("   Execution time: #{profile.execution_time_ms}ms")
    IO.puts("   Memory delta: #{Float.round(profile.memory_delta_bytes / 1024, 1)}KB")
    IO.puts("   Peak memory: #{profile.peak_memory_mb}MB")
    IO.puts("   Messages: #{profile.message_count}")

    {messages, profile}
  end

  @doc """
  Analyzes a stream of messages and provides comprehensive statistics.

  Examines message patterns, content metrics, performance data, and error
  conditions to provide insights into query execution and results.

  ## Parameters

  - `messages` - List or stream of `ClaudeAgentSDK.Message` structs

  ## Returns

  - Map with detailed analysis results

  ## Examples

      messages = ClaudeAgentSDK.query("Analyze this code")
      stats = ClaudeAgentSDK.DebugMode.analyze_messages(messages)
      
      # %{
      #   total_messages: 5,
      #   message_types: %{assistant: 2, system: 1, result: 1, user: 1},
      #   total_cost_usd: 0.025,
      #   duration_ms: 3420,
      #   content_length: 1523,
      #   tools_used: ["Read", "Grep"],
      #   session_id: "abc123",
      #   success: true,
      #   errors: []
      # }

  ## Analysis Fields

  - `total_messages` - Count of all messages
  - `message_types` - Breakdown by message type
  - `total_cost_usd` - Total API cost (if available)
  - `duration_ms` - Total execution time
  - `content_length` - Total character count of text content
  - `tools_used` - List of tools invoked during execution
  - `session_id` - Session identifier
  - `success` - Whether query completed successfully
  - `errors` - List of any error conditions encountered

  """
  @spec analyze_messages(Enumerable.t()) :: map()
  def analyze_messages(messages) do
    messages
    |> Enum.reduce(
      %{
        total_messages: 0,
        message_types: %{},
        total_cost_usd: nil,
        duration_ms: nil,
        session_id: nil,
        content_length: 0,
        tools_used: MapSet.new(),
        errors: [],
        success: false,
        turns_used: nil,
        api_duration_ms: nil,
        model_used: nil
      },
      &analyze_message/2
    )
    |> finalize_analysis()
  end

  @doc """
  Runs a diagnostic check of the SDK environment.

  Checks:
  - CLI installation
  - Authentication status
  - Basic connectivity
  - Environment configuration

  ## Examples

      iex> ClaudeAgentSDK.DebugMode.run_diagnostics()
      🔍 Running Claude Code SDK Diagnostics...
      ✅ CLI Status: Installed at /usr/local/bin/claude
      ...
  """
  @spec run_diagnostics() :: :ok
  def run_diagnostics do
    IO.puts("🔍 Running Claude Code SDK Diagnostics...")
    IO.puts("")

    # Check CLI
    diagnosis = AuthChecker.diagnose()

    if diagnosis.cli_installed do
      IO.puts("✅ CLI Status: Installed at #{diagnosis.cli_path}")
      IO.puts("   Version: #{diagnosis.cli_version}")
    else
      IO.puts("❌ CLI Status: Not installed")
      IO.puts("   Error: #{diagnosis.cli_error}")
    end

    IO.puts("")

    # Check authentication
    if diagnosis.authenticated do
      IO.puts("✅ Authentication: #{diagnosis.auth_info}")
    else
      IO.puts("❌ Authentication: Not authenticated")
      if diagnosis[:auth_error], do: IO.puts("   Error: #{diagnosis.auth_error}")
    end

    IO.puts("")

    # Check environment
    IO.puts("📋 Environment:")
    IO.puts("   Build env: #{BuildEnv.current()}")
    IO.puts("   Mock enabled: #{Runtime.use_mock?()}")
    IO.puts("   Elixir: #{System.version()}")
    IO.puts("   OTP: #{System.otp_release()}")

    IO.puts("")

    # Test basic connectivity
    IO.puts("🔌 Testing basic connectivity...")
    test_basic_connectivity()

    IO.puts("")

    # Recommendations
    if Enum.empty?(diagnosis.recommendations) do
      IO.puts("✅ All systems operational!")
    else
      IO.puts("💡 Recommendations:")

      Enum.each(diagnosis.recommendations, fn rec ->
        IO.puts("   - #{rec}")
      end)
    end

    :ok
  end

  @doc """
  Formats a message for detailed inspection.

  ## Parameters

    - `message` - A ClaudeAgentSDK.Message struct

  ## Returns

    - Formatted string representation

  ## Examples

      iex> ClaudeAgentSDK.DebugMode.inspect_message(message)
      "Message[assistant]: \"Hello, world!\" (15 chars)"
  """
  @spec inspect_message(ClaudeAgentSDK.Message.t()) :: String.t()
  def inspect_message(message) do
    content = ContentExtractor.extract_text(message)

    content_preview =
      if content do
        truncated = String.slice(content, 0, Buffers.error_preview_length())

        if String.length(content) > Buffers.error_preview_length(),
          do: truncated <> "...",
          else: truncated
      else
        "no text content"
      end

    case message.type do
      :system ->
        data_keys = Map.keys(message.data) |> Enum.join(", ")
        "Message[#{message.type}:#{message.subtype}]: keys(#{data_keys})"

      :assistant ->
        char_count = if content, do: String.length(content), else: 0
        "Message[assistant]: \"#{content_preview}\" (#{char_count} chars)"

      :result ->
        cost = message.data[:total_cost_usd] || "unknown"

        "Message[result:#{message.subtype}]: cost=$#{cost}, duration=#{message.data[:duration_ms]}ms"

      _ ->
        "Message[#{message.type}]: #{inspect(message.data, limit: 50)}"
    end
  end

  @doc """
  Benchmarks a query and returns performance metrics.

  ## Parameters

    - `prompt` - The query prompt
    - `options` - Optional ClaudeAgentSDK.Options
    - `runs` - Number of times to run the query (default: 1)

  ## Returns

    - Map with benchmark results

  ## Examples

      iex> results = ClaudeAgentSDK.DebugMode.benchmark("Hello", nil, 3)
      %{
        runs: 3,
        avg_duration_ms: 1523,
        min_duration_ms: 1420,
        max_duration_ms: 1650,
        avg_cost_usd: 0.015
      }
  """
  @spec benchmark(String.t(), Options.t() | nil, pos_integer()) :: map()
  def benchmark(prompt, options \\ nil, runs \\ 1) do
    IO.puts("📊 Benchmarking #{runs} run(s)...")

    results =
      1..runs
      |> Enum.map(fn run_num ->
        IO.puts("   Run #{run_num}/#{runs}...")

        start_time = System.monotonic_time(:millisecond)

        messages =
          ClaudeAgentSDK.query(prompt, options)
          |> Enum.to_list()

        duration = System.monotonic_time(:millisecond) - start_time

        stats = analyze_messages(messages)

        %{
          run: run_num,
          duration_ms: duration,
          cost_usd: stats.total_cost_usd || 0,
          message_count: stats.total_messages
        }
      end)

    # Calculate aggregate stats
    durations = Enum.map(results, & &1.duration_ms)
    costs = Enum.map(results, & &1.cost_usd)

    benchmark_results = %{
      runs: runs,
      avg_duration_ms: avg(durations),
      min_duration_ms: Enum.min(durations),
      max_duration_ms: Enum.max(durations),
      avg_cost_usd: avg(costs),
      total_cost_usd: Enum.sum(costs),
      results: results
    }

    IO.puts("")
    IO.puts("📊 Benchmark Results:")
    IO.puts("   Avg Duration: #{benchmark_results.avg_duration_ms}ms")

    IO.puts(
      "   Min/Max: #{benchmark_results.min_duration_ms}ms / #{benchmark_results.max_duration_ms}ms"
    )

    IO.puts("   Avg Cost: $#{benchmark_results.avg_cost_usd}")
    IO.puts("   Total Cost: $#{benchmark_results.total_cost_usd}")

    benchmark_results
  end

  # Private helper functions

  defp build_debug_options(nil) do
    %Options{verbose: true, output_format: :stream_json}
  end

  defp build_debug_options(options) do
    %{options | verbose: true, output_format: :stream_json}
  end

  defp format_options_summary(%Options{} = options) do
    parts = [
      "max_turns: #{options.max_turns || "default"}",
      "tools: #{format_tools_summary(options)}",
      "mode: #{options.permission_mode || "default"}"
    ]

    Enum.join(parts, ", ")
  end

  defp format_tools_summary(%Options{allowed_tools: allowed, disallowed_tools: disallowed}) do
    cond do
      allowed != nil and allowed != [] -> "allowed[#{length(allowed)}]"
      disallowed != nil and disallowed != [] -> "disallowed[#{length(disallowed)}]"
      true -> "default"
    end
  end

  defp check_authentication do
    case AuthChecker.authenticated?() do
      true -> "✅ Auth: Ready"
      false -> "❌ Auth: Not authenticated"
    end
  end

  defp check_environment do
    mock_status =
      if Runtime.use_mock?(), do: "mock", else: "live"

    "#{BuildEnv.current()}/#{mock_status}"
  end

  defp execute_debug_query(prompt, options, start_time) do
    ClaudeAgentSDK.query(prompt, options)
    |> Stream.map(fn msg ->
      elapsed = System.monotonic_time(:millisecond) - start_time
      debug_info = format_debug_message(msg, elapsed)
      IO.puts(debug_info)
      msg
    end)
    |> Enum.to_list()
  end

  defp print_final_summary(messages, total_time) do
    stats = analyze_messages(messages)

    IO.puts("\n📊 Summary:")
    IO.puts("   Total time: #{total_time}ms")
    IO.puts("   API time: #{stats.api_duration_ms || "unknown"}ms")

    if stats.total_cost_usd do
      IO.puts("   Cost: $#{stats.total_cost_usd}")
    end

    if stats.content_length > 0 do
      IO.puts("   Content: #{stats.content_length} chars")
    end

    if not Enum.empty?(stats.tools_used) do
      tools_list = Enum.join(stats.tools_used, ", ")
      IO.puts("   Tools: #{tools_list}")
    end

    if not Enum.empty?(stats.errors) do
      error_list = Enum.join(stats.errors, ", ")
      IO.puts("   ⚠️  Errors: #{error_list}")
    end
  end

  defp print_error_suggestions(exception) do
    suggestions =
      case exception do
        %ErlangError{original: :enoent} ->
          ["Ensure Claude CLI is installed: #{CLIConfig.install_command()}"]

        %ErlangError{original: :timeout} ->
          ["Query timed out - try reducing complexity or increasing timeout"]

        error when is_struct(error) and error.__struct__ == Jason.DecodeError ->
          ["JSON parsing error - possible CLI output format issue"]

        _ ->
          ["Run ClaudeAgentSDK.DebugMode.run_diagnostics() for environment check"]
      end

    IO.puts("\n💡 Suggestions:")
    Enum.each(suggestions, &IO.puts("   - #{&1}"))
  end

  defp format_debug_message(msg, elapsed) do
    data_preview = format_message_data(msg)
    type_str = format_message_type(msg)
    "   [#{elapsed}ms] #{type_str}: #{data_preview}"
  end

  defp format_message_data(msg) do
    case msg.type do
      :assistant -> format_assistant_data(msg)
      :system -> format_system_data(msg)
      :result -> format_result_data(msg)
      _ -> inspect(msg.data, limit: 50)
    end
  end

  defp format_message_type(msg) do
    if msg.subtype, do: "#{msg.type}:#{msg.subtype}", else: "#{msg.type}"
  end

  defp format_assistant_data(msg) do
    content = ContentExtractor.extract_text(msg)
    format_assistant_preview(content)
  end

  defp format_system_data(msg) do
    session = msg.data[:session_id] || "unknown"
    model = msg.data[:model] || "unknown"
    "session_id=#{String.slice(session, 0, 8)}..., model=#{model}"
  end

  defp format_result_data(msg) do
    cost = msg.data[:total_cost_usd] || "unknown"
    turns = msg.data[:num_turns] || "unknown"
    "cost=$#{cost}, turns=#{turns}"
  end

  defp analyze_message(message, acc) do
    acc
    |> Map.update(:total_messages, 1, &(&1 + 1))
    |> Map.update(:message_types, %{}, fn types ->
      Map.update(types, message.type, 1, &(&1 + 1))
    end)
    |> update_cost_duration(message)
    |> update_session_id(message)
    |> update_model_info(message)
    |> update_content_length(message)
    |> extract_tools_used(message)
    |> check_for_errors(message)
  end

  defp update_cost_duration(acc, %{type: :result, data: data}) do
    acc
    |> Map.put(:total_cost_usd, data[:total_cost_usd])
    |> Map.put(:duration_ms, data[:duration_ms])
    |> Map.put(:api_duration_ms, data[:duration_api_ms])
    |> Map.put(:turns_used, data[:num_turns])
    |> Map.put(:success, data[:subtype] == :success || data["subtype"] == "success")
  end

  defp update_cost_duration(acc, _), do: acc

  defp update_session_id(acc, %{type: :system, data: data}) do
    session_id = data[:session_id] || data["session_id"]
    if session_id, do: Map.put(acc, :session_id, session_id), else: acc
  end

  defp update_session_id(acc, _), do: acc

  defp update_model_info(acc, %{type: :system, data: data}) do
    model = data[:model] || data["model"]
    if model, do: Map.put(acc, :model_used, model), else: acc
  end

  defp update_model_info(acc, _), do: acc

  defp update_content_length(acc, message) do
    case ContentExtractor.extract_text(message) do
      nil -> acc
      text -> Map.update(acc, :content_length, String.length(text), &(&1 + String.length(text)))
    end
  end

  defp extract_tools_used(acc, %{type: :assistant, data: %{message: %{"content" => content}}})
       when is_list(content) do
    tools =
      content
      |> Enum.filter(fn item ->
        is_map(item) && (item["type"] == "tool_use" || Map.has_key?(item, "name"))
      end)
      |> Enum.map(& &1["name"])
      |> Enum.reject(&is_nil/1)

    Map.update(acc, :tools_used, MapSet.new(tools), &MapSet.union(&1, MapSet.new(tools)))
  end

  defp extract_tools_used(acc, _), do: acc

  defp check_for_errors(acc, %{type: :result, subtype: subtype}) when subtype != :success do
    Map.update(acc, :errors, [subtype], &[subtype | &1])
  end

  defp check_for_errors(acc, _), do: acc

  defp finalize_analysis(acc) do
    %{acc | tools_used: MapSet.to_list(acc.tools_used), errors: Enum.reverse(acc.errors)}
  end

  defp perform_connectivity_test do
    # Simple echo test
    case System.cmd("claude", ["--print", "test", "--output-format", "json"],
           stderr_to_stdout: true,
           env: []
         ) do
      {output, 0} ->
        check_connectivity_output(output)

      {error, code} ->
        IO.puts("   ❌ Connectivity test failed (exit #{code})")
        IO.puts("   Error: #{String.trim(error)}")
    end
  end

  defp check_connectivity_output(output) do
    if String.contains?(output, "message") or String.contains?(output, "content") do
      IO.puts("   ✅ Basic connectivity OK")
    else
      IO.puts("   ⚠️  Unexpected response format")
    end
  end

  defp test_basic_connectivity do
    # Check if mocking is enabled
    if Runtime.use_mock?() do
      IO.puts("   ✅ Basic connectivity OK (mocked)")
    else
      perform_connectivity_test()
    end
  rescue
    e ->
      IO.puts("   ❌ Connectivity test error: #{inspect(e)}")
  end

  defp avg([]), do: 0

  defp avg(numbers) do
    Enum.sum(numbers) / length(numbers)
  end

  defp format_assistant_preview(nil), do: "no content"

  defp format_assistant_preview(content) do
    preview = String.slice(content, 0, 80)
    if String.length(content) > 80, do: preview <> "...", else: preview
  end
end
