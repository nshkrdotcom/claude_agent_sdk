# Abort Signal Support Always None

- **What's missing:** The abort signal passed to callbacks (`can_use_tool`, hook callbacks) is always `None`. The SDK defines a `signal` field in `ToolPermissionContext` and `HookContext` but never populates it with a functional abort mechanism.

- **Evidence:**
  - `src/claude_agent_sdk/_internal/query.py:229-232`:
    ```python
    context = ToolPermissionContext(
        signal=None,  # TODO: Add abort signal support
        suggestions=permission_request.get("permission_suggestions", [])
        or [],
    )
    ```

  - `src/claude_agent_sdk/_internal/query.py:276`:
    ```python
    {"signal": None},  # TODO: Add abort signal support
    ```

  - `src/claude_agent_sdk/types.py:115`:
    ```python
    signal: Any | None = None  # Future: abort signal support
    ```

- **Impact:** Callback implementations cannot check if they should abort early. Long-running callbacks (e.g., permission decisions that require user input, complex hook logic) cannot be interrupted. This prevents cooperative cancellation patterns.

- **Proposed fix:**
  1. Create an `AbortSignal` class (or use `anyio.CancelScope`)
  2. Pass a live signal to callbacks that is triggered when:
     - The SDK receives a `control_cancel_request` for the associated request
     - The session is being closed
     - The CLI sends an interrupt
  3. Document how callbacks should check `signal.is_set()` for cooperative cancellation
  4. Consider using Python's `asyncio.CancelledError` semantics
