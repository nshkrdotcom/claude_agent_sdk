defmodule ClaudeAgentSDK.InterruptReceiptTest do
  @moduledoc """
  Unit coverage for `ClaudeAgentSDK.InterruptReceipt` (upstream
  `interrupt_receipt_v1`, TS v0.3.205 / CLI 2.1.205+).
  """
  use ClaudeAgentSDK.SupertesterCase, async: true

  alias ClaudeAgentSDK.InterruptReceipt

  test "from_response extracts still_queued uuids" do
    receipt = InterruptReceipt.from_response(%{"still_queued" => ["a", "b"]})
    assert receipt.still_queued == ["a", "b"]
    assert receipt.raw == %{"still_queued" => ["a", "b"]}
  end

  test "from_response tolerates nil and empty payloads" do
    assert InterruptReceipt.from_response(nil).still_queued == []
    assert InterruptReceipt.from_response(%{}).still_queued == []
  end

  test "from_response filters non-string entries (matching the TS SDK)" do
    receipt = InterruptReceipt.from_response(%{"still_queued" => ["a", 1, nil, "b"]})
    assert receipt.still_queued == ["a", "b"]
  end

  test "from_response tolerates a non-list still_queued" do
    assert InterruptReceipt.from_response(%{"still_queued" => "oops"}).still_queued == []
  end

  test "the live golden fixture payload parses" do
    fixture =
      Path.expand("../support/fixtures/cli_2_1_207/control_interrupt_response.jsonl", __DIR__)

    frame = fixture |> File.read!() |> String.trim() |> Jason.decode!()
    payload = get_in(frame, ["response", "response"])

    receipt = InterruptReceipt.from_response(payload)

    assert receipt.still_queued == [
             "8ae5d648-31f4-402d-9679-c263519429c5",
             "5344016a-f16a-40c9-bb8e-82a2fbfe0743"
           ]
  end
end
