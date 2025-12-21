defmodule ClaudeAgentSDK.CLIVersionTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.CLI

  describe "version constants" do
    test "recommended_version/0 returns semver string" do
      version = CLI.recommended_version()
      assert is_binary(version)
      assert {:ok, _} = Version.parse(version)
    end

    test "recommended_version is >= minimum_version" do
      {:ok, recommended} = Version.parse(CLI.recommended_version())
      {:ok, minimum} = Version.parse(CLI.minimum_version())
      assert Version.compare(recommended, minimum) in [:eq, :gt]
    end

    test "recommended_version is 2.0.75" do
      assert CLI.recommended_version() == "2.0.75"
    end
  end
end
