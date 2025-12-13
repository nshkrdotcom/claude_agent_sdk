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
    Application.put_env(:claude_agent_sdk, :use_mock, false)

    IO.puts("🔴 Running tests with LIVE API calls...")
    IO.puts("⚠️  Warning: This will make real API calls and may incur costs!")
    IO.puts("   Default: runs only @tag :live tests (override by passing file paths / flags)")
    IO.puts("")

    # Run test task using Mix.Task module
    # This is the proper way to delegate to another task
    args = normalize_args(args)
    Mix.Task.run("test", args)
  end

  defp normalize_args(args) when is_list(args) do
    args
    |> maybe_put_color()
    |> maybe_put_exclude_mock()
    |> maybe_put_include_integration()
    |> maybe_put_live_filters()
  end

  defp maybe_put_color([]), do: ["--color"]
  defp maybe_put_color(args), do: args

  defp maybe_put_exclude_mock(args) do
    if exclude_mock?(args) do
      args
    else
      args ++ ["--exclude", "mock"]
    end
  end

  defp exclude_mock?(args) do
    Enum.chunk_every(args, 2, 1, :discard)
    |> Enum.any?(fn
      ["--exclude", "mock"] -> true
      _ -> false
    end)
  end

  defp maybe_put_include_integration(args) do
    if include_tag?(args, "integration") do
      args
    else
      args ++ ["--include", "integration"]
    end
  end

  defp maybe_put_live_filters(args) do
    cond do
      only_specified?(args) ->
        maybe_put_include_live(args)

      contains_test_paths?(args) ->
        maybe_put_include_live(args)

      true ->
        args ++ ["--only", "live"]
    end
  end

  defp maybe_put_include_live(args) do
    if include_tag?(args, "live") do
      args
    else
      args ++ ["--include", "live"]
    end
  end

  defp include_tag?(args, tag) do
    Enum.chunk_every(args, 2, 1, :discard)
    |> Enum.any?(fn
      ["--include", ^tag] -> true
      _ -> false
    end)
  end

  defp only_specified?(args), do: "--only" in args

  defp contains_test_paths?(args) do
    Enum.any?(args, fn arg ->
      is_binary(arg) and
        not String.starts_with?(arg, "-") and
        (String.contains?(arg, "_test.exs") or String.starts_with?(arg, "test/"))
    end)
  end
end
