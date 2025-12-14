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
end
