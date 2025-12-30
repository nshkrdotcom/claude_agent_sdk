defmodule ClaudeAgentSDK.ProcessJSONDecodeErrorTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Errors.CLIJSONDecodeError
  alias ClaudeAgentSDK.{Message, Options, Process}

  test "non-JSON output yields a structured JSON decode error result" do
    [msg] = Process.__parse_output__("this is not json\n")

    assert %Message{type: :result, subtype: :error_during_execution, data: data} = msg
    assert data.is_error == true
    assert %CLIJSONDecodeError{line: "this is not json"} = data.error_struct
  end

  test "oversized JSON lines yield a buffer overflow JSON decode error" do
    output = String.duplicate("a", 20) <> "\n"
    options = %Options{max_buffer_size: 10}

    [msg] = Process.__parse_output__(output, options)

    assert %Message{type: :result, subtype: :error_during_execution, data: data} = msg
    assert data.is_error == true
    assert %CLIJSONDecodeError{message: message} = data.error_struct
    assert message =~ "maximum buffer size"
  end
end
