# ADR 0002 — Control client ignores cwd/env/user/max buffer options

- Status: Proposed
- Date: 2025-12-02

## Context
- Python’s transport merges caller-provided env vars, sets `cwd`/`user`, and respects `max_buffer_size` when launching the CLI (`anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/transport/subprocess_cli.py:31-68` and `302-335`).
- The Elixir control path (`Client` + `Port.open/2`) always spawns with default OS env, no working-directory change, a hard-coded 64KB line limit, and no user switch (`lib/claude_agent_sdk/client.ex:1073-1088`). These options are only honored in the non-control `Process` runner.

## Gap
- When features force the control client (hooks, SDK MCP, permission callbacks, agents), callers cannot supply the env/cwd/user/buffer settings that Python supports.

## Consequences
- SDK MCP servers, plugins, or tools that depend on env secrets or a specific working directory fail under Elixir despite working in Python.
- Long JSON frames risk truncation because `max_buffer_size` is ignored in the control path.

## Recommendation
- Propagate `Options.env`, `cwd`, `user`, and `max_buffer_size` into the control transport (either by extending `Port.open/2` options or by reusing `Transport.Port` there) so control-mode behaviour matches the Python transport.
