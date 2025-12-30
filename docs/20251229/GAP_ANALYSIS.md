# Python SDK vs Elixir SDK Gap Analysis

**Date:** 2025-12-29
**Python SDK Version:** 0.1.x (claude-agent-sdk-python)
**Elixir SDK Version:** 0.7.x (claude_agent_sdk)

---

## Executive Summary

This document provides a comprehensive gap analysis between the official Python Claude Agent SDK and the Elixir port. The analysis covers features, implementation differences, API parity, and type system variations.

**Overall Parity Assessment:** ~85% feature parity achieved

### Critical Gaps: 2
### High Priority Gaps: 6
### Medium Priority Gaps: 8
### Low Priority Gaps: 5

---

## 1. Features in Python SDK Missing from Elixir SDK

### 1.1 Critical Severity

| Feature | Python Location | Elixir Status | Description | Recommended Action |
|---------|-----------------|---------------|-------------|-------------------|
| `get_server_info()` | `client.py:296-319` | Missing | Returns initialization info including available commands and output styles | Implement in Client module after initialization |
| Async Context Manager Protocol | `client.py:369-377` | Different | Python uses `async with` for automatic connect/disconnect | Add `start_session/stop_session` pattern with try/finally |

### 1.2 High Severity

| Feature | Python Location | Elixir Status | Description | Recommended Action |
|---------|-----------------|---------------|-------------|-------------------|
| `debug_stderr` Option | `types.py:644-645` | Missing | Deprecated file-like object for debug output | Add for backward compatibility |
| Bundled CLI Discovery | `subprocess_cli.py:103-116` | Missing | Find bundled CLI binary in `_bundled` directory | Implement `_find_bundled_cli/0` in Process module |
| CLI Version Check | `subprocess_cli.py:630-668` | Missing | Check CLI version and warn if below minimum (2.0.0) | Add version check on process start |
| `CLAUDE_CODE_ENTRYPOINT` Env Var | `subprocess_cli.py:383` | Partial | Set to `sdk-py` or `sdk-py-client` | Set to `sdk-ex` for Elixir SDK |
| `CLAUDE_AGENT_SDK_VERSION` Env Var | `subprocess_cli.py:384` | Missing | Pass SDK version to CLI for telemetry | Add version environment variable |
| Command Length Limit Handling | `subprocess_cli.py:336-366` | Missing | Windows 8000 char limit with temp file fallback | Implement for Windows compatibility |

### 1.3 Medium Severity

| Feature | Python Location | Elixir Status | Description | Recommended Action |
|---------|-----------------|---------------|-------------|-------------------|
| `PermissionUpdate` Dataclass | `types.py:69-121` | Missing | Structured permission update with `to_dict()` method | Create Elixir struct with encoder |
| `PermissionRuleValue` Dataclass | `types.py:61-66` | Missing | Permission rule value with tool_name and rule_content | Create Elixir struct |
| `PermissionUpdateDestination` Type | `types.py:53-55` | Missing | Literal type for userSettings/projectSettings/localSettings/session | Add type definition |
| `PermissionBehavior` Type | `types.py:57` | Missing | Literal type for allow/deny/ask | Add type definition |
| Async Hook Timeout (`asyncTimeout`) | `types.py:298` | Partial | Timeout for async hook operations | Support in hook output |
| `fork_session` CLI Flag | `subprocess_cli.py:276-277` | Present | Create new session ID when resuming | Already implemented |
| SDK Plugin Configuration | `types.py:425-433` | Present | Local plugin path configuration | Already implemented |
| Sandbox Network Configuration | `types.py:436-451` | Present | Network config for sandbox | Already implemented in Options |

### 1.4 Low Severity

| Feature | Python Location | Elixir Status | Description | Recommended Action |
|---------|-----------------|---------------|-------------|-------------------|
| `ToolPermissionContext.suggestions` | `types.py:129-131` | Missing | List of PermissionUpdate suggestions from CLI | Add to Permission.Context |
| `StreamEvent` Message Type | `types.py:604-611` | Present | Stream event for partial updates | Already implemented |
| Typed Hook Input Discriminated Unions | `types.py:174-237` | Different | Strongly typed hook inputs per event | Use dynamic map in Elixir |
| Hook Output Field Conversion | `query.py:34-50` | Present | Convert `async_` to `async`, `continue_` to `continue` | Already handled |
| `max_buffer_size` Option | `types.py:643` | Present | Max bytes when buffering CLI stdout | Already implemented |

---

## 2. Features in Elixir SDK Not in Python SDK

| Feature | Elixir Location | Description | Notes |
|---------|-----------------|-------------|-------|
| `OptionBuilder` Module | `option_builder.ex` | Pre-configured option sets and builder patterns | Elixir-specific convenience |
| Environment-based Options | `option_builder.ex:316-325` | Auto-select options based on Mix.env | Elixir-specific |
| `AuthManager` GenServer | `auth_manager.ex` | Token management with auto-refresh | Python relies on CLI auth |
| Transport Behaviour | `transport.ex` | Pluggable transport abstraction | More flexible than Python |
| `Streaming.Session` | `streaming.ex` | Dedicated streaming session GenServer | Different architecture |
| `StreamingRouter` | Elixir codebase | Automatic transport selection | Python lacks equivalent |
| `preferred_transport` Option | `options.ex:133` | Override automatic transport selection | Elixir-specific |
| `abort_ref` Option | `options.ex:99` | Reference for aborting requests | Elixir concurrency pattern |
| `strict_mcp_config` Option | `options.ex:118` | Only use MCP servers from --mcp-config | Not in Python SDK |
| `session_id` Option | `options.ex:111` | Explicit session ID (UUID) | Python uses resume |
| `Agent` Module | Elixir codebase | Dedicated agent definition struct | Python uses dict |
| `validate_agents/1` | `options.ex:914-953` | Agent configuration validation | Elixir-specific |

---

## 3. Implementation Differences

### 3.1 Client Architecture

| Aspect | Python SDK | Elixir SDK | Notes |
|--------|------------|------------|-------|
| Client Pattern | Async class with `async with` | GenServer with `start_link` | Different concurrency models |
| Connection Management | `connect()`/`disconnect()` | GenServer lifecycle | Elixir uses OTP supervision |
| Message Streaming | `async for` iterator | Elixir Stream | Both lazy evaluation |
| Task Group | `anyio.create_task_group()` | Elixir Task.Supervisor | Different async primitives |

### 3.2 Transport Layer

| Aspect | Python SDK | Elixir SDK | Notes |
|--------|------------|------------|-------|
| Abstraction | `Transport` protocol | `Transport` behaviour | Similar intent |
| Implementation | `SubprocessCLITransport` | Multiple (CLI, Control) | Elixir more modular |
| Write Lock | `anyio.Lock` | `self()` message passing | Different sync primitives |
| Stream Handling | `TextReceiveStream` | Port-based | OS-level difference |

### 3.3 Control Protocol

| Aspect | Python SDK | Elixir SDK | Notes |
|--------|------------|------------|-------|
| Request ID Format | `req_{counter}_{hex}` | `req_{unique_int}_{hex}` | Compatible |
| Initialize Timeout | From `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT` | Configurable | Similar |
| MCP Routing | Manual method dispatch | Similar manual dispatch | Both have TODO for SDK improvement |
| Hook Callback Storage | Dict by callback_id | Similar registry | Compatible |

### 3.4 Error Handling

| Python Error | Elixir Equivalent | Status |
|--------------|-------------------|--------|
| `CLIConnectionError` | `CLIConnectionError` | Present |
| `CLINotFoundError` | `CLINotFoundError` | Present |
| `ProcessError` | `ProcessError` | Present |
| `CLIJSONDecodeError` | `CLIJSONDecodeError` | Present |
| General `Exception` | Pattern matching on `{:error, reason}` | Different idiom |

---

## 4. API Parity Issues

### 4.1 ClaudeAgentOptions vs Options

| Python Field | Elixir Field | Status | Notes |
|--------------|--------------|--------|-------|
| `tools` | `tools` | Present | |
| `allowed_tools` | `allowed_tools` | Present | |
| `system_prompt` | `system_prompt` | Present | |
| `mcp_servers` | `mcp_servers` | Present | |
| `permission_mode` | `permission_mode` | Present | |
| `continue_conversation` | `continue_conversation` | Present | |
| `resume` | `resume` | Present | |
| `max_turns` | `max_turns` | Present | |
| `max_budget_usd` | `max_budget_usd` | Present | |
| `disallowed_tools` | `disallowed_tools` | Present | |
| `model` | `model` | Present | |
| `fallback_model` | `fallback_model` | Present | |
| `betas` | `betas` | Present | |
| `permission_prompt_tool_name` | `permission_prompt_tool` | **Renamed** | Different naming |
| `cwd` | `cwd` | Present | |
| `cli_path` | `path_to_claude_code_executable` | **Renamed** | Different naming |
| `settings` | `settings` | Present | |
| `add_dirs` | `add_dirs` + `add_dir` | **Extended** | Elixir has both |
| `env` | `env` | Present | |
| `extra_args` | `extra_args` | Present | |
| `max_buffer_size` | `max_buffer_size` | Present | |
| `debug_stderr` | N/A | **Missing** | Deprecated in Python |
| `stderr` | `stderr` | Present | |
| `can_use_tool` | `can_use_tool` | Present | |
| `hooks` | `hooks` | Present | |
| `user` | `user` | Present | |
| `include_partial_messages` | `include_partial_messages` | Present | |
| `fork_session` | `fork_session` | Present | |
| `agents` | `agents` | Present | |
| `setting_sources` | `setting_sources` | Present | |
| `sandbox` | `sandbox` | Present | |
| `plugins` | `plugins` | Present | |
| `max_thinking_tokens` | `max_thinking_tokens` | Present | |
| `output_format` | `output_format` | Present | JSON schema supported |
| `enable_file_checkpointing` | `enable_file_checkpointing` | Present | |

### 4.2 Client Methods

| Python Method | Elixir Equivalent | Status | Notes |
|---------------|-------------------|--------|-------|
| `connect()` | `start_link()` | Different | OTP pattern |
| `disconnect()` | `stop()` | Different | OTP pattern |
| `receive_messages()` | `subscribe()` + message handling | Different | Event-based in Elixir |
| `receive_response()` | Stream consumption | Different | |
| `query()` | `send_message()` | Different | Different naming |
| `interrupt()` | `interrupt()` | Present | |
| `set_permission_mode()` | `set_permission_mode()` | Present | |
| `set_model()` | `set_model()` | Present | |
| `rewind_files()` | `rewind_files()` | Present | |
| `get_server_info()` | N/A | **Missing** | Need to implement |

### 4.3 Message Types

| Python Type | Elixir Equivalent | Status |
|-------------|-------------------|--------|
| `UserMessage` | `%Message{type: :user}` | Present |
| `AssistantMessage` | `%Message{type: :assistant}` | Present |
| `SystemMessage` | `%Message{type: :system}` | Present |
| `ResultMessage` | `%Message{type: :result}` | Present |
| `StreamEvent` | `%Message{type: :stream_event}` | Present |

### 4.4 Content Block Types

| Python Type | Elixir Equivalent | Status |
|-------------|-------------------|--------|
| `TextBlock` | `%{type: :text, text: ...}` | Present |
| `ThinkingBlock` | `%{type: :thinking, ...}` | Present |
| `ToolUseBlock` | `%{type: :tool_use, ...}` | Present |
| `ToolResultBlock` | `%{type: :tool_result, ...}` | Present |

---

## 5. Type System Differences

### 5.1 Python TypedDict vs Elixir Structs

| Python Approach | Elixir Approach | Notes |
|-----------------|-----------------|-------|
| `@dataclass` for value types | `defstruct` | Similar intent |
| `TypedDict` for dicts | `@type` specs | Compile-time only in Python |
| `Literal` for enums | Atoms | Elixir atoms are more natural |
| Union types (`\|`) | `@type` with `\|` | Similar |
| `NotRequired` | `nil` default | Different optional handling |

### 5.2 Type Definitions Comparison

| Python Type | Elixir Type | Notes |
|-------------|-------------|-------|
| `PermissionMode = Literal[...]` | `@type permission_mode :: :default \| ...` | Equivalent |
| `HookEvent = Literal[...]` | `@type hook_event :: :pre_tool_use \| ...` | Equivalent |
| `McpServerConfig = Union[...]` | `@type mcp_server :: sdk_mcp_server() \| external_mcp_server()` | Equivalent |
| `HookCallback = Callable[...]` | `@type hook_callback :: (input, id, context -> output)` | Equivalent |
| `CanUseTool = Callable[...]` | `@type callback :: (Context.t() -> Result.t())` | Equivalent |

### 5.3 Error Type Mapping

| Python `AssistantMessageError` | Elixir Equivalent | Status |
|--------------------------------|-------------------|--------|
| `"authentication_failed"` | `:authentication_failed` | Present |
| `"billing_error"` | `:billing_error` | Present |
| `"rate_limit"` | `:rate_limit` | Present |
| `"invalid_request"` | `:invalid_request` | Present |
| `"server_error"` | `:server_error` | Present |
| `"unknown"` | `:unknown` | Present |

---

## 6. Hook System Comparison

### 6.1 Hook Events

| Python Event | Elixir Event | Status |
|--------------|--------------|--------|
| `"PreToolUse"` | `:pre_tool_use` | Present |
| `"PostToolUse"` | `:post_tool_use` | Present |
| `"UserPromptSubmit"` | `:user_prompt_submit` | Present |
| `"Stop"` | `:stop` | Present |
| `"SubagentStop"` | `:subagent_stop` | Present |
| `"PreCompact"` | `:pre_compact` | Present |
| N/A (not supported) | `:session_start` | **Extra** in Elixir |
| N/A (not supported) | `:session_end` | **Extra** in Elixir |
| N/A (not supported) | `:notification` | **Extra** in Elixir |

### 6.2 Hook Matcher Configuration

| Python Field | Elixir Field | Status |
|--------------|--------------|--------|
| `matcher` | `matcher` | Present |
| `hooks` | `hooks` | Present |
| `timeout` | `timeout` | Present |

### 6.3 Hook Output Fields

| Python Field | Elixir Equivalent | Status |
|--------------|-------------------|--------|
| `continue_` | Converted to `continue` | Handled |
| `async_` | Converted to `async` | Handled |
| `suppressOutput` | `suppress_output` | Present |
| `stopReason` | `stop_reason` | Present |
| `decision` | `decision` | Present |
| `systemMessage` | `system_message` | Present |
| `reason` | `reason` | Present |
| `hookSpecificOutput` | `hook_specific_output` | Present |

---

## 7. MCP Server Support Comparison

### 7.1 Server Types

| Python Type | Elixir Type | Status |
|-------------|-------------|--------|
| `McpStdioServerConfig` | `external_mcp_server` (type: :stdio) | Present |
| `McpSSEServerConfig` | `external_mcp_server` (type: :sse) | Present |
| `McpHttpServerConfig` | `external_mcp_server` (type: :http) | Present |
| `McpSdkServerConfig` | `sdk_mcp_server` (type: :sdk) | Present |

### 7.2 SDK MCP Server Handling

| Aspect | Python SDK | Elixir SDK | Status |
|--------|------------|------------|--------|
| Instance field stripping | `subprocess_cli.py:250-256` | `options.ex:686-696` | Present |
| CLI metadata passing | All servers passed | All servers passed | Present |
| Manual method routing | `query.py:423-465` | Control protocol module | Present |
| Protocol version | `"2024-11-05"` | Same | Present |

---

## 8. Authentication Comparison

| Aspect | Python SDK | Elixir SDK | Notes |
|--------|------------|------------|-------|
| Environment Variable | `ANTHROPIC_API_KEY` | `ANTHROPIC_API_KEY` | Same |
| OAuth Token | Delegated to CLI | `AuthManager` GenServer | Elixir has more |
| Token Refresh | CLI handles | `AuthManager` auto-refresh | Elixir has more |
| Provider Detection | Via env vars | `Provider` module | Both support |
| Multi-provider | Bedrock, Vertex | Bedrock, Vertex | Both support |

---

## 9. Streaming and Control Protocol

### 9.1 Streaming Features

| Feature | Python SDK | Elixir SDK | Status |
|---------|------------|------------|--------|
| Partial messages | `--include-partial-messages` | Same flag | Present |
| Stream JSON format | `--output-format stream-json` | Same flag | Present |
| Input format | `--input-format stream-json` | Same flag | Present |
| Message buffering | JSON buffer with size limit | Similar | Present |
| Write lock | `anyio.Lock` | GenServer serialization | Equivalent |

### 9.2 Control Protocol Messages

| Message Type | Python SDK | Elixir SDK | Status |
|--------------|------------|------------|--------|
| `control_request` | Encode/decode | Encode/decode | Present |
| `control_response` | Encode/decode | Encode/decode | Present |
| `control_cancel_request` | TODO in code | Partial | Gap |
| `initialize` subtype | Implemented | Implemented | Present |
| `interrupt` subtype | Implemented | Implemented | Present |
| `set_permission_mode` | Implemented | Implemented | Present |
| `set_model` | Implemented | Implemented | Present |
| `rewind_files` | Implemented | Implemented | Present |
| `can_use_tool` | Implemented | Implemented | Present |
| `hook_callback` | Implemented | Implemented | Present |
| `mcp_message` | Implemented | Implemented | Present |

---

## 10. Recommended Priority Actions

### 10.1 Critical (Implement Immediately)

1. **Add `get_server_info/1`** to Client module
   - Returns initialization result after connect
   - Matches Python SDK behavior

2. **Review async context manager pattern**
   - Consider adding `with_session/2` convenience function
   - Document OTP patterns for users coming from Python

### 10.2 High Priority (Next Release)

1. **Add CLI version check**
   - Minimum version: 2.0.0
   - Log warning if below minimum

2. **Set SDK environment variables**
   - `CLAUDE_CODE_ENTRYPOINT=sdk-ex`
   - `CLAUDE_AGENT_SDK_VERSION={version}`

3. **Add bundled CLI discovery**
   - Check `priv/bundled/` directory
   - Fall back to system PATH

4. **Command length limit handling**
   - Windows 8000 char limit
   - Use temp files for long arguments

5. **Add `debug_stderr` option**
   - Backward compatibility
   - Deprecated in favor of `stderr`

6. **Implement `PermissionUpdate` struct**
   - With `to_map/1` encoder
   - For permission suggestions

### 10.3 Medium Priority (Future Release)

1. **Add `PermissionRuleValue` struct**
2. **Add permission suggestion types**
3. **Enhance `control_cancel_request` handling**
4. **Add async hook timeout support**
5. **Typed hook input structs (optional)**
6. **Improve test coverage for parity**

### 10.4 Low Priority (Nice to Have)

1. **Add Python-compatible aliases**
   - `cli_path` alias for `path_to_claude_code_executable`
   - `permission_prompt_tool_name` alias

2. **Documentation alignment**
   - Match Python SDK docstrings
   - Add migration guide

---

## 11. Summary Tables

### 11.1 Feature Parity by Category

| Category | Python Features | Elixir Implemented | Parity % |
|----------|-----------------|-------------------|----------|
| Options/Config | 35 | 33 | 94% |
| Client Methods | 10 | 8 | 80% |
| Message Types | 5 | 5 | 100% |
| Content Blocks | 4 | 4 | 100% |
| Hook Events | 6 | 9 | 150% |
| MCP Server Types | 4 | 4 | 100% |
| Control Protocol | 8 | 7 | 88% |
| Error Types | 6 | 6 | 100% |
| Transport Layer | 3 | 4 | 133% |

### 11.2 Gaps by Severity

| Severity | Count | Key Items |
|----------|-------|-----------|
| Critical | 2 | get_server_info, async context |
| High | 6 | CLI version check, env vars, bundled CLI |
| Medium | 8 | Permission types, hook timeout |
| Low | 5 | Naming aliases, docs |

---

## 12. Conclusion

The Elixir SDK has achieved strong feature parity with the Python SDK (~85%). The most significant gaps are in:

1. **Client convenience methods** (`get_server_info`)
2. **CLI environment setup** (version check, env vars)
3. **Permission update types** (structured suggestion handling)

The Elixir SDK has also added valuable features not in Python:
- `AuthManager` for token lifecycle
- `OptionBuilder` for configuration presets
- Pluggable transport abstraction
- OTP supervision integration

The architectural differences (OTP vs async/await) are intentional and idiomatic for each language. The goal should be API compatibility where sensible while maintaining Elixir best practices.
