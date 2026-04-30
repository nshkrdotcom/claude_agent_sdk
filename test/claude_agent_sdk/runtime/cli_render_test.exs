defmodule ClaudeAgentSDK.Runtime.CLIRenderTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.{Options, Runtime.CLI}

  test "renders Claude-native flags without resolving or spawning the CLI" do
    options =
      Options.new(
        model: "haiku",
        max_turns: 1,
        tools: [],
        allowed_tools: ["Read"],
        disallowed_tools: ["Bash"],
        permission_mode: :default,
        mcp_config: "/tmp/mcp.json",
        system_prompt: "Answer directly."
      )

    {:ok, render} =
      CLI.render_for_test(
        options: options,
        execution_surface: [
          surface_kind: :local_subprocess,
          observability: %{suite: :promotion_path}
        ]
      )

    assert render.provider == :claude
    assert render.execution_surface.observability == %{suite: :promotion_path}
    assert render.provider_native.tools == []
    assert render.provider_native.allowed_tools == ["Read"]
    assert render.provider_native.disallowed_tools == ["Bash"]
    assert render.provider_native.permission_mode == :default
    assert render.provider_native.mcp_config == "/tmp/mcp.json"

    args = render.args
    assert "--tools" in args
    assert flag_value(args, "--tools") == ""
    assert flag_value(args, "--allowedTools") == "Read"
    assert flag_value(args, "--disallowedTools") == "Bash"
    assert flag_value(args, "--permission-mode") == "default"
    assert flag_value(args, "--mcp-config") == "/tmp/mcp.json"
    assert "--include-partial-messages" in args
  end

  defp flag_value(args, flag) do
    case Enum.find_index(args, &(&1 == flag)) do
      nil -> nil
      idx -> Enum.at(args, idx + 1)
    end
  end
end
