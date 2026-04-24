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

- `sonnet` - default/recommended, Claude Sonnet 4.6
- `sonnet[1m]` - Claude Sonnet 4.6 with 1M context
- `opus` - Claude Opus 4.7
- `opus[1m]` - Claude Opus 4.7 with 1M context
- `haiku` - Claude Haiku 4.5

The current native Claude aliases are:

| SDK name | Claude CLI/API alias |
|----------|----------------------|
| `sonnet` | `claude-sonnet-4-6` |
| `sonnet[1m]` | `claude-sonnet-4-6[1m]` |
| `opus` | `claude-opus-4-7` |
| `opus[1m]` | `claude-opus-4-7[1m]` |
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

## Effort Gating

Effort is still a Claude-native feature.

For native Claude models:

- `haiku` does not support effort
- `sonnet` supports `:low`, `:medium`, `:high`, `:max`
- `opus` supports `:low`, `:medium`, `:high`, `:xhigh`, `:max`

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
