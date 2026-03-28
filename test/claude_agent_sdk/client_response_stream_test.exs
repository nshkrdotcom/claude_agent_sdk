defmodule ClaudeAgentSDK.ClientResponseStreamTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Client, Message, Options}
  alias ClaudeAgentSDK.TestSupport.FakeCLI

  setup do
    Process.flag(:trap_exit, true)

    fake_cli = FakeCLI.new!()

    {:ok, client} =
      Client.start_link(FakeCLI.options(fake_cli, %Options{}))

    on_exit(fn ->
      try do
        Client.stop(client)
      catch
        :exit, _ -> :ok
      end

      FakeCLI.cleanup(fake_cli)
    end)

    assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)

    {:ok, client: client, transport: fake_cli}
  end

  test "receive_response_stream yields messages until result", %{
    client: client,
    transport: transport
  } do
    task = Task.async(fn -> Client.receive_response_stream(client) |> Enum.to_list() end)

    SupertesterCase.eventually(
      fn ->
        state = :sys.get_state(client)
        map_size(state.subscribers) > 0
      end,
      timeout: 1_000
    )

    assistant = %{
      "type" => "assistant",
      "message" => %{"role" => "assistant", "content" => "hi"},
      "session_id" => "sess"
    }

    result = %{
      "type" => "result",
      "subtype" => "success",
      "session_id" => "sess",
      "duration_ms" => 10,
      "num_turns" => 1,
      "is_error" => false
    }

    FakeCLI.push_message(transport, assistant)
    FakeCLI.push_message(transport, result)

    assert [%Message{type: :assistant}, %Message{type: :result}] = Task.await(task, 1_000)
  end

  test "client sets CLAUDE_CODE_ENTRYPOINT for client transports", %{client: client} do
    state = :sys.get_state(client)
    env = state.options.env || %{}

    assert env["CLAUDE_CODE_ENTRYPOINT"] == "sdk-elixir-client"
  end

  test "client preserves explicit atom-key entrypoint env overrides" do
    fake_cli = FakeCLI.new!()

    {:ok, client} =
      Client.start_link(
        FakeCLI.options(fake_cli, %Options{env: %{:CLAUDE_CODE_ENTRYPOINT => "custom-entrypoint"}})
      )

    try do
      state = :sys.get_state(client)
      env = state.options.env || %{}

      assert env[:CLAUDE_CODE_ENTRYPOINT] == "custom-entrypoint"
      refute Map.has_key?(env, "CLAUDE_CODE_ENTRYPOINT")
    after
      try do
        Client.stop(client)
      catch
        :exit, _ -> :ok
      end

      FakeCLI.cleanup(fake_cli)
    end
  end
end
