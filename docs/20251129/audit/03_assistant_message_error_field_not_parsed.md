# Assistant Message Error Field Not Parsed

- **What's missing:** The `AssistantMessage` dataclass has an `error` field typed as `AssistantMessageError | None`, but the message parser never extracts this field from the raw CLI output. The error information is silently discarded.

- **Evidence:**
  - `src/claude_agent_sdk/types.py:460-467`:
    ```python
    AssistantMessageError = Literal[
        "authentication_failed",
        "billing_error",
        "rate_limit",
        "invalid_request",
        "server_error",
        "unknown",
    ]
    ```

  - `src/claude_agent_sdk/types.py:479-485`:
    ```python
    @dataclass
    class AssistantMessage:
        content: list[ContentBlock]
        model: str
        parent_tool_use_id: str | None = None
        error: AssistantMessageError | None = None  # Defined but never populated
    ```

  - `src/claude_agent_sdk/_internal/message_parser.py:119-123`:
    ```python
    return AssistantMessage(
        content=content_blocks,
        model=data["message"]["model"],
        parent_tool_use_id=data.get("parent_tool_use_id"),
        # NOTE: error field is NOT extracted from data
    )
    ```

- **Impact:** When the Claude API returns an error (authentication failure, rate limiting, billing issues, etc.), users receive an `AssistantMessage` with `error=None` instead of the actual error type. This makes it difficult to programmatically handle API errors or provide meaningful feedback to end users.

- **Proposed fix:**
  1. Update `message_parser.py` to extract the error field:
     ```python
     return AssistantMessage(
         content=content_blocks,
         model=data["message"]["model"],
         parent_tool_use_id=data.get("parent_tool_use_id"),
         error=data.get("error"),  # Add this line
     )
     ```
  2. Add unit tests for parsing assistant messages with error fields
  3. Document the error types in the API reference
