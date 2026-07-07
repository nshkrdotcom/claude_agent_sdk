# Runtime Control Features

This guide covers the runtime control features that remain SDK-local after the
CLI runtime cutover.

## What The Client Owns

`ClaudeAgentSDK.Client` now sits above `CliSubprocessCore.ProtocolSession` and
keeps only Claude-specific control behavior:

- initialize handshake shaping
- runtime model switching
- hook callback execution
- permission callback execution
- SDK MCP routing
- Claude message and `stream_event` projection

The client no longer accepts custom transport injection and it no longer owns
subprocess lifecycle directly.

## Runtime Model Switching

```elixir
{:ok, client} =
  ClaudeAgentSDK.Client.start_link(%ClaudeAgentSDK.Options{
    model: "claude-sonnet-4"
  })

:ok = ClaudeAgentSDK.Client.set_model(client, "opus")
```

## Background Tasks & MCP Server Control

The client exposes control-protocol operations for managing in-flight work and
MCP servers at runtime:

```elixir
# Stop a background task by id. A task that is already gone (not_found /
# not_running) is reported as success by the CLI so stale task chips prune cleanly.
:ok = ClaudeAgentSDK.Client.stop_task(client, task_id)

# Reconnect an MCP server by name.
:ok = ClaudeAgentSDK.Client.reconnect_mcp_server(client, "github")

# Enable or disable an MCP server at runtime.
:ok = ClaudeAgentSDK.Client.toggle_mcp_server(client, "github", false)
```

Background task lifecycle is surfaced as `system` messages: `task_started`,
`task_progress`, `task_notification`, and the typed `task_updated`. Use
`ClaudeAgentSDK.Message.terminal_task_status?/1` to detect a terminal status
(`completed` / `failed` / `stopped` / `killed`) from either the notification or
the `task_updated` frame when tracking active tasks.

## Execution Surface Routing

Choose local vs SSH execution with `Options.execution_surface`:

```elixir
opts = %ClaudeAgentSDK.Options{
  execution_surface: [
    surface_kind: :ssh_exec,
    transport_options: [
      destination: "claude.example",
      user: "sdk",
      port: 22
    ]
  ]
}

{:ok, client} = ClaudeAgentSDK.Client.start_link(opts)
```

## Error Notes

- Local validation failures are returned before the client starts.
- Control requests preserve typed SDK errors such as `:timeout` and
  `{:protocol_session_down, reason}`.
- CLI-declared control errors still come back as provider strings from the
  control protocol.
