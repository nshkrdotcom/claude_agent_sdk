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

On CLI 2.1.203+ the CLI also emits the level-based
`system/background_tasks_changed` frame: the **full live task set** on every
membership change (an empty `tasks` list means the set drained), so consumers
can track background activity as state instead of stitching the edge frames.
`ClaudeAgentSDK.Message.live_background_tasks/1` returns the non-terminal
tasks from such a frame.

## Interrupts & Receipts

`ClaudeAgentSDK.Client.interrupt/1` returns a typed receipt
(CLI 2.1.205+, upstream `interrupt_receipt_v1`):

```elixir
{:ok, %ClaudeAgentSDK.InterruptReceipt{still_queued: still_queued}} =
  ClaudeAgentSDK.Client.interrupt(client)

# still_queued lists uuids of queued async messages that survive the
# interrupt — they WILL run unless cancelled first.
```

On CLIs that predate the receipt, the interrupt is still acknowledged and
`still_queued` is empty. Feature-detect from the `system/init` frame:

```elixir
ClaudeAgentSDK.Message.capability?(init_message, "interrupt_receipt_v1")
```

> Breaking change vs 0.17.x: `interrupt/1` previously returned a bare `:ok`.

## Command Lifecycle

On CLI 2.1.206+, every **uuid-stamped** inbound message emits top-level
`command_lifecycle` frames carrying its state (`queued` / `started` /
`completed` / `cancelled` / `discarded`), keyed by `command_uuid` (the
client-supplied message uuid; the frame's own `uuid` is the universal frame
id). Messages sent without a uuid — like the one-shot `-p` prompt path —
emit no lifecycle frames.

```elixir
%ClaudeAgentSDK.Message{type: :command_lifecycle, data: data} = msg
data.command_uuid  # which inbound message this is about
data.state         # "queued" | "started" | "completed" | "cancelled" | "discarded"
ClaudeAgentSDK.Message.command_terminal?(msg)  # true for the last three
```

A dead turn (see `Message.dead_turn?/1` in the error-handling guide) reports
its command lifecycle as `cancelled`, not `completed`.

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
