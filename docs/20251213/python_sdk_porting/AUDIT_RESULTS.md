# Audit Results: Python SDK Porting Docs (d553184..f834ba9)

## Documents Reviewed

- `00_overview.md`
- `01_tools_option.md`
- `02_sdk_beta.md`
- `03_file_checkpointing.md`
- `04_rate_limit_detection.md`
- `05_write_lock.md`
- `06_sandbox_adapter.md`

## Changes Made

- `00_overview.md`: Updated v0.1.12 timeline entry and added `## Audit Notes` for additional commits in-range not covered by 01–06 (PR #380, PR #388).
- `01_tools_option.md`: Aligned Elixir implementation snippets with the current `ClaudeAgentSDK.Options.to_args/1` pipeline and clarified that `:allowed_tools`/`:disallowed_tools` already exist.
- `02_sdk_beta.md`: Clarified `betas` default guidance (prefer `[]` for parity; treat `nil` as unset for backward compatibility).
- `03_file_checkpointing.md`: Fixed Elixir examples to compile, removed speculative behavior notes, and added `## Audit Notes` about the checkpoint ID discovery gap.
- `04_rate_limit_detection.md`: Corrected Elixir `AssistantError` shape to match the codebase and Python’s `AssistantMessageError` values; corrected the extraction location to `message.error`; updated test examples + error table accordingly.
- `05_write_lock.md`: No changes (matches Python diff and Elixir’s GenServer/Port architecture).
- `06_sandbox_adapter.md`: Clarified current Elixir status and added `## Audit Notes` distinguishing this feature from `ClaudeAgentSDK.OptionBuilder.sandboxed/2`.

## Key Findings / Gaps

- **File checkpointing ID discovery is currently unclear**: Python’s `ClaudeSDKClient.rewind_files/1` docstring references `UserMessage.uuid`, but Python `UserMessage` has no `uuid` field and the Python parser only extracts `uuid` for `stream_event`. The Elixir port should confirm actual CLI payloads before hard-coding a UUID extraction strategy.
- **Rate limit detection depends on a nested field**: Python parses assistant errors from `data["message"].get("error")`. Elixir currently pulls from `raw["error"]`; port should extract from `raw["message"]["error"]` (optionally falling back to `raw["error"]` for manual parsing compatibility).
- **Two additional Python commits in-range may matter for the Elixir port** (now called out in `00_overview.md`):
  - PR #380 (`a2f24a3`): Wait for first `result` before closing stdin when SDK MCP servers or hooks are present.
  - PR #388 (`69a310c`): Fail-fast pending control requests on CLI fatal errors.

## Elixir Implementation Status (Repo HEAD)

- **Already present (but may need adjustment)**:
  - `ClaudeAgentSDK.AssistantError` enum exists.
  - `ClaudeAgentSDK.Message` supports `data.error`, but the extraction location likely needs to move to `message.error`.
  - Port writes are serialized via GenServer (`ClaudeAgentSDK.Client`, `ClaudeAgentSDK.Transport.Port`), so the Python-style write lock is likely unnecessary.
- **Not yet implemented**:
  - `Options.tools` base tools option (`--tools`).
  - `Options.betas` beta flags (`--betas`).
  - `Options.sandbox` merged into `--settings` JSON.
  - `Options.enable_file_checkpointing` env var + `Client.rewind_files/2` + protocol encoder.

## Priority Recommendations

- Consider treating **Rate limit detection** as higher priority than “Medium”: it’s small, independent, and improves client reliability (retry/backoff).
- Keep **Tools** + **Betas** as “High”: both are straightforward CLI-flag parity.
- Keep **File checkpointing** “High” only once the checkpoint ID source is verified; otherwise it’s blocked on CLI payload details.
- Keep **Write lock** as “Verify-only”: Elixir’s actor model already serializes port writes in the current architecture.

## Open Questions / Follow-ups

- What exact CLI versions introduced file checkpointing + `rewind_files`? (Python SDK bundles CLI `2.0.69` at `f834ba9`.)
- Does the CLI emit a per-user-message UUID for `type: "user"` frames (and where), or is the intended ID surfaced via another message type?
