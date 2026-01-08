defmodule ResearchAgent.TranscriptLoggerTest do
  use ExUnit.Case, async: true

  alias ResearchAgent.TranscriptLogger

  @output_dir System.tmp_dir!()

  describe "start_link/1" do
    test "starts the logger process" do
      {:ok, pid} =
        TranscriptLogger.start_link(output_dir: @output_dir, session_id: "test_session_1")

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "creates the output directory if it doesn't exist" do
      new_dir = Path.join(@output_dir, "transcript_test_#{System.unique_integer([:positive])}")
      {:ok, pid} = TranscriptLogger.start_link(output_dir: new_dir, session_id: "test_session_2")
      assert File.dir?(new_dir)
      GenServer.stop(pid)
      File.rm_rf!(new_dir)
    end
  end

  describe "log_event/3" do
    setup do
      session_id = "session_#{System.unique_integer([:positive])}"
      {:ok, pid} = TranscriptLogger.start_link(output_dir: @output_dir, session_id: session_id)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      %{logger: pid, session_id: session_id}
    end

    test "logs an event to the transcript", %{logger: logger} do
      event = %{type: :user_message, content: "Research AI safety"}
      :ok = TranscriptLogger.log_event(logger, :user_input, event)

      # Give the GenServer time to write
      Process.sleep(50)

      events = TranscriptLogger.get_events(logger)
      assert length(events) == 1
      assert hd(events).event_type == :user_input
    end

    test "logs multiple events in order", %{logger: logger} do
      :ok = TranscriptLogger.log_event(logger, :user_input, %{content: "First"})
      :ok = TranscriptLogger.log_event(logger, :agent_response, %{content: "Second"})
      :ok = TranscriptLogger.log_event(logger, :tool_call, %{tool: "WebSearch"})

      Process.sleep(50)

      events = TranscriptLogger.get_events(logger)
      assert length(events) == 3
      assert Enum.map(events, & &1.event_type) == [:user_input, :agent_response, :tool_call]
    end

    test "includes timestamp with each event", %{logger: logger} do
      :ok = TranscriptLogger.log_event(logger, :test_event, %{data: "test"})

      Process.sleep(50)

      [event] = TranscriptLogger.get_events(logger)
      assert event.timestamp != nil
      assert is_binary(event.timestamp)
    end
  end

  describe "save_transcript/1" do
    setup do
      session_id = "save_session_#{System.unique_integer([:positive])}"
      {:ok, pid} = TranscriptLogger.start_link(output_dir: @output_dir, session_id: session_id)

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      %{logger: pid, session_id: session_id}
    end

    test "saves the transcript to a JSON file", %{logger: logger, session_id: session_id} do
      :ok = TranscriptLogger.log_event(logger, :research_start, %{topic: "AI"})
      :ok = TranscriptLogger.log_event(logger, :agent_spawn, %{role: "researcher"})

      {:ok, path} = TranscriptLogger.save_transcript(logger)

      assert File.exists?(path)
      assert String.contains?(path, session_id)

      content = File.read!(path)
      {:ok, decoded} = Jason.decode(content)
      assert length(decoded["events"]) == 2
      assert decoded["session_id"] == session_id

      # Cleanup
      File.rm(path)
    end
  end

  describe "get_summary/1" do
    setup do
      session_id = "summary_session_#{System.unique_integer([:positive])}"
      {:ok, pid} = TranscriptLogger.start_link(output_dir: @output_dir, session_id: session_id)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      %{logger: pid, session_id: session_id}
    end

    test "returns event counts by type", %{logger: logger} do
      :ok = TranscriptLogger.log_event(logger, :tool_call, %{tool: "WebSearch"})
      :ok = TranscriptLogger.log_event(logger, :tool_call, %{tool: "Read"})
      :ok = TranscriptLogger.log_event(logger, :agent_response, %{content: "Done"})

      Process.sleep(50)

      summary = TranscriptLogger.get_summary(logger)
      assert summary.event_count == 3
      assert summary.by_type[:tool_call] == 2
      assert summary.by_type[:agent_response] == 1
    end
  end
end
