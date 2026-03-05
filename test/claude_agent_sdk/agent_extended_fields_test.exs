defmodule ClaudeAgentSDK.Agent.ExtendedFieldsTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Agent

  describe "extended agent fields" do
    test "supports disallowed_tools" do
      agent =
        Agent.new(
          description: "Restricted agent",
          prompt: "You cannot use Bash",
          disallowed_tools: ["Bash", "Write"]
        )

      assert agent.disallowed_tools == ["Bash", "Write"]
    end

    test "supports skills" do
      agent =
        Agent.new(
          description: "Skilled agent",
          prompt: "You have skills",
          skills: ["code-review", "testing"]
        )

      assert agent.skills == ["code-review", "testing"]
    end

    test "supports mcp_servers" do
      agent =
        Agent.new(
          description: "MCP agent",
          prompt: "You have MCP servers",
          mcp_servers: ["math-server", "db-server"]
        )

      assert agent.mcp_servers == ["math-server", "db-server"]
    end

    test "supports max_turns" do
      agent =
        Agent.new(
          description: "Limited agent",
          prompt: "You have limited turns",
          max_turns: 5
        )

      assert agent.max_turns == 5
    end

    test "all new fields default to nil" do
      agent =
        Agent.new(
          description: "Basic agent",
          prompt: "You are basic"
        )

      assert agent.disallowed_tools == nil
      assert agent.skills == nil
      assert agent.mcp_servers == nil
      assert agent.max_turns == nil
    end
  end

  describe "to_cli_map/1 with extended fields" do
    test "includes disallowedTools in CLI map" do
      agent =
        Agent.new(
          description: "Agent",
          prompt: "Prompt",
          disallowed_tools: ["Bash"]
        )

      map = Agent.to_cli_map(agent)
      assert map["disallowedTools"] == ["Bash"]
    end

    test "includes skills in CLI map" do
      agent =
        Agent.new(
          description: "Agent",
          prompt: "Prompt",
          skills: ["testing"]
        )

      map = Agent.to_cli_map(agent)
      assert map["skills"] == ["testing"]
    end

    test "includes mcpServers in CLI map" do
      agent =
        Agent.new(
          description: "Agent",
          prompt: "Prompt",
          mcp_servers: ["math"]
        )

      map = Agent.to_cli_map(agent)
      assert map["mcpServers"] == ["math"]
    end

    test "includes maxTurns in CLI map" do
      agent =
        Agent.new(
          description: "Agent",
          prompt: "Prompt",
          max_turns: 10
        )

      map = Agent.to_cli_map(agent)
      assert map["maxTurns"] == 10
    end

    test "omits nil extended fields from CLI map" do
      agent =
        Agent.new(
          description: "Agent",
          prompt: "Prompt"
        )

      map = Agent.to_cli_map(agent)
      refute Map.has_key?(map, "disallowedTools")
      refute Map.has_key?(map, "skills")
      refute Map.has_key?(map, "mcpServers")
      refute Map.has_key?(map, "maxTurns")
    end

    test "full agent with all fields" do
      agent =
        Agent.new(
          description: "Full agent",
          prompt: "Full prompt",
          allowed_tools: ["Read", "Edit"],
          disallowed_tools: ["Bash"],
          model: "sonnet",
          skills: ["review"],
          mcp_servers: ["math"],
          max_turns: 5
        )

      map = Agent.to_cli_map(agent)
      assert map["description"] == "Full agent"
      assert map["prompt"] == "Full prompt"
      assert map["tools"] == ["Read", "Edit"]
      assert map["disallowedTools"] == ["Bash"]
      assert map["model"] == "sonnet"
      assert map["skills"] == ["review"]
      assert map["mcpServers"] == ["math"]
      assert map["maxTurns"] == 5
    end
  end
end
