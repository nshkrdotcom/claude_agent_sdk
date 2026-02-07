defmodule ClaudeAgentSDK.Parity.AgentsFileRemovedTest do
  @moduledoc """
  Grep-gate tests verifying the AgentsFile module has been fully removed.

  These tests ensure that no source code references remain for the
  deleted AgentsFile module or its associated temp_files functionality.
  """

  use ExUnit.Case, async: true

  @lib_dir Path.expand("../../../lib", __DIR__)

  describe "AgentsFile module removal" do
    test "agents_file.ex does not exist in lib directory" do
      path = Path.join(@lib_dir, "claude_agent_sdk/agents_file.ex")
      refute File.exists?(path), "Expected #{path} to not exist, but it does"
    end

    test "no source files in lib/ reference AgentsFile" do
      matches = grep_lib_sources("AgentsFile")

      assert matches == [],
             "Expected no source files to reference AgentsFile, but found:\n#{format_matches(matches)}"
    end

    test "no source files in lib/ reference temp_files" do
      matches = grep_lib_sources("temp_files")

      assert matches == [],
             "Expected no source files to reference temp_files, but found:\n#{format_matches(matches)}"
    end
  end

  defp grep_lib_sources(pattern) do
    @lib_dir
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      path
      |> File.read!()
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _num} -> String.contains?(line, pattern) end)
      |> Enum.map(fn {line, num} ->
        relative = Path.relative_to(path, @lib_dir)
        "  #{relative}:#{num}: #{String.trim(line)}"
      end)
    end)
  end

  defp format_matches(matches), do: Enum.join(matches, "\n")
end
