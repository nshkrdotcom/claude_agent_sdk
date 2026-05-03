defmodule ClaudeAgentSDK.ExamplesHygieneTest do
  use ExUnit.Case, async: true

  @forbidden_literals [
    "ClaudeAgentSDK.Mock",
    "FakeCLI",
    "MockTransport",
    "use_mock",
    "command -v claude",
    "claude --",
    "System.cmd(\"claude\"",
    "System.cmd( \"claude\"",
    "CliSubprocessCore.Command"
  ]

  test "runnable examples are live-only and use SDK APIs instead of direct Claude CLI calls" do
    violations =
      "examples/**/*"
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)
      |> Enum.reject(&allowed_path?/1)
      |> Enum.flat_map(&violations_for_file/1)

    assert violations == []
  end

  defp allowed_path?(path) do
    normalized = Path.relative_to_cwd(path)

    String.contains?(normalized, "/test/") or
      String.contains?(normalized, "/_build/") or
      String.contains?(normalized, "/deps/") or
      String.ends_with?(normalized, "/test_helper.exs")
  end

  defp violations_for_file(path) do
    text = File.read!(path)

    @forbidden_literals
    |> Enum.flat_map(fn literal ->
      if String.contains?(text, literal) do
        ["#{Path.relative_to_cwd(path)} contains #{inspect(literal)}"]
      else
        []
      end
    end)
  end
end
