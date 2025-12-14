#!/usr/bin/env elixir

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.Hooks.Output
alias Examples.Support

Support.ensure_mock!()
Support.header!("Hooks Output Demo (mock, deterministic)")

outputs = [
  Output.allow() |> Output.with_system_message("ok"),
  Output.deny("blocked") |> Output.with_reason("policy"),
  Output.allow() |> Output.suppress_output(),
  %{async: true},
  %{async: true, asyncTimeout: 250}
]

Enum.each(outputs, fn output ->
  :ok = Output.validate(output)
  IO.inspect(Output.to_json_map(output), label: "output json")
end)

IO.puts("\n✓ Hook outputs validate and JSON-encode (including async/asyncTimeout)")
