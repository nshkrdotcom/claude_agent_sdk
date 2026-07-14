defmodule ClaudeAgentSDK.ExamplesHygieneTest do
  use ExUnit.Case, async: false

  @repo_root Path.expand("../..", __DIR__)

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

  test "packaged example projects use the release Elixir floor and shared SDK source" do
    violations =
      @repo_root
      |> Path.join("examples/*/mix.exs")
      |> Path.wildcard()
      |> Enum.flat_map(&release_requirement_violations/1)

    assert violations == []
  end

  test "package selection excludes the ignored lock and preserves tracked example locks" do
    refute ClaudeAgentSdk.MixProject.example_package_file?("examples/mix_task_chat/mix.lock")

    assert ClaudeAgentSdk.MixProject.example_package_file?("examples/phoenix_chat/mix.lock")
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

  defp release_requirement_violations(path) do
    text = File.read!(path)
    relative = Path.relative_to(path, @repo_root)

    []
    |> maybe_add(
      not String.contains?(text, ~s(elixir: "~> 1.19")),
      "#{relative} does not require Elixir ~> 1.19"
    )
    |> maybe_add(
      not String.contains?(text, "DependencySources.dep(:claude_agent_sdk"),
      "#{relative} bypasses the shared claude_agent_sdk dependency source"
    )
  end

  defp maybe_add(violations, true, violation), do: [violation | violations]
  defp maybe_add(violations, false, _violation), do: violations
end
