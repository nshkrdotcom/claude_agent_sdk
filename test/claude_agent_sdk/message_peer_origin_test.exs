defmodule ClaudeAgentSDK.MessagePeerOriginTest do
  @moduledoc """
  Coverage for peer-message provenance (TS v0.3.205): user-role frames carry
  an optional `origin` discriminated union; the `"peer"` variant exposes the
  sender's addressable identity (`from`), normalized display `name`, decoded
  message `body`, and `senderTaskId` for in-process background subagents.
  """
  use ClaudeAgentSDK.SupertesterCase, async: true

  alias ClaudeAgentSDK.Message

  defp parse!(map) do
    {:ok, msg} = map |> Jason.encode!() |> Message.from_json()
    msg
  end

  defp peer_user_frame do
    %{
      "type" => "user",
      "uuid" => "u-1",
      "session_id" => "s-1",
      "parent_tool_use_id" => nil,
      "message" => %{
        "role" => "user",
        "content" => [%{"type" => "text", "text" => "[peer message] hello"}]
      },
      "origin" => %{
        "kind" => "peer",
        "from" => "agent-researcher",
        "name" => "Researcher",
        "senderTaskId" => "btask_a1b2c3",
        "body" => "hello"
      }
    }
  end

  test "user frames surface the origin union" do
    msg = parse!(peer_user_frame())
    assert msg.data.origin["kind"] == "peer"
  end

  test "peer_origin/1 returns the typed peer provenance" do
    peer = peer_user_frame() |> parse!() |> Message.peer_origin()

    assert peer.from == "agent-researcher"
    assert peer.name == "Researcher"
    assert peer.body == "hello"
    assert peer.sender_task_id == "btask_a1b2c3"
    # unknown/raw keys survive
    assert peer["kind"] == "peer"
  end

  test "peer_origin/1 tolerates absent optional fields" do
    frame = put_in(peer_user_frame(), ["origin"], %{"kind" => "peer", "from" => "peer-2"})
    peer = frame |> parse!() |> Message.peer_origin()

    assert peer.from == "peer-2"
    assert peer.name == nil
    assert peer.body == nil
  end

  test "peer_origin/1 is nil for non-peer origins" do
    frame = put_in(peer_user_frame(), ["origin"], %{"kind" => "human"})
    assert frame |> parse!() |> Message.peer_origin() == nil
  end

  test "peer_origin/1 is nil when origin is absent" do
    frame = Map.delete(peer_user_frame(), "origin")
    msg = parse!(frame)
    assert Message.peer_origin(msg) == nil
    refute Map.has_key?(msg.data, :origin)
  end

  test "peer_origin/1 is nil for non-user messages" do
    msg = parse!(%{"type" => "system", "subtype" => "init", "session_id" => "s"})
    assert Message.peer_origin(msg) == nil
  end

  test "the schema-derived golden fixture parses with typed peer origin" do
    fixture = Path.expand("../support/fixtures/cli_2_1_207/peer_message_event.jsonl", __DIR__)

    [frame] =
      fixture
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.reject(&String.starts_with?(&1, "#"))

    {:ok, msg} = Message.from_json(frame)
    peer = Message.peer_origin(msg)

    assert peer.from == "agent-researcher"
    assert peer.name == "Researcher"
    assert peer.body == "status update: fixture capture complete"
  end
end
