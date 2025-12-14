# Python → Elixir Claude Agent SDK Parity Audit (2025-12-13)

This audit compares the Python SDK at `anthropics/claude-agent-sdk-python/` against the Elixir SDK at the repo root and documents Python functionality that is missing or incompletely ported to Elixir.

Total documented gaps: **25**

## Top Priorities

### Critical

1. **Settings isolation default differs**: Python always emits `--setting-sources ""` (no filesystem settings unless explicitly enabled); Elixir omits the flag when unset, likely changing default behavior. See `01_types_options_gaps.md`.
2. **System prompt default differs**: Python forces “no system prompt” by emitting `--system-prompt ""` when unset; Elixir omits `--system-prompt`, risking CLI defaults. See `01_types_options_gaps.md`.
3. **Permission control response casing**: Python replies with `updatedInput` / `updatedPermissions`; Elixir emits `updated_input` / `updated_permissions`, likely breaking permission callbacks in real CLI flows. See `04_control_protocol_gaps.md`.

### High

4. **SDK MCP control-protocol compatibility**: Python expects `subtype: "mcp_message"` with `server_name`; Elixir currently expects `subtype: "sdk_mcp_request"` with `serverName`. Add compatibility for both. See `04_control_protocol_gaps.md`.
5. **Control request timeouts**: Python times out control requests (default 60s) and cleans up pending entries; Elixir can hang indefinitely on unacknowledged requests. See `04_control_protocol_gaps.md` and `07_recent_features_gaps.md`.
6. **CLI discovery parity**: Python supports bundled CLI and expanded search paths (`~/.claude/local/claude`, common Node install locations); Elixir discovery is PATH-only. See `03_transport_gaps.md`.
7. **`cwd` semantics differ**: Python errors if `cwd` doesn’t exist; Elixir streaming transport creates the directory. See `03_transport_gaps.md`.

## Medium/Low Themes

- **Ergonomics/typing**: Python exposes structured message content blocks and `ResultMessage.usage`; Elixir currently exposes raw payloads and omits some extracted fields. See `05_message_parsing_gaps.md`.
- **Hook capabilities**: Python supports async hook deferral outputs (`async`/`asyncTimeout`); Elixir does not. See `01_types_options_gaps.md`.
- **Transport UX/edge cases**: Python mitigates Windows command-length issues for `--agents @file`; Elixir always inlines. See `03_transport_gaps.md`.
- **Error taxonomy**: Python provides structured exceptions; Elixir primarily uses tuples and embeds errors into result messages. See `06_error_handling_gaps.md`.

## Notes on Already-Ported/Verified Items

These Python features appear present in Elixir (no gaps recorded here): tools option (`--tools`), betas (`--betas`), sandbox settings merged into `--settings`, file checkpointing env var and `rewind_files`, and assistant `error` parsing for rate-limit/billing/auth failures.

