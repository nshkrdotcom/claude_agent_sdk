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

## Execution Surface Routing

Choose local vs SSH execution with `Options.execution_surface`:

```elixir
opts = %ClaudeAgentSDK.Options{
  execution_surface: [
    surface_kind: :static_ssh,
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
