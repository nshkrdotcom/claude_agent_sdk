defmodule Mix.Tasks.Test.Live do
  use Mix.Task

  @shortdoc "Runs tests with live Claude API calls"
  @moduledoc """
  Runs tests against the live Claude API instead of using mocks.

  This task temporarily disables mocking and runs the test suite with actual API calls.
  Use with caution as it will make real API calls and incur costs.

  ## Usage

      mix test.live
      mix test.live test/specific_test.exs

  ## Options

  All options are passed through to the underlying `mix test` task.
  """

  @impl Mix.Task
  def run(args) do
    # Mark that we're running in live mode
    System.put_env("LIVE_TESTS", "true")
    
    # Start the application in test mode but with live API
    Application.put_env(:claude_code_sdk, :use_mock, false)

    IO.puts("🔴 Running tests with LIVE API calls...")
    IO.puts("⚠️  Warning: This will make real API calls and may incur costs!")
    IO.puts("")

    # Run test task using Mix.Task module
    # This is the proper way to delegate to another task
    args = if args == [], do: ["--color"], else: args
    Mix.Task.run("test", args)
  end
end
