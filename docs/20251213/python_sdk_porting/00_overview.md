# Python SDK Changes Overview (d553184..f834ba9)

## Summary

This document outlines the changes in the Python `claude-agent-sdk` between commits `d553184` and `f834ba9` (v0.1.11 to v0.1.16) and provides guidance for porting them to the Elixir SDK.

## Release Timeline

| Version | Notable Changes |
|---------|-----------------|
| v0.1.11 | ARM64 Linux bundle, SDK MCP stdin fix, Pydantic 2.12+ fixes |
| v0.1.12 | **Tools option**, **SDK Beta support**, **Write lock for concurrent transport writes**, fail-fast pending control requests on CLI error |
| v0.1.13 | CLI version bumps |
| v0.1.14 | CLI version bumps |
| v0.1.15 | **File checkpointing and rewind_files support** |
| v0.1.16 | **Rate limit detection fix** |

## Key Features to Port

### High Priority (New Features)

1. **Tools Option** - Controls base set of available tools (PR #389)
   - See: [01_tools_option.md](./01_tools_option.md)

2. **SDK Beta Support** - Beta feature flags like 1M context window (PR #390)
   - See: [02_sdk_beta.md](./02_sdk_beta.md)

3. **File Checkpointing & Rewind** - Track and rewind file changes (PR #395)
   - See: [03_file_checkpointing.md](./03_file_checkpointing.md)

### Medium Priority (Bug Fixes)

4. **Rate Limit Detection** - Parse error field in AssistantMessage (PR #405)
   - See: [04_rate_limit_detection.md](./04_rate_limit_detection.md)

5. **Write Lock for Concurrent Transport Writes** - Prevent race conditions (PR #391)
   - See: [05_write_lock.md](./05_write_lock.md)

### Lower Priority

6. **Sandbox Adapter Interface** - Programmatic sandbox configuration (PR #363)
   - See: [06_sandbox_adapter.md](./06_sandbox_adapter.md)

## Elixir SDK Current State

The Elixir SDK has the following relevant modules:

| Module | Purpose | Relevance |
|--------|---------|-----------|
| `ClaudeAgentSDK.Options` | Configuration struct | Add new options fields |
| `ClaudeAgentSDK.Client` | Bidirectional client | Add rewind_files method |
| `ClaudeAgentSDK.Message` | Message parsing | Rate limit detection |
| `ClaudeAgentSDK.Process` | CLI subprocess | Environment variables |
| `ClaudeAgentSDK.ControlProtocol.Protocol` | Control protocol | Add rewind_files request |
| `ClaudeAgentSDK.Transport.Port` | Port transport | Write lock (if needed) |

## Implementation Order

Recommended order based on dependencies:

1. **Rate limit detection** - Small, independent fix
2. **Tools option** - Independent, CLI flag addition
3. **SDK beta support** - Independent, CLI flag addition
4. **Sandbox adapter** - Requires `--settings` merge logic (Elixir currently passes `settings` through without merging)
5. **File checkpointing** - Requires control protocol changes
6. **Write lock** - Elixir/OTP may handle this differently

## Files Changed in Python SDK

```
.github/workflows/publish.yml                      |   6 +-
CHANGELOG.md                                       |  54 ++++
README.md                                          |   4 +-
examples/tools_option.py                           | 111 +++++++
pyproject.toml                                     |   2 +-
src/claude_agent_sdk/__init__.py                   |  14 +-
src/claude_agent_sdk/_cli_version.py               |   2 +-
src/claude_agent_sdk/_internal/message_parser.py   |   1 +
src/claude_agent_sdk/_internal/query.py            |  56 +++-
src/claude_agent_sdk/_internal/transport/subprocess_cli.py | 151 +++++++---
src/claude_agent_sdk/_version.py                   |   2 +-
src/claude_agent_sdk/client.py                     |  27 ++
src/claude_agent_sdk/types.py                      | 107 +++++++
tests/test_transport.py                            | 326 +++++++++++++++++++++
```

## Audit Notes

This doc set focuses on PRs #363, #389, #390, #391, #395, and #405, but the Python range includes a couple additional behavior changes worth double-checking in the Elixir port:

1. **SDK MCP stdin closure / stream lifecycle** (`a2f24a3`, PR #380)
   - Python `Query.stream_input/1` now waits for the first `result` message before closing stdin when SDK MCP servers or hooks are present (env var: `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT`).
   - The Elixir SDK routes SDK MCP + hooks through `ClaudeAgentSDK.Query.ClientStream` / `ClaudeAgentSDK.Client`, which likely avoids this entire class of issue, but confirm there is no premature stdin/port shutdown in control mode.

2. **Fail-fast pending control requests on CLI exit** (`69a310c`, PR #388)
   - Python signals all pending control requests when the message reader hits a fatal error so callers don’t wait for a long timeout.
   - In Elixir, confirm `ClaudeAgentSDK.Client` callers waiting on `pending_requests` fail promptly (and preferably with a useful error) when the CLI exits unexpectedly.
