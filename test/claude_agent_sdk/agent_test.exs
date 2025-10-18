defmodule ClaudeAgentSDK.AgentTest do
  @moduledoc """
  Tests for Agent struct definition and validation.

  Tests the Agent struct that represents custom agent definitions
  with specific tools, prompts, and models.
  """
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.Agent

  describe "new/1" do
    test "creates an agent with all valid fields" do
      agent =
        Agent.new(
          name: :code_reviewer,
          description: "Reviews code for best practices",
          prompt: "You are a code reviewer...",
          allowed_tools: ["Read", "Grep"],
          model: "claude-sonnet-4"
        )

      assert %Agent{} = agent
      assert agent.name == :code_reviewer
      assert agent.description == "Reviews code for best practices"
      assert agent.prompt == "You are a code reviewer..."
      assert agent.allowed_tools == ["Read", "Grep"]
      assert agent.model == "claude-sonnet-4"
    end

    test "creates an agent with minimal required fields" do
      agent =
        Agent.new(
          description: "A simple agent",
          prompt: "You are helpful"
        )

      assert %Agent{} = agent
      assert agent.description == "A simple agent"
      assert agent.prompt == "You are helpful"
      assert agent.name == nil
      assert agent.allowed_tools == nil
      assert agent.model == nil
    end

    test "creates an agent with only certain tools allowed" do
      agent =
        Agent.new(
          description: "Read-only agent",
          prompt: "You can only read files",
          allowed_tools: ["Read", "Glob"]
        )

      assert agent.allowed_tools == ["Read", "Glob"]
    end

    test "creates an agent with a specific model" do
      agent =
        Agent.new(
          description: "Opus agent",
          prompt: "Use Opus model",
          model: "claude-opus-4"
        )

      assert agent.model == "claude-opus-4"
    end
  end

  describe "validate/1" do
    test "validates a complete agent successfully" do
      agent =
        Agent.new(
          name: :tester,
          description: "Creates tests",
          prompt: "You are a testing expert",
          allowed_tools: ["Read", "Write"],
          model: "sonnet"
        )

      assert :ok = Agent.validate(agent)
    end

    test "validates agent with minimal fields" do
      agent =
        Agent.new(
          description: "Simple agent",
          prompt: "Be helpful"
        )

      assert :ok = Agent.validate(agent)
    end

    test "returns error when description is missing" do
      agent = %Agent{
        prompt: "You are helpful",
        description: nil
      }

      assert {:error, :description_required} = Agent.validate(agent)
    end

    test "returns error when description is empty string" do
      agent =
        Agent.new(
          description: "",
          prompt: "You are helpful"
        )

      assert {:error, :description_required} = Agent.validate(agent)
    end

    test "returns error when prompt is missing" do
      agent = %Agent{
        description: "Test agent",
        prompt: nil
      }

      assert {:error, :prompt_required} = Agent.validate(agent)
    end

    test "returns error when prompt is empty string" do
      agent =
        Agent.new(
          description: "Test agent",
          prompt: ""
        )

      assert {:error, :prompt_required} = Agent.validate(agent)
    end

    test "returns error when allowed_tools is not a list" do
      agent =
        Agent.new(
          description: "Test agent",
          prompt: "You are helpful",
          allowed_tools: "Read"
        )

      assert {:error, :allowed_tools_must_be_list} = Agent.validate(agent)
    end

    test "returns error when allowed_tools contains non-strings" do
      agent =
        Agent.new(
          description: "Test agent",
          prompt: "You are helpful",
          allowed_tools: ["Read", 123, "Write"]
        )

      assert {:error, :allowed_tools_must_be_strings} = Agent.validate(agent)
    end

    test "returns error when model is not a string" do
      agent =
        Agent.new(
          description: "Test agent",
          prompt: "You are helpful",
          model: :invalid
        )

      assert {:error, :model_must_be_string} = Agent.validate(agent)
    end

    test "allows nil allowed_tools" do
      agent =
        Agent.new(
          description: "Test agent",
          prompt: "You are helpful",
          allowed_tools: nil
        )

      assert :ok = Agent.validate(agent)
    end

    test "allows nil model" do
      agent =
        Agent.new(
          description: "Test agent",
          prompt: "You are helpful",
          model: nil
        )

      assert :ok = Agent.validate(agent)
    end

    test "allows empty allowed_tools list" do
      agent =
        Agent.new(
          description: "Test agent",
          prompt: "You are helpful",
          allowed_tools: []
        )

      assert :ok = Agent.validate(agent)
    end
  end

  describe "to_cli_map/1" do
    test "converts agent to CLI-compatible map format" do
      agent =
        Agent.new(
          description: "Code reviewer",
          prompt: "You are a code reviewer",
          allowed_tools: ["Read", "Grep"],
          model: "sonnet"
        )

      map = Agent.to_cli_map(agent)

      assert map == %{
               "description" => "Code reviewer",
               "prompt" => "You are a code reviewer",
               "tools" => ["Read", "Grep"],
               "model" => "sonnet"
             }
    end

    test "omits nil fields from CLI map" do
      agent =
        Agent.new(
          description: "Simple agent",
          prompt: "Be helpful"
        )

      map = Agent.to_cli_map(agent)

      assert map == %{
               "description" => "Simple agent",
               "prompt" => "Be helpful"
             }

      refute Map.has_key?(map, "tools")
      refute Map.has_key?(map, "model")
    end

    test "handles empty allowed_tools list" do
      agent =
        Agent.new(
          description: "No tools agent",
          prompt: "You have no tools",
          allowed_tools: []
        )

      map = Agent.to_cli_map(agent)

      assert map["tools"] == []
    end
  end
end
