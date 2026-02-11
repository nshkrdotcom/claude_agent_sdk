defmodule ClaudeAgentSDK.Config.OrchestrationTest do
  use ExUnit.Case, async: false

  alias ClaudeAgentSDK.Config.Orchestration

  setup do
    original = Application.get_env(:claude_agent_sdk, Orchestration)
    on_exit(fn -> restore(original) end)
    :ok
  end

  defp restore(nil),
    do: Application.delete_env(:claude_agent_sdk, Orchestration)

  defp restore(val),
    do: Application.put_env(:claude_agent_sdk, Orchestration, val)

  describe "defaults" do
    test "max_concurrent" do
      assert Orchestration.max_concurrent() == 5
    end

    test "max_retries" do
      assert Orchestration.max_retries() == 3
    end

    test "backoff_ms" do
      assert Orchestration.backoff_ms() == 1_000
    end
  end

  describe "runtime override" do
    test "overrides max_concurrent" do
      Application.put_env(:claude_agent_sdk, Orchestration, max_concurrent: 10)

      assert Orchestration.max_concurrent() == 10
    end

    test "non-overridden keys keep defaults" do
      Application.put_env(:claude_agent_sdk, Orchestration, max_concurrent: 10)

      assert Orchestration.max_retries() == 3
    end
  end
end
