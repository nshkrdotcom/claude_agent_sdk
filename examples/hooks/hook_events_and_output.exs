#!/usr/bin/env elixir

# Example: 0.18.0 hook output helpers + include_hook_events (LIVE)
#
# Demonstrates:
#   - The new Hooks.Output helpers: defer/1, with_updated_tool_output/2,
#     with_reload_skills/1, with_session_title/2 (built + inspected, deterministic)
#   - include_hook_events: true, which makes the CLI emit hook lifecycle frames
#     as HookEventMessage (system subtype hook_started / hook_response) on the
#     message stream, in addition to invoking your registered callbacks
#
# Run: mix run examples/hooks/hook_events_and_output.exs

Code.require_file(Path.expand("../support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{Client, ContentExtractor, Message, Options}
alias ClaudeAgentSDK.Hooks.{Matcher, Output}
alias Examples.Support

Support.ensure_live!()
Support.header!("Hooks Example: output helpers + include_hook_events (live)")

defmodule HookEventsDemo do
  def show_output_helpers do
    IO.puts("\nNew 0.18.0 Hooks.Output helpers (deterministic):")

    IO.inspect(Output.defer("needs human review"),
      label: "defer/1"
    )

    IO.inspect(
      Output.continue() |> Output.with_updated_tool_output(%{"stdout" => "redacted"}),
      label: "with_updated_tool_output/2"
    )

    IO.inspect(
      Output.add_context("SessionStart", "loaded")
      |> Output.with_reload_skills()
      |> Output.with_session_title("Nightly triage"),
      label: "SessionStart reloadSkills + sessionTitle"
    )
  end

  # A PostToolUse hook that annotates the tool result for the model.
  def annotate(_input, _tool_use_id, _context) do
    Output.continue()
    |> Output.with_additional_context("(hook observed this tool call)")
  end
end

HookEventsDemo.show_output_helpers()

hooks = %{
  post_tool_use: [Matcher.new("*", [&HookEventsDemo.annotate/3])]
}

options =
  %Options{
    tools: ["Bash"],
    allowed_tools: ["Bash(echo *)"],
    hooks: hooks,
    include_hook_events: true,
    model: "haiku",
    permission_mode: :default
  }
  |> Support.with_execution_surface()

{:ok, client} = Client.start_link(options)
IO.puts("\nClient started with a PostToolUse hook and include_hook_events: true.\n")

:ok = Client.query(client, "Run this exact bash command: echo hello-from-hooks")
{:ok, messages} = Client.receive_response(client)

Enum.each(messages, fn
  %Message{type: :system, subtype: subtype} = msg
  when subtype in [:hook_started, :hook_response] ->
    IO.puts("HookEventMessage: #{subtype} (#{inspect(msg.data[:hook_event_name])})")

  %Message{type: :assistant} = msg ->
    text = ContentExtractor.extract_text(msg)
    if is_binary(text) and text != "", do: IO.puts("Assistant: #{text}")

  _ ->
    :ok
end)

Client.stop(client)
Support.halt_if_runner!()
