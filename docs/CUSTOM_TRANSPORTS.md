# Custom Transport Guide

Custom transport injection has been removed from `ClaudeAgentSDK.Client`,
`ClaudeAgentSDK.Query`, and the common CLI lane.

## What To Use Instead

- Use `ClaudeAgentSDK.Options.execution_surface` to select where Claude runs
  (local subprocess, static SSH, or other core-owned execution surfaces).
- Keep provider-specific Claude behavior in `claude_agent_sdk`.
- Add new transport or execution-surface families in `cli_subprocess_core`,
  then select them from the SDK through `execution_surface`.

## Example

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

ClaudeAgentSDK.query("Hello", opts) |> Enum.to_list()
```

## Control Client Boundary

`ClaudeAgentSDK.Client` now owns only Claude-specific control semantics:

- hooks
- permission callbacks
- SDK MCP routing
- provider-native message projection

The underlying session and channel lifecycle live in
`CliSubprocessCore.ProtocolSession`.
