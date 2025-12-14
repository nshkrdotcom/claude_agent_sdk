# Python → Elixir Parity Audit: Recent Features (0.1.10+) Gaps

---

Gap: “Faster error handling” for pending control requests (no indefinite waits)

Python Location: `anthropics/claude-agent-sdk-python/CHANGELOG.md:31-34`, `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/query.py:339-385`

Python Code:
```md
- **Faster error handling**: CLI errors (e.g., invalid session ID) now propagate to pending requests immediately instead of waiting for the 60-second timeout (#388)
```

```py
with anyio.fail_after(timeout):
    await event.wait()
...
except TimeoutError as e:
    raise Exception(f"Control request timeout: {request.get('subtype')}") from e
```

Elixir Status: Partial

Elixir Location: `lib/claude_agent_sdk/client.ex:1295` (pending request map with no general timeout handling), `lib/claude_agent_sdk/client.ex:897-906` (CLI exit stops the GenServer without replying to pending requests)

Priority: High

Suggested Implementation:
Implement per-request timeouts for all control requests and ensure that CLI exit/transport failure replies to all in-flight `GenServer.call/3` waiters with structured errors rather than crashing callers.

Complexity: Moderate

