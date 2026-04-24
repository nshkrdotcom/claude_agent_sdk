defmodule ClaudeAgentSDK.ExamplesHygieneTest do
  use ExUnit.Case, async: true

  @forbidden_patterns [
    "ClaudeAgentSDK\\.Mock",
    "FakeCLI",
    "MockTransport",
    "use_mock",
    "command -v claude",
    "claude --",
    "System\\.cmd\\(\\s*\"claude\"",
    "CliSubprocessCore\\.Command"
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
    String.contains?(normalized, "/test/") or String.ends_with?(normalized, "/test_helper.exs")
  end

  defp violations_for_file(path) do
    text = File.read!(path)

    @forbidden_patterns
    |> Enum.flat_map(fn pattern ->
      if Regex.match?(Regex.compile!(pattern), text) do
        ["#{Path.relative_to_cwd(path)} matches #{inspect(pattern)}"]
      else
        []
      end
    end)
  end
end
