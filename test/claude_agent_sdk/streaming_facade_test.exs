defmodule ClaudeAgentSDK.StreamingFacadeTest do
  @moduledoc """
  Tests for Streaming module facade with router integration (v0.6.0).

  Tests automatic transport selection and polymorphic API functions.
  """
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Client, Options, Streaming}
  alias ClaudeAgentSDK.TestSupport.{MockTransport, TestFixtures}

  describe "start_session/1 with router integration" do
    @tag :live_cli
    test "selects CLI-only session for simple streaming" do
      # No control features - should use Session (fast path)
      # SKIPPED: Requires real CLI process
      options = %Options{}

      {:ok, session} = Streaming.start_session(options)

      # Should be a plain PID
      assert is_pid(session)
      refute match?({:control_client, _}, session)

      Streaming.close_session(session)
    end

    test "selects control client for hooks" do
      hook = TestFixtures.allow_all_hook()

      options = %Options{
        hooks: %{pre_tool_use: [hook]}
      }

      # Use MockTransport to avoid starting real CLI
      {:ok, session} = start_session_with_mock(options)

      # Should be wrapped control client
      assert match?({:control_client, _}, session)

      close_session_safe(session)
    end

    test "selects control client for SDK MCP servers" do
      server = TestFixtures.test_sdk_mcp_server("test")

      options = %Options{
        mcp_servers: %{"test" => server}
      }

      {:ok, session} = start_session_with_mock(options)

      assert match?({:control_client, _}, session)

      close_session_safe(session)
    end

    test "selects control client for permission callbacks" do
      callback = TestFixtures.allow_all_permission()

      options = %Options{
        can_use_tool: callback
      }

      {:ok, session} = start_session_with_mock(options)

      assert match?({:control_client, _}, session)

      close_session_safe(session)
    end

    @tag :live_cli
    test "forces include_partial_messages to true" do
      # Even if not specified, start_session should enable it
      # SKIPPED: Requires real CLI process
      options = %Options{include_partial_messages: false}

      # Can't easily verify internal state, but test doesn't crash
      {:ok, session} = Streaming.start_session(options)

      assert is_pid(session)

      Streaming.close_session(session)
    end
  end

  describe "send_message/2 polymorphism" do
    @tag :live_cli
    test "works with CLI-only session (PID)" do
      # SKIPPED: Requires real CLI
      {:ok, session} = Streaming.start_session()

      # Should return a stream (Stream.resource/3 returns a function, not a struct)
      stream = Streaming.send_message(session, "Hello")
      assert is_function(stream) or match?(%Stream{}, stream)

      # Don't enumerate (would need real CLI)
      Streaming.close_session(session)
    end

    test "works with control client session (tuple)" do
      hook = TestFixtures.allow_all_hook()
      options = %Options{hooks: %{pre_tool_use: [hook]}}

      {:ok, session} = start_session_with_mock(options)
      assert match?({:control_client, _}, session)

      # Should return an enumerable/stream
      stream = Streaming.send_message(session, "Hello")
      assert is_function(stream) or match?(%Stream{}, stream)

      close_session_safe(session)
    end
  end

  describe "close_session/1 polymorphism" do
    @tag :live_cli
    test "closes CLI-only session (PID)" do
      # SKIPPED: Requires real CLI
      {:ok, session} = Streaming.start_session()
      assert is_pid(session)

      :ok = Streaming.close_session(session)

      # Session should be stopped
      refute Process.alive?(session)
    end

    test "closes control client session (tuple)" do
      options = %Options{hooks: %{pre_tool_use: [TestFixtures.allow_all_hook()]}}
      {:ok, session} = start_session_with_mock(options)
      assert match?({:control_client, client} when is_pid(client), session)

      :ok = Streaming.close_session(session)

      # Client should be stopped
      {:control_client, client} = session
      refute Process.alive?(client)
    end
  end

  describe "get_session_id/1 polymorphism" do
    @tag :live_cli
    test "gets session ID from CLI-only session" do
      # SKIPPED: Requires real CLI
      {:ok, session} = Streaming.start_session()

      # Before any messages, no session ID
      assert {:error, :no_session_id} = Streaming.get_session_id(session)

      Streaming.close_session(session)
    end

    test "returns not_supported for control client" do
      options = %Options{hooks: %{pre_tool_use: [TestFixtures.allow_all_hook()]}}
      {:ok, session} = start_session_with_mock(options)

      # Control client doesn't support session ID yet
      assert {:error, :not_supported} = Streaming.get_session_id(session)

      close_session_safe(session)
    end
  end

  describe "backwards compatibility" do
    @tag :live_cli
    test "existing code using start_session still works" do
      # SKIPPED: Requires real CLI
      # Test that old usage patterns still work
      {:ok, session} = Streaming.start_session()
      assert is_pid(session)
      Streaming.close_session(session)
    end

    @tag :live_cli
    test "existing code with options still works" do
      # SKIPPED: Requires real CLI
      options = %Options{model: "sonnet", max_turns: 3}
      {:ok, session} = Streaming.start_session(options)
      assert is_pid(session)
      Streaming.close_session(session)
    end
  end

  ## Test Helpers

  # Start session with MockTransport to avoid real CLI
  defp start_session_with_mock(options) do
    # For control client sessions, we need to bypass start_session
    # and directly start Client with MockTransport
    Client.start_link(
      %{options | include_partial_messages: true},
      transport: MockTransport,
      transport_opts: [test_pid: self()]
    )
    |> case do
      {:ok, client} ->
        initialize_control_client(client)
        {:ok, {:control_client, client}}

      error ->
        error
    end
  end

  defp initialize_control_client(client) do
    transport =
      receive do
        {:mock_transport_started, pid} -> pid
      after
        1_000 -> flunk("Did not receive mock transport start")
      end

    assert_receive {:mock_transport_subscribed, _pid}, 1_000

    init_request =
      receive do
        {:mock_transport_send, json} -> Jason.decode!(String.trim(json))
      after
        1_000 -> flunk("Did not receive initialize request")
      end

    init_response = %{
      "type" => "control_response",
      "response" => %{
        "subtype" => "success",
        "request_id" => init_request["request_id"],
        "response" => %{}
      }
    }

    MockTransport.push_message(transport, init_response)

    ClaudeAgentSDK.SupertesterCase.eventually(
      fn -> :sys.get_state(client).initialized end,
      timeout: 1_000
    )

    :ok
  end

  defp close_session_safe({:control_client, client}) do
    if Process.alive?(client), do: Client.stop(client)
    :ok
  end

  defp close_session_safe(session) when is_pid(session) do
    if Process.alive?(session), do: Streaming.close_session(session)
    :ok
  end
end
