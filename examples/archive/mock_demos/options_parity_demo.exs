#!/usr/bin/env elixir

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.Options
alias Examples.Support

Support.ensure_mock!()
Support.header!("Options Parity Demo (mock, deterministic)")

base = %Options{}
args = Options.to_args(base)

IO.inspect(args, label: "Options.to_args(%Options{})")

for {flag, value} <- [{"--setting-sources", ""}, {"--system-prompt", ""}] do
  idx = Enum.find_index(args, &(&1 == flag))

  case idx do
    nil ->
      raise "Expected #{flag} to be present"

    idx ->
      actual = Enum.at(args, idx + 1)

      if actual != value,
        do: raise("Expected #{flag} value #{inspect(value)}, got #{inspect(actual)}")
  end
end

IO.puts("\n✓ Default parity flags present")

preset =
  %Options{
    system_prompt: %{
      type: :preset,
      preset: :claude_code,
      append: "Always reply with one sentence."
    }
  }

preset_args = Options.to_args(preset)
IO.inspect(preset_args, label: "system_prompt preset args")

if "--append-system-prompt" not in preset_args do
  raise "Expected --append-system-prompt for preset with append"
end

if "--system-prompt" in preset_args do
  raise "Expected --system-prompt to be omitted when using preset append"
end

IO.puts("\n✓ Preset append emits --append-system-prompt")

IO.puts("\nAll checks passed.")
