defmodule ClaudeAgentSDK.QueryControlTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.Hooks.Matcher
  alias ClaudeAgentSDK.{Options, Query}

  defmodule StubClientStream do
    def stream(prompt, options) do
      send(self(), {:client_stream_invoked, prompt, options})
      [:client_stream]
    end
  end

  defmodule StubProcess do
    def stream(args, options, stdin_prompt) do
      send(self(), {:process_stream_invoked, args, options, stdin_prompt})
      [:process_stream]
    end
  end

  defp restore_env(key, original) do
    if is_nil(original) do
      Application.delete_env(:claude_agent_sdk, key)
    else
      Application.put_env(:claude_agent_sdk, key, original)
    end
  end

  describe "control routing for query/2" do
    setup do
      original_client = Application.get_env(:claude_agent_sdk, :client_stream_module)
      original_process = Application.get_env(:claude_agent_sdk, :process_module)

      Application.put_env(:claude_agent_sdk, :client_stream_module, StubClientStream)
      Application.put_env(:claude_agent_sdk, :process_module, StubProcess)

      on_exit(fn ->
        restore_env(:client_stream_module, original_client)
        restore_env(:process_module, original_process)
      end)

      :ok
    end

    test "routes to control client when hooks are configured" do
      hook = fn _input, _tool_use_id, _context -> %{} end
      options = %Options{hooks: %{pre_tool_use: [Matcher.new("Bash", [hook])]}}

      assert [:client_stream] = Query.run("build", options) |> Enum.to_list()

      assert_received {:client_stream_invoked, "build", ^options}
      refute_received {:process_stream_invoked, _, _, _}
    end

    test "routes to process stream when no control features are present" do
      options = %Options{}

      assert [:process_stream] = Query.run("hello", options) |> Enum.to_list()

      assert_received {:process_stream_invoked, _args, ^options, "hello"}
      refute_received {:client_stream_invoked, _, _, _}
    end
  end
end
