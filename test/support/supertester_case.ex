defmodule ClaudeAgentSDK.SupertesterCase do
  @moduledoc """
  Shared test foundation leveraging Supertester utilities for deterministic OTP testing.
  """

  use ExUnit.CaseTemplate

  using opts do
    isolation = Keyword.get(opts, :isolation, :basic)

    quote do
      use Supertester.ExUnitFoundation, isolation: unquote(isolation)

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
    start = System.monotonic_time(:millisecond)
    deadline = start + timeout

    do_eventually(fun, interval, deadline, start)
  end

  defp do_eventually(fun, interval, deadline, start_time) do
    case fun.() do
      result when result in [false, nil] ->
        if System.monotonic_time(:millisecond) >= deadline do
          elapsed = System.monotonic_time(:millisecond) - start_time

          flunk(
            "eventually/2 timed out after #{elapsed} ms (timeout #{deadline - start_time} ms)"
          )
        else
          Process.sleep(interval)
          do_eventually(fun, interval, deadline, start_time)
        end

      result ->
        result
    end
  end
end
