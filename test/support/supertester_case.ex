defmodule ClaudeAgentSDK.SupertesterCase do
  @moduledoc """
  Shared test foundation leveraging Supertester utilities for deterministic OTP testing.
  """

  use ExUnit.CaseTemplate

  using opts do
    requested_async = Keyword.get(opts, :async, false)
    isolation = Keyword.get(opts, :isolation, :basic)
    telemetry_isolation = Keyword.get(opts, :telemetry_isolation, false)
    logger_isolation = Keyword.get(opts, :logger_isolation, false)
    ets_isolation = Keyword.get(opts, :ets_isolation, [])

    quote do
      use ExUnit.Case, async: unquote(requested_async)

      setup context do
        {:ok, base_context} =
          Supertester.UnifiedTestFoundation.setup_isolation(unquote(isolation), context)

        isolation_context = base_context.isolation_context

        isolation_context =
          if unquote(telemetry_isolation) do
            {:ok, _test_id, ctx} =
              Supertester.TelemetryHelpers.setup_telemetry_isolation(isolation_context)

            ctx
          else
            isolation_context
          end

        isolation_context =
          if unquote(logger_isolation) do
            {:ok, ctx} = Supertester.LoggerIsolation.setup_logger_isolation(isolation_context)

            if level = context[:logger_level] do
              Supertester.LoggerIsolation.isolate_level(level)
            end

            ctx
          else
            isolation_context
          end

        isolation_context =
          if unquote(ets_isolation) != [] do
            {:ok, ctx} =
              Supertester.ETSIsolation.setup_ets_isolation(
                isolation_context,
                unquote(ets_isolation)
              )

            ctx
          else
            isolation_context
          end

        if events = context[:telemetry_events] do
          Supertester.TelemetryHelpers.attach_isolated(events)
        end

        if tables = context[:ets_tables] do
          tables
          |> List.wrap()
          |> Enum.each(fn table ->
            {:ok, _} = Supertester.ETSIsolation.mirror_table(table)
          end)
        end

        {:ok, %{base_context | isolation_context: isolation_context}}
      end

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
