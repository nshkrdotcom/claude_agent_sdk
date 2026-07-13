defmodule ClaudeAgentSDK.DependencyBoundaryTest do
  use ExUnit.Case, async: true

  @repo_root Path.expand("../..", __DIR__)

  @forbidden_deps [
    :agent_session_manager,
    :gemini_cli_sdk,
    :codex_sdk,
    :amp_sdk,
    :inference
  ]

  test "claude_agent_sdk does not declare ASM or sibling SDK deps" do
    assert_forbidden_deps_absent(Mix.Project.config()[:deps], @forbidden_deps)
  end

  test "release metadata retains 0.18.0 and requires Elixir 1.19" do
    project = Mix.Project.config()

    assert project[:version] == "0.18.0"
    assert project[:elixir] == "~> 1.19"
  end

  test "publish mode uses CLI core 0.2 from Hex" do
    dep =
      @repo_root
      |> DependencySources.deps(publish?: true)
      |> Keyword.fetch!(:cli_subprocess_core)

    assert dep == "~> 0.2.0"
  end

  test "public SDK source does not expose raw Execution Plane structs" do
    violations =
      @repo_root
      |> Path.join("lib/**/*.ex")
      |> Path.wildcard()
      |> Enum.filter(fn path ->
        path
        |> File.read!()
        |> String.contains?("ExecutionPlane.")
      end)
      |> Enum.map(&Path.relative_to(&1, @repo_root))

    assert violations == []
  end

  defp assert_forbidden_deps_absent(deps, forbidden_deps) when is_list(deps) do
    declared = MapSet.new(Enum.map(deps, &dep_name/1))

    Enum.each(forbidden_deps, fn dep ->
      refute MapSet.member?(declared, dep),
             "claude_agent_sdk must not declare dependency on #{inspect(dep)}"
    end)
  end

  defp dep_name({name, _requirement}), do: name
  defp dep_name({name, _requirement, _opts}), do: name
end
