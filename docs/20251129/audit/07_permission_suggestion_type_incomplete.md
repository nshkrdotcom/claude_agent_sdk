# Permission Suggestion Type Uses Any Instead of PermissionUpdate

- **What's missing:** The `SDKControlPermissionRequest` TypedDict uses `list[Any]` for the `permission_suggestions` field instead of the properly defined `list[PermissionUpdate]` type.

- **Evidence:**
  - `src/claude_agent_sdk/types.py:586-593`:
    ```python
    class SDKControlPermissionRequest(TypedDict):
        subtype: Literal["can_use_tool"]
        tool_name: str
        input: dict[str, Any]
        # TODO: Add PermissionUpdate type here
        permission_suggestions: list[Any] | None  # Should be list[PermissionUpdate]
        blocked_path: str | None
    ```

  - `src/claude_agent_sdk/types.py:600-603`:
    ```python
    class SDKControlSetPermissionModeRequest(TypedDict):
        subtype: Literal["set_permission_mode"]
        # TODO: Add PermissionMode
        mode: str  # Should be PermissionMode literal
    ```

- **Impact:**
  1. No type safety for permission suggestions at the TypedDict level
  2. IDE autocomplete won't show available PermissionUpdate properties
  3. Type checkers cannot validate the structure of permission suggestions
  4. The `PermissionUpdate` type is already defined but not used consistently

- **Proposed fix:**
  1. Update `SDKControlPermissionRequest` to use the proper type:
     ```python
     class SDKControlPermissionRequest(TypedDict):
         subtype: Literal["can_use_tool"]
         tool_name: str
         input: dict[str, Any]
         permission_suggestions: list[PermissionUpdate] | None
         blocked_path: str | None
     ```

  2. Update `SDKControlSetPermissionModeRequest` to use `PermissionMode`:
     ```python
     class SDKControlSetPermissionModeRequest(TypedDict):
         subtype: Literal["set_permission_mode"]
         mode: PermissionMode
     ```

  3. Remove the TODO comments once fixed
  4. Add tests that verify type compatibility
