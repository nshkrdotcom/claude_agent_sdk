defmodule ClaudeAgentSDK.Options.ShadowingTest do
  @moduledoc """
  A `can_use_tool` callback is silently shadowed when configured alongside a
  whole-tool `allowed_tools` grant, `skills: :all`, or `bypass_permissions`.
  Building such options emits a one-time warning (parity with Python v0.2.111 /
  TypeScript v0.3.198). Also locks the env version-injection behavior.
  """
  use ClaudeAgentSDK.SupertesterCase

  import ExUnit.CaptureLog

  alias ClaudeAgentSDK.{Options, Process}

  defp cb, do: fn _tool, _input, _ctx -> {:allow, %{}} end

  describe "can_use_tool shadowing warning" do
    test "warns when a whole-tool allowed_tools grant shadows the callback" do
      log =
        capture_log(fn ->
          Options.new(can_use_tool: cb(), allowed_tools: ["Read"])
        end)

      assert log =~ "can_use_tool"
    end

    test "warns for Read() and Read(*) whole-tool grants" do
      for grant <- ["Read()", "Read(*)"] do
        log = capture_log(fn -> Options.new(can_use_tool: cb(), allowed_tools: [grant]) end)
        assert log =~ "can_use_tool", "expected warning for grant #{inspect(grant)}"
      end
    end

    test "warns when bypass_permissions shadows the callback" do
      log =
        capture_log(fn ->
          Options.new(can_use_tool: cb(), permission_mode: :bypass_permissions)
        end)

      assert log =~ "can_use_tool"
    end

    test "warns when skills: :all shadows the callback" do
      log = capture_log(fn -> Options.new(can_use_tool: cb(), skills: :all) end)
      assert log =~ "can_use_tool"
    end

    test "does not warn for an arg-scoped tool grant" do
      log =
        capture_log(fn ->
          Options.new(can_use_tool: cb(), allowed_tools: ["Bash(git *)"])
        end)

      refute log =~ "can_use_tool"
    end

    test "does not warn when can_use_tool is absent" do
      log = capture_log(fn -> Options.new(allowed_tools: ["Read"]) end)
      refute log =~ "can_use_tool"
    end
  end

  describe "env version injection (TS v0.3.149 parity)" do
    test "CLAUDE_AGENT_SDK_VERSION is injected even with a custom env" do
      env = Process.__env_vars__(Options.new(env: %{"FOO" => "bar"}))
      assert env["CLAUDE_AGENT_SDK_VERSION"] not in [nil, ""]
      assert env["FOO"] == "bar"
      refute Map.has_key?(env, "CLAUDECODE")
    end
  end
end
