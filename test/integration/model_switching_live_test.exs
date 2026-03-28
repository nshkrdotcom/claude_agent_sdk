defmodule Integration.ModelSwitchingLiveTest do
  use ClaudeAgentSDK.SupertesterCase, isolation: :basic

  alias ClaudeAgentSDK.{Client, Model, Options}
  alias ClaudeAgentSDK.TestSupport.FakeCLI

  @moduletag :integration

  test "should preserve context when switching models" do
    fake_cli = FakeCLI.new!()

    {:ok, client} =
      Client.start_link(FakeCLI.options(fake_cli, %Options{model: "sonnet"}))

    on_exit(fn ->
      try do
        Client.stop(client)
      catch
        :exit, _ -> :ok
      end

      FakeCLI.cleanup(fake_cli)
    end)

    assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)
    _init_request_id = FakeCLI.respond_initialize_success!(fake_cli)

    stream_task =
      Task.async(fn ->
        Client.stream_messages(client)
        |> Enum.take(3)
      end)

    wait_for_stream_subscriber(client)

    initial_message = %{
      "type" => "assistant",
      "message" => %{"content" => "Started with sonnet", "role" => "assistant"},
      "session_id" => "integration-session"
    }

    FakeCLI.push_message(fake_cli, initial_message)

    set_model_task = Task.async(fn -> Client.set_model(client, "opus") end)

    assert :ok = FakeCLI.wait_for_request_count(fake_cli, 2, 1_000)
    [_init_json, set_model_json | _rest] = FakeCLI.recorded_messages(fake_cli)
    decoded = Jason.decode!(set_model_json)
    assert decoded["request"]["subtype"] == "set_model"
    request_id = decoded["request_id"]

    {:ok, normalized} = Model.validate("opus")

    response = %{
      "type" => "control_response",
      "response" => %{
        "request_id" => request_id,
        "subtype" => "success",
        "response" => %{"model" => normalized}
      }
    }

    FakeCLI.push_message(fake_cli, response)
    assert :ok = Task.await(set_model_task, 1_000)

    follow_up = %{
      "type" => "assistant",
      "message" => %{"content" => "Now speaking as opus", "role" => "assistant"},
      "session_id" => "integration-session"
    }

    FakeCLI.push_message(fake_cli, follow_up)

    final_message = %{
      "type" => "result",
      "subtype" => "success",
      "session_id" => "integration-session",
      "total_cost_usd" => 0.002
    }

    FakeCLI.push_message(fake_cli, final_message)

    streamed = Task.await(stream_task, 1_500)

    contents =
      streamed
      |> Enum.filter(&(&1.type == :assistant))
      |> Enum.map(& &1.data[:message]["content"])

    assert contents == ["Started with sonnet", "Now speaking as opus"]
    assert {:ok, ^normalized} = Client.get_model(client)
    Task.shutdown(stream_task)
  end

  defp wait_for_stream_subscriber(client) do
    SupertesterCase.eventually(
      fn ->
        state = :sys.get_state(client)
        map_size(state.subscribers) > 0
      end,
      timeout: 500
    )

    :ok
  end
end
