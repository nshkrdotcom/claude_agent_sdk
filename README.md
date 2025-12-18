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

`claude_agent_sdk` is an Elixir SDK for programmatically interacting with **Claude Code** via the **Claude Code CLI**. It provides:

- A clean, streaming-first API (`ClaudeAgentSDK.query/2`, `ClaudeAgentSDK.Streaming`)
- A full **bidirectional control client** for advanced features (hooks, permissions, SDK MCP tooling)
- Operational tooling (auth diagnostics, debug mode, orchestration, session persistence)

## Quick links

- HexDocs: https://hexdocs.pm/claude_agent_sdk
- Hex package: https://hex.pm/packages/claude_agent_sdk
- Claude Code SDK docs (upstream): https://docs.anthropic.com/en/docs/claude-code/sdk
- Claude Code hooks (upstream): https://docs.anthropic.com/en/docs/claude-code/hooks

---

## Architecture

The SDK has two “lanes”:

- **CLI-only lane** (fast path): simple queries and pure streaming
- **Control-client lane** (feature path): hooks, permissions, SDK MCP servers, runtime control

```mermaid
flowchart TB
  App[Your Elixir app] --> SDK[ClaudeAgentSDK API]

  SDK -->|"query/continue/resume"| Query[ClaudeAgentSDK.Query]
  SDK -->|"start_session/send_message"| StreamAPI[ClaudeAgentSDK.Streaming]

  Query --> Router["StreamingRouter / feature detection"]
  StreamAPI --> Router

  Router -->|"CLI-only path"| Proc["Process / Streaming.Session"]
  Router -->|"Control path"| Client["Client (GenServer + control protocol)"]

  Client --> Transport["Transport (Port or Erlexec)"]
  Proc --> CLI["Claude Code CLI"]

  Transport --> CLI
  CLI --> Claude["Claude service"]

  Client --> Hooks["Hooks callbacks"]
  Client --> Perms["Permission callback"]
  Client --> MCP["SDK MCP bridge"]
````

---

## Prerequisites

### Install Claude Code CLI

This library shells out to the Claude Code CLI. Install it first:

```bash
npm install -g @anthropic-ai/claude-code
```

### CLI discovery and version checks

The SDK centralizes CLI discovery in `ClaudeAgentSDK.CLI`:

* Candidate executables: `claude-code`, then `claude`
* Minimum supported version: `2.0.0`
* Recommended version: `2.0.72`

You can verify what the SDK sees:

```elixir
{:ok, path} = ClaudeAgentSDK.CLI.find_executable()
{:ok, version} = ClaudeAgentSDK.CLI.version()

ClaudeAgentSDK.CLI.version_supported?()
ClaudeAgentSDK.CLI.warn_if_outdated()
```

---

## Installation

Add the dependency to `mix.exs`:

```elixir
def deps do
  [
    {:claude_agent_sdk, "~> 0.6"}
  ]
end
```

Then:

```bash
mix deps.get
```

---

## Authentication

The SDK supports three approaches (in precedence order):

1. **Environment variable credentials** (best for CI/CD)
2. **Stored OAuth token via AuthManager** (best for local dev without re-login)
3. **Existing `claude login` session** (legacy/manual)

### Recommended for CI/CD: environment variables

Anthropic:

```bash
export CLAUDE_AGENT_OAUTH_TOKEN="sk-ant-oat01-..."
# or legacy:
export ANTHROPIC_API_KEY="sk-ant-api03-..."
```

AWS Bedrock:

```bash
export CLAUDE_AGENT_USE_BEDROCK=1
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_REGION=us-west-2
# or AWS_PROFILE / ~/.aws/credentials
```

Google Vertex AI:

```bash
export CLAUDE_AGENT_USE_VERTEX=1
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json
export GOOGLE_CLOUD_PROJECT=your-project-id
```

### Local dev: one-time OAuth token setup

The SDK includes a Mix task that runs `claude setup-token` and persists the token securely:

```bash
mix claude.setup_token
```

Status and health checks:

```elixir
alias ClaudeAgentSDK.AuthManager

:ok = AuthManager.ensure_authenticated()
status = AuthManager.status()
```

### Diagnostics

If you want a clear, actionable environment report:

```elixir
alias ClaudeAgentSDK.AuthChecker

diagnosis = AuthChecker.diagnose()
AuthChecker.ensure_ready!()
```

---

## Core API

### `ClaudeAgentSDK.query/2`

`query/2` returns a **lazy stream** of `ClaudeAgentSDK.Message` structs.

```elixir
alias ClaudeAgentSDK.{ContentExtractor, Options}

opts = %Options{max_turns: 3, output_format: :stream_json}

ClaudeAgentSDK.query("Say hello from Elixir", opts)
|> Enum.each(fn msg ->
  case msg.type do
    :assistant ->
      IO.puts(ContentExtractor.extract_text(msg) || "")

    :result ->
      IO.inspect(msg.data, label: "result")
      :ok

    _ ->
      :ok
  end
end)
```

### `continue/2` and `resume/3`

```elixir
# Continue the last conversation
ClaudeAgentSDK.continue("Add error handling")
|> Enum.to_list()

# Resume a specific session
ClaudeAgentSDK.resume("session-id", "Now add tests")
|> Enum.to_list()
```

---

## Options: configuring behavior

`ClaudeAgentSDK.Options` maps directly to CLI flags (plus higher-level SDK routing):

Common fields you will likely use:

* `max_turns`
* `system_prompt` / `append_system_prompt`
* `output_format` (`:text | :json | :stream_json | %{type: :json_schema, schema: ...}`)
* `model` / `fallback_model`
* `allowed_tools` / `disallowed_tools`
* `permission_mode`
* `cwd`
* `timeout_ms`
* `include_partial_messages` (streaming)
* `preferred_transport` (`:auto | :cli | :control`)

Example:

```elixir
alias ClaudeAgentSDK.Options

opts = %Options{
  model: "sonnet",
  fallback_model: "haiku",
  max_turns: 5,
  permission_mode: :plan,
  output_format: :stream_json,
  allowed_tools: ["Read", "Grep"],
  cwd: "/path/to/project"
}
```

### Option presets with `OptionBuilder`

If you want sensible defaults per environment / use case:

```elixir
alias ClaudeAgentSDK.OptionBuilder

dev_opts  = OptionBuilder.build_development_options()
prod_opts = OptionBuilder.build_production_options()
analysis  = OptionBuilder.build_analysis_options()
env_opts  = OptionBuilder.for_environment()
```

---

## Streaming (typewriter / incremental UX)

`ClaudeAgentSDK.Streaming` provides persistent sessions and `text_delta` events.

```elixir
alias ClaudeAgentSDK.Streaming

{:ok, session} = Streaming.start_session()

Streaming.send_message(session, "Write a one-sentence summary of OTP.")
|> Stream.each(fn
  %{type: :text_delta, text: chunk} -> IO.write(chunk)
  %{type: :message_stop} -> IO.puts("\n")
  _ -> :ok
end)
|> Stream.run()

:ok = Streaming.close_session(session)
```

### Automatic transport selection

Streaming uses `ClaudeAgentSDK.Transport.StreamingRouter` to select:

* **CLI streaming session** when you do not require control features
* **Control client** when you enable hooks, permissions, SDK MCP servers, or certain runtime agent/permission settings

You can override selection:

```elixir
alias ClaudeAgentSDK.Options

# Force CLI-only
opts = %Options{preferred_transport: :cli}

# Force control client
opts = %Options{preferred_transport: :control}
```

---

## Control-client features

If you need hooks, permission gating, SDK MCP tools, runtime model switching, or bidirectional control protocol support, use `ClaudeAgentSDK.Client`.

### Bidirectional client lifecycle

```elixir
alias ClaudeAgentSDK.{Client, Options}

{:ok, client} = Client.start_link(%Options{model: "sonnet"})
:ok = Client.send_message(client, "Summarize this repository in 3 bullets.")

Client.stream_messages(client)
|> Enum.take_while(&(&1.type != :result))
|> Enum.each(&IO.inspect/1)

:ok = Client.stop(client)
```

---

## Hooks

Hooks are callback functions invoked by the Claude Code CLI during agent execution (tool calls, prompt submission, lifecycle events). They are configured through `Options.hooks` using matchers.

```elixir
alias ClaudeAgentSDK.{Client, Options}
alias ClaudeAgentSDK.Hooks.{Matcher, Output}

defmodule MyHooks do
  def block_dangerous_bash(%{"tool_name" => "Bash", "tool_input" => %{"command" => cmd}}, _id, _ctx) do
    if String.contains?(cmd, "rm -rf") do
      Output.deny("Blocked potentially destructive command")
      |> Output.with_system_message("Command blocked by policy.")
    else
      Output.allow()
    end
  end

  def block_dangerous_bash(_input, _id, _ctx), do: %{}
end

opts = %Options{
  hooks: %{
    pre_tool_use: [
      Matcher.new("Bash", [&MyHooks.block_dangerous_bash/3], timeout_ms: 1_500)
    ]
  }
}

{:ok, client} = Client.start_link(opts)
:ok = Client.send_message(client, "Try running rm -rf /tmp (do not actually do it).")
Client.stream_messages(client) |> Enum.to_list()
Client.stop(client)
```

Supported hook events (see `ClaudeAgentSDK.Hooks`):

* `:session_start`, `:session_end`
* `:notification`
* `:pre_tool_use`, `:post_tool_use`
* `:user_prompt_submit`
* `:stop`, `:subagent_stop`
* `:pre_compact`

---

## Permission system

The permission system allows you to centrally control tool execution with a callback.

* Callback: `t:ClaudeAgentSDK.Permission.callback/0`
* Context: `ClaudeAgentSDK.Permission.Context`
* Result: `ClaudeAgentSDK.Permission.Result`
* Modes: `:default | :accept_edits | :plan | :bypass_permissions`

```elixir
alias ClaudeAgentSDK.{Client, Options}
alias ClaudeAgentSDK.Permission.Result

permission_callback = fn ctx ->
  case {ctx.tool_name, ctx.tool_input} do
    {"Bash", %{"command" => cmd}} when is_binary(cmd) and String.contains?(cmd, "rm -rf") ->
      Result.deny("Command blocked by policy", interrupt: true)

    _ ->
      Result.allow()
  end
end

opts = %Options{
  permission_mode: :default,
  can_use_tool: permission_callback
}

{:ok, client} = Client.start_link(opts)
:ok = Client.send_message(client, "Try a bash command.")
Client.stream_messages(client) |> Enum.to_list()
Client.stop(client)
```

Runtime mode switching is supported:

```elixir
:ok = ClaudeAgentSDK.Client.set_permission_mode(client, :plan)
```

---

## Agents (custom personas)

Agents are first-class structs (`ClaudeAgentSDK.Agent`) you can attach to options and switch at runtime.

```elixir
alias ClaudeAgentSDK.{Agent, Client, Options}

coder =
  Agent.new(
    name: :coder,
    description: "Implementation-focused engineering assistant",
    prompt: "You are a pragmatic senior engineer. Prefer small, safe changes.",
    allowed_tools: ["Read", "Write", "Grep"],
    model: "sonnet"
  )

reviewer =
  Agent.new(
    name: :reviewer,
    description: "Strict code reviewer",
    prompt: "You review code for correctness, safety, and clarity. Be precise.",
    allowed_tools: ["Read", "Grep"],
    model: "sonnet"
  )

opts = %Options{agents: %{coder: coder, reviewer: reviewer}, agent: :reviewer}

{:ok, client} = Client.start_link(opts)
:ok = Client.set_agent(client, :coder)
{:ok, active} = Client.get_agent(client)
Client.stop(client)
```

---

## SDK MCP servers (in-process tools)

The SDK includes a lightweight in-process MCP tool system:

* Define tools via `use ClaudeAgentSDK.Tool` + `deftool`
* Create a server via `ClaudeAgentSDK.create_sdk_mcp_server/1`
* Provide it via `Options.mcp_servers`

> Note: SDK MCP support depends on CLI control-protocol messages; the SDK implements routing and JSON-RPC responses, but availability depends on your Claude Code CLI version and feature set.

```elixir
defmodule MyTools do
  use ClaudeAgentSDK.Tool

  deftool :add, "Add two numbers", %{
    type: "object",
    properties: %{
      a: %{type: "number"},
      b: %{type: "number"}
    },
    required: ["a", "b"]
  } do
    def execute(%{"a" => a, "b" => b}) do
      {:ok, %{"content" => [%{"type" => "text", "text" => "#{a + b}"}]}}
    end
  end
end

server =
  ClaudeAgentSDK.create_sdk_mcp_server(
    name: "calculator",
    version: "1.0.0",
    tools: [MyTools.Add]
  )

opts = %ClaudeAgentSDK.Options{
  mcp_servers: %{"calculator" => server}
}
```

---

## Orchestration (parallelism, pipelines, retry)

For application-level workflows:

```elixir
alias ClaudeAgentSDK.Orchestrator

queries = [
  {"Analyze module A", %ClaudeAgentSDK.Options{max_turns: 3}},
  {"Analyze module B", %ClaudeAgentSDK.Options{max_turns: 3}}
]

{:ok, results} = Orchestrator.query_parallel(queries, max_concurrent: 2)

{:ok, final} =
  Orchestrator.query_pipeline(
    [
      {"Summarize this code", %ClaudeAgentSDK.Options{}},
      {"Suggest refactors", %ClaudeAgentSDK.Options{}}
    ],
    use_context: true
  )

{:ok, messages} =
  Orchestrator.query_with_retry(
    "Do a quick review",
    %ClaudeAgentSDK.Options{},
    max_retries: 3,
    backoff_ms: 1_000
  )
```

---

## Session persistence

`ClaudeAgentSDK.SessionStore` persists message histories and metadata.

```elixir
alias ClaudeAgentSDK.{Session, SessionStore}

{:ok, _} = SessionStore.start_link()

messages = ClaudeAgentSDK.query("Draft an implementation plan") |> Enum.to_list()
session_id = Session.extract_session_id(messages)

:ok =
  SessionStore.save_session(session_id, messages,
    tags: ["planning", "important"],
    description: "Implementation plan draft"
  )

{:ok, session_data} = SessionStore.load_session(session_id)
sessions = SessionStore.search(tags: ["important"])
```

---

## Debugging and diagnostics

### DebugMode

```elixir
alias ClaudeAgentSDK.DebugMode

DebugMode.run_diagnostics()
messages = DebugMode.debug_query("Explain supervision trees")
stats = DebugMode.analyze_messages(messages)
bench = DebugMode.benchmark("hello", nil, 3)
```

### Content extraction helper

```elixir
alias ClaudeAgentSDK.ContentExtractor

text =
  ClaudeAgentSDK.query("Write a haiku about BEAM")
  |> Stream.filter(&ContentExtractor.has_text?/1)
  |> Stream.map(&ContentExtractor.extract_text/1)
  |> Enum.join("\n")
```

---

## Mix tasks (included)

This repository ships operational Mix tasks you can run directly:

* `mix claude.setup_token`
  Interactive OAuth token acquisition + persistence (uses `claude setup-token`)

* `mix showcase [--live]`
  Run a comprehensive feature demo in mock mode (default) or live mode

* `mix run.live path/to/script.exs [args...]`
  Runs scripts with mocking disabled (live API calls)

* `mix test.live [mix test args...]`
  Runs tests with mocking disabled; defaults to `--only live` unless overridden

---

## Security and operational guidance

* Prefer `permission_mode: :plan` or explicit `allowed_tools` in production workloads.
* Treat tokens as secrets; the default token store writes `~/.claude_sdk/token.json` with user-only permissions.
* Use hooks and/or the permission callback to centrally enforce policy (file access rules, command allow-lists, audit logging).
* When running live in CI, use environment variables and avoid interactive flows.

---

## Repository reference links

If you are browsing this repository, these files are the best entry points:

* Core public API: `claude_agent_sdk.ex`
* Options and CLI flag mapping: `claude_agent_sdk/options.ex`
* Query routing: `claude_agent_sdk/query.ex`
* Streaming API and session backend: `claude_agent_sdk/streaming.ex`, `claude_agent_sdk/streaming/session.ex`
* Control client (hooks, permissions, MCP): `claude_agent_sdk/client.ex`
* Hooks system: `claude_agent_sdk/hooks/*`
* Permission system: `claude_agent_sdk/permission/*`
* Auth tooling: `claude_agent_sdk/auth_manager.ex`, `claude_agent_sdk/auth_checker.ex`, `claude_agent_sdk/auth/*`
* Orchestration: `claude_agent_sdk/orchestrator.ex`
* Persistence: `claude_agent_sdk/session_store.ex`
* Diagnostics: `claude_agent_sdk/debug_mode.ex`

---

## License

MIT License
