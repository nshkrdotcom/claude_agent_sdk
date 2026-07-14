defmodule ClaudeAgentSDK.ReleasePreparationTest do
  use ExUnit.Case, async: true

  @repo_root Path.expand("../..", __DIR__)

  test "package and HexDocs expose only public release presentation files" do
    project = Mix.Project.config()
    package_files = project[:package][:files]

    assert project[:version] == "0.18.0"
    assert project[:docs][:source_ref] == "v0.18.0"
    assert project[:docs][:assets] == %{"assets" => "assets"}
    assert project[:docs][:logo] == "assets/claude_agent_sdk.svg"

    for required <-
          ~w(lib assets build_support guides mix.exs README.md LICENSE CHANGELOG.md) do
      assert required in package_files
    end

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
