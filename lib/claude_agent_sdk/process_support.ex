defmodule ClaudeAgentSDK.ProcessSupport do
  @moduledoc false

  @spec await_down(reference() | term(), pid(), non_neg_integer()) :: :down | :timeout
  def await_down(down_ref, pid, timeout_ms)
      when is_pid(pid) and is_integer(timeout_ms) and timeout_ms >= 0 do
    receive do
      {:DOWN, ^down_ref, :process, ^pid, _reason} ->
        :down
    after
      timeout_ms ->
        :timeout
    end
  end
end
