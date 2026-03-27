defmodule ClaudeAgentSDK.ForbiddenTokensTest do
  use ExUnit.Case, async: true

  @legacy_backend Enum.join(["erl", "exec"])
  @paths [
    "README.md",
    "guides",
    "lib/claude_agent_sdk/runtime",
    "lib/claude_agent_sdk/streaming.ex",
    "lib/claude_agent_sdk/streaming",
    "lib/claude_agent_sdk/transport.ex",
    "test/claude_agent_sdk/client_transport_stderr_test.exs",
    "test/claude_agent_sdk/parity/print_removal_test.exs",
    "test/claude_agent_sdk/query_cli_stream_cleanup_test.exs",
    "test/claude_agent_sdk/transport"
  ]

  test "shared-lane public surfaces do not mention the legacy backend label" do
    project_root = Path.expand("..", __DIR__)

    offending_files =
      @paths
      |> Enum.flat_map(&expand_files(project_root, &1))
      |> Enum.filter(fn path ->
        path
        |> File.read!()
        |> String.downcase()
        |> String.contains?(@legacy_backend)
      end)

    assert offending_files == []
  end

  defp expand_files(project_root, relative_path) do
    path = Path.join(project_root, relative_path)

    cond do
      File.regular?(path) ->
        [relative_path]

      File.dir?(path) ->
        path
        |> Path.join("**/*")
        |> Path.wildcard(match_dot: false)
        |> Enum.filter(&File.regular?/1)
        |> Enum.map(&Path.relative_to(&1, project_root))

      true ->
        []
    end
  end
end
