# Claude Code Hooks Implementation for Elixir SDK

**Version:** 1.0
**Date:** 2025-10-16
**Status:** Design Proposal
**Authors:** Claude Code Development Team

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Background](#background)
3. [Requirements](#requirements)
4. [Architecture Overview](#architecture-overview)
5. [Detailed Design](#detailed-design)
6. [Implementation Plan](#implementation-plan)
7. [Examples](#examples)
8. [Testing Strategy](#testing-strategy)
9. [References](#references)

---

## Executive Summary

This document proposes adding Claude Code Hooks support to the Elixir SDK, bringing it to feature parity with the Python SDK. Hooks are callback functions that execute at specific lifecycle events during Claude's agent loop, enabling:

- **Intercepting tool calls** before/after execution
- **Adding contextual information** automatically
- **Controlling execution flow** based on runtime conditions
- **Implementing security policies** and validation
- **Monitoring and auditing** agent behavior

The implementation will follow the Python SDK's architecture while adapting to Elixir's functional, process-based paradigm.

---

## Background

### What are Claude Code Hooks?

Claude Code Hooks are functions invoked by the Claude Code CLI at specific points in the agent execution loop. Unlike tools (which Claude calls), hooks are invoked by the CLI application itself to provide deterministic processing and feedback.

**Key Characteristics:**
- **Not visible to Claude** - Hooks are infrastructure-level callbacks
- **Synchronous execution** - Block the agent loop until complete
- **Bidirectional control** - Can modify behavior, add context, or block actions
- **Pattern-based matching** - Target specific tools or events

### Current State

**Python SDK (`claude-agent-sdk-python`):**
- ✅ Full hooks implementation (v0.0.20+)
- ✅ All hook events supported (except SessionStart/SessionEnd/Notification due to setup limitations)
- ✅ Control protocol integration
- ✅ Comprehensive examples and tests

**Elixir SDK (`claude_agent_sdk`):**
- ❌ No hooks support
- ✅ Basic control protocol infrastructure exists (stdin/stdout streaming)
- ✅ Options system for CLI arguments
- ⚠️ Would need bidirectional communication for hooks

### Why Add Hooks?

1. **Feature Parity** - Match Python SDK capabilities
2. **Security** - Implement runtime validation and blocking
3. **Automation** - Add context automatically based on events
4. **Compliance** - Audit and log tool usage
5. **User Demand** - Common request from SDK users

---

## Requirements

### Functional Requirements

#### FR1: Hook Event Support
Support the following hook events:
- **PreToolUse** - Before tool execution
- **PostToolUse** - After tool execution
- **UserPromptSubmit** - When user submits a prompt
- **Stop** - When agent finishes
- **SubagentStop** - When subagent finishes
- **PreCompact** - Before context compaction

*Note: SessionStart, SessionEnd, and Notification hooks are not supported in SDK mode per Python SDK limitations.*

#### FR2: Hook Callback Interface
Hooks must be Elixir functions with signature:
```elixir
@type hook_callback ::
  (input :: map(), tool_use_id :: String.t() | nil, context :: map() ->
    hook_output :: map())
```

#### FR3: Hook Matcher Configuration
Support pattern-based matching:
```elixir
%{
  "PreToolUse" => [
    %HookMatcher{
      matcher: "Bash",           # Match specific tool
      hooks: [callback_fn]
    },
    %HookMatcher{
      matcher: "Write|Edit",     # Regex pattern
      hooks: [another_callback]
    }
  ]
}
```

#### FR4: Hook Output Control
Hooks must return maps with control fields:
- `continue` - Whether to continue execution (boolean)
- `stopReason` - Message when stopping (string)
- `systemMessage` - User-visible message (string)
- `reason` - Claude-visible feedback (string)
- `suppressOutput` - Hide from transcript (boolean)
- `hookSpecificOutput` - Event-specific control (map)

#### FR5: Permission Decision Control
PreToolUse hooks must support:
```elixir
%{
  "hookSpecificOutput" => %{
    "hookEventName" => "PreToolUse",
    "permissionDecision" => "allow" | "deny" | "ask",
    "permissionDecisionReason" => "..."
  }
}
```

#### FR6: Additional Context Injection
PostToolUse and UserPromptSubmit hooks must support:
```elixir
%{
  "hookSpecificOutput" => %{
    "hookEventName" => "PostToolUse",
    "additionalContext" => "Context for Claude to consider"
  }
}
```

### Non-Functional Requirements

#### NFR1: Performance
- Hook invocation overhead < 10ms
- No blocking on hook registration
- Efficient callback storage and lookup

#### NFR2: Reliability
- Graceful handling of hook errors
- Timeout protection (default 60s per hook)
- No crashes from malformed hook output

#### NFR3: Developer Experience
- Clear error messages for invalid hook configurations
- Comprehensive examples in documentation
- Type specs for all hook-related functions

#### NFR4: Compatibility
- Maintain backward compatibility with existing SDK code
- Optional feature - works without hooks configured
- Compatible with Claude CLI 2.0.0+

---

## Architecture Overview

### High-Level Components

```
┌─────────────────────────────────────────────────────────────┐
│                      User Application                        │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │         ClaudeAgentSDK.Client (New)                │    │
│  │  - Bidirectional streaming                         │    │
│  │  - Control protocol handler                        │    │
│  │  - Hook callback registry                          │    │
│  └────────────────────────────────────────────────────┘    │
│                           │                                  │
└───────────────────────────┼──────────────────────────────────┘
                            │
                ┌───────────▼──────────┐
                │   Control Protocol    │
                │   (JSON over stdio)   │
                └───────────┬──────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
    ┌───▼────┐      ┌───────▼────────┐   ┌────▼─────┐
    │ Claude │      │  Hook Callbacks │   │ Messages │
    │  CLI   │◄────►│   Invocation    │   │ Streaming│
    └────────┘      └─────────────────┘   └──────────┘
```

### Control Protocol Flow

```
┌──────────┐                                    ┌──────────┐
│  Elixir  │                                    │ Claude   │
│   SDK    │                                    │   CLI    │
└────┬─────┘                                    └─────┬────┘
     │                                                │
     │  1. Send initialize with hooks config          │
     ├───────────────────────────────────────────────>│
     │                                                │
     │  2. CLI registers hooks                        │
     │                                          ┌─────▼────┐
     │                                          │ Register │
     │                                          │  Hooks   │
     │                                          └─────┬────┘
     │                                                │
     │  3. Agent runs, hook triggers                  │
     │                                          ┌─────▼────────┐
     │                                          │PreToolUse:   │
     │                                          │  Bash cmd    │
     │                                          └─────┬────────┘
     │                                                │
     │  4. CLI sends hook_callback request            │
     │<───────────────────────────────────────────────┤
     │  {type: "control_request",                     │
     │   request: {subtype: "hook_callback",          │
     │            callback_id: "hook_0",              │
     │            input: {...}}}                      │
     │                                                │
     │  5. SDK invokes registered callback            │
 ┌───▼──────────┐                                     │
 │ Find hook_0  │                                     │
 │ Execute fn   │                                     │
 └───┬──────────┘                                     │
     │                                                │
     │  6. SDK sends control_response                 │
     ├───────────────────────────────────────────────>│
     │  {type: "control_response",                    │
     │   response: {subtype: "success",               │
     │             response: {...}}}                  │
     │                                                │
     │  7. CLI processes hook output                  │
     │                                          ┌─────▼────────┐
     │                                          │ Process      │
     │                                          │ Decision     │
     │                                          └─────┬────────┘
     │                                                │
     │  8. Continue or block based on hook            │
     │                                                │
```

### Key Design Decisions

#### Decision 1: Bidirectional Communication Required

**Problem:** Current Elixir SDK uses one-way streaming (SDK → CLI → SDK messages). Hooks require bidirectional communication where CLI can request SDK to invoke callbacks.

**Solution:** Implement `ClaudeAgentSDK.Client` module that:
- Maintains persistent connection via GenServer
- Handles both incoming messages and control requests
- Uses separate process for reading messages

**Alternatives Considered:**
- Polling CLI for hook requests ❌ (too slow, not supported by CLI)
- External hook scripts only ❌ (defeats purpose of SDK hooks)

#### Decision 2: Callback Registry with Unique IDs

**Problem:** How to reference Elixir functions from CLI when it triggers hooks?

**Solution:** Assign each callback a unique ID during initialization:
```elixir
# During init
hook_callbacks = %{
  "hook_0" => &MyModule.check_bash/3,
  "hook_1" => &MyModule.review_output/3
}

# In initialize request
%{
  "PreToolUse" => [
    %{
      "matcher" => "Bash",
      "hookCallbackIds" => ["hook_0"]
    }
  ]
}
```

**Alternatives Considered:**
- Function names as strings ❌ (not safe, serialization issues)
- Separate process per hook ❌ (too heavy, complex lifecycle)

#### Decision 3: Synchronous Hook Execution

**Problem:** Should hooks be async or sync?

**Solution:** Synchronous execution within GenServer to match Python SDK and CLI expectations:
- CLI blocks waiting for response
- Simpler error handling
- Predictable execution order

**Timeout Protection:**
- Default 60s timeout per hook
- Configurable via options
- Automatic error response on timeout

#### Decision 4: Options Structure

Add `hooks` field to existing `Options` struct:
```elixir
defstruct [
  # ... existing fields ...
  :hooks  # %{hook_event => [%HookMatcher{}]}
]
```

**Why not separate module?** Keep configuration centralized, matches Python SDK structure.

---

## Detailed Design

### Module Structure

```
lib/claude_agent_sdk/
├── client.ex              # NEW: Bidirectional client (GenServer)
├── hooks/
│   ├── hooks.ex          # NEW: Type definitions and utilities
│   ├── matcher.ex        # NEW: HookMatcher struct
│   ├── output.ex         # NEW: HookOutput struct and helpers
│   └── registry.ex       # NEW: Callback registry (internal)
├── control_protocol/
│   ├── protocol.ex       # NEW: Control message encoding/decoding
│   ├── request.ex        # NEW: Request types
│   └── response.ex       # NEW: Response types
├── options.ex            # MODIFIED: Add hooks field
├── process.ex            # EXISTING: Process management
└── ...
```

### Type Definitions

#### `lib/claude_agent_sdk/hooks/hooks.ex`

```elixir
defmodule ClaudeAgentSDK.Hooks do
  @moduledoc """
  Type definitions and utilities for Claude Code Hooks.

  See: https://docs.anthropic.com/en/docs/claude-code/hooks
  """

  alias ClaudeAgentSDK.Hooks.{Matcher, Output}

  @type hook_event ::
    :pre_tool_use
    | :post_tool_use
    | :user_prompt_submit
    | :stop
    | :subagent_stop
    | :pre_compact

  @type hook_input :: %{
    required(:hook_event_name) => String.t(),
    required(:session_id) => String.t(),
    required(:transcript_path) => String.t(),
    required(:cwd) => String.t(),
    optional(:tool_name) => String.t(),
    optional(:tool_input) => map(),
    optional(:tool_response) => term(),
    optional(:prompt) => String.t(),
    optional(:message) => String.t(),
    optional(:trigger) => String.t(),
    optional(:custom_instructions) => String.t(),
    optional(:stop_hook_active) => boolean()
  }

  @type hook_context :: %{
    optional(:signal) => reference()
  }

  @type hook_callback ::
    (hook_input(), String.t() | nil, hook_context() -> Output.t())

  @type hook_config :: %{
    hook_event() => [Matcher.t()]
  }

  @doc """
  Converts an Elixir hook event atom to CLI string format.

  ## Examples

      iex> event_to_string(:pre_tool_use)
      "PreToolUse"
  """
  @spec event_to_string(hook_event()) :: String.t()
  def event_to_string(:pre_tool_use), do: "PreToolUse"
  def event_to_string(:post_tool_use), do: "PostToolUse"
  def event_to_string(:user_prompt_submit), do: "UserPromptSubmit"
  def event_to_string(:stop), do: "Stop"
  def event_to_string(:subagent_stop), do: "SubagentStop"
  def event_to_string(:pre_compact), do: "PreCompact"

  @doc """
  Converts a CLI hook event string to Elixir atom.
  """
  @spec string_to_event(String.t()) :: hook_event() | nil
  def string_to_event("PreToolUse"), do: :pre_tool_use
  def string_to_event("PostToolUse"), do: :post_tool_use
  def string_to_event("UserPromptSubmit"), do: :user_prompt_submit
  def string_to_event("Stop"), do: :stop
  def string_to_event("SubagentStop"), do: :subagent_stop
  def string_to_event("PreCompact"), do: :pre_compact
  def string_to_event(_), do: nil

  @doc """
  Validates a hook configuration.

  Returns `:ok` if valid, `{:error, reason}` otherwise.
  """
  @spec validate_config(hook_config()) :: :ok | {:error, String.t()}
  def validate_config(config) when is_map(config) do
    config
    |> Enum.reduce_while(:ok, fn {event, matchers}, _acc ->
      cond do
        not is_atom(event) ->
          {:halt, {:error, "Hook event must be an atom, got: #{inspect(event)}"}}

        event not in [:pre_tool_use, :post_tool_use, :user_prompt_submit,
                      :stop, :subagent_stop, :pre_compact] ->
          {:halt, {:error, "Invalid hook event: #{event}"}}

        not is_list(matchers) ->
          {:halt, {:error, "Matchers must be a list for event #{event}"}}

        true ->
          case validate_matchers(matchers) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end
      end
    end)
  end

  def validate_config(_), do: {:error, "Hook config must be a map"}

  defp validate_matchers(matchers) do
    Enum.reduce_while(matchers, :ok, fn matcher, _acc ->
      if match?(%Matcher{}, matcher) do
        {:cont, :ok}
      else
        {:halt, {:error, "Each matcher must be a HookMatcher struct"}}
      end
    end)
  end
end
```

#### `lib/claude_agent_sdk/hooks/matcher.ex`

```elixir
defmodule ClaudeAgentSDK.Hooks.Matcher do
  @moduledoc """
  Hook matcher configuration.

  Defines which hooks should run for which tool patterns and
  how long callbacks are allowed to execute before timing out.
  """

  alias ClaudeAgentSDK.Hooks
  @min_timeout_ms 1_000

  @type t :: %__MODULE__{
          matcher: String.t() | nil,
          hooks: [Hooks.hook_callback()],
          timeout_ms: pos_integer() | nil
        }

  @enforce_keys [:hooks]
  defstruct [:matcher, :hooks, :timeout_ms]

  @doc """
  Creates a new hook matcher.

  ## Parameters

  - `matcher` - Tool name pattern (e.g., "Bash", "Write|Edit", "*")
                `nil` matches all tools
  - `hooks` - List of callback functions
  - `opts` - Keyword list
    - `:timeout_ms` - Optional timeout in milliseconds (default 60s, floored to 1s)

  ## Examples

      # Match specific tool
      Matcher.new("Bash", [&MyModule.check_bash/3])

      # Match multiple tools with regex
      Matcher.new("Write|Edit", [&check_file_edit/3])

      # Match all tools
      Matcher.new(nil, [&log_all_tools/3])
  """
  @spec new(String.t() | nil, [Hooks.hook_callback()], keyword()) :: t()
  def new(matcher, hooks, opts \\ []) when is_list(hooks) and is_list(opts) do
    %__MODULE__{
      matcher: matcher,
      hooks: hooks,
      timeout_ms: sanitize_timeout_ms(Keyword.get(opts, :timeout_ms))
    }
  end

  @doc """
  Converts matcher to CLI format for initialization.
  """
  @spec to_cli_format(t(), (Hooks.hook_callback() -> String.t())) :: map()
  def to_cli_format(%__MODULE__{} = matcher, callback_id_fn) do
    callback_ids = Enum.map(matcher.hooks, callback_id_fn)

    %{
      "matcher" => matcher.matcher,
      "hookCallbackIds" => callback_ids
    }
    |> maybe_put_timeout(sanitize_timeout_ms(matcher.timeout_ms))
  end

  def sanitize_timeout_ms(nil), do: nil

  def sanitize_timeout_ms(timeout_ms) when is_integer(timeout_ms) and timeout_ms > 0 do
    max(timeout_ms, @min_timeout_ms)
  end

  def sanitize_timeout_ms(timeout_ms) when is_float(timeout_ms) and timeout_ms > 0 do
    timeout_ms |> round() |> max(@min_timeout_ms)
  end

  def sanitize_timeout_ms(_), do: @min_timeout_ms

  defp maybe_put_timeout(map, nil), do: map
  defp maybe_put_timeout(map, timeout_ms), do: Map.put(map, "timeout", timeout_ms)
end
```

#### `lib/claude_agent_sdk/hooks/output.ex`

```elixir
defmodule ClaudeAgentSDK.Hooks.Output do
  @moduledoc """
  Hook output structure and helpers.

  Represents the return value from hook callbacks.
  See: https://docs.anthropic.com/en/docs/claude-code/hooks#hook-output
  """

  @type permission_decision :: :allow | :deny | :ask

  @type hook_specific_output ::
    pre_tool_use_output()
    | post_tool_use_output()
    | user_prompt_submit_output()

  @type pre_tool_use_output :: %{
    hookEventName: String.t(),
    permissionDecision: permission_decision(),
    permissionDecisionReason: String.t()
  }

  @type post_tool_use_output :: %{
    hookEventName: String.t(),
    additionalContext: String.t()
  }

  @type user_prompt_submit_output :: %{
    hookEventName: String.t(),
    additionalContext: String.t()
  }

  @type t :: %{
    optional(:continue) => boolean(),
    optional(:stopReason) => String.t(),
    optional(:suppressOutput) => boolean(),
    optional(:systemMessage) => String.t(),
    optional(:reason) => String.t(),
    optional(:decision) => :block,
    optional(:hookSpecificOutput) => hook_specific_output()
  }

  @doc """
  Creates hook output to allow a PreToolUse.
  """
  @spec allow(String.t()) :: t()
  def allow(reason \\ "Approved") do
    %{
      hookSpecificOutput: %{
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        permissionDecisionReason: reason
      }
    }
  end

  @doc """
  Creates hook output to deny a PreToolUse.
  """
  @spec deny(String.t()) :: t()
  def deny(reason) do
    %{
      hookSpecificOutput: %{
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: reason
      }
    }
  end

  @doc """
  Creates hook output to add context.
  """
  @spec add_context(String.t(), String.t()) :: t()
  def add_context(event_name, context) do
    %{
      hookSpecificOutput: %{
        hookEventName: event_name,
        additionalContext: context
      }
    }
  end

  @doc """
  Creates hook output to stop execution.
  """
  @spec stop(String.t()) :: t()
  def stop(reason) do
    %{
      continue: false,
      stopReason: reason
    }
  end

  @doc """
  Validates hook output structure.
  """
  @spec validate(t()) :: :ok | {:error, String.t()}
  def validate(output) when is_map(output) do
    # Basic validation - more comprehensive checks possible
    :ok
  end

  def validate(_), do: {:error, "Hook output must be a map"}

  @doc """
  Converts Elixir output to JSON-compatible map for CLI.
  """
  @spec to_json_map(t()) :: map()
  def to_json_map(output) when is_map(output) do
    output
    |> Enum.map(fn
      {:continue, val} -> {"continue", val}
      {key, val} when is_atom(key) -> {Atom.to_string(key), val}
      {key, val} -> {key, val}
    end)
    |> Map.new()
  end
end
```

### Client Implementation

#### `lib/claude_agent_sdk/client.ex`

```elixir
defmodule ClaudeAgentSDK.Client do
  @moduledoc """
  Bidirectional client for Claude Code with hook support.

  This GenServer maintains a persistent connection to the Claude CLI
  process, handles control protocol messages, and invokes hook callbacks.

  ## Usage

      # Start client
      {:ok, pid} = Client.start_link(options)

      # Send query
      :ok = Client.query(pid, "Write a function")

      # Receive messages
      stream = Client.stream_messages(pid)

      # Stop client
      :ok = Client.stop(pid)

  ## With Hooks

      options = %Options{
        hooks: %{
          pre_tool_use: [
            Matcher.new("Bash", [&check_bash_command/3])
          ]
        }
      }

      {:ok, pid} = Client.start_link(options)
  """

  use GenServer
  require Logger

  alias ClaudeAgentSDK.{Options, Hooks, ControlProtocol}
  alias ClaudeAgentSDK.Hooks.{Matcher, Registry}

  @type state :: %{
    port: port(),
    options: Options.t(),
    registry: Registry.t(),
    message_queue: :queue.queue(),
    subscribers: [pid()],
    pending_requests: %{String.t() => reference()},
    initialized: boolean()
  }

  ## Public API

  @doc """
  Starts the client GenServer.
  """
  @spec start_link(Options.t()) :: GenServer.on_start()
  def start_link(%Options{} = options) do
    GenServer.start_link(__MODULE__, options)
  end

  @doc """
  Sends a query to Claude.
  """
  @spec query(pid(), String.t()) :: :ok
  def query(pid, prompt) when is_binary(prompt) do
    GenServer.call(pid, {:query, prompt})
  end

  @doc """
  Returns a stream of messages from Claude.
  """
  @spec stream_messages(pid()) :: Enumerable.t()
  def stream_messages(pid) do
    Stream.resource(
      fn -> subscribe(pid) end,
      fn state -> receive_next_message(state) end,
      fn _state -> :ok end
    )
  end

  @doc """
  Stops the client.
  """
  @spec stop(pid()) :: :ok
  def stop(pid) do
    GenServer.stop(pid)
  end

  ## GenServer Callbacks

  @impl true
  def init(%Options{} = options) do
    # Validate hooks configuration
    case validate_hooks(options.hooks) do
      :ok ->
        start_cli_process(options)

      {:error, reason} ->
        {:stop, {:hooks_validation_failed, reason}}
    end
  end

  @impl true
  def handle_call({:query, prompt}, _from, state) do
    case send_query(state.port, prompt) do
      :ok -> {:reply, :ok, state}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    case parse_cli_output(data) do
      {:control_request, request} ->
        handle_control_request(request, state)

      {:message, message} ->
        broadcast_message(message, state)
        {:noreply, state}

      {:error, reason} ->
        Logger.error("Failed to parse CLI output: #{reason}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :port, port, reason}, %{port: port} = state) do
    Logger.info("CLI process exited: #{inspect(reason)}")
    {:stop, :normal, state}
  end

  ## Private Functions

  defp start_cli_process(options) do
    # Build CLI command
    cmd = build_cli_command(options)

    # Open port
    port = Port.open({:spawn, cmd}, [:binary, :exit_status, :use_stdio])

    # Create hook registry
    registry = Registry.new()
    registry = register_hooks(registry, options.hooks)

    # Send initialize request
    state = %{
      port: port,
      options: options,
      registry: registry,
      message_queue: :queue.new(),
      subscribers: [],
      pending_requests: %{},
      initialized: false
    }

    case send_initialize(state) do
      {:ok, new_state} -> {:ok, new_state}
      {:error, reason} -> {:stop, {:init_failed, reason}}
    end
  end

  defp handle_control_request(request, state) do
    request_id = request["request_id"]
    request_data = request["request"]

    case request_data["subtype"] do
      "hook_callback" ->
        handle_hook_callback(request_id, request_data, state)

      other ->
        Logger.warn("Unsupported control request: #{other}")
        send_error_response(state.port, request_id, "Unsupported request")
        {:noreply, state}
    end
  end

  defp handle_hook_callback(request_id, request_data, state) do
    callback_id = request_data["callback_id"]
    input = request_data["input"]
    tool_use_id = request_data["tool_use_id"]

    # Look up callback in registry
    case Registry.get_callback(state.registry, callback_id) do
      {:ok, callback_fn} ->
        # Invoke callback (with timeout protection)
        task = Task.async(fn ->
          try do
            context = %{signal: nil}
            callback_fn.(input, tool_use_id, context)
          rescue
            e -> {:error, Exception.message(e)}
          end
        end)

        result = case Task.yield(task, 60_000) || Task.shutdown(task) do
          {:ok, output} when is_map(output) ->
            {:ok, output}

          {:ok, {:error, reason}} ->
            {:error, reason}

          nil ->
            {:error, "Hook callback timeout after 60s"}
        end

        case result do
          {:ok, output} ->
            send_success_response(state.port, request_id, output)

          {:error, reason} ->
            send_error_response(state.port, request_id, reason)
        end

        {:noreply, state}

      :error ->
        send_error_response(state.port, request_id,
                           "Callback not found: #{callback_id}")
        {:noreply, state}
    end
  end

  defp register_hooks(registry, nil), do: registry
  defp register_hooks(registry, hooks) when is_map(hooks) do
    Enum.reduce(hooks, registry, fn {_event, matchers}, acc ->
      Enum.reduce(matchers, acc, fn matcher, reg ->
        Enum.reduce(matcher.hooks, reg, fn callback, r ->
          Registry.register(r, callback)
        end)
      end)
    end)
  end

  defp send_initialize(state) do
    # Build hooks config
    hooks_config = build_hooks_config(state.registry, state.options.hooks)

    # Send initialize control request
    request = %{
      "type" => "control_request",
      "request_id" => generate_request_id(),
      "request" => %{
        "subtype" => "initialize",
        "hooks" => hooks_config
      }
    }

    json = Jason.encode!(request)
    Port.command(state.port, json <> "\n")

    # Wait for response...
    {:ok, %{state | initialized: true}}
  end

  defp build_hooks_config(_registry, nil), do: nil
  defp build_hooks_config(registry, hooks) do
    hooks
    |> Enum.map(fn {event, matchers} ->
      event_str = Hooks.event_to_string(event)

      matchers_config = Enum.map(matchers, fn matcher ->
        callback_ids = Enum.map(matcher.hooks, fn callback ->
          Registry.get_id(registry, callback)
        end)

        %{
          "matcher" => matcher.matcher,
          "hookCallbackIds" => callback_ids
        }
      end)

      {event_str, matchers_config}
    end)
    |> Map.new()
  end

  defp validate_hooks(nil), do: :ok
  defp validate_hooks(hooks), do: Hooks.validate_config(hooks)

  # ... more private functions ...
end
```

#### `lib/claude_agent_sdk/hooks/registry.ex`

```elixir
defmodule ClaudeAgentSDK.Hooks.Registry do
  @moduledoc false
  # Internal module for managing hook callback registration

  alias ClaudeAgentSDK.Hooks

  @type t :: %__MODULE__{
    callbacks: %{String.t() => Hooks.hook_callback()},
    reverse_map: %{Hooks.hook_callback() => String.t()},
    counter: non_neg_integer()
  }

  defstruct callbacks: %{},
            reverse_map: %{},
            counter: 0

  @doc """
  Creates a new registry.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc """
  Registers a callback and returns updated registry.

  If callback already registered, returns existing ID.
  """
  @spec register(t(), Hooks.hook_callback()) :: t()
  def register(%__MODULE__{} = registry, callback) when is_function(callback, 3) do
    case Map.get(registry.reverse_map, callback) do
      nil ->
        # New callback
        id = "hook_#{registry.counter}"
        %{registry |
          callbacks: Map.put(registry.callbacks, id, callback),
          reverse_map: Map.put(registry.reverse_map, callback, id),
          counter: registry.counter + 1
        }

      _existing_id ->
        # Already registered
        registry
    end
  end

  @doc """
  Gets callback by ID.
  """
  @spec get_callback(t(), String.t()) :: {:ok, Hooks.hook_callback()} | :error
  def get_callback(%__MODULE__{} = registry, id) do
    case Map.get(registry.callbacks, id) do
      nil -> :error
      callback -> {:ok, callback}
    end
  end

  @doc """
  Gets ID for a callback.
  """
  @spec get_id(t(), Hooks.hook_callback()) :: String.t() | nil
  def get_id(%__MODULE__{} = registry, callback) do
    Map.get(registry.reverse_map, callback)
  end
end
```

### Options Integration

#### Modifications to `lib/claude_agent_sdk/options.ex`

```elixir
# Add to defstruct
defstruct [
  # ... existing fields ...
  :hooks  # %{atom() => [Matcher.t()]} | nil
]

# Add to @type t
@type t :: %__MODULE__{
  # ... existing fields ...
  hooks: Hooks.hook_config() | nil
}

# Note: No CLI argument conversion needed for hooks
# Hooks are sent via control protocol, not CLI args
```

---

## Implementation Plan

### Phase 1: Core Infrastructure (Week 1)

**Tasks:**
1. Create module structure
   - `lib/claude_agent_sdk/hooks/hooks.ex`
   - `lib/claude_agent_sdk/hooks/matcher.ex`
   - `lib/claude_agent_sdk/hooks/output.ex`
   - `lib/claude_agent_sdk/hooks/registry.ex`

2. Implement type definitions and utilities
   - Hook event conversions
   - Validation functions
   - Output helpers

3. Add hooks field to Options
   - Update struct
   - Update type specs
   - Add validation

**Deliverables:**
- ✅ Type modules with full specs
- ✅ Unit tests for utilities
- ✅ Documentation

### Phase 2: Control Protocol (Week 2)

**Tasks:**
1. Create control protocol modules
   - `lib/claude_agent_sdk/control_protocol/protocol.ex`
   - Request/response encoding/decoding

2. Implement message parsing
   - Distinguish control messages from SDK messages
   - Handle JSON-RPC format

3. Add error handling
   - Malformed messages
   - Unknown request types

**Deliverables:**
- ✅ Protocol encoder/decoder
- ✅ Unit tests with real CLI messages
- ✅ Error case handling

### Phase 3: Client Implementation (Week 3)

**Tasks:**
1. Implement `ClaudeAgentSDK.Client` GenServer
   - Port management
   - Message routing
   - Hook registry

2. Implement initialization handshake
   - Send hooks configuration
   - Handle initialize response

3. Implement hook callback handling
   - Receive hook_callback requests
   - Invoke user callbacks with timeout
   - Send responses back to CLI

**Deliverables:**
- ✅ Working Client module
- ✅ Integration tests with mock CLI
- ✅ Timeout protection

### Phase 4: Testing & Examples (Week 4)

**Tasks:**
1. Create comprehensive test suite
   - Unit tests for all modules
   - Integration tests with real CLI
   - Error scenarios

2. Write examples
   - Basic PreToolUse hook
   - PostToolUse with context
   - Complex multi-hook scenario
   - Error handling examples

3. Update documentation
   - API reference
   - Hook guide
   - Migration guide

**Deliverables:**
- ✅ 90%+ test coverage
- ✅ 5+ working examples
- ✅ Complete documentation

### Phase 5: Polish & Release (Week 5)

**Tasks:**
1. Performance optimization
   - Benchmark hook overhead
   - Optimize message parsing
   - Reduce allocations

2. Developer experience
   - Better error messages
   - Helpful warnings
   - Type specs everywhere

3. Release preparation
   - Changelog
   - Migration guide
   - Blog post

**Deliverables:**
- ✅ v0.3.0 release
- ✅ Release notes
- ✅ Announcement

---

## Examples

### Example 1: Block Dangerous Bash Commands

```elixir
defmodule MyApp.Hooks do
  alias ClaudeAgentSDK.Hooks.Output

  def check_bash_command(input, _tool_use_id, _context) do
    case input do
      %{"tool_name" => "Bash", "tool_input" => %{"command" => command}} ->
        dangerous_patterns = ["rm -rf", "dd if=", "mkfs", "> /dev/"]

        if Enum.any?(dangerous_patterns, &String.contains?(command, &1)) do
          Output.deny("Dangerous command blocked: #{command}")
        else
          Output.allow()
        end

      _ ->
        %{}  # Not a Bash command, allow
    end
  end
end

# Usage
options = %Options{
  allowed_tools: ["Bash"],
  hooks: %{
    pre_tool_use: [
      Matcher.new("Bash", [&MyApp.Hooks.check_bash_command/3])
    ]
  }
}

{:ok, pid} = Client.start_link(options)
Client.query(pid, "Delete all files with rm -rf /")
# Hook will block this command!
```

### Example 2: Add Context from Environment

```elixir
defmodule MyApp.Hooks do
  alias ClaudeAgentSDK.Hooks.Output

  def add_project_context(_input, _tool_use_id, _context) do
    # Read project info
    recent_issues = get_recent_github_issues()
    current_branch = get_current_git_branch()

    context = """
    Project Context:
    - Current branch: #{current_branch}
    - Recent issues: #{Enum.join(recent_issues, ", ")}
    - Last deploy: #{get_last_deploy_time()}
    """

    Output.add_context("SessionStart", context)
  end

  defp get_recent_github_issues do
    # GitHub API call
    ["#123: Fix auth", "#124: Add logging"]
  end

  defp get_current_git_branch do
    {result, 0} = System.cmd("git", ["branch", "--show-current"])
    String.trim(result)
  end

  defp get_last_deploy_time do
    # Check deployment log
    "2 hours ago"
  end
end

# Usage
options = %Options{
  hooks: %{
    session_start: [
      Matcher.new(nil, [&MyApp.Hooks.add_project_context/3])
    ]
  }
}
```

### Example 3: Log All Tool Usage

```elixir
defmodule MyApp.Hooks do
  require Logger

  def log_tool_use(input, tool_use_id, _context) do
    tool_name = input["tool_name"]
    tool_input = input["tool_input"]

    Logger.info("Tool used",
      tool: tool_name,
      tool_use_id: tool_use_id,
      input: tool_input
    )

    # Don't modify behavior, just log
    %{}
  end

  def log_tool_result(input, tool_use_id, _context) do
    tool_name = input["tool_name"]
    tool_response = input["tool_response"]

    Logger.info("Tool completed",
      tool: tool_name,
      tool_use_id: tool_use_id,
      success: not Map.get(tool_response, "is_error", false)
    )

    %{}
  end
end

# Usage
options = %Options{
  hooks: %{
    pre_tool_use: [
      Matcher.new("*", [&MyApp.Hooks.log_tool_use/3])
    ],
    post_tool_use: [
      Matcher.new("*", [&MyApp.Hooks.log_tool_result/3])
    ]
  }
}
```

### Example 4: Enforce File Edit Policy

```elixir
defmodule MyApp.SecurityPolicy do
  alias ClaudeAgentSDK.Hooks.Output

  def enforce_file_policy(input, _tool_use_id, _context) do
    case input do
      %{"tool_name" => tool, "tool_input" => %{"file_path" => path}}
      when tool in ["Write", "Edit"] ->
        cond do
          String.ends_with?(path, ".env") ->
            Output.deny("Cannot modify .env files")

          String.contains?(path, "/config/secrets") ->
            Output.deny("Cannot modify secrets directory")

          not String.starts_with?(path, "/allowed/path") ->
            Output.deny("Can only modify files in /allowed/path")

          true ->
            Output.allow()
        end

      _ ->
        %{}
    end
  end
end

# Usage
options = %Options{
  allowed_tools: ["Write", "Edit", "Read"],
  hooks: %{
    pre_tool_use: [
      Matcher.new("Write|Edit", [&MyApp.SecurityPolicy.enforce_file_policy/3])
    ]
  }
}
```

---

## Testing Strategy

### Unit Tests

**Test Coverage:**
- `Hooks` module: 100%
- `Matcher` module: 100%
- `Output` module: 100%
- `Registry` module: 100%
- `Client` module: 90%+ (excluding complex integration scenarios)

**Key Test Cases:**
1. Type conversions (event atoms ↔ strings)
2. Hook configuration validation
3. Output structure validation
4. Registry registration and lookup
5. Matcher pattern matching
6. Error handling for malformed input

### Integration Tests

**Test Scenarios:**
1. **Successful Hook Execution**
   - Hook receives correct input
   - Hook returns valid output
   - CLI processes decision correctly

2. **Hook Blocks Action**
   - PreToolUse denies tool
   - CLI doesn't execute tool
   - Claude receives feedback

3. **Hook Adds Context**
   - PostToolUse adds context
   - Context appears in next message to Claude

4. **Hook Timeout**
   - Hook takes > 60s
   - Client sends timeout error
   - CLI continues gracefully

5. **Hook Exception**
   - Hook raises exception
   - Client catches and reports
   - CLI continues gracefully

6. **Multiple Hooks**
   - Multiple hooks for same event
   - All hooks execute
   - Decisions are combined correctly

7. **Complex Workflow**
   - PreToolUse allows
   - Tool executes
   - PostToolUse reviews result
   - Claude receives feedback

### E2E Tests

**Real CLI Integration:**
```elixir
defmodule ClaudeAgentSDK.HooksE2ETest do
  use ExUnit.Case

  @moduletag :integration
  @moduletag timeout: 120_000

  test "PreToolUse blocks dangerous bash command" do
    options = %Options{
      allowed_tools: ["Bash"],
      hooks: %{
        pre_tool_use: [
          Matcher.new("Bash", [&TestHooks.block_rm/3])
        ]
      }
    }

    {:ok, pid} = Client.start_link(options)

    # Send dangerous command
    Client.query(pid, "Run: rm -rf /tmp/important")

    # Collect messages
    messages = Client.stream_messages(pid) |> Enum.to_list()

    # Verify command was blocked
    assert Enum.any?(messages, fn msg ->
      match?(%{type: :assistant, data: %{content: content}} when
        String.contains?(content, "blocked"), msg)
    end)
  end

  test "PostToolUse adds monitoring context" do
    # Test that PostToolUse hooks can add context
  end

  test "Multiple hooks execute in order" do
    # Test hook execution order
  end
end
```

### Performance Tests

**Benchmarks:**
```elixir
defmodule ClaudeAgentSDK.HooksBenchmark do
  use Benchfella

  bench "hook invocation overhead" do
    # Measure time from hook trigger to callback invocation
  end

  bench "registry lookup" do
    # Measure registry.get_callback performance
  end

  bench "output serialization" do
    # Measure JSON encoding of hook output
  end
end
```

**Target Metrics:**
- Hook invocation overhead: < 10ms
- Registry lookup: < 1ms
- Output serialization: < 5ms
- Memory per registered hook: < 1KB

---

## References

### Documentation
- [Claude Code Hooks Reference](https://docs.anthropic.com/en/docs/claude-code/hooks)
- [Python SDK Hooks Example](https://github.com/anthropics/claude-agent-sdk-python/blob/main/examples/hooks.py)
- [Control Protocol Specification](https://docs.anthropic.com/en/docs/claude-code/sdk)

### Implementation References
- Python SDK `query.py`: Control protocol handling
- Python SDK `types.py`: Hook type definitions
- Python SDK `client.py`: Hook callback invocation

### Related Issues
- Feature request: "Add hooks support to Elixir SDK"
- Discussion: "Control protocol best practices"

---

## Appendix A: Control Protocol Message Examples

### Initialize Request (SDK → CLI)

```json
{
  "type": "control_request",
  "request_id": "req_1_a3f2c9",
  "request": {
    "subtype": "initialize",
    "hooks": {
      "PreToolUse": [
        {
          "matcher": "Bash",
          "hookCallbackIds": ["hook_0", "hook_1"]
        }
      ],
      "PostToolUse": [
        {
          "matcher": "*",
          "hookCallbackIds": ["hook_2"]
        }
      ]
    }
  }
}
```

### Initialize Response (CLI → SDK)

```json
{
  "type": "control_response",
  "response": {
    "subtype": "success",
    "request_id": "req_1_a3f2c9",
    "response": {
      "commands": [...],
      "capabilities": {...}
    }
  }
}
```

### Hook Callback Request (CLI → SDK)

```json
{
  "type": "control_request",
  "request_id": "req_2_b7e4d1",
  "request": {
    "subtype": "hook_callback",
    "callback_id": "hook_0",
    "tool_use_id": "toolu_01ABC123",
    "input": {
      "hook_event_name": "PreToolUse",
      "session_id": "550e8400-e29b-41d4-a716-446655440000",
      "transcript_path": "/path/to/transcript.jsonl",
      "cwd": "/project/dir",
      "tool_name": "Bash",
      "tool_input": {
        "command": "rm -rf /tmp/data"
      }
    }
  }
}
```

### Hook Callback Response (SDK → CLI)

```json
{
  "type": "control_response",
  "response": {
    "subtype": "success",
    "request_id": "req_2_b7e4d1",
    "response": {
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "Dangerous rm -rf command blocked"
      },
      "systemMessage": "Security policy blocked this command",
      "reason": "rm -rf is not allowed"
    }
  }
}
```

---

## Appendix B: Comparison with Python SDK

| Feature | Python SDK | Elixir SDK (Proposed) | Notes |
|---------|-----------|----------------------|-------|
| **Hook Events** | | | |
| PreToolUse | ✅ | ✅ | Identical behavior |
| PostToolUse | ✅ | ✅ | Identical behavior |
| UserPromptSubmit | ✅ | ✅ | Identical behavior |
| Stop | ✅ | ✅ | Identical behavior |
| SubagentStop | ✅ | ✅ | Identical behavior |
| PreCompact | ✅ | ✅ | Identical behavior |
| SessionStart | ❌ | ❌ | Not in SDK mode |
| SessionEnd | ❌ | ❌ | Not in SDK mode |
| Notification | ❌ | ❌ | Not in SDK mode |
| **Configuration** | | | |
| Matcher patterns | ✅ | ✅ | Same syntax |
| Regex support | ✅ | ✅ | Same syntax |
| Multiple hooks | ✅ | ✅ | Same behavior |
| **Hook Output** | | | |
| permissionDecision | ✅ | ✅ | Identical |
| additionalContext | ✅ | ✅ | Identical |
| continue/stopReason | ✅ | ✅ | Identical |
| systemMessage/reason | ✅ | ✅ | Identical |
| **Implementation** | | | |
| Callback signature | `(dict, str, ctx) -> dict` | `(map, str, map) -> map` | Same semantics |
| Async callbacks | ✅ (async/await) | ✅ (Task) | Different mechanism |
| Timeout protection | ✅ 60s | ✅ 60s | Same default |
| Error handling | ✅ Exception | ✅ try/rescue | Different mechanism |
| **Developer Experience** | | | |
| Type hints | ✅ TypedDict | ✅ @type/@spec | Different system |
| Examples | ✅ hooks.py | ✅ examples/ | Similar coverage |
| Documentation | ✅ Docstrings | ✅ @moduledoc | Different format |

---

**End of Document**
