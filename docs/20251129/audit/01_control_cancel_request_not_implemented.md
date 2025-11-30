# Control Cancel Request Not Implemented

- **What's missing:** The `control_cancel_request` message type is received from the CLI but not handled. The SDK simply ignores these messages without providing any mechanism for callers to cancel pending control requests.

- **Evidence:**
  - `src/claude_agent_sdk/_internal/query.py:193-196`:
    ```python
    elif msg_type == "control_cancel_request":
        # Handle cancel requests
        # TODO: Implement cancellation support
        continue
    ```
  The message is consumed but no action is taken.

- **Impact:** Users cannot cancel in-flight control protocol requests. If a hook callback or permission callback takes too long, there is no way to interrupt it from the SDK side. The CLI may send cancel requests that the SDK silently ignores.

- **Proposed fix:**
  1. Add a `cancelled` flag or event to pending control requests in `Query`
  2. When `control_cancel_request` is received, mark the corresponding request as cancelled
  3. Propagate cancellation to in-flight callbacks (e.g., by raising a `CancelledError`)
  4. Document the cancellation behavior in the public API
