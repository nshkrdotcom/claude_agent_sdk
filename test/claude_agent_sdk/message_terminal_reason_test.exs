defmodule ClaudeAgentSDK.MessageTerminalReasonTest do
  @moduledoc """
  Coverage for the `terminal_reason` result field (CLI 2.1.204+ / TS v0.3.204)
  and the `Message.dead_turn?/1` classifier.

  The dead-turn set is the CLI 2.1.207 ground truth (11 values): the six
  changelog-new reasons plus blocking_limit, rapid_refill_breaker,
  prompt_too_long, image_error, and model_error. Aborts and clean
  completions are not dead turns.
  """
  use ClaudeAgentSDK.SupertesterCase, async: true

  alias ClaudeAgentSDK.Message

  @dead_reasons ~w(
    blocking_limit rapid_refill_breaker prompt_too_long image_error
    model_error api_error malformed_tool_use_exhausted budget_exhausted
    structured_output_retry_exhausted tool_deferred_unavailable
    turn_setup_failed
  )

  @not_dead_reasons ~w(
    aborted_streaming aborted_tools stop_hook_prevented hook_stopped
    tool_deferred max_turns background_requested completed
  )

  defp parse!(map) do
    {:ok, msg} = map |> Jason.encode!() |> Message.from_json()
    msg
  end

  test "parses terminal_reason on success results" do
    msg =
      parse!(%{
        "type" => "result",
        "subtype" => "success",
        "session_id" => "s1",
        "result" => "ok",
        "is_error" => false,
        "num_turns" => 1,
        "duration_ms" => 10,
        "duration_api_ms" => 8,
        "total_cost_usd" => 0.1,
        "terminal_reason" => "budget_exhausted"
      })

    assert msg.data.terminal_reason == "budget_exhausted"
    assert Message.dead_turn?(msg)
  end

  test "parses terminal_reason on error results" do
    msg =
      parse!(%{
        "type" => "result",
        "subtype" => "error_during_execution",
        "session_id" => "s2",
        "is_error" => true,
        "error" => "boom",
        "terminal_reason" => "api_error"
      })

    assert msg.data.terminal_reason == "api_error"
    assert Message.dead_turn?(msg)
  end

  test "a completed success turn is not a dead turn" do
    msg =
      parse!(%{
        "type" => "result",
        "subtype" => "success",
        "session_id" => "s1",
        "result" => "ok",
        "is_error" => false,
        "num_turns" => 1,
        "terminal_reason" => "completed"
      })

    assert msg.data.terminal_reason == "completed"
    refute Message.dead_turn?(msg)
  end

  test "absent terminal_reason -> field omitted, not a dead turn" do
    msg =
      parse!(%{
        "type" => "result",
        "subtype" => "success",
        "session_id" => "s3",
        "result" => "ok",
        "is_error" => false,
        "num_turns" => 1
      })

    refute Map.has_key?(msg.data, :terminal_reason)
    refute Message.dead_turn?(msg)
  end

  for reason <- @dead_reasons do
    test "#{reason} classifies as a dead turn" do
      assert Message.dead_turn?(unquote(reason))
    end
  end

  for reason <- @not_dead_reasons do
    test "#{reason} does not classify as a dead turn" do
      refute Message.dead_turn?(unquote(reason))
    end
  end

  test "unknown terminal_reason string is preserved but not dead" do
    msg =
      parse!(%{
        "type" => "result",
        "subtype" => "success",
        "session_id" => "s4",
        "result" => "ok",
        "is_error" => false,
        "terminal_reason" => "some_future_reason"
      })

    assert msg.data.terminal_reason == "some_future_reason"
    refute Message.dead_turn?(msg)
    refute Message.dead_turn?("some_future_reason")
  end

  test "dead_turn?/1 tolerates nil and non-result messages" do
    refute Message.dead_turn?(nil)

    msg = parse!(%{"type" => "system", "subtype" => "init", "session_id" => "s"})
    refute Message.dead_turn?(msg)
  end

  test "the live budget_exhausted golden fixture parses as a dead turn" do
    fixture =
      Path.expand("../support/fixtures/cli_2_1_207/result_terminal_reason.jsonl", __DIR__)

    {:ok, msg} = fixture |> File.read!() |> String.trim() |> Message.from_json()
    assert msg.data.terminal_reason == "budget_exhausted"
    assert Message.dead_turn?(msg)
  end
end
