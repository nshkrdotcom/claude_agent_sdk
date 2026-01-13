#!/usr/bin/env elixir

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{Client, ContentExtractor, Options}
alias Examples.Support

defmodule FilesystemAgentsLive do
  def run do
    Support.ensure_live!()
    Support.header!("Filesystem Agents via setting_sources (live)")

    # Define demo_dir before try block so it's in scope for after
    demo_dir =
      Path.join(
        System.tmp_dir!(),
        "claude_agent_sdk_filesystem_agents_demo_#{System.unique_integer([:positive])}"
      )

    try do
      agents_dir = Path.join([demo_dir, ".claude", "agents"])
      File.mkdir_p!(agents_dir)

      agent_content = """
      ---
      name: fs-test-agent
      description: Filesystem test agent for SDK regression testing
      tools: Read
      ---

      # Filesystem Test Agent

      You are a simple test agent. When asked a question, provide a brief answer.
      """

      File.write!(Path.join(agents_dir, "fs-test-agent.md"), agent_content)
      IO.puts("Demo working directory: #{demo_dir}")

      options = %Options{
        cwd: demo_dir,
        setting_sources: ["project"],
        max_turns: 1,
        model: "haiku",
        output_format: :stream_json
      }

      {:ok, client} = Client.start_link(options)

      :ok = Client.query(client, "Say hello in exactly 3 words")
      {:ok, messages} = Client.receive_response(client)
      Client.stop(client)

      IO.inspect(Enum.map(messages, & &1.type), label: "Message types")

      init = Enum.find(messages, &(&1.type == :system and &1.subtype == :init))
      result = Enum.find(messages, &(&1.type == :result))

      case result do
        %{subtype: :success} -> :ok
        %{subtype: other} -> raise "Query did not succeed (result subtype: #{inspect(other)})"
        nil -> raise "No result message returned."
      end

      if is_nil(init) do
        raise "No init message observed."
      end

      IO.inspect(init.raw["agents"], label: ~s(init.raw["agents"]))

      if not Enum.member?(init.raw["agents"] || [], "fs-test-agent") do
        raise "Filesystem agent not found in init agents list."
      end

      assistant_text =
        messages
        |> Enum.filter(&(&1.type == :assistant))
        |> Enum.map(&ContentExtractor.extract_text/1)
        |> Enum.reject(&(&1 in [nil, ""]))

      if assistant_text == [] do
        raise "No assistant text returned."
      end

      IO.puts("Assistant: #{Enum.join(assistant_text, "\n")}")
    after
      Process.sleep(100)
      File.rm_rf!(demo_dir)
    end
  end
end

FilesystemAgentsLive.run()
Support.halt_if_runner!()
