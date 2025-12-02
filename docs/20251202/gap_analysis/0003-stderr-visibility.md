# ADR 0003 — No stderr routing or callbacks in control client

- Status: Proposed
- Date: 2025-12-02

## Context
- Python streams CLI stderr to a caller-provided callback (or debug file) and only suppresses it when unused (`anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/transport/subprocess_cli.py:318-399`).
- Elixir’s control client appends `2>/dev/null` to every command and never surfaces stderr to the caller (`lib/claude_agent_sdk/client.ex:1186-1189`). There is no option to observe or log stderr when debugging hook/MCP sessions.

## Gap
- Developers cannot collect CLI diagnostics during control-protocol sessions, making it impossible to debug MCP startup errors, auth issues, or CLI regressions from Elixir.

## Consequences
- Failures that appear on stderr in Python (and are capturable via callbacks) are silently dropped in Elixir, slowing incident response and masking misconfigurations.

## Recommendation
- Add an `stderr` callback/IO target option for the control client (parity with Python), and stop unconditionally discarding stderr so users can opt into visibility.
