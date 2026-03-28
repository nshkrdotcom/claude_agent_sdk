defmodule ClaudeAgentSDK.ClientQueryTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Client, Options}
  alias ClaudeAgentSDK.TestSupport.FakeCLI

  test "query/3 injects session_id and parent_tool_use_id for string prompts" do
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
    assert {:ok, init_request_id} = Client.await_init_sent(client, 1_000)
    assert :ok = FakeCLI.wait_for_request_count(fake_cli, 1, 1_000)

    init_response = %{
      "type" => "control_response",
      "response" => %{
        "subtype" => "success",
        "request_id" => init_request_id,
        "response" => %{}
      }
    }

    FakeCLI.push_message(fake_cli, init_response)

    assert :ok = Client.query(client, "Hello", "my_session")

    assert :ok = FakeCLI.wait_for_request_count(fake_cli, 2, 1_000)
    [_init_json, msg_json | _] = FakeCLI.recorded_messages(fake_cli)
    decoded = Jason.decode!(String.trim(msg_json))

    assert decoded["type"] == "user"
    assert decoded["session_id"] == "my_session"
    assert decoded["parent_tool_use_id"] == nil
    assert decoded["message"]["role"] == "user"
    assert decoded["message"]["content"] == "Hello"
  end

  test "query/3 injects session_id into message maps when missing" do
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
    assert {:ok, init_request_id} = Client.await_init_sent(client, 1_000)
    assert :ok = FakeCLI.wait_for_request_count(fake_cli, 1, 1_000)

    init_response = %{
      "type" => "control_response",
      "response" => %{
        "subtype" => "success",
        "request_id" => init_request_id,
        "response" => %{}
      }
    }

    FakeCLI.push_message(fake_cli, init_response)

    msgs = [
      %{
        "type" => "user",
        "message" => %{"role" => "user", "content" => "Hello from map"},
        "parent_tool_use_id" => nil
      }
    ]

    assert :ok = Client.query(client, msgs, "my_session")

    assert :ok = FakeCLI.wait_for_request_count(fake_cli, 2, 1_000)
    [_init_json, msg_json | _] = FakeCLI.recorded_messages(fake_cli)
    decoded = Jason.decode!(String.trim(msg_json))

    assert decoded["session_id"] == "my_session"
    assert decoded["message"]["content"] == "Hello from map"
  end
end
