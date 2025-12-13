# Write Lock for Concurrent Transport Writes

**PR**: #391
**Commit**: 2d67166
**Author**: Carlos Cuevas
**Priority**: Medium

## Overview

This fix adds a write lock to `SubprocessCLITransport` to prevent concurrent writes from parallel subagents. In Python's async model (using Trio), concurrent writes to a stream cause `BusyResourceError`.

## Problem

When multiple subagents run in parallel and invoke MCP tools, the CLI sends concurrent `control_request` messages. Each handler tries to write a response back to the subprocess stdin at the same time. Trio's `TextSendStream` isn't thread-safe for concurrent access.

## Python Implementation

### Transport (`subprocess_cli.py`)

```python
class SubprocessCLITransport(Transport):
    def __init__(self, ...):
        # ...
        self._write_lock: anyio.Lock = anyio.Lock()

    async def close(self) -> None:
        """Close the transport and clean up resources."""
        # ... cleanup temp files ...

        if not self._process:
            self._ready = False
            return

        # ... close stderr task group ...

        # Close stdin stream (acquire lock to prevent race with concurrent writes)
        async with self._write_lock:
            self._ready = False  # Set inside lock to prevent TOCTOU with write()
            if self._stdin_stream:
                with suppress(Exception):
                    await self._stdin_stream.aclose()
                self._stdin_stream = None

        # ... rest of cleanup ...

    async def write(self, data: str) -> None:
        """Write raw data to the transport."""
        async with self._write_lock:
            # All checks inside lock to prevent TOCTOU races with close()/end_input()
            if not self._ready or not self._stdin_stream:
                raise CLIConnectionError("ProcessTransport is not ready for writing")

            if self._process and self._process.returncode is not None:
                raise CLIConnectionError(
                    f"Cannot write to terminated process (exit code: {self._process.returncode})"
                )

            if self._exit_error:
                raise CLIConnectionError(
                    f"Cannot write to process that exited with error: {self._exit_error}"
                ) from self._exit_error

            try:
                await self._stdin_stream.send(data)
            except Exception as e:
                self._ready = False
                self._exit_error = CLIConnectionError(
                    f"Failed to write to process stdin: {e}"
                )
                raise self._exit_error from e

    async def end_input(self) -> None:
        """End the input stream (close stdin)."""
        async with self._write_lock:
            if self._stdin_stream:
                with suppress(Exception):
                    await self._stdin_stream.aclose()
                self._stdin_stream = None
```

## Elixir Considerations

### Does Elixir Need This?

**Maybe not in the same way.** The concurrency models differ significantly:

| Aspect | Python (Trio/anyio) | Elixir (BEAM) |
|--------|---------------------|---------------|
| Concurrency | Async/await tasks | Processes with mailboxes |
| Shared state | Shared in-memory | Process isolation |
| Race conditions | Common with shared streams | Serialized via GenServer |
| Write ordering | Manual lock needed | GenServer serializes calls |

### Current Elixir Architecture

The Elixir SDK uses `GenServer` pattern in `ClaudeAgentSDK.Client`:

```elixir
# All writes go through GenServer calls, which are serialized
defp send_payload(%{port: port}, payload) when is_port(port) do
  try do
    Port.command(port, ensure_newline(payload))
    :ok
  rescue
    e -> {:error, e}
  end
end
```

**Key insight**: Since all operations on the transport go through a single GenServer process, writes are already serialized. The mailbox pattern provides implicit locking.

### Potential Issue

If the Elixir SDK uses the `StreamingRouter` or `Transport.Port` with multiple concurrent callers, there could be issues. Check:

1. `lib/claude_agent_sdk/transport/port.ex` - Is it GenServer-based?
2. `lib/claude_agent_sdk/transport/streaming_router.ex` - Are writes serialized?

### If a Lock IS Needed

In Elixir, use a GenServer's inherent serialization, or if you need explicit locking:

```elixir
defmodule ClaudeAgentSDK.Transport.Port do
  use GenServer

  @impl true
  def init(opts) do
    {:ok, %{port: nil, ready: false}}
  end

  @impl true
  def handle_call({:write, data}, _from, %{port: port, ready: true} = state)
      when is_port(port) do
    # GenServer handles serialization - only one handle_call at a time
    case Port.command(port, data) do
      true -> {:reply, :ok, state}
      false -> {:reply, {:error, :write_failed}, state}
    end
  end

  def handle_call({:write, _data}, _from, state) do
    {:reply, {:error, :not_ready}, state}
  end

  @impl true
  def handle_call(:close, _from, %{port: port} = state) when is_port(port) do
    # Closing also serialized - no TOCTOU race
    Port.close(port)
    {:reply, :ok, %{state | port: nil, ready: false}}
  end
end
```

### Alternative: Mutex for Non-GenServer Code

If you have code outside a GenServer that needs protection:

```elixir
defmodule ClaudeAgentSDK.WriteLock do
  @moduledoc """
  Simple mutex implementation for write serialization.
  Only needed if writes occur outside GenServer serialization.
  """

  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> :unlocked end, name: __MODULE__)
  end

  def with_lock(fun) do
    # Acquire lock
    case Agent.get_and_update(__MODULE__, fn
      :unlocked -> {:ok, :locked}
      :locked -> {:busy, :locked}
    end) do
      :ok ->
        try do
          fun.()
        after
          Agent.update(__MODULE__, fn _ -> :unlocked end)
        end

      :busy ->
        # Wait and retry
        Process.sleep(10)
        with_lock(fun)
    end
  end
end
```

## Tests (If Implementing)

```elixir
describe "concurrent write serialization" do
  test "concurrent writes are serialized" do
    {:ok, transport} = Transport.Port.start_link([])

    # Spawn multiple concurrent writers
    tasks =
      for i <- 1..10 do
        Task.async(fn ->
          Transport.Port.write(transport, "message_#{i}\n")
        end)
      end

    # All should succeed (serialized, not concurrent)
    results = Task.await_many(tasks, 5000)
    assert Enum.all?(results, &(&1 == :ok))
  end
end
```

## Recommendation

**Verify first**: Check if the current Elixir implementation already handles this via GenServer serialization.

1. Review `ClaudeAgentSDK.Client.send_payload/2` - Are all writes through `handle_call`?
2. Review `Transport.Port` - Is it a GenServer?
3. Review hook callback handling - Are responses serialized?

If all writes go through GenServer handlers, **no additional lock is needed** - Elixir's actor model provides this for free.

If there are code paths that bypass GenServer (direct port writes), then add serialization.

## Notes

1. Python's issue stems from shared mutable state with async/await
2. Elixir's actor model naturally avoids most of these issues
3. The "TOCTOU" (time-of-check-time-of-use) race in Python happens because async code can yield between checking state and using it
4. In GenServer, each `handle_call` is atomic - no yields between check and use
5. Only implement explicit locking if you identify a non-serialized code path
