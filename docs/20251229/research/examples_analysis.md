# Claude Agent SDK Examples Analysis

**Date:** 2025-12-29
**Author:** Research Analysis
**Scope:** Complete analysis of all examples in the `examples/` directory

---

## Table of Contents

1. [Overview](#overview)
2. [Directory Structure](#directory-structure)
3. [Prerequisites and Setup](#prerequisites-and-setup)
4. [How to Run Examples](#how-to-run-examples)
5. [Example Categories](#example-categories)
   - [Basic Examples](#basic-examples)
   - [Session and Features](#session-and-features)
   - [Streaming](#streaming)
   - [Hooks](#hooks)
   - [Advanced Features](#advanced-features)
   - [Runtime Control](#runtime-control)
   - [Archived Examples](#archived-examples)
6. [Key Usage Patterns](#key-usage-patterns)
7. [Dependencies and Requirements](#dependencies-and-requirements)
8. [Quick Reference Table](#quick-reference-table)

---

## Overview

The Claude Agent SDK examples directory contains **21 live examples** (plus archived/mock examples) demonstrating all SDK features. These examples make real API calls to Claude Code CLI and serve as:

- **Learning resources** for SDK capabilities
- **Integration tests** for SDK functionality
- **Reference implementations** for common patterns

All examples follow a consistent structure:
1. Load `support/example_helper.exs` for utilities
2. Call `Support.ensure_live!()` to verify CLI availability
3. Demonstrate the feature with real Claude interactions
4. Call `Support.halt_if_runner!()` for clean exit when run via `run_all.sh`

---

## Directory Structure

```
examples/
├── README.md                           # Main examples documentation
├── run_all.sh                          # Run all examples sequentially
├── support/
│   └── example_helper.exs              # Shared utilities (ensure_live!, header!, halt_if_runner!)
├── _output/                            # Runtime output directory (sessions, files)
│
├── basic_example.exs                   # Minimal SDK usage
├── session_features_example.exs        # SessionStore + resume
├── structured_output_live.exs          # JSON schema output
├── sandbox_settings_live.exs           # Sandbox configuration
├── tools_and_betas_live.exs            # Tool configuration
├── sdk_mcp_tools_live.exs              # SDK MCP tools
├── assistant_error_live.exs            # Error handling
├── file_checkpointing_live.exs         # File rewind/checkpointing
├── filesystem_agents_live.exs          # Filesystem agent loading
│
├── streaming_tools/
│   ├── quick_demo.exs                  # Minimal streaming
│   ├── basic_streaming_with_hooks.exs  # Streaming + hooks
│   └── sdk_mcp_streaming.exs           # Streaming + SDK MCP
│
├── hooks/
│   ├── context_injection.exs           # user_prompt_submit hook
│   ├── basic_bash_blocking.exs         # pre_tool_use allow/deny
│   ├── file_policy_enforcement.exs     # Sandbox + sensitive files
│   ├── logging_and_audit.exs           # Pre/post tool audit
│   └── complete_workflow.exs           # All hooks combined
│
├── advanced_features/
│   ├── agents_live.exs                 # Multi-agent workflow
│   ├── permissions_live.exs            # Permission callbacks
│   └── sdk_mcp_live_demo.exs           # SDK MCP tools demo
│
├── runtime_control/
│   └── control_parity_live.exs         # Runtime permission switching
│
└── archive/                            # Archived/mock examples
    ├── advanced_features/
    ├── mock_demos/
    ├── runtime_control/
    ├── streaming_tools/
    ├── hooks/
    └── top_level/
```

---

## Prerequisites and Setup

### Required

1. **Claude Code CLI** installed globally:
   ```bash
   npm install -g @anthropic-ai/claude-code
   ```

2. **Authentication** (one of):
   - Interactive login: `claude login`
   - Environment variable: `ANTHROPIC_API_KEY`
   - OAuth token: `CLAUDE_AGENT_OAUTH_TOKEN`

3. **Verify installation**:
   ```bash
   claude --version
   ```

### Optional Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `CLAUDE_EXAMPLES_FORCE_HALT` | Force exit after each example | `false` |
| `CLAUDE_EXAMPLES_TIMEOUT_SECONDS` | Timeout per example | `900` (15 min) |
| `CLAUDE_EXAMPLES_PREFLIGHT_TIMEOUT_SECONDS` | Auth check timeout | `30` |
| `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT` | Stream close timeout (ms) | `60000` |
| `CLAUDE_CODE_BETAS` | Comma-separated beta flags | (none) |

---

## How to Run Examples

### Run All Examples

```bash
bash examples/run_all.sh
```

This script:
- Verifies CLI installation and authentication
- Sets `CLAUDE_EXAMPLES_FORCE_HALT=true`
- Runs each example with timeout protection
- Reports success/failure for each

### Run Single Example

```bash
mix run examples/basic_example.exs
```

### Run from IEx (Interactive)

```bash
iex -S mix
iex> Code.require_file("examples/basic_example.exs")
```

### Run with Custom Options

```bash
# Increase timeout for slow examples
CLAUDE_EXAMPLES_TIMEOUT_SECONDS=1200 bash examples/run_all.sh

# Enable beta features
CLAUDE_CODE_BETAS=feature1,feature2 mix run examples/tools_and_betas_live.exs
```

---

## Example Categories

### Basic Examples

#### `basic_example.exs`
**Purpose:** Minimal SDK usage demonstrating the simplest query pattern.

**Key Patterns:**
```elixir
alias ClaudeAgentSDK.{ContentExtractor, OptionBuilder}

# Simple options with Haiku model
options = OptionBuilder.with_haiku()

# Make query and collect response
response = ClaudeAgentSDK.query("Say exactly one word: hello", options)
  |> Enum.to_list()

# Extract text from assistant messages
text = response
  |> Enum.filter(&(&1.type == :assistant))
  |> Enum.map(&ContentExtractor.extract_text/1)
  |> Enum.join("\n")
```

**Demonstrates:**
- `ClaudeAgentSDK.query/2` API
- `ContentExtractor.extract_text/1` for message parsing
- Stream-to-list collection pattern

---

### Session and Features

#### `session_features_example.exs`
**Purpose:** Session persistence, search, and resume capabilities.

**Key Patterns:**
```elixir
alias ClaudeAgentSDK.{Options, Session, SessionStore}

# Start session store
{:ok, _} = SessionStore.start_link(storage_dir: "/path/to/sessions")

# Extract session ID from messages
session_id = Session.extract_session_id(messages)

# Save session with metadata
SessionStore.save_session(session_id, messages,
  tags: ["examples"],
  description: "Demo session"
)

# Search saved sessions
results = SessionStore.search(tags: ["examples"])

# Resume existing session
resumed = ClaudeAgentSDK.resume(session_id, "Follow-up prompt", options)
```

**Demonstrates:**
- `SessionStore` for persistence
- Session tagging and search
- `ClaudeAgentSDK.resume/3` for conversation continuation
- CLI flags: `--fork-session`, `--add-dir`, `--strict-mcp-config`

---

#### `structured_output_live.exs`
**Purpose:** JSON schema-validated structured output.

**Key Patterns:**
```elixir
# Define JSON schema
schema = %{
  "type" => "object",
  "properties" => %{
    "summary" => %{"type" => "string"},
    "next_steps" => %{"type" => "array", "items" => %{"type" => "string"}}
  },
  "required" => ["summary", "next_steps"]
}

# Configure options with JSON schema output
options = %Options{
  output_format: %{type: :json_schema, schema: schema},
  model: "haiku",
  max_turns: 5,
  tools: []
}

# Find structured output in result
structured = Enum.find_value(messages, fn
  %{type: :result, data: %{structured_output: so}} -> so
  _ -> nil
end)
```

**Demonstrates:**
- `output_format: %{type: :json_schema, schema: schema}`
- Schema validation via CLI
- Structured output extraction

---

#### `sandbox_settings_live.exs`
**Purpose:** Sandbox configuration merged into CLI settings.

**Key Patterns:**
```elixir
alias ClaudeAgentSDK.{CLI, Options}

# Define sandbox configuration
sandbox = %{
  enabled: true,
  autoAllowBashIfSandboxed: true,
  excludedCommands: ["docker"],
  network: %{allowLocalBinding: true}
}

# Options with sandbox
options = %Options{
  model: "haiku",
  max_turns: 1,
  sandbox: sandbox
}

# Sandbox is merged into --settings JSON
CLI.to_args(options)  # Includes --settings with sandbox config
```

**Demonstrates:**
- `sandbox` option configuration
- Merging sandbox into settings JSON
- Settings file vs JSON string handling

---

#### `tools_and_betas_live.exs`
**Purpose:** Tool configuration variants and beta features.

**Key Patterns:**
```elixir
# Explicit tool list
%Options{tools: ["Read", "Glob", "Grep"]}

# Disable all built-in tools
%Options{tools: []}

# Use preset tool set
%Options{tools: %{type: :preset, preset: :claude_code}}

# Enable beta features
%Options{betas: ["feature1", "feature2"]}
```

**Demonstrates:**
- Tool configuration variants
- `init` message tool list parsing
- Beta feature enablement

---

#### `sdk_mcp_tools_live.exs`
**Purpose:** In-process MCP tools without subprocess overhead.

**Key Patterns:**
```elixir
# Define tools with deftool macro
defmodule Examples.CalculatorTools do
  use ClaudeAgentSDK.Tool

  deftool :add,
          "Add two numbers together",
          %{
            type: "object",
            properties: %{
              a: %{type: "number", description: "First number"},
              b: %{type: "number", description: "Second number"}
            },
            required: ["a", "b"]
          } do
    def execute(%{"a" => a, "b" => b}) do
      {:ok, %{"content" => [%{"type" => "text", "text" => "Result: #{a + b}"}]}}
    end
  end
end

# Create SDK MCP server
server = ClaudeAgentSDK.create_sdk_mcp_server(
  name: "calculator",
  version: "1.0.0",
  tools: [Examples.CalculatorTools.Add, Examples.CalculatorTools.Multiply]
)

# Use in options
options = %Options{
  mcp_servers: %{"calc" => server},
  allowed_tools: ["mcp__calc__add", "mcp__calc__multiply"],
  permission_mode: :bypass_permissions
}
```

**Demonstrates:**
- `deftool` macro for tool definition
- `ClaudeAgentSDK.create_sdk_mcp_server/1`
- MCP tool naming convention: `mcp__<server>__<tool>`
- In-process tool execution

---

#### `assistant_error_live.exs`
**Purpose:** Assistant error metadata and streaming error handling.

**Key Patterns:**
```elixir
alias ClaudeAgentSDK.{Message, Streaming}

# Streaming with error detection
{text, error} = Streaming.send_message(session, prompt)
  |> Enum.reduce({"", nil}, fn
    %{type: :text_delta, text: chunk}, {acc, err} -> {acc <> chunk, err}
    %{type: :message_stop, error: err_code}, {acc, _} -> {acc, err_code}
    %{type: :error, error: reason}, _ -> {"", reason || :unknown}
    _, acc -> acc
  end)

# Aggregated message error detection
assistant_error = Enum.find_value(messages, fn
  %Message{type: :assistant, data: %{error: err}} -> err
  _ -> nil
end)
```

**Demonstrates:**
- Error field extraction from assistant messages
- Streaming vs aggregated error handling
- Error codes: `:authentication_failed`, rate limits, etc.

---

#### `file_checkpointing_live.exs`
**Purpose:** File rewind/checkpointing via git integration.

**Key Patterns:**
```elixir
alias ClaudeAgentSDK.{Client, Message}

# Enable checkpointing in options
options = %Options{
  cwd: demo_dir,
  enable_file_checkpointing: true,
  permission_mode: :accept_edits,
  tools: ["Read", "Write", "Edit"]
}

# Extract user message ID for checkpointing
user_message_id = Message.user_uuid(message)

# Rewind files to checkpoint
Client.rewind_files(client, user_message_id)
```

**Demonstrates:**
- `enable_file_checkpointing: true`
- User message ID extraction for checkpoints
- `Client.rewind_files/2` API
- Git repository initialization for checkpointing

---

#### `filesystem_agents_live.exs`
**Purpose:** Loading agent definitions from filesystem.

**Key Patterns:**
```elixir
# Create agent markdown file at .claude/agents/agent-name.md
agent_content = """
---
name: fs-test-agent
description: Test agent for SDK
tools: Read
---

# Filesystem Test Agent

You are a simple test agent...
"""

# Options to load filesystem agents
options = %Options{
  cwd: demo_dir,
  setting_sources: ["project"],  # Load from .claude/agents/
  max_turns: 1,
  model: "haiku"
}

# Agents appear in init message
init = Enum.find(messages, &(&1.type == :system and &1.subtype == :init))
init.raw["agents"]  # Contains loaded agents
```

**Demonstrates:**
- `setting_sources: ["project"]` for filesystem agents
- Agent markdown format (frontmatter + content)
- Agent discovery in init message

---

### Streaming

#### `streaming_tools/quick_demo.exs`
**Purpose:** Minimal streaming session demonstration.

**Key Patterns:**
```elixir
alias ClaudeAgentSDK.{Options, Streaming}

options = %Options{model: "haiku", max_turns: 1, allowed_tools: []}

{:ok, session} = Streaming.start_session(options)

try do
  Streaming.send_message(session, "Say hello in five words.")
  |> Enum.reduce_while(%{chunks: 0, stopped?: false}, fn
    %{type: :text_delta, text: chunk}, acc ->
      IO.write(chunk)  # Typewriter effect
      {:cont, %{acc | chunks: acc.chunks + 1}}

    %{type: :message_stop}, acc ->
      {:halt, %{acc | stopped?: true}}

    %{type: :error, error: reason}, _acc ->
      raise "Streaming error: #{inspect(reason)}"

    _event, acc -> {:cont, acc}
  end)
after
  Streaming.close_session(session)
end
```

**Demonstrates:**
- `Streaming.start_session/1` and `close_session/1`
- `Streaming.send_message/2` event stream
- Event types: `:text_delta`, `:message_stop`, `:error`
- Typewriter effect with `IO.write/1`

---

#### `streaming_tools/basic_streaming_with_hooks.exs`
**Purpose:** Streaming combined with pre-tool hooks.

**Key Patterns:**
```elixir
alias ClaudeAgentSDK.Hooks.{Matcher, Output}

# Define hook callbacks
def log_tool_use(input, tool_use_id, _context) do
  IO.puts("Tool: #{input["tool_name"]}")
  Output.allow() |> Output.with_system_message("Logged")
end

def validate_bash(input, _tool_use_id, _context) do
  case input do
    %{"tool_name" => "Bash", "tool_input" => %{"command" => cmd}} ->
      if dangerous?(cmd), do: Output.deny("Blocked"), else: Output.allow()
    _ -> Output.allow()
  end
end

# Configure hooks
options = %Options{
  hooks: %{
    pre_tool_use: [
      Matcher.new("*", [&log_tool_use/3]),
      Matcher.new("Bash", [&validate_bash/3])
    ]
  }
}

# Stream with hooks
{:ok, session} = Streaming.start_session(options)
Streaming.send_message(session, prompt)
|> Enum.reduce_while(..., fn
  %{type: :tool_use_start, name: name} -> ...
  %{type: :text_delta, text: text} -> ...
  ...
end)
```

**Demonstrates:**
- Hooks with streaming API
- `Matcher.new/2` for tool matching
- `Output.allow/0`, `Output.deny/1`, `Output.with_system_message/2`
- Multiple hooks on same event type

---

#### `streaming_tools/sdk_mcp_streaming.exs`
**Purpose:** Streaming with in-process SDK MCP tools.

**Key Patterns:**
```elixir
# Create SDK MCP server
server = ClaudeAgentSDK.create_sdk_mcp_server(
  name: "math-tools",
  version: "1.0.0",
  tools: [MathTools.Add, MathTools.Multiply, MathTools.Factorial]
)

# Options with SDK MCP
options = %Options{
  mcp_servers: %{"math-tools" => server},
  model: "haiku",
  max_turns: 2
}

# Stream events include tool lifecycle
Streaming.send_message(session, prompt)
|> Enum.reduce_while({0, 0}, fn
  %{type: :tool_use_start, name: name} -> ...
  %{type: :tool_input_delta, json: json} -> ...
  %{type: :tool_complete, tool_name: name} -> ...
  %{type: :text_delta, text: text} -> ...
  %{type: :message_stop} -> ...
end)
```

**Demonstrates:**
- SDK MCP tools with streaming
- Tool lifecycle events: `tool_use_start`, `tool_input_delta`, `tool_complete`
- Automatic control client transport selection

---

### Hooks

#### `hooks/context_injection.exs`
**Purpose:** Auto-inject context via `user_prompt_submit` hook.

**Key Patterns:**
```elixir
alias ClaudeAgentSDK.Hooks.{Matcher, Output}

def add_project_context(_input, _tool_use_id, _context) do
  context_text = """
  ## Auto-Injected Context
  **Timestamp:** #{DateTime.utc_now()}
  **Environment:** #{Mix.env()}
  **Working Directory:** #{File.cwd!()}
  """

  Output.add_context("UserPromptSubmit", context_text)
end

hooks = %{
  user_prompt_submit: [
    Matcher.new(nil, [&add_project_context/3])  # nil matches all
  ]
}

options = %Options{hooks: hooks, ...}
```

**Demonstrates:**
- `user_prompt_submit` hook type
- `Output.add_context/2` for context injection
- `Matcher.new(nil, callbacks)` for universal matching

---

#### `hooks/basic_bash_blocking.exs`
**Purpose:** Block dangerous bash commands with `pre_tool_use` hook.

**Key Patterns:**
```elixir
def check_bash_command(input, _tool_use_id, _context) do
  case input do
    %{"tool_name" => "Bash", "tool_input" => %{"command" => command}} ->
      dangerous_patterns = ["rm -rf", "dd if=", "mkfs", "> /dev/"]

      if Enum.any?(dangerous_patterns, &String.contains?(command, &1)) do
        Output.deny("Dangerous command blocked")
        |> Output.with_system_message("Security policy violation")
        |> Output.with_reason("Command could cause damage")
      else
        Output.allow("Security check passed")
      end

    _ -> %{}  # Not Bash, pass through
  end
end

hooks = %{
  pre_tool_use: [Matcher.new("Bash", [&check_bash_command/3])]
}
```

**Demonstrates:**
- `pre_tool_use` hook for tool interception
- Tool-specific matching: `Matcher.new("Bash", ...)`
- `Output.deny/1` with reason and system message
- Pattern-based command validation

---

#### `hooks/file_policy_enforcement.exs`
**Purpose:** Enforce sandbox and sensitive file policies.

**Key Patterns:**
```elixir
@forbidden_files [".env", "secrets.yml", "credentials.json"]

def enforce_file_policy(input, _tool_use_id, _context) do
  case input do
    %{"tool_name" => tool, "tool_input" => %{"file_path" => path}}
    when tool in ["Write", "Edit"] ->
      cond do
        # Check forbidden filenames
        Enum.any?(@forbidden_files, &String.ends_with?(path, &1)) ->
          Output.deny("Cannot modify sensitive file")

        # Check sandbox boundaries
        not String.starts_with?(path, allowed_dir()) ->
          Output.deny("Must operate within sandbox")

        true ->
          Output.allow("File policy check passed")
      end

    _ -> %{}
  end
end

hooks = %{
  pre_tool_use: [Matcher.new("*", [&enforce_file_policy/3])]
}
```

**Demonstrates:**
- Wildcard matching: `Matcher.new("*", ...)`
- Multiple condition checks
- File path validation
- Sandbox boundary enforcement

---

#### `hooks/logging_and_audit.exs`
**Purpose:** Comprehensive audit logging with pre/post hooks.

**Key Patterns:**
```elixir
# Pre-tool hook: log invocation
def log_tool_invocation(input, tool_use_id, _context) do
  timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
  IO.puts("[AUDIT] #{timestamp} Tool: #{input["tool_name"]} ID: #{tool_use_id}")
  %{}  # Don't modify behavior
end

# Post-tool hook: log result
def log_tool_result(input, tool_use_id, _context) do
  is_error = get_in(input, ["tool_response", "is_error"]) || false
  status = if is_error, do: "FAILED", else: "SUCCESS"
  IO.puts("[AUDIT] Tool #{input["tool_name"]}: #{status}")
  %{}
end

hooks = %{
  pre_tool_use: [Matcher.new("*", [&log_tool_invocation/3])],
  post_tool_use: [Matcher.new("*", [&log_tool_result/3])]
}
```

**Demonstrates:**
- `post_tool_use` hook type
- Non-modifying hooks (return `%{}`)
- Tool response inspection
- Audit trail pattern

---

#### `hooks/complete_workflow.exs`
**Purpose:** All hook types combined in a secure workflow.

**Key Patterns:**
```elixir
hooks = %{
  # Context injection on prompt submit
  user_prompt_submit: [
    Matcher.new(nil, [&add_context/3])
  ],

  # Pre-tool: audit + security
  pre_tool_use: [
    Matcher.new("*", [
      &audit_log/3,           # Always log
      &security_validation/3  # Allow/deny
    ])
  ],

  # Post-tool: monitoring
  post_tool_use: [
    Matcher.new("*", [&monitor_execution/3])
  ]
}
```

**Demonstrates:**
- Multiple hook types working together
- Multiple callbacks per matcher
- Callback ordering (audit before security)
- Complete security workflow

---

### Advanced Features

#### `advanced_features/agents_live.exs`
**Purpose:** Multi-agent workflow with session continuity.

**Key Patterns:**
```elixir
alias ClaudeAgentSDK.Agent

# Define specialized agents
coder = Agent.new(
  name: :coder,
  description: "Python coding expert",
  prompt: "You are a Python expert...",
  allowed_tools: [],
  model: "haiku"
)

analyst = Agent.new(
  name: :analyst,
  description: "Code analysis expert",
  prompt: "You analyze code quality...",
  allowed_tools: [],
  model: "haiku"
)

# Configure with multiple agents
options = Options.new(
  agents: %{coder: coder, analyst: analyst},
  agent: :coder,  # Active agent
  max_turns: 2
)

# First query with coder
messages1 = ClaudeAgentSDK.query(prompt1, options) |> Enum.to_list()
session_id = extract_session_id(messages1)

# Switch to analyst and resume
options_analyst = %{options | agent: :analyst}
messages2 = ClaudeAgentSDK.resume(session_id, prompt2, options_analyst)
```

**Demonstrates:**
- `Agent.new/1` for agent definition
- Multiple agents in options
- Agent switching via `options.agent`
- Session continuation across agent switches

---

#### `advanced_features/permissions_live.exs`
**Purpose:** Fine-grained tool permission control.

**Key Patterns:**
```elixir
alias ClaudeAgentSDK.Permission.Result

permission_callback = fn context ->
  case {context.tool_name, context.tool_input} do
    {"Write", %{"file_path" => path} = input} ->
      if String.starts_with?(path, allowed_dir) do
        Result.allow()
      else
        # Redirect to safe location
        Result.allow(updated_input: Map.put(input, "file_path", safe_path))
      end

    {tool, _} ->
      Result.allow()  # Allow other tools
  end
end

options = Options.new(
  permission_mode: :plan,  # Triggers can_use_tool requests
  can_use_tool: permission_callback,
  tools: ["Write"],
  allowed_tools: ["Write"]
)
```

**Demonstrates:**
- `can_use_tool` callback
- `Permission.Result` module
- Input modification via `updated_input`
- Permission modes: `:default`, `:accept_edits`, `:plan`, `:bypass_permissions`

---

#### `advanced_features/sdk_mcp_live_demo.exs`
**Purpose:** Comprehensive SDK MCP tools demonstration.

**Key Patterns:**
```elixir
defmodule MathTools do
  use ClaudeAgentSDK.Tool

  deftool :add, "Add two numbers", %{...schema...} do
    def execute(%{"a" => a, "b" => b}) do
      {:ok, %{"content" => [%{"type" => "text", "text" => "#{a + b}"}]}}
    end
  end

  deftool :multiply, "Multiply numbers", %{...schema...} do
    def execute(%{"a" => a, "b" => b}) do
      {:ok, %{"content" => [%{"type" => "text", "text" => "#{a * b}"}]}}
    end
  end
end

server = ClaudeAgentSDK.create_sdk_mcp_server(
  name: "math-tools",
  version: "1.0.0",
  tools: [MathTools.Add, MathTools.Multiply]
)

# Server metadata
server.name          # "math-tools"
server.version       # "1.0.0"
server.type          # :sdk
server.registry_pid  # Process for tool dispatch
```

**Demonstrates:**
- Complete `deftool` macro usage
- JSON schema for tool inputs
- Server metadata access
- Tool result content format

---

### Runtime Control

#### `runtime_control/control_parity_live.exs`
**Purpose:** Runtime configuration changes and streaming parity.

**Key Patterns:**
```elixir
alias ClaudeAgentSDK.{Client, Query}

# Query API with hooks
query_options = %Options{
  hooks: %{user_prompt_submit: [Matcher.new(nil, [hook])]},
  permission_mode: :default,
  include_partial_messages: true
}

Query.run("Say hello", query_options) |> Enum.to_list()

# Streaming with runtime changes
{:ok, client} = Client.start_link(stream_options)

# First request
Client.stream_messages(client) |> ...
Client.send_message(client, "First prompt")

# Runtime permission mode change
:ok = Client.set_permission_mode(client, :accept_edits)

# Second request with new mode
Client.stream_messages(client) |> ...
Client.send_message(client, "Second prompt")

Client.stop(client)
```

**Demonstrates:**
- `Query.run/2` for control-aware queries
- `Client.set_permission_mode/2` for runtime changes
- `include_partial_messages: true` for stream events
- Streaming/control parity

---

### Archived Examples

The `archive/` directory contains older or experimental examples:

| Directory | Purpose |
|-----------|---------|
| `archive/mock_demos/` | Deterministic mock transport examples |
| `archive/advanced_features/` | v0.4.0 feature demos |
| `archive/runtime_control/` | Model switching, cancellation demos |
| `archive/streaming_tools/` | LiveView pattern reference |
| `archive/top_level/` | Legacy top-level examples |
| `archive/hooks/` | Archived hook documentation |

Key archived patterns:
- Mock transport for deterministic testing
- Model switching at runtime
- Subscriber broadcast patterns
- LiveView integration pseudo-code

---

## Key Usage Patterns

### Pattern 1: Basic Query with Response Extraction

```elixir
alias ClaudeAgentSDK.{ContentExtractor, OptionBuilder}

options = OptionBuilder.with_haiku()

response = ClaudeAgentSDK.query(prompt, options)
  |> Enum.to_list()
  |> Enum.filter(&(&1.type == :assistant))
  |> Enum.map(&ContentExtractor.extract_text/1)
  |> Enum.join("\n")
```

### Pattern 2: Client-Based Streaming

```elixir
alias ClaudeAgentSDK.{Client, Options}

{:ok, client} = Client.start_link(%Options{...})

task = Task.async(fn ->
  Client.stream_messages(client)
  |> Enum.reduce_while([], fn msg, acc ->
    case msg do
      %{type: :result} -> {:halt, acc}
      _ -> {:cont, [msg | acc]}
    end
  end)
end)

:ok = Client.send_message(client, prompt)
messages = Task.await(task, 120_000)

Client.stop(client)
```

### Pattern 3: Streaming API with Event Handling

```elixir
alias ClaudeAgentSDK.{Streaming, Options}

{:ok, session} = Streaming.start_session(options)

try do
  Streaming.send_message(session, prompt)
  |> Enum.each(fn
    %{type: :text_delta, text: t} -> IO.write(t)
    %{type: :tool_use_start, name: n} -> IO.puts("Tool: #{n}")
    %{type: :message_stop} -> :done
    _ -> :ignore
  end)
after
  Streaming.close_session(session)
end
```

### Pattern 4: Hook Configuration

```elixir
alias ClaudeAgentSDK.Hooks.{Matcher, Output}

hooks = %{
  user_prompt_submit: [Matcher.new(nil, [&context_hook/3])],
  pre_tool_use: [
    Matcher.new("*", [&audit_hook/3]),
    Matcher.new("Bash", [&security_hook/3])
  ],
  post_tool_use: [Matcher.new("*", [&monitor_hook/3])]
}

options = %Options{hooks: hooks, ...}
```

### Pattern 5: SDK MCP Tools

```elixir
defmodule MyTools do
  use ClaudeAgentSDK.Tool

  deftool :my_tool, "Description", %{type: "object", ...} do
    def execute(input) do
      {:ok, %{"content" => [%{"type" => "text", "text" => "result"}]}}
    end
  end
end

server = ClaudeAgentSDK.create_sdk_mcp_server(
  name: "my-server", version: "1.0.0", tools: [MyTools.MyTool]
)

options = %Options{
  mcp_servers: %{"my-server" => server},
  allowed_tools: ["mcp__my-server__my_tool"]
}
```

### Pattern 6: ETS-Based Hook State

```elixir
@table :my_hook_state

def init_table do
  :ets.new(@table, [:named_table, :public, :set])
end

def my_hook(input, _tool_use_id, _context) do
  :ets.update_counter(@table, :count, {2, 1}, {:count, 0})
  %{}
end

def get_count do
  case :ets.lookup(@table, :count) do
    [{:count, n}] -> n
    _ -> 0
  end
end
```

---

## Dependencies and Requirements

### Runtime Dependencies

| Dependency | Purpose | Required |
|------------|---------|----------|
| Claude Code CLI | Backend execution | Yes |
| Authentication | API access | Yes |
| Git | File checkpointing | For checkpointing |

### Mix Dependencies

The examples use these SDK modules:
- `ClaudeAgentSDK` - Main module
- `ClaudeAgentSDK.Options` - Configuration
- `ClaudeAgentSDK.Client` - Stateful client
- `ClaudeAgentSDK.Streaming` - Streaming API
- `ClaudeAgentSDK.Query` - Control-aware queries
- `ClaudeAgentSDK.Agent` - Agent definitions
- `ClaudeAgentSDK.Tool` - Tool definitions (`deftool`)
- `ClaudeAgentSDK.ContentExtractor` - Message parsing
- `ClaudeAgentSDK.Session` - Session utilities
- `ClaudeAgentSDK.SessionStore` - Persistence
- `ClaudeAgentSDK.Message` - Message types
- `ClaudeAgentSDK.Hooks.Matcher` - Hook matching
- `ClaudeAgentSDK.Hooks.Output` - Hook responses
- `ClaudeAgentSDK.Permission.Result` - Permission results
- `ClaudeAgentSDK.CLI` - CLI utilities

### Support Files

- `examples/support/example_helper.exs` - Shared utilities
  - `Support.ensure_live!()` - Verify CLI available
  - `Support.header!(title)` - Print section header
  - `Support.halt_if_runner!()` - Clean exit in batch mode
  - `Support.output_dir!()` - Get/create output directory
  - `Support.examples_dir()` - Get examples directory path

---

## Quick Reference Table

| Example | Category | Key Feature | API Used |
|---------|----------|-------------|----------|
| `basic_example.exs` | Basic | Minimal query | `query/2`, `ContentExtractor` |
| `session_features_example.exs` | Session | Persistence/resume | `SessionStore`, `resume/3` |
| `structured_output_live.exs` | Output | JSON schema | `output_format: %{type: :json_schema}` |
| `sandbox_settings_live.exs` | Config | Sandbox settings | `Options.sandbox` |
| `tools_and_betas_live.exs` | Config | Tool variants | `Options.tools`, `betas` |
| `sdk_mcp_tools_live.exs` | MCP | In-process tools | `deftool`, `create_sdk_mcp_server/1` |
| `assistant_error_live.exs` | Errors | Error handling | `Message.error`, `Streaming` |
| `file_checkpointing_live.exs` | Files | Checkpointing | `Client.rewind_files/2` |
| `filesystem_agents_live.exs` | Agents | File-based agents | `setting_sources: ["project"]` |
| `quick_demo.exs` | Streaming | Basic streaming | `Streaming.start_session/1` |
| `basic_streaming_with_hooks.exs` | Streaming | Hooks + streaming | `Streaming` + `Hooks` |
| `sdk_mcp_streaming.exs` | Streaming | MCP + streaming | `Streaming` + MCP |
| `context_injection.exs` | Hooks | Context inject | `user_prompt_submit`, `Output.add_context/2` |
| `basic_bash_blocking.exs` | Hooks | Security | `pre_tool_use`, `Output.deny/1` |
| `file_policy_enforcement.exs` | Hooks | File sandbox | `pre_tool_use`, wildcard matching |
| `logging_and_audit.exs` | Hooks | Audit trail | `pre_tool_use`, `post_tool_use` |
| `complete_workflow.exs` | Hooks | Full workflow | All hook types |
| `agents_live.exs` | Advanced | Multi-agent | `Agent.new/1`, `resume/3` |
| `permissions_live.exs` | Advanced | Permissions | `can_use_tool`, `Permission.Result` |
| `sdk_mcp_live_demo.exs` | Advanced | MCP demo | `deftool`, `create_sdk_mcp_server/1` |
| `control_parity_live.exs` | Runtime | Config changes | `Client.set_permission_mode/2` |

---

## Summary

The Claude Agent SDK examples provide comprehensive coverage of all SDK features:

1. **Basic Usage**: Query/response patterns, message extraction
2. **Sessions**: Persistence, search, resume, filesystem agents
3. **Streaming**: Event handling, typewriter effects, tool lifecycle
4. **Hooks**: Context injection, security validation, audit logging
5. **MCP Tools**: In-process tool definition and execution
6. **Permissions**: Fine-grained access control, input modification
7. **Agents**: Multi-agent workflows, context preservation
8. **Runtime Control**: Dynamic configuration changes

All examples are designed to be:
- Self-contained and runnable
- Documented with clear comments
- Validated with assertions
- Safe for production patterns
