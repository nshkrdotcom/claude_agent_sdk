defmodule ClaudeAgentSDK.MessageCommandLifecycleTest do
  @moduledoc """
  Coverage for the `command_lifecycle` top-level frame (CLI 2.1.206+ / TS
  v0.3.206): each uuid-stamped inbound message's lifecycle state, and the
  paired fix that zero-API results report `duration_api_ms: 0` rather than
  a stale value.

  Wire shape (confirmed live on CLI 2.1.207): `command_uuid` is the
  client-supplied uuid of the inbound message; `uuid` is the universal
  per-frame uuid.
  """
  use ClaudeAgentSDK.SupertesterCase, async: true

  alias ClaudeAgentSDK.Message

  defp parse!(map) do
    {:ok, msg} = map |> Jason.encode!() |> Message.from_json()
    msg
  end

  test "parses a command_lifecycle frame" do
    msg =
      parse!(%{
        "type" => "command_lifecycle",
        "command_uuid" => "cmd-1",
        "state" => "cancelled",
        "uuid" => "frame-1",
        "session_id" => "s1"
      })

    assert msg.type == :command_lifecycle
    assert msg.data.command_uuid == "cmd-1"
    assert msg.data.state == "cancelled"
    assert msg.data.uuid == "frame-1"
    assert msg.data.session_id == "s1"
    assert Message.command_terminal?(msg)
  end

  for {state, terminal?} <- [
        {"queued", false},
        {"started", false},
        {"completed", true},
        {"cancelled", true},
        {"discarded", true}
      ] do
    test "state #{state} terminal? == #{terminal?}" do
      assert Message.command_terminal?(unquote(state)) == unquote(terminal?)

      msg =
        parse!(%{
          "type" => "command_lifecycle",
          "command_uuid" => "cmd-1",
          "state" => unquote(state)
        })

      assert Message.command_terminal?(msg) == unquote(terminal?)
    end
  end

  test "unknown future state is preserved and not terminal" do
    msg =
      parse!(%{
        "type" => "command_lifecycle",
        "command_uuid" => "cmd-1",
        "state" => "some_future_state"
      })

    assert msg.data.state == "some_future_state"
    refute Message.command_terminal?(msg)
  end

  test "accepts status key as alias for state" do
    msg = parse!(%{"type" => "command_lifecycle", "command_uuid" => "c", "status" => "started"})
    assert msg.data.state == "started"
  end

  test "command_terminal?/1 tolerates nil and non-lifecycle messages" do
    refute Message.command_terminal?(nil)
    refute Message.command_terminal?(parse!(%{"type" => "system", "subtype" => "init"}))
  end

  test "unknown keys survive in raw" do
    msg =
      parse!(%{
        "type" => "command_lifecycle",
        "command_uuid" => "c",
        "state" => "queued",
        "future_field" => 1
      })

    assert msg.raw["future_field"] == 1
    assert msg.data["future_field"] == 1
  end

  test "the live golden fixture parses typed" do
    fixture = Path.expand("../support/fixtures/cli_2_1_207/command_lifecycle.jsonl", __DIR__)

    {:ok, msg} = fixture |> File.read!() |> String.trim() |> Message.from_json()
    assert msg.type == :command_lifecycle
    assert msg.data.state == "started"
    assert msg.data.command_uuid == "e0938219-2c4e-4aaf-8bc7-995dcfa45157"
    refute Message.command_terminal?(msg)
  end

  describe "zero-API duration_api_ms" do
    test "zero-API success result reports duration_api_ms 0" do
      msg =
        parse!(%{
          "type" => "result",
          "subtype" => "success",
          "session_id" => "s",
          "result" => "ok",
          "is_error" => false,
          "num_turns" => 0
        })

      assert msg.data.duration_api_ms == 0
    end

    test "explicit duration_api_ms passes through unchanged" do
      msg =
        parse!(%{
          "type" => "result",
          "subtype" => "success",
          "session_id" => "s",
          "result" => "ok",
          "is_error" => false,
          "num_turns" => 1,
          "duration_api_ms" => 42
        })

      assert msg.data.duration_api_ms == 42
    end

    test "the live zero-API golden fixture reports 0" do
      fixture =
        Path.expand("../support/fixtures/cli_2_1_207/result_zero_api_duration.jsonl", __DIR__)

      {:ok, msg} = fixture |> File.read!() |> String.trim() |> Message.from_json()
      assert msg.data.duration_api_ms == 0
      refute Map.has_key?(msg.data, :terminal_reason)
    end
  end
end
