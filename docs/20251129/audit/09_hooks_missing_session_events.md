# Hooks Missing SessionStart, SessionEnd, and Notification Events

- **What's missing:** The Python SDK hook system explicitly does not support `SessionStart`, `SessionEnd`, and `Notification` hook events, which are documented in the CLI hook system.

- **Evidence:**
  - `src/claude_agent_sdk/types.py:147-157`:
    ```python
    ##### Hook types
    # Supported hook event types. Due to setup limitations, the Python SDK does not
    # support SessionStart, SessionEnd, and Notification hooks.
    HookEvent = (
        Literal["PreToolUse"]
        | Literal["PostToolUse"]
        | Literal["UserPromptSubmit"]
        | Literal["Stop"]
        | Literal["SubagentStop"]
        | Literal["PreCompact"]
    )
    ```
    The comment explicitly states these hooks are not supported.

- **Impact:**
  1. **SessionStart**: Cannot run initialization logic when a session begins
     - Use case: Set up resources, log session start, configure environment
  2. **SessionEnd**: Cannot run cleanup logic when a session ends
     - Use case: Release resources, save session data, send analytics
  3. **Notification**: Cannot hook into Claude's notification system
     - Use case: Custom notification handling, logging, monitoring

- **Root Cause:**
  According to the comment, "setup limitations" prevent these hooks. This likely means:
  1. The hooks fire before/after the SDK's streaming connection is established
  2. The control protocol handshake happens after these events would fire
  3. The CLI may handle these internally before SDK communication begins

- **Proposed fix:**
  1. **Document the limitation clearly** in public documentation
  2. **Investigate workarounds**:
     - For SessionStart: Could the initialize response include session start data?
     - For SessionEnd: Could the result message trigger a callback?
     - For Notification: Can notifications be forwarded through control protocol?
  3. **Consider SDK-level alternatives**:
     ```python
     options = ClaudeAgentOptions(
         on_session_start=my_start_callback,  # SDK-level callback
         on_session_end=my_end_callback,      # SDK-level callback
     )
     ```
  4. **Open issue with CLI team** to explore control protocol support for these events
