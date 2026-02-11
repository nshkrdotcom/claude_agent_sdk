defmodule ClaudeAgentSDK.Config.BuffersTest do
  use ExUnit.Case, async: false

  alias ClaudeAgentSDK.Config.Buffers

  setup do
    original = Application.get_env(:claude_agent_sdk, Buffers)
    on_exit(fn -> restore(original) end)
    :ok
  end

  defp restore(nil), do: Application.delete_env(:claude_agent_sdk, Buffers)
  defp restore(val), do: Application.put_env(:claude_agent_sdk, Buffers, val)

  describe "defaults" do
    test "max_stdout_buffer_bytes" do
      assert Buffers.max_stdout_buffer_bytes() == 1_048_576
    end

    test "max_stderr_buffer_bytes" do
      assert Buffers.max_stderr_buffer_bytes() == 262_144
    end

    test "max_lines_per_batch" do
      assert Buffers.max_lines_per_batch() == 200
    end

    test "stream_buffer_limit" do
      assert Buffers.stream_buffer_limit() == 1_000
    end

    test "error_preview_length" do
      assert Buffers.error_preview_length() == 100
    end

    test "message_trim_length" do
      assert Buffers.message_trim_length() == 300
    end

    test "error_truncation_length" do
      assert Buffers.error_truncation_length() == 1_000
    end

    test "summary_max_length" do
      assert Buffers.summary_max_length() == 100
    end
  end

  describe "runtime override" do
    test "overrides max_stdout_buffer_bytes" do
      Application.put_env(:claude_agent_sdk, Buffers, max_stdout_buffer_bytes: 2_097_152)

      assert Buffers.max_stdout_buffer_bytes() == 2_097_152
    end

    test "non-overridden keys keep defaults" do
      Application.put_env(:claude_agent_sdk, Buffers, max_stdout_buffer_bytes: 2_097_152)

      assert Buffers.stream_buffer_limit() == 1_000
    end
  end
end
