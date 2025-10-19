defmodule ClaudeAgentSDK.OptionsAgentsTest do
  @moduledoc """
  Tests for agent-related Options functionality.

  Tests the integration of agents into the Options struct,
  including CLI argument generation and validation.
  """
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Agent, Options}

  describe "Options with agents field" do
    test "creates options with single agent" do
      code_agent =
        Agent.new(
          description: "Code expert",
          prompt: "You are a coding expert",
          allowed_tools: ["Read", "Write"]
        )

      options = Options.new(agents: %{code_expert: code_agent})

      assert options.agents == %{code_expert: code_agent}
    end

    test "creates options with multiple agents" do
      code_agent =
        Agent.new(
          description: "Code expert",
          prompt: "You are a coding expert",
          allowed_tools: ["Read", "Write", "Bash"]
        )

      doc_agent =
        Agent.new(
          description: "Documentation expert",
          prompt: "You excel at documentation",
          allowed_tools: ["Read", "Write"]
        )

      options =
        Options.new(
          agents: %{
            code_expert: code_agent,
            doc_expert: doc_agent
          }
        )

      assert Map.has_key?(options.agents, :code_expert)
      assert Map.has_key?(options.agents, :doc_expert)
    end

    test "creates options with agent field set to active agent" do
      agent =
        Agent.new(
          description: "Active agent",
          prompt: "You are active"
        )

      options =
        Options.new(
          agents: %{active: agent},
          agent: :active
        )

      assert options.agent == :active
      assert Map.has_key?(options.agents, :active)
    end

    test "creates options with nil agents" do
      options = Options.new(agents: nil)
      assert options.agents == nil
    end
  end

  describe "to_args/1 with agents" do
    test "generates --agents CLI argument with single agent" do
      agent =
        Agent.new(
          description: "Test agent",
          prompt: "You are a test"
        )

      options =
        Options.new(
          agents: %{test: agent},
          output_format: :stream_json
        )

      args = Options.to_args(options)

      # Should contain --agents with JSON
      agents_index = Enum.find_index(args, &(&1 == "--agents"))
      assert agents_index != nil

      json_arg = Enum.at(args, agents_index + 1)
      assert is_binary(json_arg)

      # Verify JSON structure
      {:ok, decoded} = Jason.decode(json_arg)
      assert Map.has_key?(decoded, "test")
      assert decoded["test"]["description"] == "Test agent"
      assert decoded["test"]["prompt"] == "You are a test"
    end

    test "generates --agents with multiple agents" do
      code_agent =
        Agent.new(
          description: "Coder",
          prompt: "You code",
          allowed_tools: ["Write"]
        )

      doc_agent =
        Agent.new(
          description: "Writer",
          prompt: "You write docs",
          model: "opus"
        )

      options =
        Options.new(
          agents: %{
            coder: code_agent,
            writer: doc_agent
          },
          output_format: :stream_json
        )

      args = Options.to_args(options)

      agents_index = Enum.find_index(args, &(&1 == "--agents"))
      json_arg = Enum.at(args, agents_index + 1)

      {:ok, decoded} = Jason.decode(json_arg)
      assert Map.has_key?(decoded, "coder")
      assert Map.has_key?(decoded, "writer")
      assert decoded["coder"]["tools"] == ["Write"]
      assert decoded["writer"]["model"] == "opus"
    end

    test "omits --agents when agents is nil" do
      options =
        Options.new(
          agents: nil,
          output_format: :stream_json
        )

      args = Options.to_args(options)

      refute Enum.member?(args, "--agents")
    end

    test "generates --agent with active agent name" do
      agent =
        Agent.new(
          description: "Active",
          prompt: "I am active"
        )

      options =
        Options.new(
          agents: %{my_agent: agent},
          agent: :my_agent,
          output_format: :stream_json
        )

      args = Options.to_args(options)

      # Should contain --agent with name
      agent_index = Enum.find_index(args, &(&1 == "--agent"))
      assert agent_index != nil

      agent_name = Enum.at(args, agent_index + 1)
      assert agent_name == "my_agent"
    end

    test "omits --agent when agent is nil" do
      options =
        Options.new(
          agents: %{test: Agent.new(description: "Test", prompt: "Test")},
          agent: nil,
          output_format: :stream_json
        )

      args = Options.to_args(options)

      refute Enum.member?(args, "--agent")
    end

    test "generates both --agents and --agent when specified" do
      agent1 = Agent.new(description: "Agent 1", prompt: "Prompt 1")
      agent2 = Agent.new(description: "Agent 2", prompt: "Prompt 2")

      options =
        Options.new(
          agents: %{a1: agent1, a2: agent2},
          agent: :a1,
          output_format: :stream_json
        )

      args = Options.to_args(options)

      assert Enum.member?(args, "--agents")
      assert Enum.member?(args, "--agent")
    end
  end

  describe "validate_agents/1" do
    test "validates options with valid agents" do
      agent =
        Agent.new(
          description: "Valid",
          prompt: "Valid prompt"
        )

      options = Options.new(agents: %{valid: agent})

      assert :ok = Options.validate_agents(options)
    end

    test "validates options with multiple valid agents" do
      agent1 = Agent.new(description: "Agent 1", prompt: "Prompt 1")
      agent2 = Agent.new(description: "Agent 2", prompt: "Prompt 2")

      options = Options.new(agents: %{a1: agent1, a2: agent2})

      assert :ok = Options.validate_agents(options)
    end

    test "returns error when agent validation fails" do
      invalid_agent =
        Agent.new(
          # Invalid: empty description
          description: "",
          prompt: "Prompt"
        )

      options = Options.new(agents: %{invalid: invalid_agent})

      assert {:error, {:invalid_agent, :invalid, :description_required}} =
               Options.validate_agents(options)
    end

    test "returns error when active agent not in agents map" do
      agent = Agent.new(description: "Test", prompt: "Test")

      options =
        Options.new(
          agents: %{test: agent},
          agent: :nonexistent
        )

      assert {:error, {:agent_not_found, :nonexistent}} =
               Options.validate_agents(options)
    end

    test "allows agent field when it exists in agents map" do
      agent = Agent.new(description: "Test", prompt: "Test")

      options =
        Options.new(
          agents: %{test: agent},
          agent: :test
        )

      assert :ok = Options.validate_agents(options)
    end

    test "validates when agents is nil" do
      options = Options.new(agents: nil)
      assert :ok = Options.validate_agents(options)
    end

    test "validates when agent is nil" do
      agent = Agent.new(description: "Test", prompt: "Test")

      options =
        Options.new(
          agents: %{test: agent},
          agent: nil
        )

      assert :ok = Options.validate_agents(options)
    end

    test "returns error when agents is not a map" do
      options = %Options{agents: "invalid"}

      assert {:error, :agents_must_be_map} = Options.validate_agents(options)
    end

    test "returns error when agent is not an atom" do
      agent = Agent.new(description: "Test", prompt: "Test")

      options = %Options{
        agents: %{test: agent},
        agent: "string_instead_of_atom"
      }

      assert {:error, :agent_must_be_atom} = Options.validate_agents(options)
    end
  end
end
