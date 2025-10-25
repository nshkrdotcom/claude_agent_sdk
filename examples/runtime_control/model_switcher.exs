Code.require_file(Path.expand("support/mock_transport.exs", __DIR__))

defmodule Examples.RuntimeControl.ModelSwitcher do
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
    IO.puts("\n== Runtime Control Demo (Mock Transport) ==")

    {:ok, client} =
      Client.start_link(%Options{model: "haiku"},
        transport: MockTransport,
        transport_opts: [owner: self()]
      )

    transport_pid = wait_for(:mock_transport_started, 500)

    stream_task =
      Task.async(fn ->
        Client.stream_messages(client)
        |> Enum.take(3)
      end)

    initial =
      message_frame("assistant", %{
        "content" => "Hello! Starting on haiku.",
        "role" => "assistant"
      })

    MockTransport.push_json(transport_pid, initial)

    switch_task = Task.async(fn -> Client.set_model(client, "opus") end)

    set_model_frame = wait_for_set_model_request(500)
    {:ok, request_id} = acknowledge_model_change(set_model_frame, transport_pid)

    :ok = Task.await(switch_task, 1_000)

    follow_up =
      message_frame("assistant", %{
        "content" => "Model switched! Now responding as claude-opus-4-20250514.",
        "role" => "assistant"
      })

    MockTransport.push_json(transport_pid, follow_up)

    result_frame = %{
      "type" => "result",
      "subtype" => "success",
      "session_id" => "demo-session",
      "total_cost_usd" => 0.0
    }

    MockTransport.push_json(transport_pid, result_frame)

    messages = Task.await(stream_task, 1_000)
    print_summary(messages, request_id, client)
    Client.stop(client)
  end

  defp run_live do
    IO.puts("\n== Runtime Control Demo (CLI Transport) ==")
    IO.puts("Attempting to use the Claude CLI. Make sure `claude login` has been executed.\n")

    case Client.start_link(%Options{model: "haiku"}) do
      {:ok, client} ->
        try do
          live_demo(client)
        after
          Client.stop(client)
        end

      {:error, reason} ->
        IO.puts("Failed to start live client: #{inspect(reason)}")
        :ok
    end
  end

  defp live_demo(client) do
    case await_model(client, 5_000) do
      {:ok, model} ->
        IO.puts("Current model before switch: #{model}")

      {:error, :timeout} ->
        IO.puts("Current model before switch: unavailable (timeout)")

      {:error, reason} ->
        IO.puts("Unable to read current model: #{inspect(reason)}")
    end

    {:ok, normalized_target} = Model.validate("opus")

    case Client.set_model(client, "opus") do
      :ok ->
        IO.puts("Requested model switch to #{normalized_target}. Waiting for confirmation...")

        case await_model_change(client, normalized_target, 5_000) do
          {:ok, model} ->
            IO.puts("Model after switch: #{model}")

          {:timeout, observed} ->
            IO.puts("Model did not update within 5s (last observed: #{observed || "unknown"})")

          {:error, reason} ->
            IO.puts("Failed to read model after switch: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("Live model switch failed: #{inspect(reason)}")
    end
  end

  defp wait_for(tag, timeout) do
    receive do
      {^tag, payload} -> payload
    after
      timeout ->
        raise "Timed out waiting for #{inspect(tag)}"
    end
  end

  defp wait_for_set_model_request(timeout) do
    frame = wait_for(:mock_transport_send, timeout)
    decoded = Jason.decode!(frame)

    case get_in(decoded, ["request", "subtype"]) do
      "set_model" ->
        frame

      _other ->
        wait_for_set_model_request(timeout)
    end
  end

  defp acknowledge_model_change(encoded_frame, transport_pid) do
    decoded = Jason.decode!(encoded_frame)
    request = decoded["request"] || %{}

    if request["subtype"] == "set_model" do
      request_id = decoded["request_id"]
      {:ok, normalized} = Model.validate(request["model"])

      MockTransport.push_json(transport_pid, %{
        "type" => "control_response",
        "response" => %{
          "request_id" => request_id,
          "subtype" => "success",
          "result" => %{"model" => normalized}
        }
      })

      {:ok, request_id}
    else
      {:error, :unexpected_frame}
    end
  end

  defp message_frame(subtype, message) do
    %{
      "type" => "assistant",
      "subtype" => subtype,
      "message" => message,
      "session_id" => "demo-session"
    }
  end

  defp print_summary(messages, request_id, client) do
    IO.puts("\nMessages received by subscribers:")

    Enum.each(messages, fn message ->
      case {message.type, message.subtype} do
        {:assistant, _} ->
          IO.puts("  • Assistant: #{inspect(message.data[:message]["content"])}")

        {:result, :success} ->
          IO.puts("  • Result: success (cost: $#{message.data[:total_cost_usd] || 0})")

        other ->
          IO.puts("  • #{inspect(other)}")
      end
    end)

    IO.puts("\nSwitch confirmed with request_id=#{request_id}")
    {:ok, model} = Client.get_model(client)
    IO.puts("Client reports current model: #{model}\n")
  end

  defp await_model(client, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    poll_for_model(client, deadline)
  end

  defp poll_for_model(client, deadline) do
    case Client.get_model(client) do
      {:ok, model} ->
        {:ok, model}

      {:error, :model_not_set} ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(100)
          poll_for_model(client, deadline)
        else
          {:error, :timeout}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp await_model_change(client, expected_model, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    poll_for_model_change(client, expected_model, deadline)
  end

  defp poll_for_model_change(client, expected_model, deadline) do
    case Client.get_model(client) do
      {:ok, ^expected_model} = ok ->
        ok

      {:ok, model} ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(100)
          poll_for_model_change(client, expected_model, deadline)
        else
          {:timeout, model}
        end

      {:error, :model_not_set} ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(100)
          poll_for_model_change(client, expected_model, deadline)
        else
          {:timeout, nil}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end

Examples.RuntimeControl.ModelSwitcher.main()
