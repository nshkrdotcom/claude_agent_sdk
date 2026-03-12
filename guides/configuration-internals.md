# Configuration Internals

This guide documents the SDK's centralized configuration system. Every
tunable constant — timeouts, buffer sizes, environment variable names,
CLI flags — lives in a single `Config.*` module namespace and can be
overridden at runtime via `Application.put_env/3` or at compile time
via `config/config.exs`.

## Architecture

```
ClaudeAgentSDK.Config              (top-level facade, mock mode, CLI stream module)
  ├── Config.Timeouts              (all timeout values)
  ├── Config.Buffers               (buffer sizes, truncation lengths)
  ├── Config.Auth                  (auth file paths, TTLs, token prefixes)
  ├── Config.CLI                   (CLI versions, flags, executable discovery)
  ├── Config.Env                   (environment variable name registry)
  └── Config.Orchestration         (concurrency limits, retries, backoff)
```

Each sub-module follows the same pattern:

1. A private `get/2` helper reads from `Application.get_env(:claude_agent_sdk, __MODULE__, [])`
2. Public zero-arity functions return the value for a named key
3. Every function has a built-in default that matches the original hardcoded value

This means **no behaviour changes** out of the box — the defaults are
identical to the values that were previously scattered as `@module_attributes`
and inline literals.

## Quick Reference

### Config.Timeouts

All values in milliseconds unless noted.

| Function | Default | Description |
|----------|---------|-------------|
| `client_init_ms/0` | 60,000 | Client initialization timeout |
| `client_hook_ms/0` | 60,000 | Hook callback execution timeout |
| `client_control_request_ms/0` | 60,000 | Control protocol request timeout |
| `client_stop_ms/0` | 5,000 | Client graceful stop timeout |
| `client_exit_wait_ms/0` | 200 | CLI exit status wait |
| `client_permission_yield_ms/0` | 60,000 | Permission callback yield timeout |
| `streaming_session_ms/0` | 300,000 | Streaming session default (5 min) |
| `stream_receive_ms/0` | 30,000 | Stream receive liveness probe (30 s) |
| `query_total_ms/0` | 4,500,000 | Total query timeout (75 min) |
| `query_parallel_ms/0` | 300,000 | Parallel query per-task timeout (5 min) |
| `transport_call_ms/0` | 5,000 | GenServer.call timeout for transport |
| `transport_force_close_ms/0` | 500 | Force-close transport timeout |
| `transport_headless_ms/0` | 5,000 | Headless mode timeout |
| `transport_finalize_ms/0` | 25 | Process finalization delay |
| `client_close_grace_ms/0` | 2,000 | Client close grace period |
| `transport_close_grace_ms/0` | 2,000 | Transport close grace period |
| `auth_ensure_ms/0` | 30,000 | `ensure_authenticated` call timeout |
| `auth_setup_token_ms/0` | 120,000 | OAuth setup_token timeout (2 min) |
| `auth_refresh_token_ms/0` | 120,000 | Token refresh timeout (2 min) |
| `auth_refresh_retry_ms/0` | 3,600,000 | Retry on refresh failure (1 h) |
| `auth_refresh_before_expiry_ms/0` | 86,400,000 | Refresh this far before expiry (1 day) |
| `auth_min_refresh_delay_ms/0` | 60,000 | Minimum delay before scheduling refresh |
| `auth_cli_test_ms/0` | 30,000 | CLI auth test command timeout |
| `auth_cli_version_ms/0` | 10,000 | CLI version check timeout |
| `tool_execution_ms/0` | 30,000 | Tool execution timeout |
| `hook_min_ms/0` | 1,000 | Minimum hook timeout floor |
| `session_cleanup_interval_ms/0` | 86,400,000 | Session cleanup check interval (24 h) |
| `orchestrator_backoff_ms/0` | 1,000 | Initial retry backoff |
| `ms_per_hour/0` | 3,600,000 | Conversion constant |
| `seconds_per_day/0` | 86,400 | Conversion constant |

### Config.Buffers

| Function | Default | Description |
|----------|---------|-------------|
| `max_stdout_buffer_bytes/0` | 1,048,576 | Max stdout buffer (1 MB) |
| `max_stderr_buffer_bytes/0` | 262,144 | Max stderr buffer (256 KB) |
| `max_lines_per_batch/0` | 200 | Lines per drain batch |
| `stream_buffer_limit/0` | 1,000 | Inbound event buffer limit |
| `error_preview_length/0` | 100 | Error/JSON preview length |
| `message_trim_length/0` | 300 | Message trim length |
| `error_truncation_length/0` | 1,000 | Orchestrator error truncation |
| `summary_max_length/0` | 100 | Default summary max length |

### Config.Auth

| Function | Default | Description |
|----------|---------|-------------|
| `token_store_path/0` | `~/.claude_sdk/token.json` | Token storage path |
| `session_storage_dir/0` | `~/.claude_sdk/sessions` | Session storage directory |
| `token_ttl_days/0` | 365 | Token validity (days) |
| `session_max_age_days/0` | 30 | Max session age (days) |
| `oauth_token_prefix/0` | `sk-ant-oat01-` | OAuth token prefix |
| `api_key_prefix/0` | `sk-ant-` | API key prefix |
| `aws_credentials_path/0` | `~/.aws/credentials` | AWS credentials file |
| `gcp_credentials_path/0` | `~/.config/gcloud/...` | GCP credentials file |
| `providers/0` | `[:anthropic, :bedrock, :vertex]` | Supported providers |

### Config.CLI

| Function | Default | Description |
|----------|---------|-------------|
| `minimum_version/0` | `"2.1.0"` | Minimum supported CLI version |
| `recommended_version/0` | `"2.1.74"` | Recommended CLI version |
| `executable_candidates/0` | `["claude-code", "claude"]` | PATH search candidates |
| `install_command/0` | `npm install -g @anthropic-ai/claude-code` | Install command for errors |
| `streaming_output_args/0` | `["--output-format", "stream-json", "--verbose"]` | Output-only streaming flags |
| `streaming_bidirectional_args/0` | (adds `--input-format`) | Full bidirectional flags |

### Config.Env

Every function returns a string literal — the canonical environment variable name.

| Function | Value |
|----------|-------|
| `anthropic_api_key/0` | `ANTHROPIC_API_KEY` |
| `oauth_token/0` | `CLAUDE_AGENT_OAUTH_TOKEN` |
| `use_bedrock/0` | `CLAUDE_AGENT_USE_BEDROCK` |
| `use_vertex/0` | `CLAUDE_AGENT_USE_VERTEX` |
| `entrypoint/0` | `CLAUDE_CODE_ENTRYPOINT` |
| `sdk_version/0` | `CLAUDE_AGENT_SDK_VERSION` |
| `file_checkpointing/0` | `CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING` |
| `stream_close_timeout/0` | `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT` |
| `skip_version_check/0` | `CLAUDE_AGENT_SDK_SKIP_VERSION_CHECK` |
| `aws_access_key_id/0` | `AWS_ACCESS_KEY_ID` |
| `aws_profile/0` | `AWS_PROFILE` |
| `gcp_credentials/0` | `GOOGLE_APPLICATION_CREDENTIALS` |
| `gcp_project/0` | `GOOGLE_CLOUD_PROJECT` |
| `ci/0` | `CI` |
| `live_mode/0` | `LIVE_MODE` |
| `live_tests/0` | `LIVE_TESTS` |
| `passthrough_vars/0` | `["CLAUDE_AGENT_OAUTH_TOKEN", "ANTHROPIC_API_KEY", "PATH", "HOME"]` |

### Config.Orchestration

| Function | Default | Description |
|----------|---------|-------------|
| `max_concurrent/0` | 5 | Max concurrent parallel queries |
| `max_retries/0` | 3 | Max retry attempts |
| `backoff_ms/0` | 1,000 | Initial exponential backoff |

## Overriding at Runtime

### Via config.exs

```elixir
# config/config.exs
config :claude_agent_sdk, ClaudeAgentSDK.Config.Timeouts,
  client_init_ms: 90_000,
  query_total_ms: 5_400_000

config :claude_agent_sdk, ClaudeAgentSDK.Config.Buffers,
  max_stdout_buffer_bytes: 2_097_152

config :claude_agent_sdk, ClaudeAgentSDK.Config.Auth,
  token_store_path: "~/.my_app/token.json",
  session_max_age_days: 60

config :claude_agent_sdk, ClaudeAgentSDK.Config.CLI,
  minimum_version: "2.1.0",
  recommended_version: "2.1.74"

config :claude_agent_sdk, ClaudeAgentSDK.Config.Orchestration,
  max_concurrent: 10,
  max_retries: 5
```

### Via Application.put_env at Runtime

```elixir
# Useful for tests or dynamic configuration
Application.put_env(
  :claude_agent_sdk,
  ClaudeAgentSDK.Config.Timeouts,
  query_total_ms: 10_000
)

# In tests, always restore original values:
setup do
  original = Application.get_env(:claude_agent_sdk, Timeouts)
  on_exit(fn ->
    if original, do: Application.put_env(:claude_agent_sdk, Timeouts, original),
    else: Application.delete_env(:claude_agent_sdk, Timeouts)
  end)
end
```

### Per-Environment Overrides

```elixir
# config/test.exs
config :claude_agent_sdk, ClaudeAgentSDK.Config.Timeouts,
  client_init_ms: 5_000,       # faster for tests
  query_total_ms: 10_000

# config/prod.exs
config :claude_agent_sdk, ClaudeAgentSDK.Config.Timeouts,
  query_total_ms: 7_200_000    # 2 hours for production
```

## Design Decisions

### Why Not a Single Flat Config Module?

Grouping by domain (timeouts, buffers, auth, etc.) provides:

- **Discoverability**: `Config.Timeouts.` tab-completion shows all timeouts
- **Selective override**: configure only the domain you care about
- **Documentation**: each module's `@moduledoc` is a focused reference

### Why Runtime Functions Instead of Module Attributes?

Module attributes (`@timeout 60_000`) are evaluated at compile time.
Functions like `Timeouts.client_init_ms()` are evaluated at runtime,
which means:

- Changes via `Application.put_env` take effect immediately
- No recompilation needed to adjust values
- Tests can override values per-test without affecting other tests

The performance cost is negligible (~1 µs per `Application.get_env`
call, which is ETS-backed).

### Why Keep Struct Defaults as Literals?

Elixir `defstruct` requires compile-time default values. Where a struct
field previously used `@some_attribute`, we replace it with the same
literal value. The struct default is just an initial value — the
`init/1` callback (or factory function) overwrites it from Config at
runtime.

## Adding New Configuration Values

1. Choose the appropriate sub-module (or create a new one under `Config/`)
2. Add a public function with `@doc`, `@spec`, and a sensible default
3. Add a test in `test/claude_agent_sdk/config/`
4. Use the function in your module instead of a hardcoded value
5. Update this guide's quick reference table
