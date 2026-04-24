#!/usr/bin/env elixir

# Demonstrates cooperative cancellation with abort signals for hooks and permissions.
# Run: mix run.live examples/runtime_control/cancellable_callbacks.exs

alias ClaudeAgentSDK.{AbortSignal, Client, Message, Options}
alias ClaudeAgentSDK.Hooks.{Matcher, Output}
alias ClaudeAgentSDK.Permission

defmodule Examples.CancellableCallbacks do
  def run do
    parent = self()

    attach_telemetry_logger()

    options = %Options{
      hooks: %{
        pre_tool_use: [
          Matcher.new("*", [hook_handler(parent)])
        ]
      },
      can_use_tool: permission_handler(parent),
      include_partial_messages: true,
      allowed_tools: ["Bash"],
      permission_mode: :plan,
      preferred_transport: :control
    }

    {:ok, client} = Client.start_link(options)

    IO.puts("\nStarting cancellable callbacks demo...")
    IO.puts("1) Send a prompt that triggers hooks + permission checks")
    IO.puts("2) Cancel midway to show abort signals\n")

    # Trigger cancellation only after callbacks start (more deterministic)
    Task.start(fn ->
      wait_for_callback_start(parent)
      IO.puts("⚡ Cancelling: stopping client to trigger abort signals...")
      Client.stop(client)
    end)

    # Stream messages with a hard timeout so the demo doesn't hang
    stream_task =
      Task.async(fn ->
        Client.stream_messages(client)
        |> Stream.take(20)
        |> Enum.each(fn message ->
          IO.inspect(message, label: "[stream]")
          if Message.final?(message), do: throw(:halt)
        end)
      end)

    # Send a prompt that will trigger tool usage (and our callbacks)
    :ok =
      Client.send_message(
        client,
        "Use Bash to run 'echo START; sleep 5; echo END' so we can cancel mid-run."
      )

    case Task.yield(stream_task, 5_000) || Task.shutdown(stream_task) do
      {:ok, _} -> :ok
      _ -> IO.puts("⚠️ Stream timeout after cancellation — expected for this demo")
    end
  end

  defp hook_handler(parent) do
    fn _input, _tool_use_id, %{signal: signal} ->
      send(parent, {:hook_started, signal})
      :telemetry.execute([:claude_agent_sdk, :example, :hook, :start], %{}, %{})
      IO.puts("🛡️ Hook started (pre_tool_use). Waiting for cancel...")

      case wait_for_cancel(signal, "hook") do
        :cancelled ->
          :telemetry.execute([:claude_agent_sdk, :example, :hook, :cancelled], %{}, %{})
          Output.deny("Cancelled before tool execution")

        :ok ->
          :telemetry.execute([:claude_agent_sdk, :example, :hook, :completed], %{}, %{})
          Output.allow()
      end
    end
  end

  defp permission_handler(parent) do
    fn %Permission.Context{signal: signal} ->
      send(parent, {:permission_started, signal})
      :telemetry.execute([:claude_agent_sdk, :example, :permission, :start], %{}, %{})
      IO.puts("✅ Permission callback running. Waiting for cancel...")

      case wait_for_cancel(signal, "permission") do
        :cancelled ->
          :telemetry.execute(
            [:claude_agent_sdk, :example, :permission, :cancelled],
            %{},
            %{}
          )

          Permission.Result.deny("Permission callback cancelled")

        :ok ->
          :telemetry.execute(
            [:claude_agent_sdk, :example, :permission, :completed],
            %{},
            %{}
          )

          Permission.Result.allow()
      end
    end
  end

  defp wait_for_callback_start(parent) do
    wait_for_messages(parent, %{hook: false, permission: false})
  end

  defp wait_for_messages(_parent, %{hook: true, permission: true}), do: :ok

  defp wait_for_messages(parent, state) do
    receive do
      {:hook_started, _signal} ->
        wait_for_messages(parent, %{state | hook: true})

      {:permission_started, _signal} ->
        wait_for_messages(parent, %{state | permission: true})
    after
      10_000 ->
        IO.puts("⚠️ Callbacks did not start within 10s; cancelling anyway")
        :ok
    end
  end

  defp wait_for_cancel(signal, label) do
    Enum.reduce_while(1..30, :ok, fn _, acc ->
      if AbortSignal.cancelled?(signal) do
        IO.puts("🔴 #{label} aborted via abort signal")
        {:halt, :cancelled}
      else
        Process.sleep(150)
        {:cont, acc}
      end
    end)
  end

  defp attach_telemetry_logger do
    handler_id = "example-cancellable-callbacks"

    :telemetry.attach_many(
      handler_id,
      [
        [:claude_agent_sdk, :example, :hook, :start],
        [:claude_agent_sdk, :example, :hook, :completed],
        [:claude_agent_sdk, :example, :hook, :cancelled],
        [:claude_agent_sdk, :example, :permission, :start],
        [:claude_agent_sdk, :example, :permission, :completed],
        [:claude_agent_sdk, :example, :permission, :cancelled]
      ],
      fn event, _measurements, _metadata, _config ->
        IO.puts("📡 Telemetry: #{Enum.join(event, ".")}")
      end,
      nil
    )
  end
end

Examples.CancellableCallbacks.run()
