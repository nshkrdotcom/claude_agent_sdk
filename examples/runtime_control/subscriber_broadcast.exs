Code.require_file(Path.expand("support/mock_transport.exs", __DIR__))

defmodule Examples.RuntimeControl.SubscriberBroadcast do
  @moduledoc false

  alias ClaudeAgentSDK.{Client, Model, Options}
  alias Examples.RuntimeControl.MockTransport

  def main(args \\ System.argv()) do
    case Enum.member?(args, "--live") do
      true -> run_live()
      false -> run_mock()
    end
  end

  defp run_mock do
    IO.puts("\n== Subscriber Broadcast Demo (Mock Transport) ==")

    {:ok, client} =
      Client.start_link(%Options{model: "claude-sonnet-4"},
        transport: MockTransport,
        transport_opts: [owner: self()]
      )

    transport_pid = wait_for(:mock_transport_started, 500)

    streams =
      Enum.map(1..2, fn idx ->
        {idx,
         Task.async(fn ->
           Client.stream_messages(client)
           |> Enum.take(3)
           |> Enum.map(&summarize(idx, &1))
         end)}
      end)

    initial = assistant_frame("Subscriber demo starting on claude-sonnet-4.")
    MockTransport.push_json(transport_pid, initial)

    switch_task = Task.async(fn -> Client.set_model(client, "opus") end)
    set_model_frame = wait_for_set_model_request(500)
    {:ok, request_id} = acknowledge_model_change(set_model_frame, transport_pid)
    :ok = Task.await(switch_task, 1_000)

    follow_up = assistant_frame("Model switch acknowledged for request #{request_id}")
    MockTransport.push_json(transport_pid, follow_up)

    result_frame = %{
      "type" => "result",
      "subtype" => "success",
      "session_id" => "subscriber-demo",
      "total_cost_usd" => 0.0
    }

    MockTransport.push_json(transport_pid, result_frame)

    Enum.each(streams, fn {idx, task} ->
      messages = Task.await(task, 1_500)
      IO.puts("\nStream #{idx} received:")
      Enum.each(messages, &IO.puts("  • #{&1}"))
    end)

    Client.stop(client)
  end

  defp run_live do
    IO.puts("\n== Subscriber Broadcast Demo (CLI Transport) ==")
    IO.puts("Subscribe with two local consumers while the CLI runs the session.\n")

    case Client.start_link(%Options{model: "claude-sonnet-4"}) do
      {:ok, client} ->
        run_live_stream(client)
        Client.stop(client)

      {:error, reason} ->
        IO.puts("Failed to start live client: #{inspect(reason)}")
    end
  end

  defp run_live_stream(client) do
    streams =
      Enum.map(1..2, fn idx ->
        {idx,
         Task.async(fn ->
           Client.stream_messages(client)
           |> Enum.take(1)
           |> Enum.map(&summarize(idx, &1))
         end)}
      end)

    case Client.set_model(client, "opus") do
      :ok -> IO.puts("Model switch requested; waiting for CLI broadcast...")
      {:error, reason} -> IO.puts("Live model switch failed: #{inspect(reason)}")
    end

    Enum.each(streams, fn {idx, task} ->
      messages = Task.await(task, 5_000)
      IO.puts("\nStream #{idx} recorded: #{inspect(messages)}")
    end)
  end

  defp assistant_frame(content) do
    %{
      "type" => "assistant",
      "message" => %{"content" => content, "role" => "assistant"},
      "session_id" => "subscriber-demo"
    }
  end

  defp summarize(idx, %ClaudeAgentSDK.Message{
         type: :assistant,
         data: %{message: %{"content" => content}}
       }) do
    "Subscriber #{idx}: assistant -> #{content}"
  end

  defp summarize(idx, %ClaudeAgentSDK.Message{type: :result, subtype: :success}) do
    "Subscriber #{idx}: result -> success"
  end

  defp summarize(idx, message) do
    "Subscriber #{idx}: #{inspect(message.type)}"
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

  defp acknowledge_model_change(frame, transport_pid) do
    decoded = Jason.decode!(frame)
    request_id = decoded["request_id"]
    {:ok, normalized} = Model.validate(decoded["request"]["model"])

    MockTransport.push_json(transport_pid, %{
      "type" => "control_response",
      "response" => %{
        "request_id" => request_id,
        "subtype" => "success",
        "result" => %{"model" => normalized}
      }
    })

    {:ok, request_id}
  end
end

Examples.RuntimeControl.SubscriberBroadcast.main()
