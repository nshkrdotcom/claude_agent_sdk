defmodule ClaudeAgentSDK.Transport.AgentsFileTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Transport.AgentsFile

  test "externalizes --agents payload to @file when command is too long" do
    agents_json = String.duplicate("x", 50)
    args = ["--agents", agents_json, "--other", "y"]

    {updated_args, temp_files} =
      AgentsFile.externalize_agents_if_needed(args, agents_cmd_length_limit: 10)

    assert [
             "--agents",
             "@" <>
               path,
             "--other",
             "y"
           ] = updated_args

    assert temp_files == [path]
    assert File.regular?(path)
    assert File.read!(path) == agents_json

    AgentsFile.cleanup_temp_files(temp_files)
    refute File.exists?(path)
  end

  test "cleans stale leaked temp files on subsequent calls" do
    stale_path =
      Path.join(
        System.tmp_dir!(),
        "claude_agent_sdk_agents_#{System.unique_integer([:positive])}.json"
      )

    File.write!(stale_path, "{\"stale\":true}")
    assert :ok = File.touch(stale_path, {{2000, 1, 1}, {0, 0, 0}})

    {_args, _temp_files} =
      AgentsFile.externalize_agents_if_needed(["--print", "hello"],
        agents_temp_file_max_age_seconds: 0
      )

    refute File.exists?(stale_path)
  end
end
