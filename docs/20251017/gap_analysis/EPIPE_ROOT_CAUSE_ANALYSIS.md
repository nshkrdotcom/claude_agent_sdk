# EPIPE Error Root Cause Analysis

**Date:** 2025-10-17
**Issue:** Examples/v0_4_0/agent_switching.exs produces EPIPE error
**Severity:** MEDIUM - Cosmetic but indicates design issue
**Status:** ROOT CAUSE IDENTIFIED

---

## Problem Statement

The `agent_switching.exs` example completes successfully but produces an EPIPE error from the Node.js Claude CLI:

```
✅ Agent Switching example complete!
...
Error: write EPIPE
    at afterWriteDispatched (node:internal/stream_base_commons:159:15)
    ...
    at Socket._writeGeneric (node:net:966:11)
```

---

## Investigation Timeline

### Observation 1: Timing Analysis

```
17:29:58.034 [debug] Sent initialize request
17:29:58.143 [debug] Terminating client  (109ms later)
Error: write EPIPE
```

The Client terminates only **109ms** after starting!

### Observation 2: Example Behavior

```elixir
# agent_switching.exs does:
{:ok, client} = Client.start_link(options)  # Starts CLI subprocess
:ok = Client.set_agent(client, :researcher) # Local operation (no CLI)
:ok = Client.set_agent(client, :technical_writer) # Local operation
Client.stop(client)  # Terminates immediately
```

**Key insight:** The example performs ONLY local operations (agent switching is GenServer state management), never sends any user messages to Claude!

### Observation 3: What Actually Happens

1. `Client.start_link` starts the CLI subprocess
2. Initialize request sent to CLI (control protocol handshake)
3. **CLI starts processing initialize request**
4. Meanwhile, example does agent switching (these are GenServer calls, not CLI operations)
5. Example finishes and calls `Client.stop`
6. `Client.terminate` is called
7. **Port.close() closes all pipes immediately**
8. CLI finishes processing initialize and tries to write response
9. **Pipe is already closed → EPIPE error**

---

## Root Cause

**The example starts a full Claude CLI subprocess but doesn't actually need it!**

Agent switching operations are entirely local:
- `Client.set_agent/2` updates GenServer state
- `Client.get_agent/1` reads GenServer state
- `Client.get_available_agents/1` reads from options

None of these operations require the CLI subprocess to be running. The CLI is only needed for actual Claude queries.

### Why This Happens

The `Client.start_link/1` **unconditionally starts the CLI subprocess** in the `:start_cli` continuation, even if no queries will be sent. This is wasteful and causes EPIPE when the client is immediately stopped.

### Secondary Issue: Abrupt Port Closing

The `Client.terminate/2` function calls `Port.close(port)` which:
1. Immediately closes stdin, stdout, stderr
2. Doesn't wait for the subprocess to finish
3. Causes EPIPE if subprocess is still writing

Python SDK avoids this by:
```python
await self._stdin_stream.aclose()  # Close stdin (sends EOF)
self._process.terminate()           # Send SIGTERM
await self._process.wait()          # Wait for clean exit
```

---

## Solutions

### Solution A: Don't Start CLI for Agent-Only Operations (BEST)

Modify `Client.start_link` to support a "no-cli" mode for examples that only use local operations:

```elixir
# In agent_switching.exs:
options = Options.new(
  agents: agents,
  agent: :code_expert,
  skip_cli_start: true  # NEW FLAG
)

# In Client.init:
defp init(%Options{skip_cli_start: true} = options) do
  # Don't start CLI, just initialize state
  state = %{
    port: nil,  # No CLI process
    options: options,
    # ... rest of state
  }
  {:ok, state}  # No :continue callback
end
```

**Pros:**
- No unnecessary subprocess
- No EPIPE errors
- Faster and more efficient
- Clear separation of concerns

**Cons:**
- Requires API change (new option)
- Examples need updating

### Solution B: Wait for CLI Exit in Terminate (PARTIAL FIX)

Make `terminate` wait for the process to exit before closing port:

```elixir
def terminate(reason, %{port: port}) when is_port(port) do
  # Wait for CLI to exit naturally
  receive do
    {^port, {:exit_status, _}} -> :ok
  after
    500 -> :ok  # Timeout and force close
  end

  Port.close(port)
  :ok
end
```

**Pros:**
- No API changes needed
- Reduces EPIPE occurrence

**Cons:**
- Doesn't fix root cause (unnecessary CLI start)
- Still wasteful to start CLI for non-query operations
- May not work if exit_status already handled

### Solution C: Lazy CLI Start (BEST LONG-TERM)

Start CLI only when first message is sent:

```elixir
def handle_call({:send_message, msg}, from, %{port: nil} = state) do
  # No CLI yet, start it now
  case start_cli_process(state) do
    {:ok, new_state} ->
      # Now send the message
      handle_call({:send_message, msg}, from, new_state)

    {:error, reason} ->
      {:reply, {:error, reason}, state}
  end
end
```

**Pros:**
- CLI only started when actually needed
- No wasted resources
- No EPIPE for agent-only examples
- Transparent to users

**Cons:**
- More complex initialization logic
- First message might be slower

---

## Recommended Fix

**Immediate (v0.5.1):** Solution B (wait for exit)
- Low risk
- Reduces EPIPE errors
- No API changes

**Long-term (v0.6.0):** Solution C (lazy CLI start)
- Proper architectural fix
- Eliminates waste
- Better user experience

---

## Testing the Fix

### Before Fix:
```bash
$ mix run examples/v0_4_0/agent_switching.exs 2>&1 | tail -5
✅ Agent Switching example complete!
...
Error: write EPIPE
  errno: -32,
  code: 'EPIPE',
```

### After Fix:
```bash
$ mix run examples/v0_4_0/agent_switching.exs 2>&1 | tail -5
✅ Agent Switching example complete!
...
# No EPIPE error
```

---

## Impact Assessment

### Current Impact

**Severity: LOW**
- Examples complete successfully
- All functionality works
- Only cosmetic error message
- Doesn't affect production usage (queries work fine)

**User Impact:**
- Confusing error message at end of examples
- Looks like something is broken (even though it's not)
- Reduces confidence in the SDK

### After Fix

- Clean example output
- No confusing errors
- More efficient (no unnecessary CLI starts)

---

## Implementation Plan

### Phase 1: Immediate Fix (v0.5.1 - 1 hour)

1. Update `Client.terminate/2` to suppress stderr from CLI
2. Or redirect stderr to /dev/null during port close
3. Test with all examples

### Phase 2: Proper Fix (v0.6.0 - 1 day)

1. Implement lazy CLI start
2. Add `skip_cli_start` option for testing
3. Update examples to not start CLI unnecessarily
4. Comprehensive testing

---

## Simpler Workaround for Examples

Instead of fixing the Client, fix the examples to not start the CLI:

```elixir
# Current (starts CLI unnecessarily):
{:ok, client} = Client.start_link(options)
Client.set_agent(client, :researcher)
Client.stop(client)

# Fixed (demonstrate without starting CLI):
# Just show the configuration, don't start Client
IO.puts("Agent configuration:")
IO.puts("  - Active: #{options.agent}")
IO.puts("  - Available: #{Map.keys(options.agents)}")
IO.puts("\nIn live mode with actual queries:")
IO.puts("  Client.set_agent(client, :researcher) would switch agents")
```

**This is the simplest fix for v0.5.1.**

---

## Conclusion

### Root Cause

**EPIPE occurs because:**
1. Examples start Client (which starts CLI subprocess)
2. Examples only do local operations (no Claude queries)
3. Examples immediately stop Client
4. Client.terminate closes port while CLI is still initializing
5. CLI tries to write initialize response to closed pipe → EPIPE

### The Real Issue

**The example is using the wrong pattern.** Agent switching doesn't require a running CLI - it's just updating GenServer state. The example should either:
- **Option 1:** Don't start the Client at all (just show configuration)
- **Option 2:** Send an actual query to Claude to demonstrate agents in action
- **Option 3:** Use a mock Client that doesn't start the subprocess

### Recommended Action

**For v0.5.1:**
- Update `agent_switching.exs` to not start the Client
- Just demonstrate the configuration
- Add note: "For live agent switching, see `agents_live.exs`"

**For v0.6.0:**
- Implement lazy CLI start
- CLI only starts when first message is sent
- Prevents EPIPE in all similar cases

---

**Status: ROOT CAUSE IDENTIFIED - Ready to implement fix**
