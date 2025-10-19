defmodule Integration.ModelSwitchingLiveTest do
  use ClaudeAgentSDK.SupertesterCase, isolation: :basic

  alias ClaudeAgentSDK.{Client, Options, Model}
  alias ClaudeAgentSDK.TestSupport.MockTransport

  @moduletag :integration

  test "should preserve context when switching models" do
    {:ok, client} =
      Client.start_link(%Options{model: "claude-sonnet-4"},
        transport: MockTransport,
        transport_opts: [test_pid: self()]
      )

    on_exit(fn ->
      try do
        Client.stop(client)
      catch
        :exit, _ -> :ok
      end
    end)

    assert_receive {:mock_transport_started, transport_pid}, 200
    assert_receive {:mock_transport_send, _init_json}, 200

    stream_task =
      Task.async(fn ->
        Client.stream_messages(client)
        |> Enum.take(3)
      end)

    initial_message = %{
      "type" => "assistant",
      "message" => %{"content" => "Started with sonnet", "role" => "assistant"},
      "session_id" => "integration-session"
    }

    MockTransport.push_message(transport_pid, Jason.encode!(initial_message))

    set_model_task = Task.async(fn -> Client.set_model(client, "opus") end)

    assert_receive {:mock_transport_send, set_model_json}, 200
    decoded = Jason.decode!(set_model_json)
    assert decoded["request"]["subtype"] == "set_model"
    request_id = decoded["request_id"]

    {:ok, normalized} = Model.validate("opus")

    response = %{
      "type" => "control_response",
      "response" => %{
        "request_id" => request_id,
        "subtype" => "success",
        "result" => %{"model" => normalized}
      }
    }

    MockTransport.push_message(transport_pid, Jason.encode!(response))
    assert :ok = Task.await(set_model_task, 1_000)

    follow_up = %{
      "type" => "assistant",
      "message" => %{"content" => "Now speaking as opus", "role" => "assistant"},
      "session_id" => "integration-session"
    }

    MockTransport.push_message(transport_pid, Jason.encode!(follow_up))

    final_message = %{
      "type" => "result",
      "subtype" => "success",
      "session_id" => "integration-session",
      "total_cost_usd" => 0.002
    }

    MockTransport.push_message(transport_pid, Jason.encode!(final_message))

    messages =
      SupertesterCase.eventually(fn -> Task.yield(stream_task, 25) end,
        timeout: 1_500
      )

    assert {:ok, streamed} = messages

    contents =
      streamed
      |> Enum.filter(&(&1.type == :assistant))
      |> Enum.map(& &1.data[:message]["content"])

    assert contents == ["Started with sonnet", "Now speaking as opus"]
    assert {:ok, ^normalized} = Client.get_model(client)
    Task.shutdown(stream_task)
  end
end
