# Configuration Guide

This guide provides comprehensive documentation for configuring the Claude Agent SDK for Elixir. It covers all available options, presets, environment variables, and authentication methods.

## Table of Contents

1. [Options Struct Overview](#options-struct-overview)
2. [Complete Options Reference](#complete-options-reference)
3. [Output Formats](#output-formats)
4. [Model Selection](#model-selection)
5. [Tool Configuration](#tool-configuration)
6. [Sandbox Settings](#sandbox-settings)
7. [OptionBuilder Presets](#optionbuilder-presets)
8. [Environment Variables](#environment-variables)
9. [Authentication Configuration](#authentication-configuration)

---

## Options Struct Overview

The `ClaudeAgentSDK.Options` struct is the primary configuration mechanism for SDK requests. All fields are optional and will be omitted from the CLI command if not provided.

### Creating Options

```elixir
# Using struct syntax
options = %ClaudeAgentSDK.Options{
  max_turns: 5,
  output_format: :stream_json,
  verbose: true
}

# Using new/1 function
options = ClaudeAgentSDK.Options.new(
  max_turns: 5,
  output_format: :stream_json,
  verbose: true
)

# Using OptionBuilder presets
options = ClaudeAgentSDK.OptionBuilder.build_development_options()
```

### Basic Example

```elixir
options = %ClaudeAgentSDK.Options{
  system_prompt: "You are a helpful coding assistant",
  allowed_tools: ["Read", "Edit", "Bash"],
  permission_mode: :accept_edits,
  cwd: "/path/to/project",
  max_turns: 10
}

ClaudeAgentSDK.query("Refactor this code for better performance", options)
|> Enum.to_list()
```

---

## Complete Options Reference

### Core Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `max_turns` | `integer()` | `nil` | Maximum number of conversation turns |
| `system_prompt` | `String.t() \| map()` | `nil` | Custom system prompt or preset configuration |
| `append_system_prompt` | `String.t()` | `nil` | Additional prompt to append to system prompt |
| `output_format` | `atom() \| map()` | `nil` | Output format (see [Output Formats](#output-formats)) |
| `verbose` | `boolean()` | `nil` | Enable verbose output |
| `cwd` | `String.t()` | `nil` | Working directory for CLI operations |
| `timeout_ms` | `integer()` | `4,500,000` | Command timeout in milliseconds (75 minutes) |

### Model Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `model` | `String.t()` | `nil` | Model selection ("opus", "sonnet", "haiku", or full model name) |
| `fallback_model` | `String.t()` | `nil` | Fallback model when primary is busy |
| `max_thinking_tokens` | `pos_integer()` | `nil` | Maximum tokens for model thinking |

### Tool Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `tools` | `list() \| map()` | `nil` | Base tools set selection |
| `allowed_tools` | `[String.t()]` | `nil` | List of allowed tool names |
| `disallowed_tools` | `[String.t()]` | `nil` | List of disallowed tool names |

### Permission Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `permission_mode` | `atom()` | `nil` | Permission handling mode (see [Permission Modes](#permission-modes)) |
| `permission_prompt_tool` | `String.t()` | `nil` | Tool for permission prompts |
| `can_use_tool` | `function()` | `nil` | Permission callback function |

### MCP Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `mcp_servers` | `map()` or `String.t()` | `nil` | MCP server configurations or JSON/path string (alias for `mcp_config`) |
| `mcp_config` | `String.t()` | `nil` | Path to MCP configuration file |
| `strict_mcp_config` | `boolean()` | `nil` | Only use MCP servers from config |

### Session Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `session_id` | `String.t()` | `nil` | Explicit session ID (UUID) |
| `continue_conversation` | `boolean()` | `nil` | Continue most recent conversation |
| `resume` | `String.t()` | `nil` | Resume specific session by ID |
| `fork_session` | `boolean()` | `nil` | Create new session when resuming |

### Agent Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `agents` | `map()` | `nil` | Custom agent definitions |
| `agent` | `atom()` | `nil` | Active agent name (key from agents map) |

### Advanced Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `hooks` | `map()` | `nil` | Hook configurations for lifecycle events |
| `sandbox` | `map()` | `nil` | Sandbox settings merged into CLI settings |
| `settings` | `String.t()` | `nil` | Settings JSON string or file path |
| `setting_sources` | `[String.t()]` | `nil` | Setting source locations |
| `betas` | `[String.t()]` | `[]` | SDK beta feature flags |
| `plugins` | `[map()]` | `[]` | Plugin configurations |
| `add_dir` | `[String.t()]` | `nil` | Additional directories for tool access |
| `add_dirs` | `[String.t()]` | `[]` | Additional directories (list form) |
| `max_budget_usd` | `number()` | `nil` | Maximum budget in USD |
| `enable_file_checkpointing` | `boolean()` | `nil` | Enable file checkpointing and rewind |

### Streaming Options (v0.6.0+)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `include_partial_messages` | `boolean()` | `nil` | Enable character-level streaming |
| `preferred_transport` | `atom()` | `nil` | Transport selection (`:auto`, `:cli`, `:control`) |

### Internal/Advanced Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `executable` | `String.t()` | `nil` | Custom executable to run (CLI path override) |
| `executable_args` | `[String.t()]` | `nil` | Arguments for custom executable |
| `path_to_claude_code_executable` | `String.t()` | `nil` | Path to Claude Code CLI (Python `cli_path` equivalent) |
| `abort_ref` | `reference()` | `nil` | Reference for aborting requests |
| `extra_args` | `map()` | `%{}` | Additional CLI arguments (boolean `true`/`nil` => flag only; `false` => omit) |
| `env` | `map()` | `%{}` | Environment variable overrides |
| `stderr` | `function()` | `nil` | Stderr callback function |
| `user` | `String.t()` | `nil` | User identifier |
| `max_buffer_size` | `pos_integer()` | `nil` | Maximum JSON buffer size (default: 1MB, overflow yields `CLIJSONDecodeError`) |

---

If you omit `max_buffer_size`, the SDK enforces a 1MB default across Port, erlexec, and sync process parsing to match Python SDK limits.

The `stderr` callback is invoked for non-JSON stderr lines across query, client, and streaming session flows.

## Output Formats

The SDK supports multiple output formats for different use cases.

### Standard Formats

| Format | Description | Use Case |
|--------|-------------|----------|
| `:text` | Plain text output | Simple responses, human-readable output |
| `:json` | JSON-formatted output | Structured data, parsing responses |
| `:stream_json` | Streaming JSON | Real-time updates, long-running tasks |

Note: SDK query/streaming/client flows always use `stream-json` for transport parsing. If you set `:text` or `:json`, the SDK normalizes the CLI output to `stream-json` and only forwards `--json-schema` when provided.

### Basic Usage

```elixir
# Plain text (simplest)
%Options{output_format: :text}

# JSON (structured)
%Options{output_format: :json}

# Streaming JSON (real-time)
%Options{output_format: :stream_json}
```

### JSON Schema (Structured Outputs)

Request validated JSON output by providing a schema:

```elixir
# Tuple syntax
schema = %{
  "type" => "object",
  "properties" => %{
    "summary" => %{"type" => "string"},
    "score" => %{"type" => "number"}
  },
  "required" => ["summary", "score"]
}

options = %Options{output_format: {:json_schema, schema}}
```

```elixir
# Map syntax with explicit type
options = %Options{
  output_format: %{
    type: :json_schema,
    schema: %{
      "type" => "object",
      "properties" => %{
        "title" => %{"type" => "string"},
        "tags" => %{"type" => "array", "items" => %{"type" => "string"}}
      },
      "required" => ["title"]
    },
    output_format: :stream_json  # Optional: base format for streaming
  }
}
```

### Output Format Types

```elixir
@type output_format :: :text | :json | :stream_json | structured_output_format()

@type structured_output_format ::
  {:json_schema, map()} |
  %{
    type: :json_schema | String.t(),
    schema: map(),
    output_format: :json | :stream_json | String.t()  # optional
  }
```

---

## Model Selection

The SDK supports all Claude models with convenient shorthand names.

### Available Models

| Shorthand | Full Model ID | Best For |
|-----------|---------------|----------|
| `"haiku"` | Auto-selects latest Haiku | Fast responses, simple queries, cost-effective |
| `"sonnet"` | Auto-selects latest Sonnet | Balanced performance, general tasks |
| `"opus"` | Auto-selects latest Opus | Complex reasoning, detailed code generation |

### Model Configuration

```elixir
# Using shorthand
options = %Options{model: "sonnet"}

# Using full model name
options = %Options{model: "claude-sonnet-4-5-20250929"}

# With fallback model
options = %Options{
  model: "opus",
  fallback_model: "sonnet"
}
```

### Using OptionBuilder

```elixir
# Maximum capability
options = ClaudeAgentSDK.OptionBuilder.with_opus()

# Balanced performance
options = ClaudeAgentSDK.OptionBuilder.with_sonnet()

# Fast responses (default)
options = ClaudeAgentSDK.OptionBuilder.with_haiku()

# Add model to existing options
options = ClaudeAgentSDK.OptionBuilder.build_development_options()
|> ClaudeAgentSDK.OptionBuilder.with_model("opus", "sonnet")
```

### Model Selection Comparison

| Model | Speed | Cost | Capability | Recommended For |
|-------|-------|------|------------|-----------------|
| Haiku | Fastest | Lowest | Good | Quick queries, high volume |
| Sonnet | Balanced | Medium | Great | Most use cases |
| Opus | Slowest | Highest | Best | Complex tasks, detailed analysis |

---

## Tool Configuration

Control which tools Claude can use during execution.

### Available Built-in Tools

| Tool | Description | Risk Level |
|------|-------------|------------|
| `"Read"` | Read file contents | Low |
| `"Write"` | Create/overwrite files | Medium |
| `"Edit"` | Modify existing files | Medium |
| `"Bash"` | Execute shell commands | High |
| `"Grep"` | Search file contents | Low |
| `"Find"` | Find files by pattern | Low |
| `"Glob"` | Pattern-based file matching | Low |

### Allowing Specific Tools

```elixir
# Only allow read operations
options = %Options{
  allowed_tools: ["Read", "Grep", "Find"]
}

# Allow file modifications
options = %Options{
  allowed_tools: ["Read", "Write", "Edit"]
}

# Full access (development only)
options = %Options{
  allowed_tools: ["Bash", "Read", "Write", "Edit", "Grep", "Find"]
}
```

### Disallowing Specific Tools

```elixir
# Prevent dangerous operations
options = %Options{
  disallowed_tools: ["Bash", "Write", "Edit"]
}

# Combine allowed and disallowed
options = %Options{
  allowed_tools: ["Read", "Write", "Grep"],
  disallowed_tools: ["Bash"]
}
```

### Tools Preset Configuration

```elixir
# Use Claude Code default tools
options = %Options{
  tools: %{type: :preset, preset: :claude_code}
}

# Explicit tool list
options = %Options{
  tools: ["Read", "Edit"]
}

# Disable all built-in tools
options = %Options{
  tools: []
}
```

### MCP Tool Configuration

```elixir
# SDK MCP server (in-process)
server = ClaudeAgentSDK.create_sdk_mcp_server(
  name: "calculator",
  version: "1.0.0",
  tools: [MyTools.Add, MyTools.Multiply]
)

options = %Options{
  mcp_servers: %{"calc" => server},
  allowed_tools: ["mcp__calc__add", "mcp__calc__multiply"]
}

# External MCP server (subprocess)
external_server = %{
  type: :stdio,
  command: "npx",
  args: ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/files"]
}

options = %Options{
  mcp_servers: %{"filesystem" => external_server}
}
```

`mcp_servers` also accepts a JSON string or file path (alias for `mcp_config`):

```elixir
options = %Options{mcp_servers: "/path/to/mcp.json"}
```

---

## Sandbox Settings

Configure sandboxed execution for safe, isolated operations.

### Basic Sandbox Configuration

```elixir
options = %Options{
  sandbox: %{
    enabled: true,
    allowed_paths: ["/tmp/sandbox", "/home/user/safe"],
    denied_paths: ["/etc", "/root"],
    network_disabled: true
  }
}
```

### Using OptionBuilder Sandbox Preset

```elixir
# Create sandboxed environment
options = ClaudeAgentSDK.OptionBuilder.sandboxed("/tmp/sandbox")

# Sandbox with custom tools
options = ClaudeAgentSDK.OptionBuilder.sandboxed(
  "/tmp/safe",
  ["Read", "Write", "Grep"]
)
```

### Sandbox with Bypass Permissions

```elixir
# Safe within sandbox, all tools auto-allowed
options = %Options{
  cwd: "/tmp/isolated",
  permission_mode: :bypass_permissions,
  allowed_tools: ["Read", "Write"],
  disallowed_tools: ["Bash"],
  sandbox: %{
    enabled: true,
    root: "/tmp/isolated"
  }
}
```

---

## OptionBuilder Presets

The `ClaudeAgentSDK.OptionBuilder` module provides pre-configured option sets for common scenarios.

### Environment Presets

#### Development

Best for local development, debugging, and experimentation.

```elixir
options = ClaudeAgentSDK.OptionBuilder.build_development_options()
```

| Setting | Value |
|---------|-------|
| `max_turns` | 10 |
| `verbose` | true |
| `output_format` | `:stream_json` |
| `allowed_tools` | `["Bash", "Read", "Write", "Edit", "Grep", "Find"]` |
| `permission_mode` | `:accept_edits` |

#### Staging

Best for CI/CD pipelines, automated testing, and code review.

```elixir
options = ClaudeAgentSDK.OptionBuilder.build_staging_options()
```

| Setting | Value |
|---------|-------|
| `max_turns` | 5 |
| `verbose` | false |
| `output_format` | `:json` |
| `allowed_tools` | `["Read"]` |
| `disallowed_tools` | `["Bash", "Write", "Edit"]` |
| `permission_mode` | `:plan` |

#### Production

Best for production monitoring, read-only analysis, and customer-facing features.

```elixir
options = ClaudeAgentSDK.OptionBuilder.build_production_options()
```

| Setting | Value |
|---------|-------|
| `max_turns` | 3 |
| `verbose` | false |
| `output_format` | `:stream_json` |
| `allowed_tools` | `["Read"]` |
| `disallowed_tools` | `["Bash", "Write", "Edit", "Grep", "Find"]` |
| `permission_mode` | `:plan` |

#### Auto-Select by Mix Environment

```elixir
# Automatically selects based on Mix.env()
options = ClaudeAgentSDK.OptionBuilder.for_environment()
# :dev -> development options
# :test -> staging options
# :prod -> production options
```

### Use-Case Presets

#### Analysis

Best for code reviews, security audits, and quality analysis.

```elixir
options = ClaudeAgentSDK.OptionBuilder.build_analysis_options()
```

| Setting | Value |
|---------|-------|
| `max_turns` | 7 |
| `output_format` | `:stream_json` |
| `allowed_tools` | `["Read", "Grep", "Find"]` |
| `disallowed_tools` | `["Write", "Edit", "Bash"]` |
| `permission_mode` | `:plan` |

#### Documentation

Best for API docs, README generation, and code documentation.

```elixir
options = ClaudeAgentSDK.OptionBuilder.build_documentation_options()
```

| Setting | Value |
|---------|-------|
| `max_turns` | 8 |
| `output_format` | `:stream_json` |
| `allowed_tools` | `["Read", "Write", "Grep"]` |
| `disallowed_tools` | `["Bash", "Edit"]` |
| `permission_mode` | `:accept_edits` |

#### Testing

Best for unit test creation, test analysis, and quality assurance.

```elixir
options = ClaudeAgentSDK.OptionBuilder.build_testing_options()
```

| Setting | Value |
|---------|-------|
| `max_turns` | 6 |
| `output_format` | `:stream_json` |
| `allowed_tools` | `["Read", "Write", "Grep"]` |
| `disallowed_tools` | `["Bash", "Edit"]` |
| `permission_mode` | `:accept_edits` |

#### Chat

Best for help desk, documentation queries, and general assistance.

```elixir
options = ClaudeAgentSDK.OptionBuilder.build_chat_options()
```

| Setting | Value |
|---------|-------|
| `max_turns` | 1 |
| `output_format` | `:text` |
| `allowed_tools` | `[]` |
| `disallowed_tools` | `["Bash", "Read", "Write", "Edit", "Grep", "Find"]` |
| `permission_mode` | `:plan` |

#### Quick

Best for simple questions, quick checks, and lightweight operations.

```elixir
options = ClaudeAgentSDK.OptionBuilder.quick()
```

| Setting | Value |
|---------|-------|
| `max_turns` | 1 |
| `output_format` | `:text` |
| `allowed_tools` | `[]` |
| `permission_mode` | `:plan` |

### Preset Comparison Table

| Preset | max_turns | Tools | Permission Mode | Use Case |
|--------|-----------|-------|-----------------|----------|
| Development | 10 | All | accept_edits | Local dev |
| Staging | 5 | Read-only | plan | CI/CD |
| Production | 3 | Read-only | plan | Production |
| Analysis | 7 | Read, Search | plan | Code review |
| Documentation | 8 | Read, Write | accept_edits | Doc generation |
| Testing | 6 | Read, Write | accept_edits | Test generation |
| Chat | 1 | None | plan | Simple Q&A |
| Quick | 1 | None | plan | Fast queries |

### Builder Utilities

#### Merging Options

```elixir
# Merge with preset name
options = ClaudeAgentSDK.OptionBuilder.merge(:development, %{max_turns: 15})

# Merge with existing options
base = ClaudeAgentSDK.OptionBuilder.build_chat_options()
options = ClaudeAgentSDK.OptionBuilder.merge(base, %{max_turns: 3})
```

#### Chainable Builders

```elixir
options = ClaudeAgentSDK.OptionBuilder.build_development_options()
|> ClaudeAgentSDK.OptionBuilder.with_working_directory("/project")
|> ClaudeAgentSDK.OptionBuilder.with_system_prompt("You are an expert")
|> ClaudeAgentSDK.OptionBuilder.with_additional_tools(["Grep"])
|> ClaudeAgentSDK.OptionBuilder.with_turn_limit(15)
```

#### Validation

```elixir
options = ClaudeAgentSDK.OptionBuilder.build_development_options()

case ClaudeAgentSDK.OptionBuilder.validate(options) do
  {:ok, options} ->
    IO.puts("Options valid")

  {:warning, options, warnings} ->
    IO.puts("Warnings: #{inspect(warnings)}")

  {:error, reason} ->
    IO.puts("Invalid: #{reason}")
end
```

#### Available Presets

```elixir
ClaudeAgentSDK.OptionBuilder.available_presets()
# => [:development, :staging, :production, :analysis, :chat, :documentation, :testing]
```

---

## Environment Variables

### Authentication Variables

| Variable | Description | Priority |
|----------|-------------|----------|
| `ANTHROPIC_API_KEY` | Anthropic API key | Primary |
| `CLAUDE_AGENT_OAUTH_TOKEN` | OAuth token from `claude login` | Primary |

### Provider Selection

| Variable | Value | Description |
|----------|-------|-------------|
| `CLAUDE_AGENT_USE_BEDROCK` | `"1"` | Use AWS Bedrock |
| `CLAUDE_AGENT_USE_VERTEX` | `"1"` | Use Google Vertex AI |

### AWS Bedrock Credentials

| Variable | Description |
|----------|-------------|
| `AWS_ACCESS_KEY_ID` | AWS access key ID |
| `AWS_SECRET_ACCESS_KEY` | AWS secret access key |
| `AWS_PROFILE` | AWS profile name |
| `AWS_REGION` | AWS region |

### Google Vertex AI Credentials

| Variable | Description |
|----------|-------------|
| `GOOGLE_APPLICATION_CREDENTIALS` | Path to service account JSON |
| `GOOGLE_CLOUD_PROJECT` | GCP project ID |

### SDK Internal Variables

| Variable | Description |
|----------|-------------|
| `CLAUDE_CODE_ENTRYPOINT` | Set automatically to `"sdk-elixir"` |
| `CLAUDE_AGENT_SDK_VERSION` | Current SDK version |

### Setting Environment Variables in Options

```elixir
options = %Options{
  env: %{
    "CUSTOM_VAR" => "value",
    "DEBUG" => "true"
  }
}
```

---

## Authentication Configuration

### Authentication Methods

The SDK supports three authentication methods:

1. **Anthropic API** (default) - Direct API key or OAuth session
2. **AWS Bedrock** - Using AWS credentials
3. **Google Vertex AI** - Using GCP credentials

### Quick Authentication Check

```elixir
# Boolean check
if ClaudeAgentSDK.AuthChecker.authenticated?() do
  ClaudeAgentSDK.query("Hello!")
else
  IO.puts("Please authenticate first")
end

# Ensure ready (raises on failure)
ClaudeAgentSDK.AuthChecker.ensure_ready!()
```

### Full Diagnostic Check

```elixir
diagnosis = ClaudeAgentSDK.AuthChecker.diagnose()

IO.inspect(diagnosis)
# %{
#   cli_installed: true,
#   cli_version: "2.0.75",
#   authenticated: true,
#   auth_method: "Anthropic API",
#   api_key_source: "env",
#   status: :ready,
#   recommendations: ["Environment is ready for Claude queries"],
#   last_checked: ~U[2025-12-29 12:00:00Z]
# }
```

### AuthManager for Token Management

```elixir
# Start AuthManager (typically in application supervision tree)
{:ok, _pid} = ClaudeAgentSDK.AuthManager.start_link()

# Ensure authenticated
:ok = ClaudeAgentSDK.AuthManager.ensure_authenticated()

# Setup token (interactive, requires terminal)
{:ok, token} = ClaudeAgentSDK.AuthManager.setup_token()

# Get current token
{:ok, token} = ClaudeAgentSDK.AuthManager.get_token()

# Refresh token
{:ok, token} = ClaudeAgentSDK.AuthManager.refresh_token()

# Check status
status = ClaudeAgentSDK.AuthManager.status()
# %{
#   authenticated: true,
#   provider: :anthropic,
#   token_present: true,
#   expires_at: ~U[2025-11-07 00:00:00Z],
#   time_until_expiry_hours: 720
# }

# Clear authentication
:ok = ClaudeAgentSDK.AuthManager.clear_auth()
```

### Application Configuration

```elixir
# config/config.exs
config :claude_agent_sdk,
  auth_storage: :file,                    # :file | :application_env | :custom
  auth_file_path: "~/.claude_sdk/token.json",
  auto_refresh: true,
  refresh_before_expiry: 86_400_000       # 1 day in ms
```

### Authentication by Provider

#### Anthropic API (Default)

```bash
# Option 1: Environment variable
export ANTHROPIC_API_KEY=sk-ant-api03-...

# Option 2: CLI login
claude login
```

```elixir
# Check Anthropic auth
ClaudeAgentSDK.AuthChecker.auth_method_available?(:anthropic)
```

#### AWS Bedrock

```bash
# Enable Bedrock
export CLAUDE_AGENT_USE_BEDROCK=1

# AWS credentials (one of these methods)
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
# OR
export AWS_PROFILE=my-profile
# OR
# Use ~/.aws/credentials file
```

```elixir
# Check Bedrock auth
ClaudeAgentSDK.AuthChecker.auth_method_available?(:bedrock)
```

#### Google Vertex AI

```bash
# Enable Vertex AI
export CLAUDE_AGENT_USE_VERTEX=1

# GCP credentials (one of these methods)
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/credentials.json
# OR
export GOOGLE_CLOUD_PROJECT=my-project
# OR
# Use default application credentials
```

```elixir
# Check Vertex auth
ClaudeAgentSDK.AuthChecker.auth_method_available?(:vertex)
```

### Authentication Status Types

```elixir
@type auth_status ::
  :ready |              # Fully configured and authenticated
  :cli_not_found |      # Claude CLI not installed
  :not_authenticated |  # CLI installed but not authenticated
  :invalid_credentials | # Authentication failed
  :unknown              # Unknown state
```

### Troubleshooting Authentication

```elixir
diagnosis = ClaudeAgentSDK.AuthChecker.diagnose()

case diagnosis.status do
  :ready ->
    IO.puts("Ready to use Claude")

  :cli_not_found ->
    IO.puts("Install CLI: npm install -g @anthropic-ai/claude-code")

  :not_authenticated ->
    IO.puts("Authenticate: claude login")
    IO.puts("Or set: ANTHROPIC_API_KEY=...")

  :invalid_credentials ->
    IO.puts("Check credentials and try re-authenticating")

  _ ->
    IO.puts("Recommendations:")
    Enum.each(diagnosis.recommendations, &IO.puts("  - #{&1}"))
end
```

---

## Permission Modes

Control how tool permissions are handled.

| Mode | Description |
|------|-------------|
| `:default` | All tools go through permission callback |
| `:accept_edits` | Edit operations auto-allowed |
| `:plan` | Creates plan, shows to user, executes after approval |
| `:bypass_permissions` | All tools allowed without callback |

```elixir
# Default - manual approval for each tool
%Options{permission_mode: :default}

# Accept edits - auto-approve file modifications
%Options{permission_mode: :accept_edits}

# Plan mode - review before execution
%Options{permission_mode: :plan}

# Bypass - no permissions (use with caution)
%Options{permission_mode: :bypass_permissions}
```

### Custom Permission Callback

```elixir
alias ClaudeAgentSDK.Permission.{Context, Result}

callback = fn context ->
  case context.tool_name do
    "Bash" ->
      if String.contains?(context.tool_input["command"], "rm -rf") do
        Result.deny("Dangerous command")
      else
        Result.allow()
      end

    "Write" ->
      if String.starts_with?(context.tool_input["file_path"], "/etc/") do
        Result.deny("Cannot write to /etc")
      else
        Result.allow()
      end

    _ ->
      Result.allow()
  end
end

options = %Options{
  can_use_tool: callback,
  permission_mode: :default
}
```

---

## Transport Configuration (v0.6.0+)

The SDK automatically selects the appropriate transport based on configured features.

### Transport Types

| Transport | Description | When Used |
|-----------|-------------|-----------|
| `:cli` | Simple CLI streaming | No hooks, MCP, or permissions |
| `:control` | Control protocol client | Hooks, MCP servers, or permission callbacks |
| `:auto` | Automatic selection | Default |

### Override Transport Selection

```elixir
# Force CLI-only mode (ignores control features)
%Options{preferred_transport: :cli}

# Force control client (even without features)
%Options{preferred_transport: :control}

# Automatic selection (default)
%Options{preferred_transport: :auto}
```

### Enable Character-Level Streaming

```elixir
options = %Options{
  include_partial_messages: true,
  hooks: %{pre_tool_use: [...]},
  mcp_servers: %{"math" => sdk_server}
}
# Automatically selects control client with streaming enabled
```

---

## Complete Configuration Examples

### Development Setup

```elixir
options = %ClaudeAgentSDK.Options{
  model: "sonnet",
  max_turns: 10,
  verbose: true,
  output_format: :stream_json,
  cwd: "/path/to/project",
  allowed_tools: ["Bash", "Read", "Write", "Edit", "Grep", "Find"],
  permission_mode: :accept_edits,
  system_prompt: "You are a helpful Elixir development assistant."
}
```

### Production Read-Only Analysis

```elixir
options = %ClaudeAgentSDK.Options{
  model: "haiku",
  max_turns: 3,
  verbose: false,
  output_format: :stream_json,
  allowed_tools: ["Read"],
  disallowed_tools: ["Bash", "Write", "Edit"],
  permission_mode: :plan,
  max_budget_usd: 0.50,
  system_prompt: "Provide concise, accurate analysis."
}
```

### Sandboxed Execution

```elixir
options = %ClaudeAgentSDK.Options{
  cwd: "/tmp/sandbox",
  permission_mode: :bypass_permissions,
  allowed_tools: ["Read", "Write"],
  disallowed_tools: ["Bash"],
  max_turns: 5,
  output_format: :stream_json,
  sandbox: %{
    enabled: true,
    root: "/tmp/sandbox"
  }
}
```

### With MCP Tools

```elixir
# Create SDK MCP server
server = ClaudeAgentSDK.create_sdk_mcp_server(
  name: "calculator",
  version: "1.0.0",
  tools: [Calculator.Add, Calculator.Multiply]
)

options = %ClaudeAgentSDK.Options{
  mcp_servers: %{"calc" => server},
  allowed_tools: ["mcp__calc__add", "mcp__calc__multiply"],
  include_partial_messages: true,
  output_format: :stream_json
}
```

### With Custom Hooks

```elixir
alias ClaudeAgentSDK.Hooks.{Matcher, Output}

check_bash = fn input, _id, _ctx ->
  cmd = get_in(input, ["tool_input", "command"]) || ""
  if String.contains?(cmd, "rm -rf") do
    Output.deny("Dangerous command blocked")
  else
    Output.allow()
  end
end

options = %ClaudeAgentSDK.Options{
  hooks: %{
    pre_tool_use: [%Matcher{matcher: "Bash", hooks: [check_bash]}]
  },
  allowed_tools: ["Bash", "Read"],
  include_partial_messages: true
}
```

---

## Further Reading

- [Hooks Guide](hooks.md) - Comprehensive guide to lifecycle hooks
- [MCP Tools Guide](mcp-tools.md) - MCP server design and tool creation
- [API Documentation](https://hexdocs.pm/claude_agent_sdk) - Full API reference
