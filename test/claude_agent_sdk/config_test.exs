defmodule ClaudeAgentSDK.ConfigTest do
  use ExUnit.Case, async: false

  alias ClaudeAgentSDK.Config

  test "use_mock?/0 reads application config with false default" do
    original = Application.get_env(:claude_agent_sdk, :use_mock)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:claude_agent_sdk, :use_mock)
      else
        Application.put_env(:claude_agent_sdk, :use_mock, original)
      end
    end)

    Application.delete_env(:claude_agent_sdk, :use_mock)
    refute Config.use_mock?()

    Application.put_env(:claude_agent_sdk, :use_mock, true)
    assert Config.use_mock?()
  end

  test "cli_stream_module/0 prefers cli_stream_module and falls back to process_module" do
    original_cli = Application.get_env(:claude_agent_sdk, :cli_stream_module)
    original_process = Application.get_env(:claude_agent_sdk, :process_module)

    on_exit(fn ->
      restore_env(:cli_stream_module, original_cli)
      restore_env(:process_module, original_process)
    end)

    Application.put_env(:claude_agent_sdk, :cli_stream_module, Foo.CLI)
    Application.put_env(:claude_agent_sdk, :process_module, Foo.Process)
    assert Config.cli_stream_module() == Foo.CLI

    Application.delete_env(:claude_agent_sdk, :cli_stream_module)
    assert Config.cli_stream_module() == Foo.Process

    Application.delete_env(:claude_agent_sdk, :process_module)
    assert Config.cli_stream_module() == ClaudeAgentSDK.Query.CLIStream
  end

  defp restore_env(key, nil), do: Application.delete_env(:claude_agent_sdk, key)
  defp restore_env(key, value), do: Application.put_env(:claude_agent_sdk, key, value)
end
