# Runtime Control Features

This guide explains how to use the runtime control capabilities introduced in `claude_agent_sdk` v0.5.0. With these additions you can change Claude models mid-session and swap out the communication transport without restarting your client process.

## Overview

- **Runtime Model Switching** – call `ClaudeAgentSDK.Client.set_model/2` to change the active model while preserving conversation context.
- **Transport Abstraction** – provide a module that implements `ClaudeAgentSDK.Transport` to customise how the SDK talks to the Claude CLI (or any future backend).
- **Deterministic Tests** – the new transport layer is fully mockable, making it simple to run acceptance tests without shelling out to the CLI.

## Runtime Boundary

- Common query and streaming transport ownership now lives in
  `cli_subprocess_core`.
- `ClaudeAgentSDK.Client` stays SDK-local only for the Claude control family:
  hooks, permissions, SDK MCP routing, and control request state.
- `ClaudeAgentSDK.Transport.Erlexec` is now a compatibility facade. It no
  longer owns subprocess lifecycle.

## ASM Extension Seam

`agent_session_manager` may offer an optional Claude extension seam under
`ASM.Extensions.ProviderSDK.Claude`, but that seam is only a bridge.

It can:

- derive `ClaudeAgentSDK.Options` from ASM-style config
- start `ClaudeAgentSDK.Client` from ASM config or session defaults

ASM-owned fields such as `cwd`, `permission_mode`, `model`, `max_turns`, and
the transport timeout still stay in ASM config. The optional native override
bag is only for Claude-native settings.

It does not redefine any control semantics.

The actual control family remains here in `claude_agent_sdk`:

- `ClaudeAgentSDK.Client`
- `ClaudeAgentSDK.ControlProtocol.Protocol`
- `ClaudeAgentSDK.Hooks`
- `ClaudeAgentSDK.Permission`

## Quick Start

```elixir
{:ok, client} =
  ClaudeAgentSDK.Client.start_link(%ClaudeAgentSDK.Options{
    model: "claude-sonnet-4"
  })

# ... exchange messages ...

:ok = ClaudeAgentSDK.Client.set_model(client, "opus")
# model now set to "claude-opus-4-20250514" without dropping context
```

`set_model/2` accepts either short model names (`"opus"`, `"sonnet"`, `"haiku"`) or fully-qualified versions (e.g. `"claude-opus-4-20250514"`). The helper normalises the value and validates that the SDK knows how to talk to the requested model before sending the control protocol request.

### Hands-on Examples

Run the ready-made scripts to see these flows in action:

```bash
mix run examples/runtime_control/model_switcher.exs
mix run examples/runtime_control/transport_swap.exs
mix run examples/runtime_control/subscriber_broadcast.exs
```

Each script defaults to the deterministic mock transport and accepts `--live` to attempt real CLI interaction once `claude login` has been configured.

### Handling Errors

```elixir
case ClaudeAgentSDK.Client.set_model(client, "unknown") do
  :ok ->
    :ok

  {:error, {:invalid_model, suggestions}} ->
    Logger.warning("Try one of: #{Enum.join(suggestions, \", \")}")

  {:error, reason} ->
    Logger.error("Failed to switch model: #{inspect(reason)}")
end
```

Errors can originate from local validation (invalid model name) or from the CLI itself (for example if a paid tier is required). The response includes the failure reason surfaced by the control protocol.

Transport implementations now normalize low-level failures as:

```elixir
{:error, {:transport, reason}}
```

Examples include `{:error, {:transport, :not_connected}}`, `{:error, {:transport, :timeout}}`, and `{:error, {:transport, {:send_failed, detail}}}`.

### Inspecting the Current Model

```elixir
with {:ok, model} <- ClaudeAgentSDK.Client.get_model(client) do
  IO.puts("Currently using #{model}")
end
```

`get_model/1` returns `{:ok, model}` after the client initialises. If the CLI has not answered the initialise request yet you may receive `{:error, :model_not_set}` – simply retry after you receive the first system message.

## Transport Abstraction

Every client now delegates IO to a transport module. The default built-in path
uses `CliSubprocessCore.Transport` directly, while
`ClaudeAgentSDK.Transport.Erlexec` remains available for legacy callers that
still want the old SDK-local module name.

```elixir
{:ok, client} =
  ClaudeAgentSDK.Client.start_link(%ClaudeAgentSDK.Options{},
    transport: MyApp.Transport.WebSocket,
    transport_opts: [url: "wss://...", headers: ...]
  )
```

A custom transport module must implement the `ClaudeAgentSDK.Transport`
behaviour:

```elixir
defmodule MyApp.Transport.WebSocket do
  @behaviour ClaudeAgentSDK.Transport

  def start_link(opts), do: WebSockex.start_link(opts[:url], __MODULE__, opts)
  def send(pid, payload), do: WebSockex.send_frame(pid, {:text, ensure_newline(payload)})
  def subscribe(pid, subscriber), do: GenServer.call(pid, {:subscribe, subscriber})
  def close(pid), do: WebSockex.close(pid)
  def status(pid), do: WebSockex.state(pid)
end
```

The SDK expects newline-terminated JSON frames for CLI compatibility. Ensure outbound payloads end with a newline character to avoid protocol mismatches.

### Writing Tests with the Mock Transport

We ship a deterministic `ClaudeAgentSDK.TestSupport.MockTransport` for tests. It records outgoing payloads and lets you inject synthetic CLI messages:

```elixir
{:ok, client} =
  Client.start_link(%Options{},
    transport: ClaudeAgentSDK.TestSupport.MockTransport,
    transport_opts: [test_pid: self()]
  )

:ok = GenServer.call(client, {:subscribe})
MockTransport.push_message(transport_pid, Jason.encode!(%{"type" => "assistant", ...}))

assert_receive {:claude_message, %ClaudeAgentSDK.Message{type: :assistant}}
```

This pattern removes the need for sleep-based synchronisation in your test suite.

## Control Protocol Additions

The control protocol gained two functions:

- `ClaudeAgentSDK.ControlProtocol.Protocol.encode_set_model_request/2`
- `ClaudeAgentSDK.ControlProtocol.Protocol.decode_set_model_response/1`

These helpers keep the transport layer simple and make it easy to write integration tests that assert on raw JSON frames.

## Migration Notes

- Applications that previously held onto the client port should now treat the transport as an opaque module. Use `Client.stop/1` to trigger a graceful shutdown.
- `Client.start_link/2` accepts an optional keyword list with `:transport` and `:transport_opts`. Existing code that only passes `%Options{}` now defaults to the shared-core transport lane automatically.
- Tests that previously called the CLI directly should be switched to the mock transport to benefit from deterministic messaging. See `test/support/mock_transport.ex` for reference.
