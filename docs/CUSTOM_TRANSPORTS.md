# Custom Transport Guide

The new transport abstraction lets you decide where the SDK sends control frames. This guide shows how to build, configure, and test a custom transport module.

## 1. Implement the Behaviour

Create a module that implements `ClaudeAgentSDK.Transport`:

```elixir
defmodule MyApp.Transport.WebSocket do
  @behaviour ClaudeAgentSDK.Transport

  alias MyApp.Transport.WebSocket.State

  def start_link(opts) do
    WebSockex.start_link(opts[:url], __MODULE__, %State{subscribers: MapSet.new(), opts: opts})
  end

  def send(pid, message) do
    WebSockex.send_frame(pid, {:text, append_newline(message)})
  end

  def subscribe(pid, subscriber) do
    GenServer.call(pid, {:subscribe, subscriber})
  end

  def close(pid), do: WebSockex.close(pid)

  def status(pid), do: GenServer.call(pid, :status)

  defp append_newline(message) when is_binary(message) do
    if String.ends_with?(message, \"\\n\"), do: message, else: message <> \"\\n\"
  end
end
```

The callbacks should:

- **start_link/1** – boot whatever process manages your connection
- **send/2** – forward newline-terminated JSON strings to Claude (or your proxy)
- **subscribe/2** – register calling processes so they receive `{:transport_message, payload}` messages
- **close/1** – shut down gracefully
- **status/1** – expose a health indicator (connected/disconnected/error)

## 2. Start the Client with Your Transport

```elixir
{:ok, client} =
  ClaudeAgentSDK.Client.start_link(%ClaudeAgentSDK.Options{},
    transport: MyApp.Transport.WebSocket,
    transport_opts: [
      url: \"wss://my-edge.example.com/claude\",
      headers: [{\"authorization\", \"Bearer ...\"}]
    ]
  )
```

`transport_opts` is opaque to the SDK and is passed directly to your transport's `start_link/1`.

## 3. Testing Strategy

Use the provided mock transport for unit tests and your real transport for an integration smoke test. The `examples/runtime_control/transport_swap.exs` script showcases this pattern end-to-end with both fast and delayed transport configurations.

```elixir
defmodule MyApp.Transport.WebSocketTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.TestSupport.MockTransport

  test \"falls back to mock transport in test env\" do
    {:ok, client} =
      Client.start_link(%Options{},
        transport: MockTransport,
        transport_opts: [test_pid: self()]
      )

    :ok = GenServer.call(client, {:subscribe})
    MockTransport.push_message(self(), %{\"type\" => \"assistant\", \"message\" => %{\"content\" => \"hi\"}})
    assert_receive {:claude_message, %ClaudeAgentSDK.Message{type: :assistant}}
  end
```

For your WebSocket transport write a focused integration test that uses a local echo server or a controllable fake.

## 4. Pitfalls & Tips

- Always append a newline to outbound JSON to mirror the CLI protocol.
- When broadcasting inbound messages, send them as raw binaries; the client handles decoding.
- Make sure to handle `{:DOWN, _, :process, subscriber, _}` messages so dead subscribers are removed.
- Return `{:error, {:transport_failed, reason}}` from `start_link/1` if you cannot initialise the connection. This bubbles up to `Client.start_link/2`.
- Use the new `ClaudeAgentSDK.SupertesterCase.eventually/2` helper in tests to avoid `Process.sleep/1`.

## 5. Reference Implementation

See `ClaudeAgentSDK.Transport.Port` for a complete example of a transport module. It demonstrates:

- Port lifecycle management
- Broadcasting messages to subscribers
- Maintaining connection status
- Graceful shutdown semantics
