defmodule ClaudeAgentSDK.QueryStreamingTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Message, Options, Query}
  alias ClaudeAgentSDK.TestSupport.MockTransport

  test "streams responses while sending enumerable prompts through injected transport" do
    prompt = [
      %{
        "type" => "user",
        "message" => %{"role" => "user", "content" => "hi"}
      }
    ]

    stream = Query.run(prompt, %Options{}, {MockTransport, [test_pid: self()]})

    task = Task.async(fn -> Enum.take(stream, 1) end)

    assert_receive {:mock_transport_started, transport}, 200
    assert_receive {:mock_transport_subscribed, _pid}, 200
    assert_receive {:mock_transport_send, sent_prompt}, 200
    assert sent_prompt == hd(prompt)
    assert_receive {:mock_transport_end_input, ^transport}, 200

    assistant = %{
      "type" => "assistant",
      "message" => %{"role" => "assistant", "content" => "hello"},
      "session_id" => "sess"
    }

    MockTransport.push_message(transport, Jason.encode!(assistant))

    assert [%Message{type: :assistant}] = Task.await(task, 500)
  end
end
