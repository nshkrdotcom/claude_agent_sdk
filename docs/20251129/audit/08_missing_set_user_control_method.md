# Missing set_user Runtime Control Method

- **What's missing:** The SDK does not expose a `set_user` method for runtime user switching, even though the `user` parameter exists in `ClaudeAgentOptions` and the control protocol supports dynamic user changes.

- **Evidence:**
  - `src/claude_agent_sdk/types.py:561`:
    ```python
    user: str | None = None
    ```
    User is defined as a startup option only.

  - `src/claude_agent_sdk/_internal/transport/subprocess_cli.py:334`:
    ```python
    self._process = await anyio.open_process(
        cmd,
        ...
        user=self._options.user,  # Set at process start only
    )
    ```

  - `src/claude_agent_sdk/client.py`: Has `set_permission_mode` and `set_model` but no `set_user`

  - `src/claude_agent_sdk/_internal/query.py`: Has `set_permission_mode` and `set_model` but no `set_user`

  - Compare to Elixir SDK (per CHANGELOG.md):
    ```
    Release 0.6.3: Control protocol parity for runtime user switching and permissions
    ```

- **Impact:**
  1. Cannot switch user context during a session
  2. Must restart the client to change user
  3. Multi-tenant applications cannot dynamically switch users
  4. Feature parity gap with Elixir SDK

- **Proposed fix:**
  1. Add `set_user` method to `Query`:
     ```python
     async def set_user(self, user: str | None) -> None:
         """Change the user during conversation."""
         await self._send_control_request({
             "subtype": "set_user",
             "user": user,
         })
     ```

  2. Add `set_user` method to `ClaudeSDKClient`:
     ```python
     async def set_user(self, user: str | None) -> None:
         """Change the user during conversation (only works with streaming mode)."""
         if not self._query:
             raise CLIConnectionError("Not connected. Call connect() first.")
         await self._query.set_user(user)
     ```

  3. Add `SDKControlSetUserRequest` TypedDict:
     ```python
     class SDKControlSetUserRequest(TypedDict):
         subtype: Literal["set_user"]
         user: str | None
     ```

  4. Add to `SDKControlRequest` union type
  5. Add tests for runtime user switching
