defmodule ClaudeAgentSDK.ClientInitTimeoutEnvTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Client, Options}
  alias ClaudeAgentSDK.TestSupport.MockTransport

  setup do
    Process.flag(:trap_exit, true)
    original = System.get_env("CLAUDE_CODE_STREAM_CLOSE_TIMEOUT")

    on_exit(fn ->
      case original do
        nil -> System.delete_env("CLAUDE_CODE_STREAM_CLOSE_TIMEOUT")
        value -> System.put_env("CLAUDE_CODE_STREAM_CLOSE_TIMEOUT", value)
      end
    end)

    :ok
  end

  describe "init_timeout_seconds_from_env/0" do
    test "defaults to 60s when env is missing" do
      System.delete_env("CLAUDE_CODE_STREAM_CLOSE_TIMEOUT")
      assert Client.init_timeout_seconds_from_env() == 60
    end

    test "floors small or invalid values to 60s" do
      System.put_env("CLAUDE_CODE_STREAM_CLOSE_TIMEOUT", "1000")
      assert Client.init_timeout_seconds_from_env() == 60

      System.put_env("CLAUDE_CODE_STREAM_CLOSE_TIMEOUT", "not-a-number")
      assert Client.init_timeout_seconds_from_env() == 60
    end

    test "parses milliseconds into seconds" do
      System.put_env("CLAUDE_CODE_STREAM_CLOSE_TIMEOUT", "120000")
      assert Client.init_timeout_seconds_from_env() == 120

      System.put_env("CLAUDE_CODE_STREAM_CLOSE_TIMEOUT", "61500")
      assert Client.init_timeout_seconds_from_env() == 61.5
    end
  end

  describe "initialize control wait timeout" do
    test "uses env-derived timeout when waiting for initialize response" do
      System.put_env("CLAUDE_CODE_STREAM_CLOSE_TIMEOUT", "120000")

      {:ok, client} =
        Client.start_link(%Options{},
          transport: MockTransport,
          transport_opts: [test_pid: self()]
        )

      on_exit(fn -> safe_stop(client) end)

      assert_receive {:mock_transport_started, _transport}, 1_000
      assert {:ok, _request_id} = Client.await_init_sent(client, 1_000)
      assert_receive {:mock_transport_send, _init_json}, 1_000

      state = :sys.get_state(client)

      assert state.init_timeout_ms == 120_000
      assert is_reference(state.init_timeout_ref)
      assert is_binary(state.init_request_id)

      remaining = Process.read_timer(state.init_timeout_ref)
      assert is_integer(remaining)
      assert remaining <= 120_000
      assert remaining > 0
    end
  end

  defp safe_stop(pid) when is_pid(pid) do
    Client.stop(pid)
  catch
    :exit, _ -> :ok
  end
end
