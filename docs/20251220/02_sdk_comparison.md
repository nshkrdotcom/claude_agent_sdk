# Python vs Elixir SDK Comparison

**Date**: 2025-12-20
**Python SDK Version**: v0.1.18 (commit 3eb12c5)
**Elixir SDK Version**: v0.6.7 → v0.6.8

## Feature Parity Matrix

| Feature | Python SDK | Elixir SDK | Parity |
|---------|------------|------------|--------|
| **Core API** | | | |
| One-shot query | `query()` | `ClaudeAgentSDK.query/2` | Full |
| Bidirectional client | `ClaudeSDKClient` | `ClaudeAgentSDK.Client` | Full |
| Streaming | `async for event` | `Stream` pipeline | Full |
| **Options** | | | |
| Model selection | `model`, `fallback_model` | `model`, `fallback_model` | Full |
| System prompt | `system_prompt` (dict) | `system_prompt` (map/string) | Full |
| Session management | `session_id`, `resume`, `fork_session` | `session_id`, `resume`, `fork_session` | Full |
| Working directories | `cwd`, `add_dirs` | `cwd`, `add_dirs` | Full |
| Allowed tools | `allowed_tools` | `allowed_tools` | Full |
| Tools selection | `tools` | `tools` | Full |
| Betas | `betas` | `betas` | Full |
| Permission mode | `permission_mode` | `permission_mode` | Full |
| Budget | `max_budget_usd` | `max_budget_usd` | Full |
| Thinking tokens | `max_thinking_tokens` | `max_thinking_tokens` | Full |
| MCP config | `mcp_config` | `mcp_config` | Full |
| Plugins | `plugins` | `plugins` | Full |
| Settings sources | `setting_sources` | `setting_sources` | Full |
| Custom settings | `settings` | `settings` | Full |
| Agents | `agents` | `agents` | Full |
| Env variables | `env` | `env` | Full |
| User override | (n/a - Windows only) | `user` (via erlexec) | N/A |
| **Hooks** | | | |
| Pre-tool-use | `pre_tool_use` | `:pre_tool_use` | Full |
| Post-tool-use | `post_tool_use` | `:post_tool_use` | Full |
| User prompt submit | `user_prompt_submit` | `:user_prompt_submit` | Full |
| Stop | `stop` | `:stop` | Full |
| Subagent stop | `subagent_stop` | `:subagent_stop` | Full |
| Pre-compact | `pre_compact` | `:pre_compact` | Full |
| **Permissions** | | | |
| Permission callback | `on_permission_request` | `can_use_tool` callback | Full |
| Permission modes | 4 modes | 4 modes | Full |
| **SDK MCP Servers** | | | |
| In-process MCP | `@mcp_tool` decorator | `deftool` macro | Full |
| Tool registry | Internal | `Tool.Registry` | Full |
| **File Checkpointing** | | | |
| Enable checkpointing | `enable_file_checkpointing` | `enable_file_checkpointing` | Full |
| Rewind files | `rewind_files()` | `Client.rewind_files/2` | Full |
| Message UUID | `uuid` field | `Message.user_uuid/1` | Full |
| **Transport** | | | |
| Subprocess management | `subprocess_cli.py` | `Transport.Port` | Full |
| Write locking | `asyncio.Lock` | GenServer serialization | Full |
| Stderr callback | `stderr_callback` | `stderr_callback` | Full |
| CLI discovery | `_find_cli()` | `CLI.find_executable/0` | Full |
| CLI version check | `MINIMUM_VERSION` | `@minimum_version` | Full |
| Skip version check | `SKIP_VERSION_CHECK` env | `SKIP_VERSION_CHECK` env | Full |
| **CLI Version Tracking** | | | |
| Recommended version | `__cli_version__` (2.0.74) | `@recommended_version` (2.0.72 → 2.0.74) | Full after port |
| **Structured Outputs** | | | |
| JSON schema | `json_schema` | `json_schema` | Full |
| Output parsing | `structured_output` | `structured_output` | Full |

## Version Mapping

| Python Version | Elixir Version | Key Features |
|----------------|----------------|--------------|
| v0.1.18 | v0.6.7 → v0.6.8 | CLI version 2.0.74 |
| v0.1.17 | v0.6.7 | Message UUID, CLI 2.0.72 |
| v0.1.16 | v0.6.5 | Error field parsing |
| v0.1.15 | v0.6.5 | File checkpointing |
| v0.1.14 | v0.6.5 | CLI bumps |
| v0.1.13 | v0.6.6 | Error propagation, write locks |
| v0.1.12 | v0.6.5 | Tools option, betas |

## Architecture Comparison

### Python SDK Architecture

```
claude_agent_sdk/
├── __init__.py          # Public API exports
├── types.py             # Type definitions (Options, Messages, etc.)
├── query.py             # query() function wrapper
├── client.py            # ClaudeSDKClient class wrapper
├── _errors.py           # Error types
├── _cli_version.py      # CLI version constant
└── _internal/
    ├── client.py        # Internal client implementation
    ├── query.py         # Internal query implementation
    ├── message_parser.py # Message parsing logic
    └── transport/
        ├── __init__.py  # Transport protocol
        └── subprocess_cli.py # CLI subprocess management
```

### Elixir SDK Architecture

```
lib/claude_agent_sdk/
├── claude_agent_sdk.ex   # Public API (query/2, etc.)
├── options.ex            # Options struct
├── message.ex            # Message types
├── cli.ex                # CLI discovery & version
├── errors.ex             # Error structs
├── client.ex             # GenServer client
├── query.ex              # Query implementation
├── process.ex            # Subprocess via erlexec
├── streaming/
│   ├── streaming.ex      # Streaming API
│   ├── session.ex        # Session GenServer
│   └── event_parser.ex   # SSE event parsing
├── transport/
│   └── port.ex           # Port-based transport
├── control_protocol/
│   └── protocol.ex       # Control message encoding
├── hooks/
│   ├── hooks.ex          # Hook types
│   ├── matcher.ex        # Pattern matching
│   ├── output.ex         # Hook output helpers
│   └── registry.ex       # Callback registry
├── permission.ex          # Permission types
└── tool.ex               # MCP tool macros
```

## Key Differences

### 1. Concurrency Model

| Aspect | Python | Elixir |
|--------|--------|--------|
| Runtime | asyncio/anyio | BEAM/OTP |
| Client | async/await | GenServer |
| Streaming | async generator | Stream |
| Locking | asyncio.Lock | GenServer serialization |

### 2. Type System

| Aspect | Python | Elixir |
|--------|--------|--------|
| Types | Pydantic/TypedDict | Structs + typespecs |
| Validation | Runtime (Pydantic) | Compile-time (Dialyzer) |
| Union types | `Union[A, B]` | `a() | b()` |

### 3. Error Handling

| Aspect | Python | Elixir |
|--------|--------|--------|
| Exceptions | Class-based | Exception structs |
| Return types | Optional exceptions | `{:ok, _} | {:error, _}` |
| Pattern | try/except | Tagged tuples |

## Conclusion

The Elixir SDK maintains feature parity with the Python SDK while leveraging Elixir/OTP idioms:

- GenServer for state management (vs async classes)
- Streams for lazy evaluation (vs async generators)
- Typespecs for static analysis (vs Pydantic)
- Supervision trees for fault tolerance
- ETS for caching (SessionStore)

After this port (v0.6.8), the Elixir SDK will be fully aligned with Python SDK v0.1.18.
