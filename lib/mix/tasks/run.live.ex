defmodule Mix.Tasks.Run.Live do
  use Mix.Task

  @shortdoc "Runs Elixir scripts with live Claude API calls"
  @moduledoc """
  Runs Elixir scripts against the live Claude API instead of using mocks.

  This task temporarily disables mocking and runs the specified script with actual API calls.
  Use with caution as it will make real API calls and incur costs.

  ## Usage

      mix run.live script.exs
      mix run.live examples/basic_example.exs
      mix run.live examples/simple_analyzer.exs path/to/file.txt

  ## Examples

      # Run a simple analysis script
      mix run.live examples/simple_analyzer.exs lib/claude_agent_sdk.ex
      
      # Run any custom script with live API
      mix run.live my_script.exs

  ## Options

  All additional arguments are passed through to the script.
  """

  @impl Mix.Task
  def run(args) do
    case args do
      [] ->
        Mix.shell().error("Usage: mix run.live <script.exs> [args...]")
        System.halt(1)

      [script_path | script_args] ->
        unless File.exists?(script_path) do
          Mix.shell().error("Script not found: #{script_path}")
          System.halt(1)
        end

        # Mark that we're running in live mode (checked by Process.use_mock?)
        System.put_env("LIVE_MODE", "true")

        # Configure the application for live API
        # Note: This must be done BEFORE the script runs
        Application.put_env(:claude_agent_sdk, :use_mock, false, persistent: true)

        IO.puts("🔴 Running script with LIVE API calls...")
        IO.puts("⚠️  Warning: This will make real API calls and may incur costs!")
        IO.puts("📄 Script: #{script_path}")
        IO.puts("")

        # Set script arguments for System.argv()
        System.put_env("ARGV", Enum.join(script_args, " "))

        # Run the script using Mix.Task module
        Mix.Task.run("run", [script_path | script_args])
    end
  end
end
