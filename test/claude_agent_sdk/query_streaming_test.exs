defmodule ClaudeAgentSDK.QueryStreamingTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Errors.CLIJSONDecodeError
  alias ClaudeAgentSDK.{Message, Options, Query}
  alias ClaudeAgentSDK.Permission.Result
  alias ClaudeAgentSDK.TestSupport.FakeCLI

  test "streams responses while sending enumerable prompts through the real command lane" do
    fake_cli = FakeCLI.new!()
    on_exit(fn -> FakeCLI.cleanup(fake_cli) end)

    prompt = [
      %{
        "type" => "user",
        "message" => %{"role" => "user", "content" => "hi"}
      }
    ]

    stream = Query.run(prompt, FakeCLI.options(fake_cli, %Options{}))
    task = Task.async(fn -> Enum.take(stream, 1) end)

    assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)
    assert :ok = FakeCLI.wait_for_request_count(fake_cli, 1, 1_000)
    assert :ok = FakeCLI.wait_until_stdin_closed(fake_cli, 1_000)

    [sent_prompt] = FakeCLI.decoded_messages(fake_cli)
    assert sent_prompt == hd(prompt)

    assistant = %{
      "type" => "assistant",
      "message" => %{"role" => "assistant", "content" => "hello"},
      "session_id" => "sess"
    }

    FakeCLI.push_message(fake_cli, assistant)

    assert [%Message{type: :assistant}] = Task.await(task, 500)
  end

  test "rejects custom transport injection for CLI-only query streaming" do
    assert_raise ArgumentError,
                 ~r/custom transport injection has been removed; use execution_surface instead/,
                 fn ->
                   Query.run("hi", %Options{}, {:legacy_transport, []})
                 end
  end

  test "rejects custom transport injection for control-client query streaming" do
    callback = fn _context -> Result.allow() end

    assert_raise ArgumentError,
                 ~r/custom transport injection has been removed; use execution_surface instead/,
                 fn ->
                   Query.run("hi", %Options{can_use_tool: callback}, {:legacy_transport, []})
                 end
  end

  test "CLI-only query streaming skips non-JSON stdout lines" do
    fake_cli = FakeCLI.new!()
    on_exit(fn -> FakeCLI.cleanup(fake_cli) end)

    controller =
      Task.async(fn ->
        assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)
        assert :ok = FakeCLI.wait_for_request_count(fake_cli, 1, 1_000)
        assert :ok = FakeCLI.wait_until_stdin_closed(fake_cli, 1_000)
        FakeCLI.push_message(fake_cli, "not json")
        FakeCLI.push_message(fake_cli, %{"type" => "result", "subtype" => "success"})
      end)

    stream = Query.run("hi", FakeCLI.options(fake_cli, %Options{}))

    assert [%Message{type: :result}] = Enum.to_list(stream)

    Task.await(controller, 1_000)
  end

  test "transport_error_mode :raise raises on malformed CLI stream frames" do
    fake_cli = FakeCLI.new!()
    on_exit(fn -> FakeCLI.cleanup(fake_cli) end)

    controller =
      Task.async(fn ->
        assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)
        assert :ok = FakeCLI.wait_for_request_count(fake_cli, 1, 1_000)
        assert :ok = FakeCLI.wait_until_stdin_closed(fake_cli, 1_000)
        FakeCLI.push_message(fake_cli, "[1]")
      end)

    stream = Query.run("hi", FakeCLI.options(fake_cli, %Options{transport_error_mode: :raise}))

    assert_raise CLIJSONDecodeError, fn ->
      Enum.to_list(stream)
    end

    Task.await(controller, 1_000)
  end

  test "transport_error_mode :raise raises on malformed control-client frames" do
    fake_cli = FakeCLI.new!()
    on_exit(fn -> FakeCLI.cleanup(fake_cli) end)

    callback = fn _context -> Result.allow() end

    controller =
      Task.async(fn ->
        assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)
        {:ok, init_request} = FakeCLI.initialize_request(fake_cli)

        FakeCLI.push_message(fake_cli, %{
          "type" => "control_response",
          "response" => %{
            "subtype" => "success",
            "request_id" => init_request["request_id"],
            "response" => %{}
          }
        })

        assert :ok = FakeCLI.wait_for_request_count(fake_cli, 2, 1_000)
        FakeCLI.push_message(fake_cli, "[1]")
      end)

    stream =
      Query.run(
        "hi",
        FakeCLI.options(fake_cli, %Options{
          can_use_tool: callback,
          transport_error_mode: :raise
        })
      )

    assert_raise CLIJSONDecodeError, fn ->
      Enum.to_list(stream)
    end

    Task.await(controller, 1_000)
  end
end
