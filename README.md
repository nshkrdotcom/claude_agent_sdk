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

An Elixir SDK aiming for feature-complete parity with the official [claude-agent-sdk-python](https://github.com/anthropics/claude-agent-sdk-python). Build AI-powered applications with Claude using a production-ready interface for the [Claude Code CLI](https://code.claude.com/docs/en/cli-reference), featuring streaming responses, lifecycle hooks, permission controls, and in-process tool execution via MCP.

> **Note:** This SDK does not bundle the Claude Code CLI. You must install it separately (see [Prerequisites](#prerequisites)).

---

## What You Can Build

- **AI coding assistants** with real-time streaming output
- **Automated code review** pipelines with custom permission policies
- **Multi-agent workflows** with specialized personas
- **Tool-augmented applications** using the Model Context Protocol (MCP)
- **Interactive chat interfaces** with typewriter-style output

---

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:claude_agent_sdk, "~> 0.14.0"}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

### Prerequisites

Install the Claude Code CLI (requires Node.js):

```bash
npm install -g @anthropic-ai/claude-code
```

Verify installation:

```bash
claude --version
```

---

## Quick Start

### 1. Authenticate

Choose one method:

```bash
# Option A: Environment variable (recommended for CI/CD)
export ANTHROPIC_API_KEY="sk-ant-api03-..."

# Option B: OAuth token
export CLAUDE_AGENT_OAUTH_TOKEN="sk-ant-oat01-..."

# Option C: Interactive login
claude login
```

### 2. Run Your First Query

```elixir
alias ClaudeAgentSDK.{ContentExtractor, Options}

# Simple query with streaming collection
ClaudeAgentSDK.query("Write a function that calculates factorial in Elixir")
|> Enum.each(fn msg ->
  case msg.type do
    :assistant -> IO.puts(ContentExtractor.extract_text(msg) || "")
    :result -> IO.puts("Done! Cost: $#{msg.data.total_cost_usd}")
    _ -> :ok
  end
end)
```

### 3. Real-Time Streaming

```elixir
alias ClaudeAgentSDK.Streaming

{:ok, session} = Streaming.start_session()

Streaming.send_message(session, "Explain GenServers in one paragraph")
|> Stream.each(fn
  %{type: :text_delta, text: chunk} -> IO.write(chunk)
  %{type: :message_stop} -> IO.puts("")
  _ -> :ok
end)
|> Stream.run()

Streaming.close_session(session)
```

If session initialization or message send fails, the stream now emits an immediate
`%{type: :error, error: reason}` event instead of waiting for the 5-minute stream timeout.

---

## Authentication

The SDK supports three authentication methods, checked in this order:

| Method | Environment Variable | Best For |
|--------|---------------------|----------|
| OAuth Token | `CLAUDE_AGENT_OAUTH_TOKEN` | Production / CI |
| API Key | `ANTHROPIC_API_KEY` | Development |
| CLI Login | (uses `claude login` session) | Local development |

### Cloud Providers

**AWS Bedrock:**
```bash
export CLAUDE_AGENT_USE_BEDROCK=1
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_REGION=us-west-2
```

**Google Vertex AI:**
```bash
export CLAUDE_AGENT_USE_VERTEX=1
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json
export GOOGLE_CLOUD_PROJECT=your-project-id
```

### Token Setup (Local Development)

For persistent authentication without re-login:

```bash
mix claude.setup_token
```

`AuthManager` keeps running if token storage save/clear fails and returns `{:error, reason}`.
Handle `clear_auth/0` accordingly in your app code:

```elixir
case ClaudeAgentSDK.AuthManager.clear_auth() do
  :ok -> :ok
  {:error, reason} -> IO.puts("Failed to clear auth: #{inspect(reason)}")
end
```

Check authentication status:

```elixir
alias ClaudeAgentSDK.AuthChecker
diagnosis = AuthChecker.diagnose()
# => %{authenticated: true, auth_method: "Anthropic API", ...}
```

---

## Core Concepts

### Choosing the Right API

| API | Use Case | When to Use |
|-----|----------|-------------|
| `query/2` | Simple queries | Batch processing, scripts |
| `Streaming` | Typewriter UX | Chat interfaces, real-time output |
| `Client` | Full control | Multi-turn agents, tools, hooks |

### Query API

The simplest way to interact with Claude:

```elixir
# Basic query
messages = ClaudeAgentSDK.query("What is recursion?") |> Enum.to_list()

# With options
opts = %ClaudeAgentSDK.Options{
  model: "sonnet",
  max_turns: 5,
  output_format: :stream_json
}
messages = ClaudeAgentSDK.query("Explain OTP", opts) |> Enum.to_list()

# Streamed input prompts (unidirectional)
prompts = [
  %{"type" => "user", "message" => %{"role" => "user", "content" => "Hello"}},
  %{"type" => "user", "message" => %{"role" => "user", "content" => "How are you?"}}
]

ClaudeAgentSDK.query(prompts, opts) |> Enum.to_list()

# Custom transport injection
ClaudeAgentSDK.query("Hello", opts, {ClaudeAgentSDK.Transport.Erlexec, []})
|> Enum.to_list()

# Lazy transport startup (defer subprocess spawn to handle_continue)
ClaudeAgentSDK.query(
  "Hello",
  opts,
  {ClaudeAgentSDK.Transport.Erlexec, [startup_mode: :lazy]}
)
|> Enum.to_list()

# Continue a conversation
ClaudeAgentSDK.continue("Can you give an example?") |> Enum.to_list()

# Resume a specific session
ClaudeAgentSDK.resume("session-id", "What about supervision trees?") |> Enum.to_list()
```

### Streaming API

For real-time, character-by-character output:

```elixir
alias ClaudeAgentSDK.{Options, Streaming}

{:ok, session} = Streaming.start_session(%Options{model: "haiku"})

# Send messages and stream responses
Streaming.send_message(session, "Write a haiku about Elixir")
|> Enum.each(fn
  %{type: :text_delta, text: t} -> IO.write(t)
  %{type: :tool_use_start, name: n} -> IO.puts("\nUsing tool: #{n}")
  %{type: :message_stop} -> IO.puts("\n---")
  _ -> :ok
end)

# Multi-turn conversation (context preserved)
Streaming.send_message(session, "Now write one about Phoenix")
|> Enum.to_list()

Streaming.close_session(session)
```

**Subagent Streaming:** When Claude spawns subagents via the Task tool, events include a `parent_tool_use_id` field to identify the source. Main agent events have `nil`, subagent events have the Task tool call ID. Streaming events also include `uuid`, `session_id`, and `raw_event` metadata for parity with the Python SDK. Stream event wrappers require `uuid` and `session_id` (missing keys raise). See the [Streaming Guide](guides/streaming.md#subagent-events-parent_tool_use_id) for details.

### Hooks System

Intercept and control agent behavior at key lifecycle points:

```elixir
alias ClaudeAgentSDK.{Client, Options}
alias ClaudeAgentSDK.Hooks.{Matcher, Output}

# Block dangerous commands
check_bash = fn input, _id, _ctx ->
  case input do
    %{"tool_name" => "Bash", "tool_input" => %{"command" => cmd}} ->
      if String.contains?(cmd, "rm -rf") do
        Output.deny("Dangerous command blocked")
      else
        Output.allow()
      end
    _ -> %{}
  end
end

opts = %Options{
  hooks: %{
    pre_tool_use: [Matcher.new("Bash", [check_bash])]
  }
}

{:ok, client} = Client.start_link(opts)
```

**Available Hook Events (all 12 Python SDK events supported):**
- `pre_tool_use` / `post_tool_use` / `post_tool_use_failure` - Tool execution lifecycle
- `user_prompt_submit` - Before sending user messages
- `stop` / `subagent_stop` / `subagent_start` - Agent lifecycle
- `notification` - CLI notifications
- `permission_request` - Permission dialog interception
- `session_start` / `session_end` - Session lifecycle
- `pre_compact` - Before context compaction

See the [Hooks Guide](guides/hooks.md) for comprehensive documentation.

### Supervision

Hook and permission callbacks run in async tasks. For production, add the SDK
task supervisor so callback processes are supervised:

```elixir
children = [
  ClaudeAgentSDK.TaskSupervisor,
  {ClaudeAgentSDK.Client, options}
]
```

If you use a custom supervisor name, configure the SDK to match:

```elixir
children = [
  {ClaudeAgentSDK.TaskSupervisor, name: MyApp.ClaudeTaskSupervisor}
]

config :claude_agent_sdk, task_supervisor: MyApp.ClaudeTaskSupervisor
```

If an explicitly configured supervisor is missing at runtime, the SDK logs a warning and
falls back to `Task.start/1`. With default settings, missing
`ClaudeAgentSDK.TaskSupervisor` falls back silently for backward compatibility.
For stricter behavior in dev/test:

```elixir
config :claude_agent_sdk, task_supervisor_strict: true
```

In strict mode, `ClaudeAgentSDK.TaskSupervisor.start_child/2` returns
`{:error, {:task_supervisor_unavailable, supervisor}}` instead of spawning
an unsupervised fallback task.

### Permission System

Fine-grained control over tool execution:

```elixir
alias ClaudeAgentSDK.{Options, Permission.Result}

permission_callback = fn ctx ->
  case ctx.tool_name do
    "Write" ->
      # Redirect system file writes to safe location
      if String.starts_with?(ctx.tool_input["file_path"], "/etc/") do
        safe_path = "/tmp/sandbox/" <> Path.basename(ctx.tool_input["file_path"])
        Result.allow(updated_input: %{ctx.tool_input | "file_path" => safe_path})
      else
        Result.allow()
      end
    _ ->
      Result.allow()
  end
end

opts = %Options{
  can_use_tool: permission_callback,
  permission_mode: :default  # :default | :accept_edits | :plan | :bypass_permissions | :delegate | :dont_ask
}
```

Note: `can_use_tool` is mutually exclusive with `permission_prompt_tool`. The SDK routes `can_use_tool` through the control client (including string prompts), auto-enables `include_partial_messages`, and sets `permission_prompt_tool` to `\"stdio\"` internally so the CLI can emit permission callbacks. Use `:default` or `:plan` for built-in tool permissions; `:delegate` is intended for external tool execution. Hook-based fallback only applies in non-`:delegate` modes and ignores `updated_permissions`. If you do not see callbacks, your CLI build may not emit control callbacks (see `examples/advanced_features/permissions_live.exs`).

Stream a single client response until the final result:

```elixir
Client.receive_response_stream(client)
|> Enum.to_list()
```

### MCP Tools (In-Process)

Define custom tools that Claude can call directly in your application:

```elixir
defmodule MyTools do
  use ClaudeAgentSDK.Tool

  deftool :calculate, "Perform a calculation", %{
    type: "object",
    properties: %{
      expression: %{type: "string", description: "Math expression to evaluate"}
    },
    required: ["expression"]
  } do
    def execute(%{"expression" => expr}) do
      # Your logic here
      result = eval_expression(expr)
      {:ok, %{"content" => [%{"type" => "text", "text" => "Result: #{result}"}]}}
    end
  end
end

# Create an MCP server with your tools
server = ClaudeAgentSDK.create_sdk_mcp_server(
  name: "calculator",
  version: "1.0.0",
  tools: [MyTools.Calculate]
)

# Optional: start tool registry under your DynamicSupervisor
{:ok, sup} = DynamicSupervisor.start_link(strategy: :one_for_one)

server = ClaudeAgentSDK.create_sdk_mcp_server(
  name: "calculator",
  version: "1.0.0",
  tools: [MyTools.Calculate],
  supervisor: sup
)

opts = %ClaudeAgentSDK.Options{
  mcp_servers: %{"calc" => server},
  allowed_tools: ["mcp__calc__calculate"]
}
```

Note: MCP server routing only supports `initialize`, `tools/list`, `tools/call`, and `notifications/initialized`. Calls to `resources/list` or `prompts/list` return JSON-RPC method-not-found errors to match the Python SDK.
If `version` is omitted, it defaults to `"1.0.0"`.

---

## Configuration Options

Key options for `ClaudeAgentSDK.Options`:

| Option | Type | Description |
|--------|------|-------------|
| `model` | string | `"sonnet"`, `"opus"`, `"haiku"` |
| `max_turns` | integer | Maximum conversation turns |
| `system_prompt` | string | Custom system instructions |
| `output_format` | atom/map | `:text`, `:json`, `:stream_json`, or JSON schema (SDK enforces stream-json for transport; JSON schema still passed) |
| `allowed_tools` | list | Tools Claude can use |
| `permission_mode` | atom | `:default`, `:accept_edits`, `:plan`, `:bypass_permissions`, `:delegate`, `:dont_ask` |
| `hooks` | map | Lifecycle hook callbacks |
| `mcp_servers` | map or string | MCP server configurations (or JSON/path alias for `mcp_config`) |
| `cwd` | string | Working directory for file operations |
| `timeout_ms` | integer | Command timeout (default: 75 minutes) |
| `max_buffer_size` | integer | Maximum JSON buffer size (default: 1MB, overflow yields `CLIJSONDecodeError`) |

CLI path override: set `path_to_claude_code_executable` or `executable` in `Options` (Python `cli_path` equivalent).

### Runtime Application Config

All tunable constants (timeouts, buffer sizes, auth paths, CLI flags, env var
names, concurrency limits) are centralized in `Config.*` sub-modules and can
be overridden per-environment:

```elixir
# config/config.exs
config :claude_agent_sdk, ClaudeAgentSDK.Config.Timeouts,
  query_total_ms: 5_400_000,           # total query timeout (default: 75 min)
  tool_execution_ms: 60_000            # per-tool timeout (default: 30 s)

config :claude_agent_sdk, ClaudeAgentSDK.Config.Buffers,
  max_stdout_buffer_bytes: 2_097_152   # stdout buffer (default: 1 MB)

config :claude_agent_sdk, ClaudeAgentSDK.Config.Orchestration,
  max_concurrent: 10,                  # parallel query limit (default: 5)
  max_retries: 5                       # retry attempts (default: 3)

# Legacy flat keys still work:
config :claude_agent_sdk,
  cli_stream_module: ClaudeAgentSDK.Query.CLIStream,
  task_supervisor_strict: false
```

See the [Configuration Internals](guides/configuration-internals.md) guide for
the complete reference of every tunable, its default, and override examples.

`config :claude_agent_sdk, :process_module` is still read as a fallback for query streaming,
but it is deprecated and logs a warning once per legacy module.

`SessionStore` now hydrates on-disk cache in a `handle_continue/2` step. Startup is faster,
but `list/search` can be briefly incomplete immediately after boot while warmup finishes.

`Transport.Erlexec` and `Streaming.Session` support `startup_mode: :lazy`
to defer subprocess startup to `handle_continue/2`. In lazy mode, `start_link` can succeed
before the subprocess is spawned; startup failures then surface as process exit after init.

Query-side transport errors normalize equivalent reasons to stable atoms where possible:
`{:command_not_found, "claude"}` is treated as `:cli_not_found`.

### SDK Logging

The SDK uses its own log level filter (default: `:warning`) to keep output quiet in dev. Configure via application env:

```elixir
config :claude_agent_sdk, log_level: :warning  # :debug | :info | :warning | :error | :off
```

### Option Presets

```elixir
alias ClaudeAgentSDK.OptionBuilder

# Environment-based presets
OptionBuilder.build_development_options()  # Permissive, verbose
OptionBuilder.build_production_options()   # Restrictive, safe
OptionBuilder.for_environment()            # Auto-detect from Mix.env()

# Use-case presets
OptionBuilder.build_analysis_options()     # Read-only code analysis
OptionBuilder.build_chat_options()         # Simple chat, no tools
OptionBuilder.quick()                      # Fast one-off queries
```

---

## Examples

The `examples/` directory contains runnable demonstrations.

### Mix Task Example (Start Here)

If you want to integrate Claude into your own Mix project, see the **[mix_task_chat](examples/mix_task_chat/README.md)** example — a complete working app with Mix tasks:

```bash
cd examples/mix_task_chat
mix deps.get
mix chat "Hello, Claude!"           # Streaming response
mix chat --interactive              # Multi-turn conversation
mix ask -q "What is 2+2?"           # Script-friendly output
```

### Script Examples

```bash
# Run all examples
bash examples/run_all.sh

# Run a specific example
mix run examples/basic_example.exs
mix run examples/streaming_tools/quick_demo.exs
mix run examples/hooks/basic_bash_blocking.exs
```

**Key Examples:**
- [`mix_task_chat/`](examples/mix_task_chat/README.md) - **Full Mix task integration** (streaming + interactive chat)
- `basic_example.exs` - Minimal SDK usage
- `streaming_tools/quick_demo.exs` - Real-time streaming
- `hooks/complete_workflow.exs` - Full hooks integration
- `sdk_mcp_tools_live.exs` - Custom MCP tools
- `advanced_features/agents_live.exs` - Multi-agent workflows
- `advanced_features/subagent_spawning_live.exs` - Parallel subagent coordination
- `advanced_features/web_tools_live.exs` - WebSearch and WebFetch

### Full Application Examples

Complete Mix applications demonstrating production-ready SDK integration patterns:

| Example | Description | Key Features |
|---------|-------------|--------------|
| [`phoenix_chat/`](examples/phoenix_chat/README.md) | Real-time chat with Phoenix LiveView | LiveView, Channels, streaming responses, session management |
| [`document_generation/`](examples/document_generation/README.md) | AI-powered Excel document generation | elixlsx, natural language parsing, Mix tasks |
| [`research_agent/`](examples/research_agent/README.md) | Multi-agent research coordination | Task tool, subagent tracking via hooks, parallel execution |
| [`skill_invocation/`](examples/skill_invocation/README.md) | Skill tool usage and tracking | Skill definitions, hook-based tracking, GenServer state |
| [`email_agent/`](examples/email_agent/README.md) | AI-powered email assistant | SQLite storage, rule-based processing, natural language queries |

```bash
# Run Phoenix Chat
cd examples/phoenix_chat && mix deps.get && mix phx.server
# Visit http://localhost:4000

# Run Document Generation
cd examples/document_generation && mix deps.get && mix generate.demo

# Run Research Agent
cd examples/research_agent && mix deps.get && mix research "quantum computing"

# Run Skill Invocation demo
cd examples/skill_invocation && mix deps.get && mix run -e "SkillInvocation.demo()"

# Run Email Agent
cd examples/email_agent && mix deps.get && mix email.assistant "find emails from last week"
```

---

## Guides

| Guide | Description |
|-------|-------------|
| [Getting Started](guides/getting-started.md) | Installation, authentication, and first query |
| [Streaming](guides/streaming.md) | Real-time streaming and typewriter effects |
| [Hooks](guides/hooks.md) | Lifecycle hooks for tool control |
| [MCP Tools](guides/mcp-tools.md) | In-process tool definitions with MCP |
| [Permissions](guides/permissions.md) | Fine-grained permission controls |
| [Configuration](guides/configuration.md) | Complete options reference |
| [Agents](guides/agents.md) | Custom agent personas |
| [Sessions](guides/sessions.md) | Session management and persistence |
| [Testing](guides/testing.md) | Mock system and testing patterns |
| [Error Handling](guides/error-handling.md) | Error types and recovery |

## Upgrading

For breaking changes and migration notes, see `CHANGELOG.md`.

**0.12.0 breaking changes:**
- `Transport.Port` removed. `Transport.Erlexec` is now the sole built-in transport. Users who explicitly passed `Transport.Port` must switch to `Transport.Erlexec` or omit the transport option.
- `Transport.normalize_reason(:port_closed)` removed. Custom transports should return `:not_connected` directly.
- Transport error tuple shape updated: low-level failures now use `{:error, {:transport, reason}}` instead of bare `{:error, reason}`.
- String prompts now delivered via stdin (`--input-format stream-json`) instead of CLI arg (`-- prompt`).

**0.11.0 breaking changes:**
- `--print` flag removed from all modules. All queries now use `--output-format stream-json` exclusively.
- `--agents` CLI flag removed. Agents are now sent via the `initialize` control request. Use `Options.agents_for_initialize/1`.
- `AgentsFile` module deleted. Remove any `agents_temp_file_max_age_seconds` config.
- `Client` state is now a `defstruct`. Four deprecated fields removed: `current_model`, `pending_model_change`, `current_permission_mode`, `pending_inbound_count`.
- All 12 hook events are now supported (6 new: `post_tool_use_failure`, `notification`, `subagent_start`, `permission_request`, `session_start`, `session_end`).

**0.10.0 fix (resume turn persistence):**
- `resume/3` no longer uses `--print --resume` (one-shot mode that dropped intermediate turns). It now uses `--resume` with `--input-format stream-json`, preserving the full conversation history across resume calls.
- Updated default Opus model to `claude-opus-4-6`.

**0.9.0 breaking change (streaming):**
- Stream event wrappers now require `uuid` and `session_id`. Missing keys raise and terminate the streaming client.
- If you emit or mock `stream_event` wrappers, include both fields (custom transports, fixtures, tests).

**Additional Resources:**
- [CHANGELOG.md](CHANGELOG.md) - Version history and release notes
- [HexDocs](https://hexdocs.pm/claude_agent_sdk/) - API documentation
- [Claude Code SDK](https://docs.anthropic.com/en/docs/claude-code/sdk) - Upstream documentation

---

## License

MIT License - see [LICENSE](LICENSE) for details.

---

<div align="center">
  <sub>Built with Elixir and Claude</sub>
</div>
