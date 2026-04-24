defmodule ClaudeAgentSDK.ProcessJSONDecodeErrorTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Errors.CLIJSONDecodeError
  alias ClaudeAgentSDK.{Message, Options, Process}

  test "non-JSON stdout lines are skipped before parsing JSON frames" do
    output = """
    this is not json
    {"type":"result","subtype":"success","session_id":"s","result":"ok","is_error":false}
    """

    [msg] = Process.__parse_output__(output)

    assert %Message{type: :result, subtype: :success, data: data} = msg
    assert data.result == "ok"
  end

  test "oversized JSON lines yield a buffer overflow JSON decode error" do
    output = "{" <> String.duplicate("a", 20) <> "\n"
    options = %Options{max_buffer_size: 10}

    [msg] = Process.__parse_output__(output, options)

    assert %Message{type: :result, subtype: :error_during_execution, data: data} = msg
    assert data.is_error == true
    assert %CLIJSONDecodeError{message: message} = data.error_struct
    assert message =~ "maximum buffer size"
  end
end
