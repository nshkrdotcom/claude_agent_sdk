#!/usr/bin/env elixir

# Demo script showing mocked vs live API calls

IO.puts("🎭 Claude Code SDK - Mock Demo")
IO.puts("=" |> String.duplicate(40))

# Enable mocking
Application.put_env(:claude_code_sdk, :use_mock, true)

# Start the mock server
{:ok, _} = ClaudeCodeSDK.Mock.start_link()

# Set up a custom mock response
ClaudeCodeSDK.Mock.set_response("fibonacci", [
  %{
    "type" => "system",
    "subtype" => "init", 
    "session_id" => "mock-fib-123",
    "model" => "claude-mock",
    "tools" => [],
    "cwd" => "/mock",
    "permissionMode" => "default",
    "apiKeySource" => "mock"
  },
  %{
    "type" => "assistant",
    "message" => %{
      "role" => "assistant",
      "content" => """
      Here's a Fibonacci function in Elixir:
      
      ```elixir
      def fibonacci(n) when n <= 1, do: n
      def fibonacci(n), do: fibonacci(n - 1) + fibonacci(n - 2)
      ```
      
      This is a MOCKED response - no API call was made!
      """
    },
    "session_id" => "mock-fib-123"
  },
  %{
    "type" => "result",
    "subtype" => "success",
    "session_id" => "mock-fib-123",
    "total_cost_usd" => 0.0,
    "duration_ms" => 0,
    "is_error" => false
  }
])

IO.puts("\n📡 Making MOCKED API call...")
IO.puts("   (No actual API request will be made)")

ClaudeCodeSDK.query("Write a fibonacci function")
|> Enum.each(fn msg ->
  case msg.type do
    :system ->
      IO.puts("\n✅ Mock session initialized: #{msg.data["session_id"]}")
      
    :assistant ->
      content = case msg.data.message do
        %{"content" => text} when is_binary(text) -> text
        _ -> "Mock content"
      end
      IO.puts("\n🤖 Response:")
      IO.puts(content)
      
    :result ->
      IO.puts("\n💰 Cost: $#{msg.data["total_cost_usd"]} (mocked - no real cost!)")
      
    _ -> :ok
  end
end)

IO.puts("\n" <> String.duplicate("=", 40))
IO.puts("✅ Mock demo complete - no API calls were made!")
IO.puts("\nTo make real API calls, run:")
IO.puts("  Application.put_env(:claude_code_sdk, :use_mock, false)")
IO.puts("  mix run demo_mock.exs")