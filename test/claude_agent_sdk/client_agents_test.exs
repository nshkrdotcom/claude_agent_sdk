defmodule ClaudeAgentSDK.ClientAgentsTest do
  @moduledoc """
  Tests for Client agent switching functionality.

  Tests the Client GenServer's ability to switch between agents
  at runtime while preserving conversation context.
  """
  use ClaudeAgentSDK.SupertesterCase, isolation: :basic

  @moduletag :requires_cli
  # Most tests spawn real CLI process (no MockTransport)
  @moduletag :live_cli

  alias ClaudeAgentSDK.{Agent, Client, Options}

  setup do
    # Define test agents
    code_agent =
      Agent.new(
        description: "Code expert",
        prompt: "You are an expert programmer",
        allowed_tools: ["Read", "Write", "Bash"],
        model: "claude-sonnet-4"
      )

    doc_agent =
      Agent.new(
        description: "Documentation expert",
        prompt: "You excel at writing clear documentation",
        allowed_tools: ["Read", "Write"],
        model: "claude-opus-4"
      )

    research_agent =
      Agent.new(
        description: "Research specialist",
        prompt: "You are skilled at research and analysis",
        allowed_tools: ["WebSearch", "WebFetch"],
        model: "claude-sonnet-4"
      )

    %{
      code_agent: code_agent,
      doc_agent: doc_agent,
      research_agent: research_agent
    }
  end

  describe "set_agent/2" do
    test "switches to a different agent", %{code_agent: code_agent, doc_agent: doc_agent} do
      options =
        Options.new(
          agents: %{
            coder: code_agent,
            writer: doc_agent
          },
          agent: :coder
        )

      {:ok, client} = Client.start_link(options)

      # Switch to doc agent
      assert :ok = Client.set_agent(client, :writer)

      # Verify the state was updated
      state = :sys.get_state(client)
      assert state.options.agent == :writer

      Client.stop(client)
    end

    test "returns error when switching to non-existent agent", %{code_agent: code_agent} do
      options =
        Options.new(
          agents: %{coder: code_agent},
          agent: :coder
        )

      {:ok, client} = Client.start_link(options)

      assert {:error, :agent_not_found} = Client.set_agent(client, :nonexistent)

      Client.stop(client)
    end

    test "returns error when no agents are configured" do
      options = Options.new(agents: nil)

      {:ok, client} = Client.start_link(options)

      assert {:error, :no_agents_configured} = Client.set_agent(client, :any_agent)

      Client.stop(client)
    end

    test "updates system prompt when switching agents", %{
      code_agent: code_agent,
      doc_agent: doc_agent
    } do
      options =
        Options.new(
          agents: %{
            coder: code_agent,
            writer: doc_agent
          },
          agent: :coder
        )

      {:ok, client} = Client.start_link(options)

      # Get initial state
      initial_state = :sys.get_state(client)
      assert initial_state.options.system_prompt == code_agent.prompt

      # Switch agent
      :ok = Client.set_agent(client, :writer)

      # Verify system prompt changed
      new_state = :sys.get_state(client)
      assert new_state.options.system_prompt == doc_agent.prompt

      Client.stop(client)
    end

    test "updates allowed tools when switching agents", %{
      code_agent: code_agent,
      doc_agent: doc_agent
    } do
      options =
        Options.new(
          agents: %{
            coder: code_agent,
            writer: doc_agent
          },
          agent: :coder
        )

      {:ok, client} = Client.start_link(options)

      # Initial allowed tools
      initial_state = :sys.get_state(client)
      assert initial_state.options.allowed_tools == ["Read", "Write", "Bash"]

      # Switch agent
      :ok = Client.set_agent(client, :writer)

      # Verify allowed tools changed
      new_state = :sys.get_state(client)
      assert new_state.options.allowed_tools == ["Read", "Write"]

      Client.stop(client)
    end

    test "updates model when switching agents", %{code_agent: code_agent, doc_agent: doc_agent} do
      options =
        Options.new(
          agents: %{
            coder: code_agent,
            writer: doc_agent
          },
          agent: :coder
        )

      {:ok, client} = Client.start_link(options)

      # Initial model
      initial_state = :sys.get_state(client)
      assert initial_state.options.model == "claude-sonnet-4"

      # Switch agent
      :ok = Client.set_agent(client, :writer)

      # Verify model changed
      new_state = :sys.get_state(client)
      assert new_state.options.model == "claude-opus-4"

      Client.stop(client)
    end

    test "switches between multiple agents", %{
      code_agent: code_agent,
      doc_agent: doc_agent,
      research_agent: research_agent
    } do
      options =
        Options.new(
          agents: %{
            coder: code_agent,
            writer: doc_agent,
            researcher: research_agent
          },
          agent: :coder
        )

      {:ok, client} = Client.start_link(options)

      # Switch to writer
      assert :ok = Client.set_agent(client, :writer)
      state1 = :sys.get_state(client)
      assert state1.options.agent == :writer

      # Switch to researcher
      assert :ok = Client.set_agent(client, :researcher)
      state2 = :sys.get_state(client)
      assert state2.options.agent == :researcher

      # Switch back to coder
      assert :ok = Client.set_agent(client, :coder)
      state3 = :sys.get_state(client)
      assert state3.options.agent == :coder

      Client.stop(client)
    end

    test "preserves conversation context when switching agents", %{
      code_agent: code_agent,
      doc_agent: doc_agent
    } do
      options =
        Options.new(
          agents: %{
            coder: code_agent,
            writer: doc_agent
          },
          agent: :coder
        )

      {:ok, client} = Client.start_link(options)

      # Send a message with code agent
      Client.send_message(client, "Write a function")

      # Get session ID from initial state
      state1 = :sys.get_state(client)
      session_id = state1.session_id

      # Switch to doc agent
      :ok = Client.set_agent(client, :writer)

      # Verify session ID is preserved
      state2 = :sys.get_state(client)
      assert state2.session_id == session_id

      Client.stop(client)
    end

    test "returns the active agent name", %{code_agent: code_agent, doc_agent: doc_agent} do
      options =
        Options.new(
          agents: %{
            coder: code_agent,
            writer: doc_agent
          },
          agent: :coder
        )

      {:ok, client} = Client.start_link(options)

      # Get current agent
      assert {:ok, :coder} = Client.get_agent(client)

      # Switch and verify
      :ok = Client.set_agent(client, :writer)
      assert {:ok, :writer} = Client.get_agent(client)

      Client.stop(client)
    end

    test "returns error when getting agent with no agents configured" do
      options = Options.new(agents: nil)

      {:ok, client} = Client.start_link(options)

      assert {:error, :no_agents_configured} = Client.get_agent(client)

      Client.stop(client)
    end
  end

  describe "Agent integration with message streaming" do
    @tag :live_cli
    # This test would require actual CLI integration
    test "switches agent mid-conversation and continues correctly", %{
      code_agent: code_agent,
      doc_agent: doc_agent
    } do
      options =
        Options.new(
          agents: %{
            coder: code_agent,
            writer: doc_agent
          },
          agent: :coder,
          max_turns: 2
        )

      {:ok, client} = Client.start_link(options)

      # Start conversation with code agent
      Client.send_message(client, "Write a hello world function")

      # Collect first response
      task =
        Task.async(fn ->
          Client.stream_messages(client)
          |> Enum.take(2)
          |> Enum.to_list()
        end)

      messages = Task.await(task, :infinity)
      assert length(messages) > 0

      # Switch to doc agent
      :ok = Client.set_agent(client, :writer)

      # Continue conversation with new agent
      Client.send_message(client, "Document the function you created")

      # Verify messages continue streaming
      task2 =
        Task.async(fn ->
          Client.stream_messages(client)
          |> Enum.take(2)
          |> Enum.to_list()
        end)

      more_messages = Task.await(task2, :infinity)
      assert length(more_messages) > 0

      Client.stop(client)
    end
  end

  describe "Agent validation on start_link" do
    test "starts successfully with valid agents", %{code_agent: code_agent} do
      options =
        Options.new(
          agents: %{coder: code_agent},
          agent: :coder
        )

      assert {:ok, client} = Client.start_link(options)

      Client.stop(client)
    end

    test "fails to start with invalid agent configuration" do
      Process.flag(:trap_exit, true)

      invalid_agent =
        Agent.new(
          # Invalid
          description: "",
          prompt: "Test"
        )

      options =
        Options.new(
          agents: %{invalid: invalid_agent},
          agent: :invalid
        )

      {:error, {:agents_validation_failed, {:invalid_agent, :invalid, :description_required}}} =
        Client.start_link(options)
    end

    test "fails to start when active agent not in agents map", %{code_agent: code_agent} do
      Process.flag(:trap_exit, true)

      options =
        Options.new(
          agents: %{coder: code_agent},
          agent: :nonexistent
        )

      {:error, {:agents_validation_failed, {:agent_not_found, :nonexistent}}} =
        Client.start_link(options)
    end

    test "starts successfully with nil agents and nil agent" do
      options =
        Options.new(
          agents: nil,
          agent: nil
        )

      assert {:ok, client} = Client.start_link(options)

      Client.stop(client)
    end
  end

  describe "get_available_agents/1" do
    test "returns list of available agent names", %{
      code_agent: code_agent,
      doc_agent: doc_agent,
      research_agent: research_agent
    } do
      options =
        Options.new(
          agents: %{
            coder: code_agent,
            writer: doc_agent,
            researcher: research_agent
          },
          agent: :coder
        )

      {:ok, client} = Client.start_link(options)

      {:ok, agents} = Client.get_available_agents(client)

      assert :coder in agents
      assert :writer in agents
      assert :researcher in agents
      assert length(agents) == 3

      Client.stop(client)
    end

    test "returns empty list when no agents configured" do
      options = Options.new(agents: nil)

      {:ok, client} = Client.start_link(options)

      assert {:ok, []} = Client.get_available_agents(client)

      Client.stop(client)
    end
  end
end
