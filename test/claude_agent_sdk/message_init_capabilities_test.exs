defmodule ClaudeAgentSDK.MessageInitCapabilitiesTest do
  @moduledoc """
  Coverage for the `capabilities` list on `system/init` frames and
  `Message.capability?/2` feature detection (TS v0.3.205 / CLI 2.1.205+
  advertises `interrupt_receipt_v1`).
  """
  use ClaudeAgentSDK.SupertesterCase, async: true

  alias ClaudeAgentSDK.Message

  defp parse!(map) do
    {:ok, msg} = map |> Jason.encode!() |> Message.from_json()
    msg
  end

  test "init frame exposes capabilities and capability?/2" do
    msg =
      parse!(%{
        "type" => "system",
        "subtype" => "init",
        "session_id" => "s",
        "capabilities" => ["interrupt_receipt_v1", "msg_lifecycle_v1"]
      })

    assert msg.data.capabilities == ["interrupt_receipt_v1", "msg_lifecycle_v1"]
    assert Message.capability?(msg, "interrupt_receipt_v1")
    assert Message.capability?(msg, "msg_lifecycle_v1")
    refute Message.capability?(msg, "nope")
  end

  test "init without capabilities defaults to []" do
    msg = parse!(%{"type" => "system", "subtype" => "init", "session_id" => "s"})
    assert msg.data.capabilities == []
    refute Message.capability?(msg, "interrupt_receipt_v1")
  end

  test "capability?/2 is false for non-init messages" do
    msg = parse!(%{"type" => "system", "subtype" => "task_started", "task_id" => "t"})
    refute Message.capability?(msg, "interrupt_receipt_v1")
  end

  test "the live golden init fixture advertises interrupt_receipt_v1" do
    fixture =
      Path.expand("../support/fixtures/cli_2_1_207/system_init_capabilities.jsonl", __DIR__)

    {:ok, msg} = fixture |> File.read!() |> String.trim() |> Message.from_json()
    assert msg.subtype == :init
    assert Message.capability?(msg, "interrupt_receipt_v1")
    assert Message.capability?(msg, "msg_lifecycle_v1")
  end
end
