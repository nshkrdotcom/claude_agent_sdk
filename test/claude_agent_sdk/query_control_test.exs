defmodule ClaudeAgentSDK.QueryControlTest do
  use ExUnit.Case, async: false

  alias ClaudeAgentSDK.Hooks.Matcher
  alias ClaudeAgentSDK.{Options, Query}

  defmodule StubClientStream do
    def stream(prompt, options, transport \\ nil) do
      send(self(), {:client_stream_invoked, prompt, options, transport})
      [:client_stream]
    end
  end

  defmodule StubCLIStream do
    def stream(prompt, options, transport \\ nil) do
      send(self(), {:cli_stream_invoked, prompt, options, transport})
      [:cli_stream]
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
    original_client = Application.get_env(:claude_agent_sdk, :client_stream_module)
    original_cli_stream = Application.get_env(:claude_agent_sdk, :cli_stream_module)
    original_process = Application.get_env(:claude_agent_sdk, :process_module)

    Application.put_env(:claude_agent_sdk, :client_stream_module, StubClientStream)
    Application.put_env(:claude_agent_sdk, :cli_stream_module, StubCLIStream)

    on_exit(fn ->
      restore_env(:client_stream_module, original_client)
      restore_env(:cli_stream_module, original_cli_stream)
      restore_env(:process_module, original_process)
    end)

    :ok
  end

  describe "control routing for query/2" do
    test "routes to control client when hooks are configured" do
      hook = fn _input, _tool_use_id, _context -> %{} end
      options = %Options{hooks: %{pre_tool_use: [Matcher.new("Bash", [hook])]}}

      assert [:client_stream] = Query.run("build", options) |> Enum.to_list()

      assert_received {:client_stream_invoked, "build", ^options, nil}
      refute_received {:cli_stream_invoked, _, _, _}
    end

    test "routes to CLI stream when no control features are present" do
      options = %Options{}

      assert [:cli_stream] = Query.run("hello", options) |> Enum.to_list()

      assert_received {:cli_stream_invoked, "hello", ^options, nil}
      refute_received {:client_stream_invoked, _, _, _}
    end
  end

  describe "can_use_tool validation" do
    test "routes to client stream when can_use_tool is used with string prompt" do
      callback = fn _ -> :ok end
      options = %Options{can_use_tool: callback}

      # String prompts with can_use_tool now route to client stream (control protocol)
      assert [:client_stream] = Query.run("hello", options) |> Enum.to_list()

      # Verify can_use_tool triggers control client routing
      assert_received {:client_stream_invoked, "hello", received_options, nil}
      assert received_options.permission_prompt_tool == "stdio"
    end

    test "raises when can_use_tool and permission_prompt_tool are both set" do
      options = %Options{can_use_tool: fn _ -> :ok end, permission_prompt_tool: "stdio"}

      assert_raise ArgumentError, fn ->
        Query.run([%{"type" => "user"}], options) |> Enum.to_list()
      end
    end

    test "auto-sets permission_prompt_tool for streaming prompts" do
      callback = fn _ -> :ok end
      options = %Options{can_use_tool: callback}
      prompt = [%{"type" => "user", "message" => %{"role" => "user", "content" => "hi"}}]

      assert [:client_stream] = Query.run(prompt, options) |> Enum.to_list()

      assert_received {:client_stream_invoked, ^prompt, updated, nil}
      assert updated.permission_prompt_tool == "stdio"
    end
  end
end
