<div align="center">
  <img src="assets/claude_agent_sdk.svg" alt="Claude Agent SDK Logo" width="200"/>
</div>

# Claude Agent SDK for Elixir

[![Hex.pm](https://img.shields.io/hexpm/v/claude_agent_sdk.svg)](https://hex.pm/packages/claude_agent_sdk)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/claude_agent_sdk/)
[![Hex.pm Downloads](https://img.shields.io/hexpm/dt/claude_agent_sdk.svg)](https://hex.pm/packages/claude_agent_sdk)
[![License](https://img.shields.io/hexpm/l/claude_agent_sdk.svg)](https://github.com/nshkrdotcom/claude_agent_sdk/blob/main/LICENSE)
[![CI](https://github.com/nshkrdotcom/claude_agent_sdk/actions/workflows/elixir.yaml/badge.svg)](https://github.com/nshkrdotcom/claude_agent_sdk/actions/workflows/elixir.yaml)
[![Last Commit](https://img.shields.io/github/last-commit/nshkrdotcom/claude_agent_sdk.svg)](https://github.com/nshkrdotcom/claude_agent_sdk/commits/main)

An Elixir SDK for programmatically interacting with Claude Code. This library provides a simple interface to query Claude and handle responses using the familiar Elixir streaming patterns.

## Architecture

```mermaid
flowchart TB
    subgraph "Elixir Application"
        SDK["ClaudeAgentSDK API"]
        Router["Streaming Router<br>(auto CLI vs control)"]
        Transport["Transport Behaviour<br>(Port, Process, Mock)"]
        ClientCtrl["Control Client<br>(GenServer + Hooks + MCP)"]
        Streaming["Streaming Facade"]
        Options["Options + Runtime Control"]
        Tests["Supertester Mock Harness"]
    end

    subgraph "Claude Code CLI"
        CLI["claude executable<br>(Node.js CLI)"]
        CLI --> API["Claude Service"]
        API --> CLI
    end

    SDK --> Options
    SDK --> Router
    Router -->|CLI path| Transport
    Router -->|Control path| ClientCtrl
    ClientCtrl --> Transport
    Transport --> CLI
    CLI --> Transport
    Transport --> Streaming
    Streaming --> SDK

    ClientCtrl --> Hooks[Hooks Registry]
    ClientCtrl --> MCP[SDK MCP Bridge]
    ClientCtrl --> Permissions[Permission Callback]
    Options --> Transport
    Options --> ClientCtrl
    Tests --> Transport
    Tests --> SDK

    style SDK fill:#4a9eff,stroke:#2d7dd2,stroke-width:2px,color:#000
    style CLI fill:#f08b54,stroke:#c36c34,stroke-width:2px,color:#000
    style API fill:#ff6b6b,stroke:#ff4757,stroke-width:2px,color:#000
```

## Prerequisites

This SDK requires the Claude Code CLI to be installed:

```bash
npm install -g @anthropic-ai/claude-code
```

### CLI discovery & version checks

- The SDK now centralizes CLI lookup in `ClaudeAgentSDK.CLI`, trying `claude-code` first and then `claude`.
- Minimum supported CLI version: `1.0.0`. Check with `ClaudeAgentSDK.CLI.version_supported?/0` or print the detected version via `ClaudeAgentSDK.CLI.version/0`.
- Emit an upgrade hint for operators with `ClaudeAgentSDK.CLI.warn_if_outdated/0`.
- Any live example (e.g., `mix run.live examples/basic_example.exs`) will use the same discovery logic, so running one is a quick end-to-end verification of your install.

## Installation

Add `claude_agent_sdk` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:claude_agent_sdk, "~> 0.6.2"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## Quick Start

1. **Authenticate the CLI** (do this once):
   ```bash
   claude login
   ```

2. **Install dependencies**:
   ```bash
   mix deps.get
   ```

3. **Run the showcase**:
   ```bash
   # Safe demo with mocks (no API costs)
   mix showcase
   
   # Live demo with real API calls (requires authentication)
   mix showcase --live
   ```

4. **Try the live script runner**:
   ```bash
   # Run example scripts with live API calls
   mix run.live examples/basic_example.exs
   mix run.live examples/simple_analyzer.exs lib/claude_agent_sdk.ex
   ```

## Streaming + Tools (v0.6.0)

The SDK now supports streaming WITH control features like hooks, SDK MCP servers, and permissions! Previously, you had to choose between fast streaming (CLI-only) or control features (blocking). Now you get both automatically.

### Automatic Transport Selection

The SDK intelligently routes your streaming requests:

- **CLI-only path**: Fast streaming without control features
  - No hooks, SDK MCP, permissions, or agents configured
  - Direct subprocess streaming (lowest latency)

- **Control client path**: Streaming WITH all features
  - Hooks enabled
  - SDK MCP servers configured
  - Permission callbacks active
  - Runtime agents configured

### Quick Example: Streaming with Hooks

```elixir
alias ClaudeAgentSDK.{Streaming, Options}
alias ClaudeAgentSDK.Hooks.{Matcher, Output}

# Define a pre-tool hook
def log_tool_use(input, _tool_id, _context) do
  tool_name = input["tool_name"]
  IO.puts("🔧 Executing tool: #{tool_name}")
  Output.allow()
end

# Configure options with hooks
options = %Options{
  hooks: %{
    pre_tool_use: [Matcher.new("*", [&log_tool_use/3])]
  }
}

# Start streaming session - automatically uses control client
{:ok, session} = Streaming.start_session(options)

# Send message and get streaming response with hook execution
Streaming.send_message(session, "Create a hello.ex file")
|> Stream.each(fn
  %{type: :text_delta, text: text} ->
    IO.write(text)  # Typewriter effect

  %{type: :tool_complete, tool_name: name} ->
    IO.puts("\n✅ Tool #{name} completed")

  %{type: :message_stop} ->
    IO.puts("\n[Complete]")
end)
|> Stream.run()

Streaming.close_session(session)
```

### Streaming with SDK MCP Servers

```elixir
# Define an SDK MCP tool
defmodule Calculator do
  use ClaudeAgentSDK.Tool

  deftool :add, "Adds two numbers", %{
    type: "object",
    properties: %{
      a: %{type: "number"},
      b: %{type: "number"}
    }
  } do
    def execute(%{"a" => a, "b" => b}) do
      {:ok, %{"content" => [%{"type" => "text", "text" => "#{a + b}"}]}}
    end
  end
end

# Create SDK MCP server
server = ClaudeAgentSDK.create_sdk_mcp_server(
  name: "calculator",
  version: "1.0.0",
  tools: [Calculator.Add]
)

# Configure streaming with MCP
options = %Options{
  mcp_servers: %{"calculator" => server}
}

# Streaming automatically uses control client
{:ok, session} = Streaming.start_session(options)

Streaming.send_message(session, "What is 123 + 456?")
|> Stream.each(fn event ->
  case event.type do
    :text_delta -> IO.write(event.text)
    :tool_use_start -> IO.puts("\n🛠️ Using #{event.name}")
    :message_stop -> IO.puts("\n")
  end
end)
|> Stream.run()

Streaming.close_session(session)
```

### Configuration Options

```elixir
# Force CLI-only mode (fast, no control features)
options = %Options{
  preferred_transport: :cli,
  include_partial_messages: true  # Auto-set by start_session
}

# Force control client mode (even without features)
options = %Options{
  preferred_transport: :control
}

# Automatic selection (default, recommended)
options = %Options{}  # Analyzes your config and chooses best transport
```

### Migration from v0.5.x

No breaking changes! Your existing streaming code works as-is:

```elixir
# v0.5.x code - still works!
{:ok, session} = Streaming.start_session()
Streaming.send_message(session, "Hello") |> Enum.to_list()
Streaming.close_session(session)

# v0.6.0 - just add hooks and they work automatically
options = %Options{hooks: %{pre_tool_use: [my_hook]}}
{:ok, session} = Streaming.start_session(options)
# Now streaming includes hook execution!
```

### Event Types with Tools

The streaming events now include tool-related events when using control client:

```elixir
# Standard streaming events (both transports)
%{type: :text_delta, text: "...", accumulated: "..."}
%{type: :message_start, model: "..."}
%{type: :message_stop, final_text: "..."}

# Tool events (control client only)
%{type: :tool_use_start, name: "Bash", id: "..."}
%{type: :tool_input_delta, json: "..."}
%{type: :tool_complete, tool_name: "Bash", result: "..."}

# Hook events (control client only)
%{type: :hook_invoked, event: :pre_tool_use, result: :allow}
```

### Examples

See working examples in `examples/streaming_tools/`:
- `basic_streaming_with_hooks.exs` - Streaming with pre-tool hooks
- `sdk_mcp_streaming.exs` - Streaming with SDK MCP servers
- `liveview_pattern.exs` - Phoenix LiveView integration

## Implementation Status

### ✅ **Currently Implemented (v0.6.0)**
- **Streaming + Tools Unification**: Automatic transport selection for streaming with hooks/MCP/permissions
- **StreamingRouter**: Intelligent routing between CLI-only and control client transports
- **Polymorphic API**: Same `Streaming` API works with both transports seamlessly
- **Core SDK Functions**: `query/2`, `continue/2`, `resume/3` with stdin support
- **Live Script Runner**: `mix run.live` for executing scripts with real API calls
- **Message Processing**: Structured message types with proper parsing
- **Options Configuration**: Full CLI argument mapping with smart presets and correct CLI formats
- **Subprocess Management**: Robust erlexec integration with stdin support
- **JSON Parsing**: Custom parser without external dependencies
- **Authentication Management**: AutoManager with OAuth token support (v2.0.10+)
  - Automatic token setup via `mix claude.setup_token`
  - Token persistence and auto-refresh (1 year validity)
  - Multi-provider support (Anthropic/Bedrock/Vertex)
  - Environment variable fallback (`CLAUDE_AGENT_OAUTH_TOKEN`, `ANTHROPIC_API_KEY`)
- **Model Selection**: Choose Opus, Sonnet, Haiku, or specific versions
  - Automatic fallback when model overloaded
  - Full model name support (e.g., `claude-sonnet-4-5-20250929`)
- **Custom Agents**: Define specialized agents with custom prompts
- **Concurrent Orchestration**: Parallel query execution and workflows
  - `Orchestrator.query_parallel/2` - Run queries concurrently (3-5x faster)
  - `Orchestrator.query_pipeline/2` - Sequential workflows with context passing
  - `Orchestrator.query_with_retry/3` - Automatic retry with exponential backoff
- **Session Persistence** (v0.2.0): Save and resume sessions across restarts
  - `SessionStore` GenServer for session management
  - Save/load sessions with tags and metadata
  - Search by tags, date range, cost
  - Automatic cleanup of old sessions
- **Advanced Session Flags** (v0.2.0): Additional CLI capabilities
  - Session forking (`fork_session`) - Experiment with different approaches
  - Multiple directories (`add_dir`) - Work across project boundaries
  - Strict MCP config (`strict_mcp_config`) - Isolated MCP testing
- **Bidirectional Streaming** (v0.2.1): Real-time character-by-character streaming
  - `ClaudeAgentSDK.Streaming` module with persistent sessions
  - Text delta events for typewriter effects
  - Multi-turn conversations with context preservation
  - Message queueing for sequential processing
  - Multiple concurrent sessions for parallelism
- **Hooks System** (v0.3.0): Lifecycle callbacks for security and monitoring
  - 6 hook events: PreToolUse, PostToolUse, UserPromptSubmit, Stop, SubagentStop, PreCompact
  - Pattern-based matching with regex support
  - Permission control (allow/deny/ask)
  - Context injection and execution control
  - Complete type safety with 102 passing tests
  - 5 working examples and comprehensive documentation
- **Control Protocol** (v0.3.0): Bidirectional CLI communication
  - Message encoding/decoding for control messages
  - Initialize requests with hooks configuration
  - Hook callback request/response handling
  - JSON protocol over stdin/stdout
- **Client GenServer** (v0.3.0): Persistent bidirectional connection
  - Port-based CLI process management
  - Message streaming with subscriber pattern
  - Runtime hook callback invocation
  - Graceful shutdown and error recovery
- **MCP Tool System** (v0.4.0): In-process MCP tools with deftool macro
  - `deftool` macro for declarative tool definition
  - `create_sdk_mcp_server/1` for SDK-based MCP servers
  - Tool.Registry GenServer for tool management
  - 42 tests covering all tool scenarios
  - **Note:** SDK MCP infrastructure complete, awaiting CLI support
- **Agent Definitions** (v0.4.0): Multi-agent support with runtime switching
  - Define agent profiles with custom prompts, tools, and models
  - `Client.set_agent/2` for runtime agent switching
  - Context preservation across agent switches
  - 38 tests covering agent workflows
- **Permission System** (v0.4.0): Fine-grained tool permission control
  - Permission callbacks for security control
  - 4 permission modes (default, accept_edits, plan, bypass_permissions)
  - Tool input modification and execution interrupts
  - `Client.set_permission_mode/2` for runtime mode changes
  - 49 tests covering security scenarios
- **Runtime Control** (v0.6.2): Change models and transports without restarting
  - `Client.set_model/2` to switch models mid-conversation
  - `Client.get_model/1` to introspect active configuration
  - `Client.interrupt/1` to stop runaway tool executions
  - `Client.get_server_info/1` to read CLI command/output-style metadata
  - `Client.receive_response/1` to collect a single response without manual streaming loops
  - Pluggable transports via `ClaudeAgentSDK.Transport`
  - Mock transport for fully offline test suites
- **Error Handling**: Improved error detection and timeout handling
- **Stream Processing**: Lazy evaluation with Elixir Streams
- **Mocking System**: Comprehensive testing without API calls (supports stdin workflows)
- **Code Quality**: Full dialyzer and credo compliance with refactored complex functions
- **Developer Tools**: ContentExtractor, AuthChecker, OptionBuilder, DebugMode, AuthManager
- **Smart Configuration**: Environment-aware defaults and preset configurations

### 🎉 **v0.4.0 Milestone: 95%+ Feature Parity with Python SDK**

All three critical features now implemented with full test coverage!
- MCP Tool System (infrastructure ready, awaiting CLI support)
- Agent Definitions (fully working)
- Permission System (fully working)

### 🔮 **Planned Features (v0.7.0+)**
- **Partial Message Streaming**: Character-level deltas sourced directly from the CLI (pending upstream support)
- **Telemetry Integration**: First-class :telemetry events + dashboards
- **Additional Transports**: HTTP/WebSocket bridges and multi-tenant gateways
- **Advanced Examples**: Phoenix LiveView dashboards, CI/CD analyzers, refactoring assistants
- **Plugin System Enhancements**: Hot-reloadable local plugins, richer config merging

## Basic Usage

```elixir
# Simple query with smart content extraction
alias ClaudeAgentSDK.{ContentExtractor, OptionBuilder}

# Use preset development options
options = OptionBuilder.build_development_options()

ClaudeAgentSDK.query("Say exactly: Hello from Elixir!", options)
|> Enum.each(fn msg ->
  case msg.type do
    :assistant ->
      content = ContentExtractor.extract_text(msg)
      IO.puts("🤖 Claude: #{content}")
      
    :result ->
      if msg.subtype == :success do
        IO.puts("✅ Success! Cost: $#{msg.data.total_cost_usd}")
      end
  end
end)
```

## Runtime Control & Custom Transports

Change models on the fly and plug in alternative transports without restarting your client:

```elixir
{:ok, client} =
  ClaudeAgentSDK.Client.start_link(%ClaudeAgentSDK.Options{model: "claude-sonnet-4"},
    transport: ClaudeAgentSDK.Transport.Port
  )

:ok = ClaudeAgentSDK.Client.set_model(client, "opus")
```

To experiment with your own transport or to write deterministic tests, take a look at:

- `docs/RUNTIME_CONTROL.md`
- `docs/CUSTOM_TRANSPORTS.md`
- `docs/MIGRATION_V0_5.md`

You can try the runtime control examples directly:

```bash
mix run examples/runtime_control/model_switcher.exs
mix run examples/runtime_control/transport_swap.exs
mix run examples/runtime_control/subscriber_broadcast.exs
```

Pass `--live` to any script to attempt the default CLI transport once `claude login` is configured.
The model switcher prints the model before and after calling `set_model/2`, making it easy to confirm the change succeeded in real time.

## Runtime Control Enhancements (v0.6.2)

The 0.6.2 release tightens parity with the Python SDK and makes custom transports easier to work with:

- **`Client.interrupt/1`** — send a control protocol interrupt from Elixir and stop dangerous or runaway tool calls instantly.
- **`Client.get_server_info/1`** — capture the CLI’s initialization payload (commands, output styles, capability flags) for your UI or logging layer.
- **`Client.receive_response/1`** — a bounded helper that streams until the `:result` frame, perfect for REPLs or short-lived jobs.
- **Expanded `Options` struct** — configure budgets, resume/fork semantics, plugin directories, env/extra CLI flags, and thinking-token caps exactly like the Python SDK.
- **Transport/Process parity** — `ClaudeAgentSDK.Transport.Port` and `ClaudeAgentSDK.Process` now respect `Options.env`, custom cwd, and larger buffer sizes while stamping `CLAUDE_AGENT_SDK_VERSION` into every subprocess.

See [CHANGELOG.md](CHANGELOG.md#061---2025-11-11) for the complete diff.

## Testing with Mocks

The SDK includes a comprehensive mocking system for testing without making actual API calls.

### Running Tests

```bash
# Run tests with mocks (default)
mix test

# Run tests with live API calls
MIX_ENV=test mix test.live

# Run specific test with live API
MIX_ENV=test mix test.live test/specific_test.exs
```

### Using Mocks in Your Code

```elixir
# Enable mocking
Application.put_env(:claude_agent_sdk, :use_mock, true)

# Start the mock server
{:ok, _} = ClaudeAgentSDK.Mock.start_link()

# Set a mock response
ClaudeAgentSDK.Mock.set_response("hello", [
  %{
    "type" => "assistant",
    "message" => %{"content" => "Hello from mock!"}
  }
])

# Query will return mock response
ClaudeAgentSDK.query("say hello") |> Enum.to_list()
```

### Mock Demo

Run the included demo to see mocking in action:

```bash
mix run demo_mock.exs
```

For detailed documentation about the mocking system, see [MOCKING.md](MOCKING.md).

## Available Examples - Organized by Feature

### 🎯 Getting Started (Start Here!)

```bash
# 1. Quick showcase - demonstrates all features in mock mode (FREE)
mix showcase

# 2. Live showcase - same with real API calls (costs money)
mix showcase --live

# 3. Simple SDK MCP test - verify MCP integration (FREE)
mix run examples/advanced_features/sdk_mcp_simple_test.exs
```

---

### 🌟 MCP Tools (SDK MCP Servers)

**Mock Mode (FREE - No API costs):**
```bash
# MCP Calculator - Tool definition and direct execution
mix run examples/advanced_features/mcp_calculator_tool.exs

# SDK MCP Simple Test - Comprehensive validation
mix run examples/advanced_features/sdk_mcp_simple_test.exs
```

**Live Mode (Real API calls - costs money):**
```bash
# SDK MCP Live Demo - Real Claude using SDK tools
MIX_ENV=test mix run.live examples/advanced_features/sdk_mcp_live_demo.exs
```

---

### 🤖 Agents & Permissions

**Mock Mode (FREE):**
```bash
# Agent Switching - Multi-agent workflows
mix run examples/advanced_features/agent_switching.exs

# Permission Control - Security callbacks
mix run examples/advanced_features/permission_control.exs

# Full Feature Showcase - All three features together
mix run examples/advanced_features/full_feature_showcase.exs
```

**Live Mode (Real API calls - costs money):**
```bash
# Agents Live - Real agent switching with multi-turn workflow
MIX_ENV=test mix run.live examples/advanced_features/agents_live.exs

# Permissions Live - Real permission checks and auditing
MIX_ENV=test mix run.live examples/advanced_features/permissions_live.exs
```

---

### 🪝 Hooks System

**All hook examples (FREE - mock mode):**
```bash
# Basic Bash Blocking - Simple hook to block dangerous commands
mix run examples/hooks/basic_bash_blocking.exs

# Complete Workflow - Full hook lifecycle demonstration
mix run examples/hooks/complete_workflow.exs

# Context Injection - Adding context to prompts
mix run examples/hooks/context_injection.exs

# File Policy Enforcement - Controlling file operations
mix run examples/hooks/file_policy_enforcement.exs

# Logging and Audit - Tracking all tool usage
mix run examples/hooks/logging_and_audit.exs
```

---

### 📚 Core Examples - Basic Usage

**Mock Mode (FREE):**
```bash
# Basic usage - Simple query example
mix run examples/basic_example.exs

# Factorial - Function generation
mix run examples/factorial_example.exs

# Custom Agents - Define specialized agents
mix run examples/custom_agents_example.exs

# Model Selection - Choose different Claude models
mix run examples/model_selection_example.exs

# Session Features - Save and resume sessions
mix run examples/session_features_example.exs

# Week 1-2 Showcase - Early features demonstration
mix run examples/week_1_2_showcase.exs
```

**Live Mode (Costs money):**
```bash
# Simple Analyzer - Code analysis
mix run.live examples/simple_analyzer.exs lib/claude_agent_sdk.ex

# File Reviewer - Review any file
mix run.live examples/file_reviewer.exs README.md

# Simple Batch - Batch processing
mix run.live examples/simple_batch.exs

# Test Generator - Generate tests (experimental)
mix run.live examples/simple_test_gen.exs

# Project Assistant - Fixed version with better features
mix run.live examples/project_assistant_fixed.exs
```

---

### 🧪 Testing & Utilities

```bash
# Auth Detection Test - Verify authentication setup
mix run examples/test_auth_detection.exs
```

---

### 📋 Running All Examples

**Quick Scripts:**

```bash
# Run ALL examples in mock mode (FREE - no API costs, ~30 examples)
./run_all_examples.sh

# Run ALL examples in LIVE mode (⚠️ EXPENSIVE - requires confirmation, default: N)
./run_all_examples.sh live
```

**Or run by specific groups:**

```bash
# Run all mock mode examples by group (FREE - no API costs)
./test_all_examples.sh all

# Run specific groups
./test_all_examples.sh getting-started  # Quick start examples
./test_all_examples.sh mcp              # MCP tools
./test_all_examples.sh agents           # Agents & Permissions
./test_all_examples.sh hooks            # Hooks system
./test_all_examples.sh core             # Core/basic examples

# ⚠️  DANGEROUS: Run live examples by group (costs money!)
./test_all_examples.sh live
```

**Manual Group Commands:**

```bash
# MCP Tools (Mock Mode)
for f in examples/advanced_features/sdk_mcp_simple_test.exs examples/advanced_features/mcp_calculator_tool.exs; do
  echo "Running $f..." && mix run "$f" && echo "✅ PASSED\n" || echo "❌ FAILED\n"
done

# Agents & Permissions (Mock Mode)
for f in examples/advanced_features/{agent_switching,permission_control,full_feature_showcase}.exs; do
  echo "Running $f..." && mix run "$f" && echo "✅ PASSED\n" || echo "❌ FAILED\n"
done

# Hooks (Mock Mode)
for f in examples/hooks/*.exs; do
  echo "Running $f..." && mix run "$f" && echo "✅ PASSED\n" || echo "❌ FAILED\n"
done

# Core Examples (Mock Mode)
for f in examples/{basic_example,factorial_example,custom_agents_example,model_selection_example,session_features_example,week_1_2_showcase,test_auth_detection}.exs; do
  echo "Running $f..." && mix run "$f" && echo "✅ PASSED\n" || echo "❌ FAILED\n"
done
```

## Live Script Runner

The SDK includes a powerful `mix run.live` task for executing Elixir scripts with live Claude API calls:

### Usage

```bash
# Run any .exs script with live API
mix run.live script.exs [args...]

# Examples
mix run.live examples/basic_example.exs
mix run.live examples/simple_analyzer.exs lib/claude_agent_sdk.ex
mix run.live examples/file_reviewer.exs path/to/your/file.txt
```

### Features

- **🔴 Live API Integration**: Makes real Claude API calls with proper stdin handling
- **⚠️ Cost Warnings**: Clear warnings about API usage and costs
- **📄 Argument Passing**: Supports passing arguments to scripts
- **🛡️ Safe by Default**: Requires explicit live mode activation
- **🎭 Mock Fallback**: Scripts can still run in mock mode during development

### Difference from Regular `mix run`

| **Command** | **API Calls** | **Costs** | **Authentication Required** |
|-------------|---------------|-----------|---------------------------|
| `mix run script.exs` | None (mock mode) | $0.00 | No |
| `mix run.live script.exs` | Real API calls | Real costs | Yes (`claude login`) |

### Example Scripts

The SDK includes several example scripts you can run immediately:

```bash
# Basic factorial function generation
mix run.live examples/basic_example.exs

# Code analysis with file input
mix run.live examples/simple_analyzer.exs lib/claude_agent_sdk.ex

# Simple batch processing
mix run.live examples/simple_batch.exs

# File review and analysis
mix run.live examples/file_reviewer.exs README.md
```

### Creating Your Own Live Scripts

Create scripts that automatically work in both mock and live modes:

```elixir
#!/usr/bin/env elixir

# Check if we're in live mode
if Application.get_env(:claude_agent_sdk, :use_mock, false) do
  {:ok, _} = ClaudeAgentSDK.Mock.start_link()
  IO.puts("🎭 Mock mode enabled")
else
  IO.puts("🔴 Live mode enabled")
end

# Your script logic here...
response = ClaudeAgentSDK.query("Your prompt here")
|> extract_response()

IO.puts("Response: #{response}")
```

### 🎭 Mock vs Live Mode

**All examples and tests can run in two modes:**

| **Mode** | **Command Format** | **API Calls** | **Costs** | **Authentication Required** |
|----------|-------------------|---------------|-----------|---------------------------|
| **Mock** | `mix showcase` | None (mocked) | $0.00 | No |
| **Live** | `mix showcase --live` | Real API calls | Real costs | Yes (`claude login`) |

### 🎯 Showcase Features

The showcase demonstrates all SDK functionality:

| **Feature Demonstrated** | **What It Shows** |
|-------------------------|-------------------|
| **OptionBuilder** | Smart configuration presets for development, production, chat, analysis |
| **AuthChecker** | Environment validation and authentication diagnostics |
| **Basic SDK Usage** | Core query functionality with mocked/real responses |
| **ContentExtractor** | Easy text extraction from complex message formats |
| **DebugMode** | Message analysis, benchmarking, troubleshooting tools |
| **Mock System** | Complete testing infrastructure without API costs |
| **Advanced Configurations** | Real-world scenarios for different use cases |
| **Performance Features** | Benchmarking and timing analysis |

### 🚀 Running Examples

**⚠️ Live mode will make real API calls and incur costs. Always test with mock mode first!**

| **Command** | **Status** | **Notes** |
|-------------|------------|-----------|
| `mix showcase` | ✅ Working | Mock mode, fast, no costs |
| `mix showcase --live` | ✅ Working | Live mode, real API calls, no hanging |
| `mix test` | ✅ Working | Mock mode, **618 tests**, 52 skipped |
| `mix test.live` | ⚠️ Requires CLI auth | Live mode; run only after `claude login` succeeds |
| `mix run example.exs` | ✅ Working | Uses mock mode by default, auto-starts Mock |
| `mix run examples/simple_analyzer.exs` | ✅ Working | Uses mock mode by default |
| `mix run.live examples/basic_example.exs` | ✅ Working | Live mode, real API calls, stdin support |
| `mix run.live examples/simple_analyzer.exs` | ✅ Working | Live mode, file analysis with arguments |

## API Reference

### Main Functions

#### `ClaudeAgentSDK.query(prompt, options \\ nil)`
Runs a query against Claude Code and returns a stream of messages.

```elixir
# Simple query
ClaudeAgentSDK.query("Write a hello world function")
|> Enum.to_list()

# With options
options = %ClaudeAgentSDK.Options{max_turns: 5, verbose: true}
ClaudeAgentSDK.query("Complex task", options)
|> Enum.to_list()
```

#### `ClaudeAgentSDK.continue(prompt \\ nil, options \\ nil)`
Continues the most recent conversation.

```elixir
ClaudeAgentSDK.continue("Now add error handling")
|> Enum.to_list()
```

#### `ClaudeAgentSDK.resume(session_id, prompt \\ nil, options \\ nil)`
Resumes a specific conversation by session ID.

```elixir
ClaudeAgentSDK.resume("session-id-here", "Add tests")
|> Enum.to_list()
```

### Options & Smart Presets

Configure requests with `ClaudeAgentSDK.Options` or use smart presets:

```elixir
# Manual configuration
%ClaudeAgentSDK.Options{
  max_turns: 10,              # Maximum conversation turns
  system_prompt: "Custom...", # Override system prompt
  output_format: :stream_json,# Output format
  verbose: true,              # Enable verbose logging
  cwd: "/path/to/project"     # Working directory
}

# Smart presets with OptionBuilder
alias ClaudeAgentSDK.OptionBuilder

# Development: permissive settings, verbose logging
options = OptionBuilder.build_development_options()

# Production: restricted settings, minimal tools
options = OptionBuilder.build_production_options()

# Analysis: read-only tools for code analysis
options = OptionBuilder.build_analysis_options()

# Chat: simple conversations
options = OptionBuilder.build_chat_options()

# Auto-detect based on Mix.env()
options = OptionBuilder.for_environment()

# Custom combinations
options = OptionBuilder.merge(:development, %{max_turns: 5})
```

#### Structured outputs (JSON Schema)
Request validated JSON responses using a schema (CLI must support `--json-schema`, as in the Python SDK 0.1.10 feature set):

```elixir
schema = %{
  "type" => "object",
  "properties" => %{"answer" => %{"type" => "string"}},
  "required" => ["answer"]
}

options = %ClaudeAgentSDK.Options{
  output_format: %{type: :json_schema, schema: schema}
}

# Live demo (pretty prints structured_output)
# mix run.live examples/structured_output_live.exs
# Tip: set CLAUDE_CODE_STREAM_CLOSE_TIMEOUT=120000 for slow MCP/server startups.
```

### Message Types

The SDK returns a stream of `ClaudeAgentSDK.Message` structs with these types:

- **`:system`** - Session initialization (session_id, model, tools)
- **`:user`** - User messages  
- **`:assistant`** - Claude's responses (data includes `:message`, `:session_id`, and optional `:error` from `:authentication_failed | :billing_error | :rate_limit | :invalid_request | :server_error | :unknown`)
- **`:result`** - Final result with cost/duration stats

Handle assistant errors surfaced mid-stream to tailor UX (e.g., retry prompts on rate limits):

```elixir
case message do
  %ClaudeAgentSDK.Message{type: :assistant, data: %{error: :rate_limit}} ->
    IO.puts("Rate limited — prompt the user to retry or wait.")

  %ClaudeAgentSDK.Message{type: :assistant, data: %{error: :authentication_failed}} ->
    IO.puts("Auth error — show login helper or token setup instructions.")

  %ClaudeAgentSDK.Message{type: :assistant} ->
    :ok
end

# Live demo: `mix run.live examples/assistant_error_live.exs`
```

### Message Processing

Use the built-in `ContentExtractor` for easy message processing:

```elixir
alias ClaudeAgentSDK.ContentExtractor

# Extract all assistant responses
content = ClaudeAgentSDK.query("Your prompt")
|> Stream.filter(fn msg -> msg.type == :assistant end)
|> Stream.map(&ContentExtractor.extract_text/1)
|> Enum.join("\n")

# Check if message has text content
if ContentExtractor.has_text?(message) do
  text = ContentExtractor.extract_text(message)
  IO.puts("Response: #{text}")
end
```

## Authentication

### Automatic Authentication (v0.1.0+)

The SDK now provides automatic token management with the AuthManager:

```bash
# One-time setup (requires Claude subscription)
$ mix claude.setup_token
```

This generates a long-lived OAuth token (1 year) and stores it securely. The SDK automatically uses this token for all queries.

### Environment Variable (Recommended for CI/CD)

```bash
# Set OAuth token
export CLAUDE_AGENT_OAUTH_TOKEN=sk-ant-oat01-your-token-here

# Or use API key (legacy)
export ANTHROPIC_API_KEY=sk-ant-api03-your-key-here
```

The SDK automatically detects and uses these environment variables.

### Legacy: Manual CLI Login

```bash
# Still supported but requires re-authentication
$ claude login
```

This SDK also supports your already-authenticated Claude CLI session.

### Authentication Checking

Use `AuthManager` to check status:

```elixir
alias ClaudeAgentSDK.AuthManager

# Check authentication status
status = AuthManager.status()
# => %{
#   authenticated: true,
#   provider: :anthropic,
#   token_present: true,
#   expires_at: ~U[2026-10-07 ...],
#   time_until_expiry_hours: 8760.0
# }

# Ensure authenticated (auto-setup if needed)
:ok = AuthManager.ensure_authenticated()
```

## Model Selection (v0.1.0+)

Choose the best Claude model for your task:

```elixir
alias ClaudeAgentSDK.OptionBuilder

# Opus - Most capable, complex reasoning
options = OptionBuilder.with_opus()
ClaudeAgentSDK.query("Design a complex system architecture", options)

# Sonnet - Balanced, cost-effective (default)
options = OptionBuilder.with_sonnet()
ClaudeAgentSDK.query("Review this code", options)

# Haiku - Fastest, lowest cost
options = OptionBuilder.with_haiku()
ClaudeAgentSDK.query("What is 2+2?", options)

# Custom model with automatic fallback
options = %Options{
  model: "opus",
  fallback_model: "sonnet"  # If opus is overloaded
}

# Use specific model version
options = %Options{
  model: "claude-sonnet-4-5-20250929"
}
```

## Custom Agents (v0.1.0+)

Define specialized agents with custom prompts:

```elixir
# Define a security-focused agent
options = %Options{
  agents: %{
    "security_reviewer" => %{
      description: "Security vulnerability scanner",
      prompt: """
      You are a security expert specializing in OWASP Top 10.
      Review code for vulnerabilities and provide specific fixes.
      """
    }
  }
}

ClaudeAgentSDK.query("Review this authentication code", options)

# Or use OptionBuilder helper
options = OptionBuilder.build_analysis_options()
|> OptionBuilder.with_agent("security_reviewer", %{
  description: "Security expert",
  prompt: "Review for OWASP Top 10 vulnerabilities"
})
```

## Bidirectional Client (v0.3.0+)

The `Client` GenServer provides bidirectional streaming communication with Claude Code, enabling hooks and interactive conversations:

```elixir
alias ClaudeAgentSDK.{Client, Options}

# Start client
{:ok, client} = Client.start_link(%Options{
  allowed_tools: ["Bash", "Write", "Read"]
})

# Send message
Client.send_message(client, "Create a hello.ex file")

# Receive messages as stream
Client.stream_messages(client)
|> Stream.filter(&(&1.type == :assistant))
|> Enum.each(&IO.inspect/1)

# Stop client
Client.stop(client)
```

**Features:**
- Persistent bidirectional connection
- Message streaming with backpressure
- Control protocol support
- Hook integration
- Automatic cleanup

## Hooks (v0.3.0+)

Hooks are callback functions that execute at specific lifecycle events during Claude's execution, enabling security policies, context injection, and monitoring:

```elixir
alias ClaudeAgentSDK.{Client, Options}
alias ClaudeAgentSDK.Hooks.{Matcher, Output}

# Define a hook callback
def check_bash_command(input, _tool_use_id, _context) do
  case input do
    %{"tool_name" => "Bash", "tool_input" => %{"command" => cmd}} ->
      if String.contains?(cmd, "rm -rf") do
        Output.deny("Dangerous command blocked")
        |> Output.with_system_message("🔒 Security policy violation")
      else
        Output.allow()
      end
    _ -> %{}
  end
end

# Configure hooks
options = %Options{
  allowed_tools: ["Bash", "Write", "Read"],
  hooks: %{
    # Block dangerous commands before execution
    pre_tool_use: [
      Matcher.new("Bash", [&check_bash_command/3])
    ],
    # Add context after operations
    post_tool_use: [
      Matcher.new("*", [&log_tool_usage/3])
    ],
    # Inject project context automatically
    user_prompt_submit: [
      Matcher.new(nil, [&add_project_context/3])
    ]
  }
}

# Start client with hooks
{:ok, client} = Client.start_link(options)

# Hooks automatically invoke when CLI triggers them
Client.send_message(client, "Run a bash command")

# The check_bash_command hook will be called before execution!
Client.stream_messages(client) |> Enum.to_list()
Client.stop(client)
```

Each matcher can override the default 60_000 ms timeout by passing `timeout_ms` (minimum 1 second) to `Matcher.new/3`; the sanitized value (floored to 1s) is included as `"timeout"` in the initialize payload and used to bound the hook callback `Task.yield/2`.

```elixir
# Tighten the pre-tool hook budget to 1.5s while leaving others at the 60s default
Matcher.new("Bash", [&check_bash_command/3], timeout_ms: 1_500)
```

**Supported Hook Events:**
- `pre_tool_use` - Before tool execution (can block)
- `post_tool_use` - After tool execution (can add context)
- `user_prompt_submit` - When user submits prompt (can add context)
- `stop` - When agent finishes (can force continuation)
- `subagent_stop` - When subagent finishes
- `pre_compact` - Before context compaction

**Hook Capabilities:**
- Permission control (allow/deny/ask)
- Context injection for intelligent conversations
- Execution control (stop/continue)
- Pattern-based tool matching with regex
- Multiple hooks per event
- Complete type safety with 102 passing tests
- Error handling with timeouts

See [HOOKS_GUIDE.md](HOOKS_GUIDE.md) for complete documentation, examples, and API reference.

### Working Examples

The SDK includes 5 complete hook examples demonstrating real-world patterns:

```bash
# 1. Basic command blocking with live CLI
mix run examples/hooks/basic_bash_blocking.exs

# 2. Auto-inject context into conversations
mix run examples/hooks/context_injection.exs

# 3. File access policy enforcement (tests hook logic)
mix run examples/hooks/file_policy_enforcement.exs

# 4. Comprehensive audit logging
mix run examples/hooks/logging_and_audit.exs

# 5. Complete workflow (all hooks together, per-matcher timeouts, live CLI)
mix run examples/hooks/complete_workflow.exs
```

**Example Output:**
- Shows hooks intercepting real tool usage
- Demonstrates security policies in action
- Displays audit logs and context injection
- All examples include clear explanations

---

## MCP Tool System (v0.4.0+)

> **⚠️ Important:** SDK MCP servers require Claude Code CLI support (not yet available as of CLI v2.0.22). Our infrastructure is complete and will work automatically when CLI adds support. Use external MCP servers for now.

Create in-process MCP tools without subprocess overhead using the `deftool` macro.

```elixir
defmodule MyTools do
  use ClaudeAgentSDK.Tool

  deftool :calculator,
          "Performs calculations",
          %{
            type: "object",
            properties: %{
              expression: %{type: "string"}
            },
            required: ["expression"]
          } do
    def execute(%{"expression" => expr}) do
      # Evaluate and return result
      result = eval_math(expr)
      {:ok, %{"content" => [%{"type" => "text", "text" => "Result: #{result}"}]}}
    end

    defp eval_math(expr), do: # ... implementation
  end
end

# Create SDK MCP server
server = ClaudeAgentSDK.create_sdk_mcp_server(
  name: "my-tools",
  version: "1.0.0",
  tools: [MyTools.Calculator]
)

# Use in options
options = Options.new(
  mcp_config: %{"my-tools" => server}
)
```

**Key benefits:**
- Tools run in the same process (no subprocess overhead)
- Easier debugging and testing
- Direct function calls
- Full Elixir ecosystem access

**Example:**
```bash
mix run examples/advanced_features/mcp_calculator_tool.exs
```

---

## Agent Definitions (v0.4.0+)

Define multiple agent profiles and switch between them at runtime.

```elixir
alias ClaudeAgentSDK.{Agent, Options, Client}

# Define agents
code_agent = Agent.new(
  name: :coder,
  description: "Expert programmer",
  prompt: "You are an expert programmer...",
  allowed_tools: ["Read", "Write", "Bash"],
  model: "claude-sonnet-4"
)

research_agent = Agent.new(
  name: :researcher,
  description: "Research specialist",
  prompt: "You excel at research...",
  allowed_tools: ["WebSearch", "WebFetch"],
  model: "claude-opus-4"
)

# Configure options with multiple agents
options = Options.new(
  agents: %{
    coder: code_agent,
    researcher: research_agent
  },
  agent: :coder  # Start with coder
)

{:ok, client} = Client.start_link(options)

# Switch agents at runtime
Client.set_agent(client, :researcher)

# Check current agent
{:ok, current} = Client.get_agent(client)  # => {:ok, :researcher}

# List available agents
{:ok, agents} = Client.get_available_agents(client)  # => {:ok, [:coder, :researcher]}
```

**Key benefits:**
- Specialized behavior for different tasks
- Runtime agent switching
- Context preservation
- Per-agent tool and model configuration

**Example:**
```bash
mix run examples/advanced_features/agent_switching.exs
```

---

## Permission System (v0.4.0+)

Control tool execution with fine-grained permission callbacks.

```elixir
alias ClaudeAgentSDK.{Options, Permission}
alias ClaudeAgentSDK.Permission.{Context, Result}

# Define permission callback
permission_callback = fn context ->
  case {context.tool_name, context.tool_input} do
    {"Bash", %{"command" => cmd}} ->
      if String.contains?(cmd, "rm -rf") do
        Result.deny("Dangerous command blocked")
      else
        Result.allow()
      end

    {"Write", %{"file_path" => path}} ->
      if String.starts_with?(path, "/etc/") do
        # Redirect to safe location
        safe_path = "/tmp/" <> Path.basename(path)
        Result.allow(updated_input: %{context.tool_input | "file_path" => safe_path})
      else
        Result.allow()
      end

    _ ->
      Result.allow()
  end
end

# Use in options
options = Options.new(
  permission_mode: :default,
  can_use_tool: permission_callback
)

{:ok, client} = Client.start_link(options)

# Change mode at runtime
Client.set_permission_mode(client, :plan)  # Require user approval
Client.set_permission_mode(client, :accept_edits)  # Auto-allow edits
Client.set_permission_mode(client, :bypass_permissions)  # Allow all
```

**Permission modes:**
- `:default` - All tools checked by callback
- `:accept_edits` - Edit operations auto-allowed
- `:plan` - User approval required
- `:bypass_permissions` - All tools allowed

**Example:**
```bash
mix run examples/advanced_features/permission_control.exs
```

---

## Control Protocol (v0.3.0+)

The Control Protocol enables bidirectional communication between the Elixir SDK and Claude Code CLI for advanced features like hooks:

**Protocol Messages:**
- `control_request` - CLI requesting hook callback execution
- `control_response` - Responses to control requests (success/error)
- `initialize` - Setup with hooks configuration
- `hook_callback` - Runtime hook invocation with context

**Implemented in:**
- `ClaudeAgentSDK.ControlProtocol.Protocol` - Message encoding/decoding
- `ClaudeAgentSDK.Client` - Protocol handler and message router
- `ClaudeAgentSDK.Hooks.Registry` - Callback ID management

The protocol runs over the same stdin/stdout channel as regular messages, using JSON with type discrimination to route messages appropriately.

## Concurrent Orchestration (v0.1.0+)

Execute multiple queries in parallel for 3-5x speedup:

```elixir
alias ClaudeAgentSDK.Orchestrator

# Parallel execution
queries = [
  {"Analyze file1.ex", analysis_opts},
  {"Analyze file2.ex", analysis_opts},
  {"Analyze file3.ex", analysis_opts}
]

{:ok, results} = Orchestrator.query_parallel(queries, max_concurrent: 3)

Enum.each(results, fn result ->
  IO.puts("Prompt: #{result.prompt}")
  IO.puts("Success: #{result.success}")
  IO.puts("Cost: $#{result.cost}")
  IO.puts("Duration: #{result.duration_ms}ms")
end)

# Pipeline workflows (output → next input)
{:ok, final_result} = Orchestrator.query_pipeline([
  {"Analyze code quality", analysis_opts},
  {"Suggest refactorings", refactor_opts},
  {"Generate tests for refactored code", test_opts}
], use_context: true)

# Retry with exponential backoff
{:ok, result} = Orchestrator.query_with_retry(
  prompt,
  options,
  max_retries: 3,
  backoff_ms: 1000
)
```

## Session Persistence (v0.2.0+)

Save and resume Claude conversations across application restarts:

```elixir
alias ClaudeAgentSDK.{SessionStore, Session}

# Start the session store
{:ok, _pid} = SessionStore.start_link()

# Execute a query
messages = ClaudeAgentSDK.query("Build a user authentication system")
|> Enum.to_list()

# Save the session with tags
session_id = Session.extract_session_id(messages)

:ok = SessionStore.save_session(session_id, messages,
  tags: ["feature-dev", "auth", "important"],
  description: "Building user authentication"
)

# Later... load and resume
{:ok, session_data} = SessionStore.load_session(session_id)
# session_data.messages - Full conversation history
# session_data.metadata - Tags, cost, timestamps

# Resume the conversation
ClaudeAgentSDK.resume(session_id, "Now add password reset functionality")

# Search sessions
security_sessions = SessionStore.search(tags: ["auth", "security"])
expensive_sessions = SessionStore.search(min_cost: 0.10)
recent_sessions = SessionStore.search(after: ~D[2025-10-01])

# Session forking - experiment with different approaches
fork_options = %Options{
  fork_session: true  # Creates new session ID, preserves context
}

ClaudeAgentSDK.resume(session_id, "Try a different approach", fork_options)
```

## Error Handling

```elixir
ClaudeAgentSDK.query("prompt")
|> Enum.each(fn msg ->
  case msg do
    %{type: :result, subtype: :success} ->
      IO.puts("✅ Success!")
      
    %{type: :result, subtype: error_type} when error_type in [:error_max_turns, :error_during_execution] ->
      IO.puts("❌ Error: #{error_type}")
      
    _ -> 
      # Process other message types
  end
end)
```

## Architecture

The SDK works by:
1. Spawning the Claude CLI as a subprocess using `erlexec`
2. Communicating via JSON messages over stdout/stderr  
3. Parsing responses into Elixir structs
4. Returning lazy Streams for efficient processing

Key benefits:
- ✅ Uses existing CLI authentication
- ✅ Efficient streaming processing
- ✅ No external JSON dependencies
- ✅ Robust subprocess management with erlexec

## Troubleshooting

**Module not available error**: Run with `mix run` instead of plain `elixir`:
```bash
# ❌ Won't work
elixir final_test.exs

# ✅ Works
mix run final_test.exs
```

**Authentication errors**: Make sure Claude CLI is authenticated:
```bash
claude login
```

**Process errors**: Ensure Claude CLI is installed:
```bash
npm install -g @anthropic-ai/claude-code
```

**Slow initialize responses (MCP/server startup)**: Increase the initialize wait by setting `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT` (milliseconds). The value is converted to seconds with a 60-second floor and is useful when the CLI needs extra time to bring up MCP servers or slow environments.

**CLI argument format errors**: Recent improvements have fixed common CLI format issues:
- Output format: Now correctly uses `stream-json` instead of `stream_json`
- Permission modes: Now correctly uses `acceptEdits` instead of `accept_edits`
- These fixes ensure compatibility with the latest Claude CLI versions

**Live mode not working**: Make sure you're using `mix run.live` for live API calls:
```bash
# ❌ Won't make live API calls
mix run examples/basic_example.exs

# ✅ Makes live API calls
mix run.live examples/basic_example.exs
```

### Debug Mode

Use `DebugMode` for detailed troubleshooting:

```elixir
alias ClaudeAgentSDK.DebugMode

# Run full diagnostics
DebugMode.run_diagnostics()

# Debug a specific query with timing
messages = DebugMode.debug_query("Hello")

# Benchmark performance
results = DebugMode.benchmark("Test query", nil, 3)
# Returns timing and cost statistics

# Analyze message statistics
stats = DebugMode.analyze_messages(messages)
```

## Developer Tools

The SDK includes four powerful modules to enhance your development experience:

### 🔧 OptionBuilder - Smart Configuration
Pre-configured option sets for common use cases:
- `build_development_options()` - Permissive settings for dev work
- `build_production_options()` - Secure settings for production  
- `build_analysis_options()` - Read-only tools for code analysis
- `build_chat_options()` - Simple conversation settings
- `for_environment()` - Auto-detects based on Mix.env()
- `merge/2` - Combine presets with custom options

### 🔍 AuthChecker - Environment Validation  
Prevents authentication errors with proactive checking:
- `authenticated?/0` - Quick boolean check
- `diagnose/0` - Full diagnostic with recommendations
- `ensure_ready!/0` - Raises if not ready for queries
- Helpful error messages and setup instructions

### 📜 ContentExtractor - Message Processing
Simplifies extracting text from complex message formats:
- `extract_text/1` - Get text from any message type
- `has_text?/1` - Check if message contains text content
- Handles strings, arrays, tool responses gracefully
- No more manual message parsing

### 🐛 DebugMode - Troubleshooting Tools
Comprehensive debugging and performance analysis:
- `debug_query/2` - Execute queries with detailed logging
- `run_diagnostics/0` - Full environment health check
- `benchmark/3` - Performance testing with statistics
- `analyze_messages/1` - Extract insights from message streams

## Main Use Cases

### 🔍 Code Analysis & Review
```elixir
# Analyze code quality and security with smart configuration
alias ClaudeAgentSDK.{OptionBuilder, ContentExtractor}

# Use analysis-specific options (read-only tools)
options = OptionBuilder.build_analysis_options()

analysis_result = ClaudeAgentSDK.query("""
Review this code for security vulnerabilities and performance issues:
#{File.read!("lib/user_auth.ex")}
""", options)
|> Stream.filter(&(&1.type == :assistant))
|> Stream.map(&ContentExtractor.extract_text/1)
|> Enum.join("\n")

IO.puts("📊 Analysis Result:\n#{analysis_result}")
```

### 📚 Documentation Generation **(FUTURE/PLANNED)**
```elixir
# Generate API documentation - FUTURE/PLANNED
ClaudeAgentSDK.query("Generate comprehensive docs for this module: #{file_content}")
|> Enum.filter(&(&1.type == :assistant))
|> Enum.map(&extract_content/1)  # extract_content helper not yet implemented
```

### 🧪 Test Generation **(FUTURE/PLANNED)**
```elixir
# Create test suites automatically - FUTURE/PLANNED
options = %ClaudeAgentSDK.Options{max_turns: 5}
ClaudeAgentSDK.query("Generate ExUnit tests for this module", options)
```

### 🔄 Code Refactoring **(FUTURE/PLANNED)**
```elixir
# Multi-step refactoring with session management - FUTURE/PLANNED
session_id = start_refactoring_session("lib/legacy_code.ex")  # Not yet implemented
ClaudeAgentSDK.resume(session_id, "Now optimize for performance")
ClaudeAgentSDK.resume(session_id, "Add proper error handling")
```

### 🤖 Interactive Development Assistant **(FUTURE/PLANNED)**
```elixir
# Pair programming sessions - FUTURE/PLANNED
ClaudeAgentSDK.query("I'm working on a GenServer. Help me implement proper state management")
|> Stream.each(&IO.puts(extract_content(&1)))  # extract_content helper not yet implemented
|> Stream.run()
```

### 🏗️ Project Scaffolding **(FUTURE/PLANNED)**
```elixir
# Generate boilerplate code - FUTURE/PLANNED  
ClaudeAgentSDK.query("""
Create a Phoenix LiveView component for user authentication with:
- Login/logout functionality  
- Session management
- Form validation
""")
```

## Testing and Development

### Environment Configuration

The SDK supports different configurations for different environments:

- **Test Environment**: Mocks enabled by default (`config/test.exs`)
- **Development Environment**: Real API calls (`config/dev.exs`)
- **Production Environment**: Real API calls (`config/prod.exs`)

### Writing Tests with Mocks

```elixir
defmodule MyAppTest do
  use ExUnit.Case
  alias ClaudeAgentSDK.Mock

  setup do
    # Clear any existing mock responses
    Mock.clear_responses()
    :ok
  end

  test "my feature works correctly" do
    # Set up mock response
    Mock.set_response("analyze", [
      %{
        "type" => "assistant",
        "message" => %{"content" => "Analysis complete: No issues found."}
      }
    ])
    
    # Your code that uses ClaudeAgentSDK
    result = MyApp.analyze_code("def hello, do: :world")
    
    # Assertions
    assert result == "Analysis complete: No issues found."
  end
end
```

## 📖 Comprehensive Documentation

For detailed documentation covering all features, advanced patterns, and integration examples, see:

**[📋 COMPREHENSIVE_MANUAL.md](COMPREHENSIVE_MANUAL.md)**

The comprehensive manual includes:
- 🏗️ **Architecture Deep Dive** - Internal workings and design patterns ✅ **IMPLEMENTED**
- ⚙️ **Advanced Configuration** - MCP support, security, performance tuning **(FUTURE/PLANNED)**
- 🔧 **Integration Patterns** - Phoenix LiveView, OTP applications, task pipelines **(FUTURE/PLANNED)**
- 🛡️ **Security & Best Practices** - Input validation, permission management **(FUTURE/PLANNED)**
- 🐛 **Troubleshooting Guide** - Common issues and debugging techniques **(FUTURE/PLANNED)**
- 💡 **Real-World Examples** - Code analysis, test generation, refactoring tools **(FUTURE/PLANNED)**

## License

MIT License
