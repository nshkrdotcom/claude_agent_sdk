#!/usr/bin/env elixir

# Run: mix run examples/runtime_control/lifecycle_frames_live.exs

Code.require_file(Path.expand("../support/example_helper.exs", __DIR__))

alias Examples.Support

defmodule LifecycleFramesLiveExample do
  @moduledoc """
  Live demo for the CLI 2.1.203–2.1.207 lifecycle surface:

  - `system/init` `capabilities` + `Message.capability?/2`
  - `terminal_reason` on results + `Message.dead_turn?/1`
  - the typed interrupt receipt (`{:ok, %InterruptReceipt{still_queued: …}}`)
  - `background_tasks_changed` + `Message.live_background_tasks/1`

  Requires a logged-in Claude CLI (`claude login` or `CLAUDE_AGENT_OAUTH_TOKEN`).
  """

  alias ClaudeAgentSDK.{Client, InterruptReceipt, Message, Options}

  def run do
    IO.puts("\nLifecycle frames demo (live CLI)\n")

    quick_turn_and_interrupt()
    background_tasks()
  end

  # -- phase 1+2: clean turn, then an interrupted turn -----------------------

  defp quick_turn_and_interrupt do
    options =
      %Options{model: "haiku", max_turns: 1, allowed_tools: []}
      |> Support.with_execution_surface()

    {:ok, client} = Client.start_link(options)
    stream = Client.stream_messages(client)

    IO.puts("== Clean turn ==")
    :ok = Client.send_message(client, "Reply with exactly: ok")
    result = consume_until_result(stream)
    report_result(result)

    if Message.dead_turn?(result), do: raise("clean turn classified as dead")

    IO.puts("\n== Interrupted turn ==")

    :ok =
      Client.send_message(
        client,
        "Count from 1 to 200, one number per line. Do not stop early."
      )

    parent = self()

    Task.start(fn ->
      Process.sleep(2_500)

      case Client.interrupt(client) do
        {:ok, %InterruptReceipt{} = receipt} ->
          IO.puts("[interrupt] receipt still_queued=#{inspect(receipt.still_queued)}")
          send(parent, {:receipt, receipt})

        {:error, reason} ->
          IO.puts("[interrupt] failed: #{inspect(reason)}")
          send(parent, {:receipt_error, reason})
      end
    end)

    result = consume_until_result(stream)
    report_result(result)

    receive do
      {:receipt, %InterruptReceipt{}} -> :ok
      {:receipt_error, reason} -> raise "interrupt did not return a receipt: #{inspect(reason)}"
    after
      10_000 -> raise "no interrupt receipt received"
    end

    Client.stop(client)
  end

  # -- phase 3: background_tasks_changed --------------------------------------

  defp background_tasks do
    IO.puts("\n== Background tasks (level frames) ==")

    options =
      %Options{model: "haiku", max_turns: 3, allowed_tools: ["Bash"]}
      |> Support.with_execution_surface()

    {:ok, client} = Client.start_link(options)
    stream = Client.stream_messages(client)

    :ok =
      Client.send_message(
        client,
        "Use the Bash tool to run the command 'sleep 6 && echo done' in the " <>
          "background (run_in_background true). After it starts, reply with " <>
          "exactly: started. Do not wait for it."
      )

    {result, bg_frames} =
      Enum.reduce_while(stream, {nil, []}, fn
        %Message{type: :system, subtype: :background_tasks_changed} = msg, {res, frames} ->
          live = Message.live_background_tasks(msg)

          IO.puts(
            "[background_tasks_changed] total=#{length(msg.data.tasks)} " <>
              "live=#{inspect(Enum.map(live, & &1.task_id))}"
          )

          {:cont, {res, frames ++ [msg]}}

        %Message{type: :result} = msg, {_res, frames} ->
          {:halt, {msg, frames}}

        _msg, acc ->
          {:cont, acc}
      end)

    report_result(result)

    case bg_frames do
      [] ->
        IO.puts("(no background_tasks_changed frames observed on this run)")

      frames ->
        IO.puts("observed #{length(frames)} background_tasks_changed frame(s)")
    end

    Client.stop(client)
  end

  # -- helpers ----------------------------------------------------------------

  defp consume_until_result(stream) do
    Enum.reduce_while(stream, nil, fn
      %Message{type: :system, subtype: :init} = msg, acc ->
        IO.puts(
          "[init] capabilities=#{inspect(msg.data.capabilities)} " <>
            "interrupt_receipt_v1=#{Message.capability?(msg, "interrupt_receipt_v1")}"
        )

        {:cont, acc}

      %Message{type: :result} = msg, _acc ->
        {:halt, msg}

      _msg, acc ->
        {:cont, acc}
    end)
  end

  defp report_result(nil), do: raise("no result message received")

  defp report_result(%Message{} = result) do
    IO.puts(
      "[result] subtype=#{inspect(result.subtype)} " <>
        "terminal_reason=#{inspect(result.data[:terminal_reason])} " <>
        "dead_turn?=#{Message.dead_turn?(result)}"
    )
  end
end

LifecycleFramesLiveExample.run()
IO.puts("\nlifecycle frames demo complete")
