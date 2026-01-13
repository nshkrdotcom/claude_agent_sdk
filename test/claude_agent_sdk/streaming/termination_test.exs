defmodule ClaudeAgentSDK.Streaming.TerminationTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.Streaming.Termination

  test "continues streaming when stop_reason is tool_use" do
    {reason1, complete1} =
      Termination.step(%{type: :message_delta, stop_reason: "tool_use"}, nil)

    assert reason1 == "tool_use"
    assert complete1 == false

    {reason2, complete2} = Termination.step(%{type: :message_stop}, reason1)

    assert reason2 == "tool_use"
    assert complete2 == false
  end

  test "completes streaming when stop_reason is end_turn" do
    {reason1, complete1} =
      Termination.step(%{type: :message_delta, stop_reason: "end_turn"}, nil)

    assert reason1 == "end_turn"
    assert complete1 == false

    {_reason2, complete2} = Termination.step(%{type: :message_stop}, reason1)

    assert complete2 == true
  end

  test "resets stop_reason on message_start" do
    {reason1, _} = Termination.step(%{type: :message_delta, stop_reason: "tool_use"}, nil)
    {reason2, _} = Termination.step(%{type: :message_start}, reason1)
    assert reason2 == nil
  end
end
