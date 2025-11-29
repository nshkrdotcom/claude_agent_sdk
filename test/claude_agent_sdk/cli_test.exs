defmodule ClaudeAgentSDK.CLITest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias ClaudeAgentSDK.CLI

  setup do
    original_path = System.get_env("PATH") || ""

    on_exit(fn ->
      System.put_env("PATH", original_path)
    end)

    {:ok, original_path: original_path}
  end

  test "find_executable/0 returns {:ok, path} when CLI exists on PATH", %{
    original_path: original_path
  } do
    with_fake_cli(original_path, [{"claude-code", "1.2.3"}], fn paths ->
      assert {:ok, path} = CLI.find_executable()
      assert path == paths["claude-code"]
    end)
  end

  test "find_executable/0 returns {:error, :not_found} when CLI is missing", %{
    original_path: original_path
  } do
    with_fake_cli(original_path, [], fn _paths ->
      assert {:error, :not_found} = CLI.find_executable()
    end)
  end

  test "find_executable/0 prefers claude-code before claude when both exist", %{
    original_path: original_path
  } do
    with_fake_cli(original_path, [{"claude-code", "1.2.3"}, {"claude", "1.2.3"}], fn paths ->
      assert {:ok, path} = CLI.find_executable()
      assert path == paths["claude-code"]
    end)
  end

  test "find_executable!/0 returns the path when CLI exists", %{original_path: original_path} do
    with_fake_cli(original_path, [{"claude", "1.2.3"}], fn paths ->
      assert CLI.find_executable!() == paths["claude"]
    end)
  end

  test "find_executable!/0 raises when CLI is missing", %{original_path: original_path} do
    with_fake_cli(original_path, [], fn _paths ->
      assert_raise RuntimeError, fn -> CLI.find_executable!() end
    end)
  end

  test "installed?/0 returns true when CLI is present", %{original_path: original_path} do
    with_fake_cli(original_path, [{"claude", "1.2.3"}], fn _paths ->
      assert CLI.installed?()
    end)
  end

  test "installed?/0 returns false when CLI is missing", %{original_path: original_path} do
    with_fake_cli(original_path, [], fn _paths ->
      refute CLI.installed?()
    end)
  end

  test "version/0 returns {:ok, version_string} when CLI reports a version", %{
    original_path: original_path
  } do
    with_fake_cli(original_path, [{"claude", "1.2.3"}], fn _paths ->
      assert {:ok, "1.2.3"} = CLI.version()
    end)
  end

  test "version/0 returns {:error, :not_found} when CLI is missing", %{
    original_path: original_path
  } do
    with_fake_cli(original_path, [], fn _paths ->
      assert {:error, :not_found} = CLI.version()
    end)
  end

  test "minimum_version/0 returns the configured minimum version string" do
    assert CLI.minimum_version() == "1.0.0"
  end

  test "version_supported?/0 returns true when installed version meets minimum", %{
    original_path: original_path
  } do
    with_fake_cli(original_path, [{"claude", "1.2.3"}], fn _paths ->
      assert CLI.version_supported?()
    end)
  end

  test "version_supported?/0 returns false when installed version is below minimum", %{
    original_path: original_path
  } do
    with_fake_cli(original_path, [{"claude", "0.9.0"}], fn _paths ->
      refute CLI.version_supported?()
    end)
  end

  test "warn_if_outdated/0 logs a warning when version is below minimum", %{
    original_path: original_path
  } do
    log =
      with_fake_cli(original_path, [{"claude", "0.9.0"}], fn _paths ->
        capture_log(fn ->
          assert :ok = CLI.warn_if_outdated()
        end)
      end)

    assert log =~ "Claude CLI version 0.9.0 is below minimum 1.0.0"
  end

  defp with_fake_cli(original_path, cli_defs, fun) do
    dir = Path.join(System.tmp_dir!(), "claude_cli_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    paths =
      cli_defs
      |> Enum.map(fn {name, version} ->
        path = Path.join(dir, name)
        write_cli_script(path, name, version)
        {name, path}
      end)
      |> Map.new()

    System.put_env("PATH", dir)

    try do
      fun.(paths)
    after
      System.put_env("PATH", original_path)
      File.rm_rf!(dir)
    end
  end

  defp write_cli_script(path, name, version) do
    File.write!(path, """
    #!/bin/sh
    if [ "$1" = "--version" ]; then
      echo "#{name} #{version}"
      exit 0
    fi

    echo "ok"
    """)

    File.chmod!(path, 0o755)
  end
end
