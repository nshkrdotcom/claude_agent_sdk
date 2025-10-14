defmodule ClaudeAgentSDK.MockTest do
  use ExUnit.Case

  alias ClaudeAgentSDK.Mock

  describe "Mock server" do
    setup do
      Mock.clear_responses()
      :ok
    end

    test "set_response/2 and get_response/1" do
      Mock.set_response("hello", [
        %{"type" => "assistant", "message" => %{"content" => "Hi there!"}}
      ])

      response = Mock.get_response("say hello")
      assert length(response) == 1
      assert hd(response)["type"] == "assistant"
    end

    test "returns default response for unmatched prompts" do
      # Clear any custom default set by other tests
      Mock.clear_responses()

      # Get response directly from mock
      response = Mock.get_response("random prompt")
      assert length(response) == 3
      assert Enum.any?(response, &(&1["type"] == "system"))
      assert Enum.any?(response, &(&1["type"] == "assistant"))
      assert Enum.any?(response, &(&1["type"] == "result"))
    end

    test "set_default_response/1" do
      custom_default = [
        %{"type" => "assistant", "message" => %{"content" => "Custom default"}}
      ]

      Mock.set_default_response(custom_default)
      response = Mock.get_response("anything")

      assert length(response) == 1
      assert hd(response)["message"]["content"] == "Custom default"
    end

    test "pattern matching works with contains" do
      Mock.set_response("code review", [
        %{"type" => "assistant", "message" => %{"content" => "Reviewing code..."}}
      ])

      response = Mock.get_response("Please do a code review of this file")
      assert hd(response)["message"]["content"] == "Reviewing code..."
    end
  end
end
