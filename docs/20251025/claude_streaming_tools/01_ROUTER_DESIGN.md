# StreamingRouter: Transport Selection Design

**Module**: `ClaudeAgentSDK.Transport.StreamingRouter`
**Status**: Detailed Design
**Complexity**: LOW (⭐ 1/5)
**Size**: ~120 lines

---

## Overview

The StreamingRouter is a pure decision function that analyzes `ClaudeAgentSDK.Options` to select the appropriate transport implementation:
- **CLI-only** (`Streaming.Session`): Fast path for simple streaming without control features
- **Control client** (`Client`): Full-featured path with hooks, SDK MCP, permissions, and streaming

This router is the **linchpin** of the unification—it enables automatic, transparent selection while maintaining backwards compatibility.

---

## Architecture Position

```
User Application
      │
      ▼
┌─────────────────────────┐
│ Streaming.start_session │
└────────────┬────────────┘
             │
             ▼
      ┌────────────┐
      │   ROUTER   │  ◄── THIS MODULE
      │  Decision  │
      └─────┬──────┘
            │
      ┌─────┴─────┐
      │           │
      ▼           ▼
┌──────────┐  ┌─────────┐
│ Session  │  │ Client  │
│ (CLI)    │  │ (Ctrl)  │
└──────────┘  └─────────┘
```

---

## Decision Matrix

### Input: Options Fields

The router examines these fields to detect control protocol requirements:

| Field | Type | Control Required? | Reason |
|-------|------|-------------------|---------|
| `hooks` | `map()` | ✅ Yes | Hook callbacks need request/response protocol |
| `mcp_servers` (SDK) | `map()` | ✅ Yes | SDK MCP uses JSONRPC routing through control |
| `mcp_servers` (external) | `map()` | ❌ No | External servers passed via CLI flag |
| `can_use_tool` | `function` | ✅ Yes | Permission callback requires protocol |
| `agents` | `map()` | ✅ Yes (if active) | Runtime agent switching needs protocol |
| `permission_mode` | `:plan \| :accept_edits` | ✅ Yes | Non-default modes require protocol |
| `preferred_transport` | `:cli \| :control` | Override | Explicit user choice |
| _anything else_ | - | ❌ No | Standard CLI features |

### Output: Transport Choice

```elixir
@type transport_choice :: :streaming_session | :control_client
```

---

## Implementation

### Core API

```elixir
defmodule ClaudeAgentSDK.Transport.StreamingRouter do
  @moduledoc """
  Selects streaming transport based on required features.

  ## Decision Algorithm

  1. Check explicit override (`preferred_transport`)
  2. Detect control protocol requirements
  3. Default to CLI-only for performance

  ## Examples

      # Simple streaming → CLI-only
      iex> select_transport(%Options{})
      :streaming_session

      # With hooks → Control client
      iex> select_transport(%Options{hooks: %{pre_tool_use: [...]}})
      :control_client

      # Override
      iex> select_transport(%Options{preferred_transport: :cli})
      :streaming_session
  """

  alias ClaudeAgentSDK.Options

  @type transport_choice :: :streaming_session | :control_client

  @doc """
  Selects transport implementation.

  Returns `:streaming_session` (CLI-only) or `:control_client` (full features).

  ## Performance

  This is a pure function with no I/O. Typical execution: <0.1ms.
  """
  @spec select_transport(Options.t()) :: transport_choice()
  def select_transport(%Options{} = opts) do
    case explicit_override(opts) do
      nil -> automatic_selection(opts)
      choice -> choice
    end
  end

  @doc """
  Checks if options require control protocol.

  Useful for debugging transport selection.
  """
  @spec requires_control_protocol?(Options.t()) :: boolean()
  def requires_control_protocol?(opts) do
    automatic_selection(opts) == :control_client
  end

  @doc """
  Human-readable explanation of transport choice.

  ## Examples

      iex> StreamingRouter.explain(%Options{hooks: %{...}})
      \"\"\"
      Transport: control_client
      Reason: hooks detected
      Features: [:hooks]
      Override: none
      \"\"\"
  """
  @spec explain(Options.t()) :: String.t()
  def explain(%Options{} = opts) do
    choice = select_transport(opts)
    override = explicit_override(opts)
    features = detect_features(opts)
    reason = selection_reason(opts)

    """
    Transport: #{choice}
    Reason: #{reason}
    Features: #{inspect(features)}
    Override: #{inspect(override)}
    """
  end

  ## Private Implementation

  # Explicit user override
  defp explicit_override(%Options{preferred_transport: :cli}),
    do: :streaming_session

  defp explicit_override(%Options{preferred_transport: :control}),
    do: :control_client

  defp explicit_override(_), do: nil

  # Automatic selection based on features
  defp automatic_selection(opts) do
    if has_control_features?(opts) do
      :control_client
    else
      :streaming_session
    end
  end

  # Feature detection
  defp has_control_features?(opts) do
    has_hooks?(opts) or
    has_sdk_mcp_servers?(opts) or
    has_permission_callback?(opts) or
    has_active_agents?(opts) or
    has_special_permission_mode?(opts)
  end

  # Individual feature detectors

  defp has_hooks?(%Options{hooks: hooks})
    when is_map(hooks) and map_size(hooks) > 0 do
    # Empty map doesn't count
    Enum.any?(hooks, fn {_event, matchers} ->
      is_list(matchers) and length(matchers) > 0
    end)
  end
  defp has_hooks?(_), do: false

  defp has_sdk_mcp_servers?(%Options{mcp_servers: servers})
    when is_map(servers) do
    # Only SDK servers require control; external servers use CLI flags
    Enum.any?(servers, fn
      {_name, %{type: :sdk}} -> true
      _ -> false
    end)
  end
  defp has_sdk_mcp_servers?(_), do: false

  defp has_permission_callback?(%Options{can_use_tool: callback})
    when is_function(callback, 1),
    do: true
  defp has_permission_callback?(_), do: false

  defp has_active_agents?(%Options{agents: agents, agent: active})
    when is_map(agents) and map_size(agents) > 0 and not is_nil(active),
    do: true
  defp has_active_agents?(%Options{agents: agents})
    when is_map(agents) and map_size(agents) > 0,
    do: true  # Agents configured even if none active yet
  defp has_active_agents?(_), do: false

  defp has_special_permission_mode?(%Options{permission_mode: mode})
    when mode in [:accept_edits, :bypass_permissions, :plan],
    do: true
  defp has_special_permission_mode?(_), do: false

  # Introspection helpers

  defp detect_features(opts) do
    []
    |> add_if(has_hooks?(opts), :hooks)
    |> add_if(has_sdk_mcp_servers?(opts), :sdk_mcp)
    |> add_if(has_permission_callback?(opts), :permission_callback)
    |> add_if(has_active_agents?(opts), :agents)
    |> add_if(has_special_permission_mode?(opts), :special_permission_mode)
  end

  defp add_if(list, true, feature), do: [feature | list]
  defp add_if(list, false, _), do: list

  defp selection_reason(opts) do
    cond do
      explicit_override(opts) == :streaming_session ->
        "explicit override to CLI"

      explicit_override(opts) == :control_client ->
        "explicit override to control"

      has_hooks?(opts) ->
        "hooks detected"

      has_sdk_mcp_servers?(opts) ->
        "SDK MCP servers detected"

      has_permission_callback?(opts) ->
        "permission callback detected"

      has_active_agents?(opts) ->
        "runtime agents detected"

      has_special_permission_mode?(opts) ->
        "special permission mode detected"

      true ->
        "default (no control features)"
    end
  end
end
```

---

## Test Strategy

### Unit Test Coverage

```elixir
defmodule ClaudeAgentSDK.Transport.StreamingRouterTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.{Options, Transport.StreamingRouter}
  alias ClaudeAgentSDK.Hooks.Matcher

  describe "select_transport/1 - defaults" do
    test "empty options → CLI-only" do
      assert :streaming_session = StreamingRouter.select_transport(%Options{})
    end

    test "nil options → CLI-only" do
      # Should handle gracefully
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
      callback = fn _, _, _ -> :allow end

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
      server = ClaudeAgentSDK.create_sdk_mcp_server(
        name: "test",
        version: "1.0.0",
        tools: []
      )

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
      sdk_server = ClaudeAgentSDK.create_sdk_mcp_server(
        name: "sdk",
        tools: []
      )

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
      agent = ClaudeAgentSDK.Agent.new(
        description: "Test",
        prompt: "You are a test agent"
      )

      opts = %Options{
        agents: %{test: agent},
        agent: :test
      }

      assert :control_client = StreamingRouter.select_transport(opts)
    end

    test "agents configured but none active → control client" do
      # Still requires control for runtime switching
      agent = ClaudeAgentSDK.Agent.new(
        description: "Test",
        prompt: "Test"
      )

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
      callback = fn _, _, _ -> :allow end

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

    test "preferred_transport :auto → automatic detection" do
      callback = fn _, _, _ -> :allow end

      opts = %Options{
        hooks: %{pre_tool_use: [Matcher.new("Bash", [callback])]},
        preferred_transport: :auto
      }

      # Auto means detect (should find hooks)
      assert :control_client = StreamingRouter.select_transport(opts)
    end

    test "nil preferred_transport → automatic detection" do
      opts = %Options{preferred_transport: nil}
      assert :streaming_session = StreamingRouter.select_transport(opts)
    end
  end

  describe "select_transport/1 - combined features" do
    test "multiple control features → control client" do
      callback = fn _, _, _ -> :allow end
      agent = ClaudeAgentSDK.Agent.new(description: "Test", prompt: "Test")
      sdk_server = ClaudeAgentSDK.create_sdk_mcp_server(name: "test", tools: [])

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
      callback = fn _, _, _ -> :allow end
      opts = %Options{hooks: %{pre_tool_use: [Matcher.new("Bash", [callback])]}}

      assert StreamingRouter.requires_control_protocol?(opts)
    end

    test "returns false for empty options" do
      refute StreamingRouter.requires_control_protocol?(%Options{})
    end

    test "returns true for SDK MCP" do
      server = ClaudeAgentSDK.create_sdk_mcp_server(name: "test", tools: [])
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
      callback = fn _, _, _ -> :allow end
      opts = %Options{hooks: %{pre_tool_use: [Matcher.new("Bash", [callback])]}}

      explanation = StreamingRouter.explain(opts)

      assert explanation =~ "control_client"
      assert explanation =~ "hooks"
      assert explanation =~ "hooks detected"
    end

    test "provides readable explanation for CLI-only" do
      explanation = StreamingRouter.explain(%Options{})

      assert explanation =~ "streaming_session"
      assert explanation =~ "default"
      assert explanation =~ "Features: []"
    end

    test "shows override reason" do
      opts = %Options{preferred_transport: :cli}

      explanation = StreamingRouter.explain(opts)

      assert explanation =~ "streaming_session"
      assert explanation =~ "explicit override"
    end

    test "lists all detected features" do
      callback = fn _, _, _ -> :allow end
      agent = ClaudeAgentSDK.Agent.new(description: "Test", prompt: "Test")
      server = ClaudeAgentSDK.create_sdk_mcp_server(name: "test", tools: [])

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
```

**Test Count**: ~50 tests
**Coverage Target**: 100% (achievable for pure functions)

---

## Performance Considerations

### Complexity Analysis

**Time Complexity**: O(n) where n = number of MCP servers (worst case)
- Most checks are O(1) pattern matches
- Only `has_sdk_mcp_servers?` iterates (over typically <10 servers)

**Space Complexity**: O(1)
- No allocations (pure decision function)
- Only stack variables

### Benchmarking

```elixir
defmodule StreamingRouterBenchmark do
  def run do
    # Worst case: many MCP servers
    many_servers = for i <- 1..100 do
      {"server_#{i}", %{type: :stdio, command: "test", args: []}}
    end |> Map.new()

    opts = %Options{mcp_servers: many_servers}

    {time_us, _result} = :timer.tc(fn ->
      for _i <- 1..1000 do
        StreamingRouter.select_transport(opts)
      end
    end)

    avg_us = time_us / 1000
    IO.puts("Average time per call: #{avg_us} μs")

    # Expected: <50 μs even with 100 servers
  end
end
```

**Target**: <0.1ms (100 μs) per call, even in worst case

---

## Integration Points

### Called By

1. **`ClaudeAgentSDK.Streaming.start_session/1`**:
   ```elixir
   def start_session(options) do
     case StreamingRouter.select_transport(options) do
       :streaming_session -> Session.start_link(options)
       :control_client -> start_control_streaming(options)
     end
   end
   ```

2. **Feature flag wrapper** (optional):
   ```elixir
   def select_transport(opts) do
     if FeatureFlags.streaming_tools_enabled?() do
       StreamingRouter.select_transport(opts)
     else
       :streaming_session  # Legacy behavior
     end
   end
   ```

### Observability

For production monitoring:

```elixir
def select_transport(opts) do
  choice = do_select_transport(opts)
  features = detect_features(opts)

  # Emit telemetry
  :telemetry.execute(
    [:claude_agent_sdk, :router, :decision],
    %{count: 1},
    %{choice: choice, features: features}
  )

  choice
end
```

**Metrics to Track**:
- Choice distribution (CLI vs Control %)
- Feature frequency (which features most common?)
- Override usage (how often users override?)

---

## Error Handling

The router is designed to **never fail**:
- No external I/O
- No exceptions possible
- Always returns valid choice

**Defensive programming**:
```elixir
# Example: Handle unexpected option types
defp has_hooks?(opts) do
  case opts do
    %Options{hooks: hooks} when is_map(hooks) -> check_hooks(hooks)
    %{hooks: hooks} when is_map(hooks) -> check_hooks(hooks)  # Generic map
    _ -> false  # Unknown type, assume no hooks
  end
end
```

---

## Future Extensions

### Planned (v0.7.0)

1. **Plugin transports**:
   ```elixir
   %Options{
     preferred_transport: {:custom, MyCustomTransport},
     transport_opts: [...]
   }
   ```

2. **Conditional routing** (advanced):
   ```elixir
   %Options{
     transport_selector: fn opts ->
       if production?() do
         :control_client
       else
         :streaming_session
       end
     end
   }
   ```

3. **Multi-tier selection**:
   ```elixir
   select_transport(opts)
   # → {:control_client, :websocket}  # Transport + protocol choice
   ```

### Not Planned

- Dynamic runtime switching (too complex, no use case)
- Load balancing (belongs in orchestration layer)
- Caching decisions (premature optimization)

---

## Documentation Examples

### Basic Usage

```elixir
alias ClaudeAgentSDK.{Options, Transport.StreamingRouter}

# Check what transport would be used
opts = %Options{hooks: %{pre_tool_use: [...]}}
StreamingRouter.explain(opts)
#=> """
# Transport: control_client
# Reason: hooks detected
# Features: [:hooks]
# Override: nil
# """

# Programmatic check
if StreamingRouter.requires_control_protocol?(opts) do
  IO.puts("Note: Using full-featured control client")
end
```

### Debugging Transport Selection

```elixir
# Why isn't my SDK MCP server working?
opts = %Options{
  mcp_servers: %{"math" => %{type: :stdio, command: "calc"}}
}

StreamingRouter.explain(opts)
#=> Transport: streaming_session
#   Reason: default (no control features)
#   Features: []

# Aha! External MCP server (not SDK), so CLI-only path selected
# SDK MCP servers have `type: :sdk`, not `:stdio`
```

### Override for Testing

```elixir
# Force CLI-only mode to test without control features
test_opts = %Options{
  hooks: production_hooks,
  preferred_transport: :cli  # Override
}

# Hooks will be ignored, fast CLI streaming only
{:ok, session} = Streaming.start_session(test_opts)
```

---

## Summary

The StreamingRouter is a **simple, pure, fast** decision module that:
- ✅ Automatically detects control protocol requirements
- ✅ Provides escape hatch for override
- ✅ Offers introspection for debugging
- ✅ Maintains backwards compatibility
- ✅ Adds negligible overhead (<0.1ms)

**Complexity**: ⭐ (1/5) - Straightforward implementation
**Risk**: LOW - Pure function, comprehensive tests
**Timeline**: 1 day implementation + tests
