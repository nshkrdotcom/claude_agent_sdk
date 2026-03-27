defmodule ClaudeAgentSDK.OptionsAgentsTest do
  @moduledoc """
  Tests for agent-related Options functionality.

  Tests the integration of agents into the Options struct,
  including agents_for_initialize/1 and validation.
  """
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Agent, Options}

  defp new_options(opts) do
    Options.new(Keyword.merge([model: "sonnet", provider_backend: :anthropic], opts))
  end

  describe "Options with agents field" do
    test "creates options with single agent" do
      code_agent =
        Agent.new(
          description: "Code expert",
          prompt: "You are a coding expert",
          allowed_tools: ["Read", "Write"]
        )

      options = new_options(agents: %{code_expert: code_agent})

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
        new_options(
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
        new_options(
          agents: %{active: agent},
          agent: :active
        )

      assert options.agent == :active
      assert Map.has_key?(options.agents, :active)
    end

    test "creates options with nil agents" do
      options = new_options(agents: nil)
      assert options.agents == nil
    end
  end

  describe "agents_for_initialize/1" do
    test "returns nil for nil agents" do
      assert Options.agents_for_initialize(nil) == nil
    end

    test "returns nil for empty agents map" do
      assert Options.agents_for_initialize(%{}) == nil
    end

    test "converts single agent to CLI map format" do
      agent =
        Agent.new(
          description: "Test agent",
          prompt: "You are a test"
        )

      result = Options.agents_for_initialize(%{test: agent})

      assert Map.has_key?(result, "test")
      assert result["test"]["description"] == "Test agent"
      assert result["test"]["prompt"] == "You are a test"
    end

    test "converts multiple agents to CLI map format" do
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

      result = Options.agents_for_initialize(%{coder: code_agent, writer: doc_agent})

      assert Map.has_key?(result, "coder")
      assert Map.has_key?(result, "writer")
      assert result["coder"]["tools"] == ["Write"]
      assert result["writer"]["model"] == "opus"
    end
  end

  describe "to_args/1 does not include --agents" do
    test "omits --agents from CLI args (agents sent via initialize)" do
      agent =
        Agent.new(
          description: "Test agent",
          prompt: "You are a test"
        )

      options =
        new_options(
          agents: %{test: agent},
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
        new_options(
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
        new_options(
          agents: %{test: Agent.new(description: "Test", prompt: "Test")},
          agent: nil,
          output_format: :stream_json
        )

      args = Options.to_args(options)

      refute Enum.member?(args, "--agent")
    end
  end

  describe "validate_agents/1" do
    test "validates options with valid agents" do
      agent =
        Agent.new(
          description: "Valid",
          prompt: "Valid prompt"
        )

      options = new_options(agents: %{valid: agent})

      assert :ok = Options.validate_agents(options)
    end

    test "validates options with multiple valid agents" do
      agent1 = Agent.new(description: "Agent 1", prompt: "Prompt 1")
      agent2 = Agent.new(description: "Agent 2", prompt: "Prompt 2")

      options = new_options(agents: %{a1: agent1, a2: agent2})

      assert :ok = Options.validate_agents(options)
    end

    test "returns error when agent validation fails" do
      invalid_agent =
        Agent.new(
          # Invalid: empty description
          description: "",
          prompt: "Prompt"
        )

      options = new_options(agents: %{invalid: invalid_agent})

      assert {:error, {:invalid_agent, :invalid, :description_required}} =
               Options.validate_agents(options)
    end

    test "returns error when active agent not in agents map" do
      agent = Agent.new(description: "Test", prompt: "Test")

      options =
        new_options(
          agents: %{test: agent},
          agent: :nonexistent
        )

      assert {:error, {:agent_not_found, :nonexistent}} =
               Options.validate_agents(options)
    end

    test "allows agent field when it exists in agents map" do
      agent = Agent.new(description: "Test", prompt: "Test")

      options =
        new_options(
          agents: %{test: agent},
          agent: :test
        )

      assert :ok = Options.validate_agents(options)
    end

    test "validates when agents is nil" do
      options = new_options(agents: nil)
      assert :ok = Options.validate_agents(options)
    end

    test "validates when agent is nil" do
      agent = Agent.new(description: "Test", prompt: "Test")

      options =
        new_options(
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
