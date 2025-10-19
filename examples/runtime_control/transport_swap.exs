Code.require_file(Path.expand("support/mock_transport.exs", __DIR__))

defmodule Examples.RuntimeControl.TransportSwap do
  @moduledoc false

  alias ClaudeAgentSDK.{Client, Model, Options}
  alias Examples.RuntimeControl.MockTransport

  def main(args \\ System.argv()) do
    IO.puts("\n== Transport Swap Demo (Mocked) ==")
    run_phase(:fast, delay_ms: 0)
    run_phase(:slow, delay_ms: 250)

    if Enum.member?(args, "--live") do
      IO.puts("\n-- Live CLI mode requested. Attempting to start port transport. --\n")
      run_live()
    else
      IO.puts("\nTip: pass --live to try the default port transport against the real CLI.\n")
    end
  end

  defp run_phase(label, opts) do
    delay_ms = Keyword.get(opts, :delay_ms, 0)
    IO.puts("\nPhase #{label}: using MockTransport with delay=#{delay_ms}ms")

    {:ok, client} =
      Client.start_link(%Options{model: "claude-sonnet-4"},
        transport: MockTransport,
        transport_opts: [owner: self(), delay_ms: delay_ms]
      )

    transport_pid = wait_for(:mock_transport_started, 500)

    initial =
      build_message(%{
        "content" => "Hello from #{label} transport.",
        "role" => "assistant"
      })

    MockTransport.push_json(transport_pid, initial)
    IO.puts("  -> Broadcast assistant message: #{initial["message"]["content"]}")

    duration = simulate_model_switch(client, transport_pid, delay_ms)

    result_frame = %{
      "type" => "result",
      "subtype" => "success",
      "session_id" => "transport-demo",
      "total_cost_usd" => 0.0
    }

    MockTransport.push_json(transport_pid, result_frame)
    IO.puts("  -> Broadcast result frame: success")

    outbound = MockTransport.recorded(transport_pid)
    IO.puts("  -> Outbound frames sent (#{length(outbound)} total):")

    Enum.each(outbound, fn json ->
      IO.puts("     • #{json}")
    end)

    IO.puts("  -> Model switch completed in ~#{duration}ms")

    Client.stop(client)
  end

  defp run_live do
    case Client.start_link(%Options{model: "claude-sonnet-4"}) do
      {:ok, client} ->
        IO.puts("Started CLI transport client. Attempting model switch to opus...")

        case Client.set_model(client, "opus") do
          :ok -> IO.puts("Model switch request sent. Watch CLI output for confirmation.")
          {:error, reason} -> IO.puts("Model switch failed: #{inspect(reason)}")
        end

        Client.stop(client)

      {:error, reason} ->
        IO.puts("Unable to start CLI transport: #{inspect(reason)}")
    end
  end

  defp simulate_model_switch(client, transport_pid, delay_ms) do
    start_ms = System.monotonic_time(:millisecond)
    request_task = Task.async(fn -> Client.set_model(client, "opus") end)

    payload = wait_for_set_model_request(500)
    decoded = Jason.decode!(payload)
    request_id = decoded["request_id"]
    requested_model = decoded["request"]["model"]

    {:ok, normalized} = Model.validate(requested_model)

    MockTransport.push_json(transport_pid, %{
      "type" => "control_response",
      "response" => %{
        "request_id" => request_id,
        "subtype" => "success",
        "result" => %{"model" => normalized}
      }
    })

    :ok = Task.await(request_task, 1_000 + delay_ms)
    finish_ms = System.monotonic_time(:millisecond)
    finish_ms - start_ms
  end

  defp build_message(message) do
    %{
      "type" => "assistant",
      "message" => message,
      "session_id" => "transport-demo"
    }
  end

  defp wait_for(tag, timeout) do
    receive do
      {^tag, payload} -> payload
    after
      timeout -> raise "Timed out waiting for #{inspect(tag)}"
    end
  end

  defp wait_for_set_model_request(timeout) do
    frame = wait_for(:mock_transport_send, timeout)
    decoded = Jason.decode!(frame)

    case get_in(decoded, ["request", "subtype"]) do
      "set_model" -> frame
      _other -> wait_for_set_model_request(timeout)
    end
  end
end

Examples.RuntimeControl.TransportSwap.main()
