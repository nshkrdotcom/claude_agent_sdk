defmodule ClaudeAgentSDK.Transport.SetupTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.Transport.Setup

  test "validate_cwd/1 accepts nil" do
    assert :ok = Setup.validate_cwd(nil)
  end

  test "validate_cwd/1 accepts existing directories" do
    dir = System.tmp_dir!()
    assert :ok = Setup.validate_cwd(dir)
  end

  test "validate_cwd/1 returns error for missing directory" do
    dir = Path.join(System.tmp_dir!(), "missing_cwd_#{System.unique_integer([:positive])}")

    refute File.dir?(dir)
    assert {:error, {:cwd_not_found, ^dir}} = Setup.validate_cwd(dir)
  end
end
