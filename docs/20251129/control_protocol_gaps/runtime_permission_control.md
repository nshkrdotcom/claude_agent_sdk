# Runtime Permission Control Gap

- **What’s missing:** `ClaudeAgentSDK.Client.set_permission_mode/2` updates local state only and never sends a control request to the CLI, so live sessions cannot change permission mode after connect. The Python SDK issues a control request (`set_permission_mode`) through its `Query._send_control_request`.
- **Evidence (Python):** `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/client.py:95-150` calls `_query.set_permission_mode(mode)`, and `Query.set_permission_mode` forwards a `{"subtype": "set_permission_mode"}` control message (`_internal/query.py:176-207`).
- **Evidence (Elixir):** `lib/claude_agent_sdk/client.ex:290-311` validates the mode and mutates `state.options`, but there is no control request or CLI notification, so the running CLI never updates.
- **Impact:** Permission behavior cannot be toggled mid-session (`:default` ↔ `:accept_edits`/`:plan`/`:bypass_permissions`), breaking parity with Python’s ability to elevate or restrict tools dynamically.
- **Proposed fix:** Mirror the Python flow: encode and send a `set_permission_mode` control request, track pending responses, and update `current_permission_mode` from the response. Add tests to cover success/error cases and ensure queries started before the change honor the new mode.
