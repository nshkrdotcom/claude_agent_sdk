# Model Configuration

`/home/home/p/g/n/claude_agent_sdk` does not own active model policy.

That authority lives in:

- `/home/home/p/g/n/cli_subprocess_core/lib/cli_subprocess_core/model_registry.ex`
- `/home/home/p/g/n/cli_subprocess_core/priv/models/claude.json`

The Claude SDK consumes the resolved payload from core and only turns that
payload into Claude CLI arguments and env.

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

Canonical Claude model names include:

- `sonnet` - default/recommended, Claude Sonnet 5
- `sonnet[1m]` - Claude Sonnet 5 with 1M context
- `opus` - Claude Opus 4.8
- `opus[1m]` - Claude Opus 4.8 with 1M context
- `fable` - Claude Fable 5
- `haiku` - Claude Haiku 4.5

Prior full IDs (`claude-sonnet-4-6`, `claude-opus-4-7`) remain valid as
back-compatible aliases. The registry is owned by `cli_subprocess_core`.

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

### Registry ownership and hex publish-ordering

The model registry (catalog JSON + resolution logic) ships from
`cli_subprocess_core`, which this SDK and `agent_session_manager` consume as
a path dependency in this workspace and as a hex dependency when published.
The full release train publishes the two Ground Plane leaves, Execution Plane,
and then **`cli_subprocess_core` 0.2.0 before this SDK**. Publish
`claude_agent_sdk` before its optional `agent_session_manager` consumer. A Hex
consumer's model lineup comes from the *published* core package, not the
workspace sibling. When
switching a workspace checkout between `:path` and `:github`/`:hex`
resolution (see `build_support/dependency_sources.config.exs`), prune any
previously fetched `deps/cli_subprocess_core` copy so a stale catalog cannot
shadow the live one.

The current native Claude aliases are:

| SDK name | Claude CLI/API alias |
|----------|----------------------|
| `sonnet` | `claude-sonnet-5` (also `claude-sonnet-4-6`, `default`) |
| `sonnet[1m]` | `claude-sonnet-5[1m]` (also `claude-sonnet-4-6[1m]`) |
| `opus` | `claude-opus-4-8` (also `claude-opus-4-7`) |
| `opus[1m]` | `claude-opus-4-8[1m]` (also `claude-opus-4-7[1m]`) |
| `fable` | `claude-fable-5` |
| `haiku` | `claude-haiku-4-5` or `claude-haiku-4-5-20251001` |

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

Effort is still a Claude-native feature.

For native Claude models:

| Model family | Supported efforts |
|--------------|-------------------|
| `sonnet`, `sonnet[1m]` | `:low`, `:medium`, `:high`, `:max` |
| `opus`, `opus[1m]` | `:low`, `:medium`, `:high`, `:xhigh`, `:max` |
| `haiku` | none; the SDK logs a warning and omits `--effort` |

For external Claude/Ollama runs, the SDK does not emit `--effort`.

That is deliberate. Once the resolved payload is an external backend model, the
SDK stops pretending the external model supports Claude-native effort semantics.

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
