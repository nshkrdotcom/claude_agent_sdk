defmodule ClaudeCodeSDK.DebugMode do
  @moduledoc """
  Debug mode utilities for troubleshooting Claude Code SDK queries.

  Provides detailed logging, timing information, and diagnostic output
  to help understand query execution and identify issues.
  """

  alias ClaudeCodeSDK.{AuthChecker, ContentExtractor, Options}

  @doc """
  Executes a query in debug mode with detailed logging.

  ## Parameters

    - `prompt` - The query prompt
    - `options` - Optional ClaudeCodeSDK.Options (verbose will be enabled)

  ## Returns

    - List of messages with debug information

  ## Examples

      iex> messages = ClaudeCodeSDK.DebugMode.debug_query("Hello")
      🐛 DEBUG MODE ENABLED
         Prompt: "Hello"
         Options: %ClaudeCodeSDK.Options{verbose: true, ...}
      ...
  """
  @spec debug_query(String.t(), Options.t() | nil) :: list()
  def debug_query(prompt, options \\ nil) do
    IO.puts("🐛 DEBUG MODE ENABLED")
    IO.puts("   Prompt: #{inspect(prompt, limit: 100)}")
    IO.puts("   Options: #{inspect(options, limit: :infinity)}")

    # Add debug options
    debug_options =
      case options do
        nil -> %Options{verbose: true}
        opts -> %{opts | verbose: true}
      end

    IO.puts("   Final options: #{inspect(debug_options, limit: :infinity)}")

    # Check authentication first
    case AuthChecker.check_auth() do
      {:ok, auth_info} ->
        IO.puts("   ✅ Auth: #{auth_info}")

      {:error, auth_error} ->
        IO.puts("   ❌ Auth Error: #{auth_error}")
    end

    # Time the query
    start_time = System.monotonic_time(:millisecond)

    try do
      result =
        ClaudeCodeSDK.query(prompt, debug_options)
        |> Stream.map(fn msg ->
          elapsed = System.monotonic_time(:millisecond) - start_time

          debug_info = format_debug_message(msg, elapsed)
          IO.puts(debug_info)

          msg
        end)
        |> Enum.to_list()

      total_time = System.monotonic_time(:millisecond) - start_time
      IO.puts("🏁 Debug completed in #{total_time}ms with #{length(result)} messages")

      result
    rescue
      e ->
        elapsed = System.monotonic_time(:millisecond) - start_time
        IO.puts("   [#{elapsed}ms] ❌ ERROR: #{inspect(e)}")
        IO.puts("   Stacktrace:")
        Exception.format_stacktrace(__STACKTRACE__) |> IO.puts()
        reraise e, __STACKTRACE__
    end
  end

  @doc """
  Analyzes a stream of messages and provides statistics.

  ## Parameters

    - `messages` - List or stream of ClaudeCodeSDK.Message structs

  ## Returns

    - Map with analysis results

  ## Examples

      iex> stats = ClaudeCodeSDK.DebugMode.analyze_messages(messages)
      %{
        total_messages: 5,
        message_types: %{assistant: 2, system: 1, result: 1, user: 1},
        total_cost_usd: 0.025,
        duration_ms: 3420,
        content_length: 1523
      }
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
        tools_used: [],
        errors: []
      },
      &analyze_message/2
    )
  end

  @doc """
  Runs a diagnostic check of the SDK environment.

  Checks:
  - CLI installation
  - Authentication status
  - Basic connectivity
  - Environment configuration

  ## Examples

      iex> ClaudeCodeSDK.DebugMode.run_diagnostics()
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
    IO.puts("   Mix env: #{Mix.env()}")
    IO.puts("   Mock enabled: #{Application.get_env(:claude_code_sdk, :use_mock, false)}")
    IO.puts("   Elixir: #{System.version()}")
    IO.puts("   OTP: #{System.otp_release()}")

    IO.puts("")

    # Test basic connectivity
    IO.puts("🔌 Testing basic connectivity...")
    test_basic_connectivity()

    IO.puts("")

    # Recommendations
    if diagnosis.recommendations != [] do
      IO.puts("💡 Recommendations:")

      Enum.each(diagnosis.recommendations, fn rec ->
        IO.puts("   - #{rec}")
      end)
    else
      IO.puts("✅ All systems operational!")
    end

    :ok
  end

  @doc """
  Formats a message for detailed inspection.

  ## Parameters

    - `message` - A ClaudeCodeSDK.Message struct

  ## Returns

    - Formatted string representation

  ## Examples

      iex> ClaudeCodeSDK.DebugMode.inspect_message(message)
      "Message[assistant]: \"Hello, world!\" (15 chars)"
  """
  @spec inspect_message(ClaudeCodeSDK.Message.t()) :: String.t()
  def inspect_message(message) do
    content = ContentExtractor.extract_text(message)

    content_preview =
      if content do
        truncated = String.slice(content, 0, 100)
        if String.length(content) > 100, do: truncated <> "...", else: truncated
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
    - `options` - Optional ClaudeCodeSDK.Options
    - `runs` - Number of times to run the query (default: 1)

  ## Returns

    - Map with benchmark results

  ## Examples

      iex> results = ClaudeCodeSDK.DebugMode.benchmark("Hello", nil, 3)
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
          ClaudeCodeSDK.query(prompt, options)
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

  # Private functions

  defp format_debug_message(msg, elapsed) do
    data_preview =
      case msg.type do
        :assistant ->
          content = ContentExtractor.extract_text(msg)
          format_assistant_preview(content)

        :system ->
          "session_id=#{msg.data[:session_id]}, model=#{msg.data[:model]}"

        :result ->
          "cost=$#{msg.data[:total_cost_usd]}, turns=#{msg.data[:num_turns]}"

        _ ->
          inspect(msg.data, limit: 50)
      end

    type_str = if msg.subtype, do: "#{msg.type}:#{msg.subtype}", else: "#{msg.type}"
    "   [#{elapsed}ms] #{type_str}: #{data_preview}"
  end

  defp analyze_message(message, acc) do
    acc
    |> Map.update(:total_messages, 1, &(&1 + 1))
    |> Map.update(:message_types, %{}, fn types ->
      Map.update(types, message.type, 1, &(&1 + 1))
    end)
    |> update_cost_duration(message)
    |> update_session_id(message)
    |> update_content_length(message)
    |> check_for_errors(message)
  end

  defp update_cost_duration(acc, %{type: :result, data: data}) do
    acc
    |> Map.put(:total_cost_usd, data[:total_cost_usd])
    |> Map.put(:duration_ms, data[:duration_ms])
  end

  defp update_cost_duration(acc, _), do: acc

  defp update_session_id(acc, %{type: :system, data: %{session_id: id}}) do
    Map.put(acc, :session_id, id)
  end

  defp update_session_id(acc, _), do: acc

  defp update_content_length(acc, message) do
    case ContentExtractor.extract_text(message) do
      nil -> acc
      text -> Map.update(acc, :content_length, String.length(text), &(&1 + String.length(text)))
    end
  end

  defp check_for_errors(acc, %{type: :result, subtype: subtype}) when subtype != :success do
    Map.update(acc, :errors, [subtype], &[subtype | &1])
  end

  defp check_for_errors(acc, _), do: acc

  defp test_basic_connectivity do
    # Check if mocking is enabled
    if Application.get_env(:claude_code_sdk, :use_mock, false) do
      IO.puts("   ✅ Basic connectivity OK (mocked)")
    else
      # Simple echo test
      case System.cmd("claude", ["--print", "test", "--output-format", "json"],
             stderr_to_stdout: true,
             timeout: 5000,
             env: []
           ) do
        {output, 0} ->
          if String.contains?(output, "message") or String.contains?(output, "content") do
            IO.puts("   ✅ Basic connectivity OK")
          else
            IO.puts("   ⚠️  Unexpected response format")
          end

        {error, code} ->
          IO.puts("   ❌ Connectivity test failed (exit #{code})")
          IO.puts("   Error: #{String.trim(error)}")
      end
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
