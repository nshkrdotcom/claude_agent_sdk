defmodule ClaudeAgentSDK.Parity.PrintRemovalTest do
  @moduledoc """
  Tests for Phase 3.5: --print removal.

  These are grep-gate tests that verify `--print` does not appear in
  any of the key source files that build CLI commands. The --print flag
  has been removed in favor of stream-json output format.
  """

  use ExUnit.Case, async: true

  @project_root Path.expand("../../..", __DIR__)

  @source_files [
    {"lib/claude_agent_sdk/query/cli_stream.ex", "CLIStream"},
    {"lib/claude_agent_sdk/streaming/session.ex", "Streaming.Session"},
    {"lib/claude_agent_sdk/transport/erlexec.ex", "Transport.Erlexec"},
    {"lib/claude_agent_sdk/process.ex", "Process"}
  ]

  # Strips Elixir comment lines (lines whose first non-whitespace char is #)
  # so that historical comments mentioning --print don't trigger false positives.
  defp non_comment_lines(contents) do
    contents
    |> String.split("\n")
    |> Enum.reject(fn line -> String.match?(line, ~r/^\s*#/) end)
    |> Enum.join("\n")
  end

  describe "--print flag removal" do
    for {file, label} <- @source_files do
      test "--print does NOT appear in #{label} (#{file})" do
        path = Path.join(@project_root, unquote(file))
        contents = File.read!(path)
        code_lines = non_comment_lines(contents)

        refute String.contains?(code_lines, "--print"),
               "Expected --print to not appear in non-comment code of #{unquote(file)}, " <>
                 "but it was found. The --print flag should have been removed " <>
                 "in favor of stream-json output format."
      end
    end
  end
end
