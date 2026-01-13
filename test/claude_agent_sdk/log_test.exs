defmodule ClaudeAgentSDK.LogTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  setup do
    previous_level = Application.get_env(:claude_agent_sdk, :log_level)
    previous_logger_level = Logger.level()

    on_exit(fn ->
      case previous_level do
        nil -> Application.delete_env(:claude_agent_sdk, :log_level)
        _ -> Application.put_env(:claude_agent_sdk, :log_level, previous_level)
      end

      Logger.configure(level: previous_logger_level)
    end)

    :ok
  end

  test "filters logs below the sdk log_level" do
    Logger.configure(level: :debug)
    Application.put_env(:claude_agent_sdk, :log_level, :warning)

    assert capture_log(fn ->
             ClaudeAgentSDK.Log.info("quiet")
           end) == ""

    assert capture_log(fn ->
             ClaudeAgentSDK.Log.error("loud")
           end) =~ "loud"
  end

  test "allows debug logs when configured" do
    Logger.configure(level: :debug)
    Application.put_env(:claude_agent_sdk, :log_level, :debug)

    log =
      capture_log(fn ->
        ClaudeAgentSDK.Log.debug("details")
      end)

    assert log =~ "details"
  end
end
