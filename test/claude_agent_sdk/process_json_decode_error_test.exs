defmodule ClaudeAgentSDK.ProcessJSONDecodeErrorTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Errors.CLIJSONDecodeError
  alias ClaudeAgentSDK.{Message, Process}

  test "non-JSON output yields a structured JSON decode error result" do
    [msg] = Process.__parse_output__("this is not json\n")

    assert %Message{type: :result, subtype: :error_during_execution, data: data} = msg
    assert data.is_error == true
    assert %CLIJSONDecodeError{line: "this is not json"} = data.error_struct
  end
end
