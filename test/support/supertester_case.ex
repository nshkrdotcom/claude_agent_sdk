defmodule ClaudeAgentSDK.SupertesterCase do
  @moduledoc """
  Shared test foundation leveraging Supertester utilities for deterministic OTP testing.
  """

  use ExUnit.CaseTemplate

  using opts do
    isolation = Keyword.get(opts, :isolation, :basic)

    quote do
      use Supertester.UnifiedTestFoundation, isolation: unquote(isolation)

      import Supertester.OTPHelpers
      import Supertester.GenServerHelpers
      import Supertester.Assertions
      import Supertester.SupervisorHelpers
      import Supertester.PerformanceHelpers
      import Supertester.ChaosHelpers

      alias ClaudeAgentSDK.SupertesterCase
    end
  end

  setup context do
    {:ok, Map.put_new(context, :supertester, %{})}
  end

  @doc """
  Convenience helper that retries the supplied function until it returns a truthy value.
  """
  @spec eventually((-> any()), keyword()) :: any()
  def eventually(fun, opts \\ []) when is_function(fun, 0) do
    timeout = Keyword.get(opts, :timeout, 1_000)
    interval = Keyword.get(opts, :interval, 25)
    deadline = System.monotonic_time(:millisecond) + timeout

    do_eventually(fun, interval, deadline)
  end

  defp do_eventually(fun, interval, deadline) do
    case fun.() do
      result when result in [false, nil] ->
        if System.monotonic_time(:millisecond) >= deadline do
          flunk("eventually/2 timed out after #{deadline} ms")
        else
          Process.sleep(interval)
          do_eventually(fun, interval, deadline)
        end

      result ->
        result
    end
  end
end
