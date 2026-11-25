defmodule ClaudeAgentSDK.ReleasePreparationTest do
  use ExUnit.Case, async: true

  @repo_root Path.expand("../..", __DIR__)

  test "package and HexDocs expose only public release presentation files" do
    project = Mix.Project.config()
    package_files = project[:package][:files]

    assert project[:version] == "0.21.2"
    assert project[:docs][:source_ref] == "v0.21.2"
    assert project[:docs][:assets] == %{"assets" => "assets"}
    assert project[:docs][:logo] == "assets/claude_agent_sdk.svg"

    for required <-
          ~w(lib assets guides mix.exs README.md LICENSE CHANGELOG.md) do
      assert required in package_files
    end

    extras = Enum.map(project[:docs][:extras], &elem(&1, 0))

    assert Enum.sort(extras) ==
             Enum.sort(~w(README.md LICENSE CHANGELOG.md) ++ Path.wildcard("guides/*.md"))

    assert Enum.sort(List.flatten(Keyword.values(project[:docs][:groups_for_extras]))) ==
             Enum.sort(extras)

    refute Enum.any?(package_files, &String.starts_with?(&1, ["docs", "examples"]))
    refute "build_support" in package_files

    assert project[:package][:links]["License"] ==
             "https://github.com/nshkrdotcom/claude_agent_sdk/blob/main/LICENSE"

    refute ".formatter.exs" in package_files
  end

  test "README has the centered 200px logo and GitHub and MIT badges" do
    readme = File.read!(Path.join(@repo_root, "README.md"))
    header = readme |> String.split("\n") |> Enum.take(20) |> Enum.join("\n")

    assert header =~ ~s(src="assets/claude_agent_sdk.svg")
    assert header =~ ~s(width="200")
    assert header =~ ~s(href="https://github.com/nshkrdotcom/claude_agent_sdk")
    assert header =~ ~s(href="LICENSE")
    assert length(Regex.scan(~r/img\.shields\.io/, header)) == 2
  end
end
