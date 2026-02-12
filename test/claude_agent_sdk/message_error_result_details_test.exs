defmodule ClaudeAgentSDK.MessageErrorResultDetailsTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Errors.ProcessError
  alias ClaudeAgentSDK.Message

  describe "error_result/2 details" do
    test "includes machine-readable details for ProcessError structs" do
      error_struct = %ProcessError{
        message: "Process exited with code 2",
        exit_code: 2,
        stderr: "fatal: config missing"
      }

      message = Message.error_result("Process failed", error_struct: error_struct)

      assert message.type == :result
      assert message.subtype == :error_during_execution
      assert message.data.error == "Process failed"
      assert message.data.error_struct == error_struct

      assert message.data.error_details == %{
               kind: :process_error,
               exit_code: 2,
               stderr: "fatal: config missing"
             }
    end

    test "uses explicit error_details when provided" do
      message =
        Message.error_result("Failed",
          error_details: %{kind: :custom, code: "E42", stderr: "boom"}
        )

      assert message.data.error == "Failed"
      assert message.data.error_details == %{kind: :custom, code: "E42", stderr: "boom"}
      refute Map.has_key?(message.data, :error_struct)
    end
  end
end
