defmodule ClaudeAgentSDK.Streaming.SessionTimeoutTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.Options
  alias ClaudeAgentSDK.Streaming.Session

  test "session timeout reflects options.timeout_ms when configured" do
    {:ok, session} = Session.start_link(%Options{timeout_ms: 1_234}, mock_stream: true)
    assert 1_234 = GenServer.call(session, :timeout_ms)
    :ok = Session.close(session)
  end

  test "session timeout falls back to default when timeout_ms is not set" do
    {:ok, session} = Session.start_link(%Options{}, mock_stream: true)
    assert 300_000 = GenServer.call(session, :timeout_ms)
    :ok = Session.close(session)
  end

  test "send_message stream timeout uses session timeout from options" do
    {:ok, session} = Session.start_link(%Options{timeout_ms: 75}, mock_stream: true)

    started_ms = System.monotonic_time(:millisecond)
    events = Session.send_message(session, "hello") |> Enum.to_list()
    elapsed_ms = System.monotonic_time(:millisecond) - started_ms

    assert [%{type: :error, error: :timeout}] = events
    assert elapsed_ms >= 50
    assert elapsed_ms < 1_000

    :ok = Session.close(session)
  end
end
