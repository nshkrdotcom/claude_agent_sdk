defmodule ClaudeAgentSDK.Integration.FilesystemAgentsTest do
  @moduledoc """
  Regression test for filesystem agents loaded via setting_sources.

  This test catches issue #406 class failures where the SDK silently
  terminates after init without producing assistant/result messages.
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  alias ClaudeAgentSDK.{Client, Message, Options}

  describe "filesystem agents via setting_sources" do
    setup do
      tmp_dir =
        Path.join(System.tmp_dir!(), "claude_fs_agents_test_#{:rand.uniform(100_000)}")

      agents_dir = Path.join([tmp_dir, ".claude", "agents"])
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

      on_exit(fn ->
        # Windows may hold file handles briefly
        Process.sleep(100)
        File.rm_rf!(tmp_dir)
      end)

      {:ok, tmp_dir: tmp_dir}
    end

    test "loads agent from filesystem and produces full response", %{tmp_dir: tmp_dir} do
      options = %Options{
        cwd: tmp_dir,
        setting_sources: ["project"],
        max_turns: 1,
        output_format: :stream_json
      }

      {:ok, client} = Client.start_link(options)
      :ok = Client.query(client, "Say hello in exactly 3 words")
      {:ok, messages} = Client.receive_response(client)
      Client.stop(client)

      message_types = Enum.map(messages, & &1.type)

      # Core regression check: must have all message types
      assert :system in message_types, "Missing system (init) message"

      assert :assistant in message_types,
             "Missing assistant message - got only: #{inspect(message_types)}. " <>
               "This may indicate issue #406 (silent failure with filesystem agents)."

      assert :result in message_types, "Missing result message"

      # Verify agent was loaded from filesystem
      init = Enum.find(messages, &(&1.type == :system and &1.subtype == :init))
      agent_names = extract_agent_names(init)

      assert "fs-test-agent" in agent_names,
             "fs-test-agent not loaded from filesystem. Found: #{inspect(agent_names)}"
    end
  end

  defp extract_agent_names(%Message{raw: raw}) do
    (raw["agents"] || [])
    |> List.wrap()
    |> Enum.flat_map(fn
      name when is_binary(name) -> [name]
      %{"name" => name} when is_binary(name) -> [name]
      _ -> []
    end)
  end
end
