# Golden stream-json fixtures — claude CLI 2.1.207

Captured live from the locally installed `claude` CLI **2.1.207** on 2026-07-10
(the CLI bundled by upstream Python SDK v0.2.116 / TypeScript SDK v0.3.207),
except where a line is marked `# SYNTHETIC`. Lines starting with `#` are
provenance comments and are skipped by the loader in
`fixtures_smoke_test.exs`; every other line is one verbatim wire frame
(one JSON object per file).

Sanitization applied to live captures (shape untouched):

- `system_init_capabilities.jsonl` — `cwd`/`memory_paths` replaced with
  generic paths; `tools`/`agents`/`skills`/`slash_commands` inventories
  truncated to representative subsets.
- `result_zero_api_duration.jsonl` — `result` text (local `/cost` output)
  replaced with a placeholder.

| File | Frame | Notes |
|---|---|---|
| `result_terminal_reason.jsonl` | `result` | Real `terminal_reason: "budget_exhausted"` (via `--max-budget-usd`); also shows the `error_max_budget_usd` result subtype. |
| `result_zero_api_duration.jsonl` | `result` | Real zero-API turn (local slash command): `duration_api_ms: 0`, **no** `terminal_reason` key (loop bypassed). |
| `system_background_tasks_changed.jsonl` | `system/background_tasks_changed` | Real level-based frame: `tasks: [{task_id, task_type, description}]`; an empty `tasks: []` frame is emitted when the set drains. |
| `command_lifecycle.jsonl` | `command_lifecycle` | Real frame: `{command_uuid, state, uuid, session_id}`. States observed live: queued/started/completed/cancelled; full enum per CLI schema: queued, started, completed, cancelled, discarded. Only uuid-stamped inbound messages emit lifecycle frames. |
| `system_init_capabilities.jsonl` | `system/init` | Real `capabilities: ["interrupt_receipt_v1", "msg_lifecycle_v1"]`. |
| `control_interrupt_response.jsonl` | `control_response` | Real interrupt receipt with non-empty `still_queued` (uuids of queued messages that survive the interrupt). |
| `peer_message_event.jsonl` | `user` + `origin` | SYNTHETIC — derived from the CLI 2.1.207 embedded schema (`origin` union, `kind: "peer"` with `from`/`name`/`senderTaskId`/`body`). |

Additional ground truth observed during capture (CLI 2.1.207):

- `terminal_reason` enum (19 values): blocking_limit, rapid_refill_breaker,
  prompt_too_long, image_error, model_error, api_error,
  malformed_tool_use_exhausted, aborted_streaming, aborted_tools,
  stop_hook_prevented, hook_stopped, tool_deferred, max_turns,
  background_requested, completed, budget_exhausted,
  structured_output_retry_exhausted, tool_deferred_unavailable,
  turn_setup_failed. Successful turns report `"completed"`; interrupts
  report `aborted_streaming`/`aborted_tools`.
- Dead-turn classification (CLI internal): blocking_limit,
  rapid_refill_breaker, prompt_too_long, image_error, model_error,
  api_error, malformed_tool_use_exhausted, budget_exhausted,
  structured_output_retry_exhausted, tool_deferred_unavailable,
  turn_setup_failed. Aborts and max_turns/background_requested/completed
  are NOT dead turns; unknown/absent default to not-dead.
- New system subtype seen live but not yet typed: `thinking_tokens`
  (estimated_tokens, estimated_tokens_delta) — falls through as a string
  subtype by design.
