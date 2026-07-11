defmodule ClaudeAgentSDK.MessageAgentToolCompletedTest do
  @moduledoc """
  Coverage for the Agent/Task tool's structured completion output (TS
  v0.3.207 `AgentToolCompletedOutput`): the subagent's final report plus run
  totals, delivered in `tool_use_result` on the user frame that carries the
  tool result. Wire shape captured live from CLI 2.1.207 (camelCase keys).
  """
  use ClaudeAgentSDK.SupertesterCase, async: true

  alias ClaudeAgentSDK.Message

  defp parse!(map) do
    {:ok, msg} = map |> Jason.encode!() |> Message.from_json()
    msg
  end

  # Shape captured live from CLI 2.1.207 (P0 fixture run).
  defp agent_tool_user_frame do
    %{
      "type" => "user",
      "uuid" => "u-1",
      "session_id" => "s-1",
      "parent_tool_use_id" => "toolu_1",
      "message" => %{"role" => "user", "content" => []},
      "tool_use_result" => %{
        "agentId" => "a127f2080af90dbac",
        "agentType" => "general-purpose",
        "status" => "completed",
        "prompt" => "Reply with exactly the number 4",
        "resolvedModel" => "claude-haiku-4-5-20251001",
        "totalDurationMs" => 1619,
        "totalTokens" => 11_065,
        "totalToolUseCount" => 0,
        "content" => [%{"type" => "text", "text" => "4"}],
        "usage" => %{"input_tokens" => 5, "output_tokens" => 2}
      }
    }
  end

  test "agent_tool_completed/1 returns the typed completion output" do
    completed = agent_tool_user_frame() |> parse!() |> Message.agent_tool_completed()

    assert completed.agent_id == "a127f2080af90dbac"
    assert completed.agent_type == "general-purpose"
    assert completed.status == "completed"
    assert completed.resolved_model == "claude-haiku-4-5-20251001"
    assert completed.total_duration_ms == 1619
    assert completed.total_tokens == 11_065
    assert completed.total_tool_use_count == 0
    assert completed.content == [%{"type" => "text", "text" => "4"}]
    assert completed.usage == %{"input_tokens" => 5, "output_tokens" => 2}
  end

  test "unknown keys survive on the typed output" do
    frame =
      update_in(agent_tool_user_frame(), ["tool_use_result"], &Map.put(&1, "future_field", 1))

    completed = frame |> parse!() |> Message.agent_tool_completed()
    assert completed["future_field"] == 1
  end

  test "agent_tool_completed/1 is nil for non-agent tool results" do
    frame = put_in(agent_tool_user_frame(), ["tool_use_result"], %{"stdout" => "ok"})
    assert frame |> parse!() |> Message.agent_tool_completed() == nil

    frame = put_in(agent_tool_user_frame(), ["tool_use_result"], "plain text result")
    assert frame |> parse!() |> Message.agent_tool_completed() == nil
  end

  test "agent_tool_completed/1 is nil when tool_use_result is absent" do
    frame = Map.delete(agent_tool_user_frame(), "tool_use_result")
    assert frame |> parse!() |> Message.agent_tool_completed() == nil
  end

  test "agent_tool_completed/1 is nil for non-user messages" do
    msg = parse!(%{"type" => "system", "subtype" => "init", "session_id" => "s"})
    assert Message.agent_tool_completed(msg) == nil
  end
end
