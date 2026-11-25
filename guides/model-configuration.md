# Model Configuration

The Claude SDK consumes the shared Claude catalog in
`cli_subprocess_core/priv/models/claude.json` and renders the resolved model as
Claude Code arguments and environment settings.

## Core-Owned Resolution

The authoritative core surface is:

- `CliSubprocessCore.ModelRegistry.resolve/3`
- `CliSubprocessCore.ModelRegistry.validate/2`
- `CliSubprocessCore.ModelRegistry.default_model/2`
- `CliSubprocessCore.ModelRegistry.build_arg_payload/3`
- `CliSubprocessCore.ModelInput.normalize/3`

`ClaudeAgentSDK.Options.new/1` routes mixed raw input or explicit
`model_payload` through `CliSubprocessCore.ModelInput.normalize/3`.

That means:

- explicit `model_payload` stays authoritative when supplied
- conflicting raw attrs fail immediately
- repo-local env defaults are only consulted when no payload was supplied

## Native Claude Backend

The default backend is the normal Claude catalog path.

| Claude Code alias | Current pinned ID |
|-------------------|-------------------|
| `sonnet` (SDK default) | `claude-sonnet-5-5` |
| `opus` | `claude-opus-5-5` |
| `haiku` | `claude-haiku-5-5` |
| `fable` | `claude-fable-5-2` |

Claude Code resolves its aliases based on the installed version and provider.
The `sonnet[1m]` and `opus[1m]` compatibility choices remain available. Explicit
older model IDs select their own versions. Use Claude Code 2.1.321 or newer
for this lineup. Older clients can resolve the aliases to earlier models.
[Claude Code model configuration](https://code.claude.com/docs/en/model-config#version-history)

## Using a model that is not in the registry

The Claude CLI accepts arbitrary `--model` strings, so a model that is newer
than the shared registry can be used directly. An unknown model id passes
through to `--model` verbatim (with a warning) instead of raising:

```elixir
# Just pass the id — unknown models pass through with a warning:
ClaudeAgentSDK.query("hi", %{model: "claude-brand-new-2027"})

# Strict callers can opt out of pass-through (unknown ids then raise):
ClaudeAgentSDK.query("hi", %{model: "claude-brand-new-2027", allow_unknown_model: false})

# Runtime switch to an unregistered model:
ClaudeAgentSDK.Client.set_model(client, "claude-brand-new-2027")
```

`fallback_model` is always passed through unvalidated. Effort validation is
driven by the shared model catalog: for a registered model, an unsupported
effort is dropped with a warning; for an unregistered model, the requested
effort is forwarded as-is and validated by the CLI/API.

### `allow_unknown_model` defaults across the ecosystem

This SDK is **permissive by default**: `allow_unknown_model` unset means
`true`, so unknown model ids pass through to `--model` with a warning (a
just-released model works before it reaches the registry).
`agent_session_manager` uses the same registry machinery but is **strict by
default** (`allow_unknown_model: false` — unknown ids are rejected unless a
caller opts in). The asymmetry is intentional — ASM is a governed
multi-provider manager — so do not "align" one to the other.

### Registry ownership and publication

Publish `cli_subprocess_core` 0.10.2 before Claude Agent SDK 0.21.2. Hex
consumers use the catalog from the published Core package. Mix Workspace Ops
and Portfolio Registry manage dependency sources for workspace development.

Restricted Mythos aliases such as `mythos-5.2` resolve to
`claude-mythos-5-2`. Account and provider eligibility govern actual access.
Verification for this release used official documentation and offline tests.

`ClaudeAgentSDK.Model.short_forms/0`, `full_ids/0`, and `list_models/0` expose
only public catalog entries. Core-owned private entries can still be validated
for env or compatibility paths, but they are not advertised by the SDK helpers.

Example:

```elixir
options =
  ClaudeAgentSDK.Options.new(
    model: "sonnet",
    max_turns: 1
  )
```

That resolves through `cli_subprocess_core` before the SDK emits `claude ...`.

## Ollama Backend

The SDK now supports an explicit Claude `:ollama` backend.

This still runs the normal `claude` binary.

The difference is that the core payload carries:

- the resolved external model id
- `ANTHROPIC_AUTH_TOKEN=ollama`
- `ANTHROPIC_API_KEY=""`
- `ANTHROPIC_BASE_URL=http://localhost:11434` or your override

### Direct external model id

```elixir
options =
  ClaudeAgentSDK.Options.new(
    provider_backend: :ollama,
    anthropic_base_url: "http://localhost:11434",
    model: "llama3.2"
  )
```

### Canonical Claude name mapped to an Ollama model

```elixir
options =
  ClaudeAgentSDK.Options.new(
    provider_backend: :ollama,
    anthropic_base_url: "http://localhost:11434",
    external_model_overrides: %{"haiku" => "llama3.2"},
    model: "haiku"
  )
```

In that case:

- the requested Claude name stays `haiku`
- the core payload resolves the transport model to `llama3.2`
- the SDK emits `claude --model llama3.2`

## Environment-Driven Backend Selection

The same Ollama path can be configured from env.

Relevant variables:

- `CLAUDE_AGENT_PROVIDER_BACKEND`
- `CLAUDE_AGENT_EXTERNAL_MODEL_OVERRIDES`
- `ANTHROPIC_BASE_URL`
- `ANTHROPIC_AUTH_TOKEN`
- `ANTHROPIC_API_KEY`

Example:

```bash
export CLAUDE_AGENT_PROVIDER_BACKEND=ollama
export CLAUDE_AGENT_EXTERNAL_MODEL_OVERRIDES='{"haiku":"llama3.2","sonnet":"llama3.2","opus":"llama3.2"}'
export ANTHROPIC_AUTH_TOKEN=ollama
export ANTHROPIC_API_KEY=""
export ANTHROPIC_BASE_URL=http://localhost:11434
```

That is the path used by `/home/home/p/g/n/claude_agent_sdk/examples/run_all.sh`
when you set `CLAUDE_EXAMPLES_BACKEND=ollama`.

Environment-driven backend selection is standalone direct-use behavior.
Governed launch rejects `provider_backend`, `anthropic_base_url`,
`anthropic_auth_token`, model-payload env overrides, and backend metadata
outside the materialized authority contract.

## Effort Gating

Current Sonnet 5.5, Opus 5.5, Haiku 5.5 and Fable 5.2 support `:low`,
`:medium`, `:high`, `:xhigh` and `:max`. Claude Code defaults these models
to medium. The Messages API defaults Sonnet 5.5 and Fable 5.2 to high.

When `effort` is omitted, the SDK leaves the flag unset and Claude Code
applies its settings and defaults. For a known model with an unsupported
level, the SDK logs a warning and omits the flag. Haiku 4.5 has no effort
control. External Ollama requests omit Claude-native effort.

The current models use adaptive thinking in Claude Code. `ultracode` is a
separate Claude Code workflow setting. [Claude Code effort and thinking](https://code.claude.com/docs/en/model-config#adjust-effort-level)

## Settings And Env From The Payload

The SDK now reads these payload fields from core:

- `resolved_model`
- `env_overrides`
- `settings_patch`
- `model_source`
- `provider_backend`

That means:

- model policy stays in core
- backend env is merged in one place
- future Claude backend settings can also be attached by the core payload

## Examples

Run the live example suite against the native Claude backend:

```bash
./examples/run_all.sh
```

Run the live example suite against Ollama:

```bash
CLAUDE_EXAMPLES_BACKEND=ollama \
CLAUDE_EXAMPLES_OLLAMA_MODEL=llama3.2 \
./examples/run_all.sh
```

The runner maps the common Claude names used by the examples onto the selected
Ollama model. Claude-only effort examples are skipped in that mode because the
external backend does not support Claude-native effort semantics.

### Pinning Fable versions

Pin `claude-fable-5-2` for Fable 5.2. The previous `claude-fable-5-1` and `claude-fable-5` IDs still select their own versions. Claude Code resolves the floating `fable` alias based on your version and provider. [Claude Code model configuration](https://code.claude.com/docs/en/model-config#work-with-fable)
