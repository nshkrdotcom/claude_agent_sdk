defmodule ClaudeAgentSDK.Transport.StreamingRouterTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.Hooks.Matcher
  alias ClaudeAgentSDK.{Options, Transport.StreamingRouter}

  describe "select_transport/1 - defaults" do
    test "empty options → CLI-only" do
      assert :streaming_session = StreamingRouter.select_transport(%Options{})
    end

    test "standard options → CLI-only" do
      opts = %Options{
        model: "sonnet",
        max_turns: 5,
        verbose: true
      }

      assert :streaming_session = StreamingRouter.select_transport(opts)
    end
  end

  describe "select_transport/1 - hooks detection" do
    test "with hooks → control client" do
      callback = fn _, _, _ -> %{behavior: :allow} end

      opts = %Options{
        hooks: %{
          pre_tool_use: [Matcher.new("Bash", [callback])]
        }
      }

      assert :control_client = StreamingRouter.select_transport(opts)
    end

    test "empty hooks map → CLI-only" do
      opts = %Options{hooks: %{}}
      assert :streaming_session = StreamingRouter.select_transport(opts)
    end

    test "hooks with empty matchers → CLI-only" do
      opts = %Options{
        hooks: %{pre_tool_use: []}
      }

      assert :streaming_session = StreamingRouter.select_transport(opts)
    end

    test "multiple hook types → control client" do
      callback = fn _, _, _ -> %{behavior: :allow} end

      opts = %Options{
        hooks: %{
          pre_tool_use: [Matcher.new("Bash", [callback])],
          post_tool_use: [Matcher.new("Write", [callback])]
        }
      }

      assert :control_client = StreamingRouter.select_transport(opts)
    end
  end

  describe "select_transport/1 - SDK MCP detection" do
    test "SDK MCP server → control client" do
      server = %{
        type: :sdk,
        name: "test",
        version: "1.0.0",
        tools: []
      }

      opts = %Options{mcp_servers: %{"test" => server}}

      assert :control_client = StreamingRouter.select_transport(opts)
    end

    test "external MCP server only → CLI-only" do
      opts = %Options{
        mcp_servers: %{
          "external" => %{
            type: :stdio,
            command: "mcp-server",
            args: []
          }
        }
      }

      assert :streaming_session = StreamingRouter.select_transport(opts)
    end

    test "mixed SDK and external → control client" do
      sdk_server = %{
        type: :sdk,
        name: "sdk",
        tools: []
      }

      opts = %Options{
        mcp_servers: %{
          "sdk" => sdk_server,
          "external" => %{type: :stdio, command: "test", args: []}
        }
      }

      # SDK server presence requires control
      assert :control_client = StreamingRouter.select_transport(opts)
    end

    test "empty mcp_servers → CLI-only" do
      opts = %Options{mcp_servers: %{}}
      assert :streaming_session = StreamingRouter.select_transport(opts)
    end
  end

  describe "select_transport/1 - permission callback" do
    test "with can_use_tool callback → control client" do
      callback = fn _ctx -> :allow end
      opts = %Options{can_use_tool: callback}

      assert :control_client = StreamingRouter.select_transport(opts)
    end

    test "nil can_use_tool → CLI-only" do
      opts = %Options{can_use_tool: nil}
      assert :streaming_session = StreamingRouter.select_transport(opts)
    end
  end

  describe "select_transport/1 - agents" do
    test "with active agent → control client" do
      agent = %ClaudeAgentSDK.Agent{
        description: "Test",
        prompt: "You are a test agent"
      }

      opts = %Options{
        agents: %{test: agent},
        agent: :test
      }

      assert :control_client = StreamingRouter.select_transport(opts)
    end

    test "agents configured but none active → control client" do
      # Still requires control for runtime switching
      agent = %ClaudeAgentSDK.Agent{
        description: "Test",
        prompt: "Test"
      }

      opts = %Options{
        agents: %{test: agent},
        agent: nil
      }

      assert :control_client = StreamingRouter.select_transport(opts)
    end

    test "empty agents → CLI-only" do
      opts = %Options{agents: %{}}
      assert :streaming_session = StreamingRouter.select_transport(opts)
    end

    test "nil agents → CLI-only" do
      opts = %Options{agents: nil}
      assert :streaming_session = StreamingRouter.select_transport(opts)
    end
  end

  describe "select_transport/1 - permission mode" do
    test "accept_edits mode → control client" do
      opts = %Options{permission_mode: :accept_edits}
      assert :control_client = StreamingRouter.select_transport(opts)
    end

    test "bypass_permissions mode → control client" do
      opts = %Options{permission_mode: :bypass_permissions}
      assert :control_client = StreamingRouter.select_transport(opts)
    end

    test "plan mode → control client" do
      opts = %Options{permission_mode: :plan}
      assert :control_client = StreamingRouter.select_transport(opts)
    end

    test "default mode → CLI-only" do
      opts = %Options{permission_mode: :default}
      assert :streaming_session = StreamingRouter.select_transport(opts)
    end

    test "nil permission_mode → CLI-only" do
      opts = %Options{permission_mode: nil}
      assert :streaming_session = StreamingRouter.select_transport(opts)
    end
  end

  describe "select_transport/1 - explicit override" do
    test "preferred_transport :cli with hooks → CLI-only" do
      callback = fn _, _, _ -> %{behavior: :allow} end

      opts = %Options{
        hooks: %{pre_tool_use: [Matcher.new("Bash", [callback])]},
        preferred_transport: :cli
      }

      # Override takes precedence
      assert :streaming_session = StreamingRouter.select_transport(opts)
    end

    test "preferred_transport :control without features → control client" do
      opts = %Options{preferred_transport: :control}

      # Forces control even without features
      assert :control_client = StreamingRouter.select_transport(opts)
    end

    test "nil preferred_transport → automatic detection" do
      opts = %Options{preferred_transport: nil}
      assert :streaming_session = StreamingRouter.select_transport(opts)
    end
  end

  describe "select_transport/1 - combined features" do
    test "multiple control features → control client" do
      callback = fn _, _, _ -> %{behavior: :allow} end
      agent = %ClaudeAgentSDK.Agent{description: "Test", prompt: "Test"}

      sdk_server = %{
        type: :sdk,
        name: "test",
        tools: []
      }

      opts = %Options{
        hooks: %{pre_tool_use: [Matcher.new("Bash", [callback])]},
        agents: %{test: agent},
        agent: :test,
        mcp_servers: %{"test" => sdk_server},
        can_use_tool: callback,
        permission_mode: :plan
      }

      # Should still be control (all features present)
      assert :control_client = StreamingRouter.select_transport(opts)
    end

    test "external MCP + standard options → CLI-only" do
      opts = %Options{
        model: "opus",
        max_turns: 10,
        mcp_servers: %{
          "ext" => %{type: :stdio, command: "test", args: []}
        }
      }

      # External MCP doesn't require control
      assert :streaming_session = StreamingRouter.select_transport(opts)
    end
  end

  describe "requires_control_protocol?/1" do
    test "returns true for hooks" do
      callback = fn _, _, _ -> %{behavior: :allow} end
      opts = %Options{hooks: %{pre_tool_use: [Matcher.new("Bash", [callback])]}}

      assert StreamingRouter.requires_control_protocol?(opts)
    end

    test "returns false for empty options" do
      refute StreamingRouter.requires_control_protocol?(%Options{})
    end

    test "returns true for SDK MCP" do
      server = %{type: :sdk, name: "test", tools: []}
      opts = %Options{mcp_servers: %{"test" => server}}

      assert StreamingRouter.requires_control_protocol?(opts)
    end

    test "returns false for external MCP only" do
      opts = %Options{
        mcp_servers: %{"ext" => %{type: :stdio, command: "test", args: []}}
      }

      refute StreamingRouter.requires_control_protocol?(opts)
    end
  end

  describe "explain/1" do
    test "provides readable explanation for hooks" do
      callback = fn _, _, _ -> %{behavior: :allow} end
      opts = %Options{hooks: %{pre_tool_use: [Matcher.new("Bash", [callback])]}}

      explanation = StreamingRouter.explain(opts)

      assert explanation =~ "control_client"
      assert explanation =~ "hooks"
    end

    test "provides readable explanation for CLI-only" do
      explanation = StreamingRouter.explain(%Options{})

      assert explanation =~ "streaming_session"
      assert explanation =~ "default"
    end

    test "shows override reason" do
      opts = %Options{preferred_transport: :cli}

      explanation = StreamingRouter.explain(opts)

      assert explanation =~ "streaming_session"
      assert explanation =~ "explicit override"
    end

    test "lists all detected features" do
      callback = fn _, _, _ -> %{behavior: :allow} end
      agent = %ClaudeAgentSDK.Agent{description: "Test", prompt: "Test"}
      server = %{type: :sdk, name: "test", tools: []}

      opts = %Options{
        hooks: %{pre_tool_use: [Matcher.new("Bash", [callback])]},
        agents: %{test: agent},
        mcp_servers: %{"test" => server},
        can_use_tool: callback
      }

      explanation = StreamingRouter.explain(opts)

      # Should list all features
      assert explanation =~ ":hooks"
      assert explanation =~ ":agents"
      assert explanation =~ ":sdk_mcp"
      assert explanation =~ ":permission_callback"
    end
  end

  describe "edge cases" do
    test "handles options with only include_partial_messages" do
      opts = %Options{include_partial_messages: true}

      # Should still default to CLI-only
      assert :streaming_session = StreamingRouter.select_transport(opts)
    end

    test "handles invalid permission mode gracefully" do
      # Type system should prevent this, but test defense
      opts = %Options{permission_mode: :invalid}

      # Should default to CLI-only
      assert :streaming_session = StreamingRouter.select_transport(opts)
    end
  end
end
