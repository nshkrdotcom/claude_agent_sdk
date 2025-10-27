defmodule ClaudeAgentSDK.TestSupport.TestFixtures do
  @moduledoc """
  Common test fixtures for integration testing.

  Provides reusable hooks, MCP servers, tools, and callbacks.
  """

  alias ClaudeAgentSDK.Hooks.Matcher

  @doc "Creates a simple allow-all hook"
  def allow_all_hook do
    callback = fn _tool_name, _input, _context ->
      %{behavior: :allow}
    end

    Matcher.new("*", [callback])
  end

  @doc "Creates a deny-all hook"
  def deny_all_hook do
    callback = fn _tool_name, _input, _context ->
      %{behavior: :deny, reason: "Denied by test"}
    end

    Matcher.new("*", [callback])
  end

  @doc "Creates a hook that allows specific tool"
  def allow_tool_hook(tool_name) do
    callback = fn _tool_name, _input, _context ->
      %{behavior: :allow}
    end

    Matcher.new(tool_name, [callback])
  end

  @doc "Creates a recording hook that tracks invocations"
  def recording_hook(test_pid \\ self()) do
    callback = fn tool_name, input, context ->
      send(test_pid, {:hook_called, :pre_tool_use, tool_name, input, context})
      %{behavior: :allow}
    end

    Matcher.new("*", [callback])
  end

  @doc "Creates a test permission callback that allows all"
  def allow_all_permission do
    fn _context -> :allow end
  end

  @doc "Creates a test permission callback that denies all"
  def deny_all_permission do
    fn _context -> :deny end
  end

  @doc "Creates a recording permission callback"
  def recording_permission(test_pid \\ self()) do
    fn context ->
      send(test_pid, {:permission_callback, context})
      :allow
    end
  end

  @doc "Creates a simple test SDK MCP server (placeholder for actual implementation)"
  def test_sdk_mcp_server(name \\ "test_server") do
    # This is a simplified version - in reality would use ClaudeAgentSDK.create_sdk_mcp_server
    %{
      type: :sdk,
      name: name,
      version: "1.0.0",
      tools: []
    }
  end

  @doc "Creates calculator SDK MCP server for testing"
  def calculator_mcp_server do
    %{
      type: :sdk,
      name: "calculator",
      version: "1.0.0",
      tools: [
        %{
          name: "add",
          description: "Adds two numbers",
          input_schema: %{
            "type" => "object",
            "properties" => %{
              "a" => %{"type" => "number"},
              "b" => %{"type" => "number"}
            },
            "required" => ["a", "b"]
          }
        }
      ]
    }
  end

  @doc "Creates a test agent definition"
  def test_agent(opts \\ []) do
    %ClaudeAgentSDK.Agent{
      description: Keyword.get(opts, :description, "Test agent"),
      prompt: Keyword.get(opts, :prompt, "You are a test agent"),
      allowed_tools: Keyword.get(opts, :allowed_tools, [])
    }
  end

  @doc "Standard test options with no control features"
  def basic_options(overrides \\ []) do
    %ClaudeAgentSDK.Options{
      model: "sonnet",
      max_turns: 5,
      verbose: true
    }
    |> struct(overrides)
  end

  @doc "Options with hooks configured"
  def options_with_hooks(hook, overrides \\ []) do
    %ClaudeAgentSDK.Options{
      model: "sonnet",
      hooks: %{pre_tool_use: [hook]}
    }
    |> struct(overrides)
  end

  @doc "Options with SDK MCP server"
  def options_with_mcp(server, overrides \\ []) do
    %ClaudeAgentSDK.Options{
      model: "sonnet",
      mcp_servers: %{server.name => server}
    }
    |> struct(overrides)
  end

  @doc "Options with permission callback"
  def options_with_permissions(callback, overrides \\ []) do
    %ClaudeAgentSDK.Options{
      model: "sonnet",
      can_use_tool: callback
    }
    |> struct(overrides)
  end
end
