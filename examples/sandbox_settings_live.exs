#!/usr/bin/env elixir

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{CLI, ContentExtractor, Options}
alias Examples.Support

defmodule SandboxSettingsLive do
  defp settings_value(%Options{} = options) do
    args = Options.to_args(options)
    idx = Enum.find_index(args, &(&1 == "--settings"))
    if is_integer(idx), do: Enum.at(args, idx + 1)
  end

  defp print_settings(label, %Options{} = options) do
    IO.puts("=== #{label} ===")
    IO.inspect(Options.to_args(options), label: "CLI args")

    value = settings_value(options)

    if is_binary(value) do
      decoded = Jason.decode!(value)
      IO.inspect(decoded, label: "--settings (decoded JSON)")
    else
      IO.puts("--settings not present")
    end

    IO.puts("")
  end

  def run do
    IO.inspect(CLI.find_executable(), label: "Claude CLI (resolved)")
    IO.inspect(CLI.version(), label: "Claude CLI (version)")
    IO.puts("")

    sandbox = %{
      enabled: true,
      autoAllowBashIfSandboxed: true,
      excludedCommands: ["docker"],
      network: %{allowLocalBinding: true}
    }

    print_settings("sandbox only", %Options{sandbox: sandbox})

    print_settings("sandbox + settings JSON string", %Options{
      settings: ~s({"foo":"bar"}),
      sandbox: sandbox
    })

    tmp_path =
      Path.join(
        System.tmp_dir!(),
        "claude_agent_sdk_settings_#{System.unique_integer([:positive])}.json"
      )

    File.write!(tmp_path, ~s({"from_file":true}))

    print_settings("sandbox + settings file path", %Options{
      settings: tmp_path,
      sandbox: sandbox
    })

    File.rm(tmp_path)

    IO.puts("=== Live query with sandbox settings ===")

    result_subtype =
      ClaudeAgentSDK.query(
        "Say hello in one sentence.",
        %Options{
          model: "haiku",
          max_turns: 1,
          output_format: :stream_json,
          sandbox: sandbox
        }
      )
      |> Enum.reduce(nil, fn
        %{type: :assistant} = message, acc ->
          text = ContentExtractor.extract_text(message)
          if text != "", do: IO.puts("Assistant: #{text}")
          acc

        %{type: :result} = message, _acc ->
          IO.puts("Result: #{message.subtype}")
          message.subtype

        _message, acc ->
          acc
      end)

    if result_subtype != :success do
      raise "Sandbox query did not succeed (result subtype: #{inspect(result_subtype)})"
    end
  end
end

Support.ensure_live!()
Support.header!("Sandbox + Settings Example (live)")
SandboxSettingsLive.run()
Support.halt_if_runner!()
