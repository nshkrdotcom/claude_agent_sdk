defmodule ClaudeAgentSDK.Config.TimeoutsTest do
  use ExUnit.Case, async: false

  alias ClaudeAgentSDK.Config.Timeouts

  setup do
    original = Application.get_env(:claude_agent_sdk, Timeouts)
    on_exit(fn -> restore(original) end)
    :ok
  end

  defp restore(nil), do: Application.delete_env(:claude_agent_sdk, Timeouts)
  defp restore(val), do: Application.put_env(:claude_agent_sdk, Timeouts, val)

  describe "defaults" do
    test "client_init_ms" do
      assert Timeouts.client_init_ms() == 60_000
    end

    test "client_hook_ms" do
      assert Timeouts.client_hook_ms() == 60_000
    end

    test "client_control_request_ms" do
      assert Timeouts.client_control_request_ms() == 60_000
    end

    test "client_stop_ms" do
      assert Timeouts.client_stop_ms() == 5_000
    end

    test "client_exit_wait_ms" do
      assert Timeouts.client_exit_wait_ms() == 200
    end

    test "client_permission_yield_ms" do
      assert Timeouts.client_permission_yield_ms() == 60_000
    end

    test "streaming_session_ms" do
      assert Timeouts.streaming_session_ms() == 300_000
    end

    test "stream_receive_ms" do
      assert Timeouts.stream_receive_ms() == 30_000
    end

    test "query_total_ms" do
      assert Timeouts.query_total_ms() == 4_500_000
    end

    test "query_parallel_ms" do
      assert Timeouts.query_parallel_ms() == 300_000
    end

    test "transport_call_ms" do
      assert Timeouts.transport_call_ms() == 5_000
    end

    test "transport_force_close_ms" do
      assert Timeouts.transport_force_close_ms() == 500
    end

    test "transport_headless_ms" do
      assert Timeouts.transport_headless_ms() == 5_000
    end

    test "transport_finalize_ms" do
      assert Timeouts.transport_finalize_ms() == 25
    end

    test "client_close_grace_ms" do
      assert Timeouts.client_close_grace_ms() == 2_000
    end

    test "transport_close_grace_ms" do
      assert Timeouts.transport_close_grace_ms() == 2_000
    end

    test "auth_ensure_ms" do
      assert Timeouts.auth_ensure_ms() == 30_000
    end

    test "auth_setup_token_ms" do
      assert Timeouts.auth_setup_token_ms() == 120_000
    end

    test "auth_refresh_token_ms" do
      assert Timeouts.auth_refresh_token_ms() == 120_000
    end

    test "auth_refresh_retry_ms" do
      assert Timeouts.auth_refresh_retry_ms() == 3_600_000
    end

    test "auth_refresh_before_expiry_ms" do
      assert Timeouts.auth_refresh_before_expiry_ms() == 86_400_000
    end

    test "auth_min_refresh_delay_ms" do
      assert Timeouts.auth_min_refresh_delay_ms() == 60_000
    end

    test "auth_cli_test_ms" do
      assert Timeouts.auth_cli_test_ms() == 30_000
    end

    test "auth_cli_version_ms" do
      assert Timeouts.auth_cli_version_ms() == 10_000
    end

    test "tool_execution_ms" do
      assert Timeouts.tool_execution_ms() == 30_000
    end

    test "hook_min_ms" do
      assert Timeouts.hook_min_ms() == 1_000
    end

    test "session_cleanup_interval_ms" do
      assert Timeouts.session_cleanup_interval_ms() == 86_400_000
    end

    test "orchestrator_backoff_ms" do
      assert Timeouts.orchestrator_backoff_ms() == 1_000
    end

    test "ms_per_hour" do
      assert Timeouts.ms_per_hour() == 3_600_000
    end

    test "seconds_per_day" do
      assert Timeouts.seconds_per_day() == 86_400
    end
  end

  describe "runtime override" do
    test "overrides client_init_ms" do
      Application.put_env(:claude_agent_sdk, Timeouts, client_init_ms: 90_000)
      assert Timeouts.client_init_ms() == 90_000
    end

    test "overrides query_total_ms" do
      Application.put_env(:claude_agent_sdk, Timeouts, query_total_ms: 5_400_000)
      assert Timeouts.query_total_ms() == 5_400_000
    end

    test "non-overridden keys keep defaults" do
      Application.put_env(:claude_agent_sdk, Timeouts, client_init_ms: 90_000)
      assert Timeouts.stream_receive_ms() == 30_000
    end
  end
end
