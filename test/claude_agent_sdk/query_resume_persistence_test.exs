defmodule ClaudeAgentSDK.QueryResumePersistenceTest do
  use ExUnit.Case, async: false

  alias ClaudeAgentSDK.{Options, Query}

  defmodule CaptureCLIStream do
    def stream_args(args, options, transport \\ nil, input \\ nil) do
      send(self(), {:cli_stream_args_invoked, args, options, transport, input})
      [:stubbed_stream]
    end
  end

  defp restore_env(key, original) do
    if is_nil(original) do
      Application.delete_env(:claude_agent_sdk, key)
    else
      Application.put_env(:claude_agent_sdk, key, original)
    end
  end

  setup do
    original_cli_stream = Application.get_env(:claude_agent_sdk, :cli_stream_module)
    Application.put_env(:claude_agent_sdk, :cli_stream_module, CaptureCLIStream)

    on_exit(fn ->
      restore_env(:cli_stream_module, original_cli_stream)
    end)

    :ok
  end

  test "resume with prompt avoids one-shot --print mode so intermediate turns are not lost" do
    assert [:stubbed_stream] ==
             Query.resume("session-123", "turn 2", %Options{})
             |> Enum.to_list()

    assert_receive {:cli_stream_args_invoked, args, %Options{}, nil, input}
    assert "--resume" in args
    assert "session-123" in args
    assert "--input-format" in args
    assert "stream-json" in args
    assert is_list(input)
    assert length(input) == 1
    assert hd(input)["session_id"] == "session-123"
    assert hd(input)["message"]["content"] == "turn 2"

    # Regression guard:
    # Using --print with --resume is one-shot and loses intermediate turns in session history.
    refute "--print" in args
  end
end
