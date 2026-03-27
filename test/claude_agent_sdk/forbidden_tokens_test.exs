defmodule ClaudeAgentSDK.ForbiddenTokensTest do
  use ExUnit.Case, async: true

  @legacy_backend Enum.join(["erl", "exec"])
  @paths [
    "README.md",
    "examples/archive/top_level/file_checkpointing_debug.exs",
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
  @transport_selector_paths [
    "README.md",
    "docs/CUSTOM_TRANSPORTS.md",
    "docs/RUNTIME_CONTROL.md",
    "guides",
    "lib/claude_agent_sdk/client.ex"
  ]

  test "shared-lane public surfaces do not mention the legacy backend label" do
    assert offending_files(@paths, fn contents ->
             contents
             |> String.downcase()
             |> String.contains?(@legacy_backend)
           end) == []
  end

  test "public Claude entrypoints do not expose legacy transport_module naming" do
    assert offending_files(@transport_selector_paths, &String.contains?(&1, "transport_module")) ==
             []
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

  defp offending_files(paths, matcher) when is_list(paths) and is_function(matcher, 1) do
    project_root = Path.expand("../..", __DIR__)

    paths
    |> Enum.flat_map(&expand_files(project_root, &1))
    |> Enum.filter(fn path ->
      project_root
      |> Path.join(path)
      |> File.read!()
      |> matcher.()
    end)
  end
end
