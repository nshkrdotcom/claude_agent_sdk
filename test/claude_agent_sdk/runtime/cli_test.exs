defmodule ClaudeAgentSDK.Runtime.CLITest do
  use ExUnit.Case, async: false

  alias ClaudeAgentSDK.{Options, Runtime.CLI}
  alias CliSubprocessCore.{Event, Payload}

  defp write_runtime_stub!(dir) do
    path = Path.join(dir, "claude_runtime_stub.sh")

    File.write!(path, """
    #!/usr/bin/env bash
    set -euo pipefail
    sleep 60
    """)

    File.chmod!(path, 0o755)
    path
  end

  describe "start_session/1" do
    test "builds a core session with Claude-compatible streaming invocation and env" do
      dir =
        Path.join(System.tmp_dir!(), "claude_runtime_cli_#{System.unique_integer([:positive])}")

      File.mkdir_p!(dir)
      stub_path = write_runtime_stub!(dir)
      session_ref = make_ref()

      options = %Options{
        executable: stub_path,
        model: "sonnet",
        provider_backend: :anthropic,
        max_turns: 4,
        system_prompt: "Be precise.",
        append_system_prompt: "Stay brief.",
        permission_mode: :plan,
        include_partial_messages: false,
        cwd: dir,
        env: %{"CLAUDE_RUNTIME_TEST" => "1"}
      }

      try do
        assert {:ok, session, %{info: info, projection_state: projection_state}} =
                 CLI.start_session(
                   options: options,
                   subscriber: {self(), session_ref}
                 )

        assert info.provider == :claude
        assert info.runtime.provider == :claude
        assert info.invocation.command == stub_path
        assert info.invocation.cwd == dir
        assert info.invocation.env["CLAUDE_RUNTIME_TEST"] == "1"
        assert info.invocation.env["CLAUDE_CODE_ENTRYPOINT"] == "sdk-elixir"
        assert info.invocation.env["CLAUDE_AGENT_SDK_VERSION"]
        assert info.invocation.user == nil
        assert info.transport.module == ExternalRuntimeTransport.Transport

        args = info.invocation.args

        assert "--input-format" in args
        assert "--output-format" in args
        assert "--include-partial-messages" in args
        assert "--verbose" in args
        assert "--model" in args
        assert "--max-turns" in args
        assert "--system-prompt" in args
        assert "--append-system-prompt" in args
        assert "--permission-mode" in args
        refute "--print" in args

        assert %{accumulated_text: "", session_id: nil} = projection_state

        monitor_ref = Process.monitor(session)
        assert :ok = CLI.close(session)
        assert_receive {:DOWN, ^monitor_ref, :process, ^session, :normal}, 2_000
      after
        File.rm_rf!(dir)
      end
    end
  end

  describe "project_event/2" do
    test "projects wrapped Claude stream events back into public streaming maps" do
      state = CLI.new_projection_state()

      start_wrapper = %{
        "type" => "stream_event",
        "uuid" => "evt-start",
        "session_id" => "sess-123",
        "parent_tool_use_id" => nil,
        "event" => %{
          "type" => "message_start",
          "message" => %{"model" => "sonnet", "role" => "assistant"}
        }
      }

      start_event =
        Event.new(:raw,
          provider: :claude,
          provider_session_id: "sess-123",
          raw: start_wrapper,
          payload: Payload.Raw.new(stream: :stdout, content: start_wrapper)
        )

      assert {[projected_start], state} = CLI.project_event(start_event, state)
      assert projected_start.type == :message_start
      assert projected_start.uuid == "evt-start"
      assert projected_start.session_id == "sess-123"
      assert projected_start.model == "sonnet"

      delta_wrapper = %{
        "type" => "stream_event",
        "uuid" => "evt-delta",
        "session_id" => "sess-123",
        "parent_tool_use_id" => "toolu_parent",
        "event" => %{
          "type" => "content_block_delta",
          "delta" => %{"type" => "text_delta", "text" => "Hello"}
        }
      }

      delta_event =
        Event.new(:raw,
          provider: :claude,
          provider_session_id: "sess-123",
          raw: delta_wrapper,
          payload: Payload.Raw.new(stream: :stdout, content: delta_wrapper)
        )

      assert {[projected_delta], state} = CLI.project_event(delta_event, state)
      assert projected_delta.type == :text_delta
      assert projected_delta.text == "Hello"
      assert projected_delta.accumulated == "Hello"
      assert projected_delta.uuid == "evt-delta"
      assert projected_delta.session_id == "sess-123"
      assert projected_delta.parent_tool_use_id == "toolu_parent"

      stop_wrapper = %{
        "type" => "stream_event",
        "uuid" => "evt-stop",
        "session_id" => "sess-123",
        "parent_tool_use_id" => "toolu_parent",
        "event" => %{"type" => "message_stop"}
      }

      stop_event =
        Event.new(:raw,
          provider: :claude,
          provider_session_id: "sess-123",
          raw: stop_wrapper,
          payload: Payload.Raw.new(stream: :stdout, content: stop_wrapper)
        )

      assert {[projected_stop], state} = CLI.project_event(stop_event, state)
      assert projected_stop.type == :message_stop
      assert projected_stop.final_text == "Hello"
      assert projected_stop.uuid == "evt-stop"
      assert projected_stop.session_id == "sess-123"
      assert state.accumulated_text == ""
      assert state.session_id == "sess-123"
    end
  end

  describe "session control surfaces" do
    test "capabilities publish session control support" do
      assert :session_history in CLI.capabilities()
      assert :session_resume in CLI.capabilities()
      assert :session_pause in CLI.capabilities()
      assert :session_intervene in CLI.capabilities()
    end

    test "list_provider_sessions/1 returns an empty standardized list for an empty directory" do
      dir =
        Path.join(
          System.tmp_dir!(),
          "claude_runtime_history_#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(dir)

      try do
        assert {:ok, []} = CLI.list_provider_sessions(directory: dir, include_worktrees: false)
      after
        File.rm_rf!(dir)
      end
    end
  end
end
