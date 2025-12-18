#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if command -v stty >/dev/null 2>&1; then
  trap 'stty sane >/dev/null 2>&1 || true' EXIT INT TERM
fi

echo "Running LIVE examples (real Claude CLI calls)."
echo "These may incur API costs."

if ! command -v claude >/dev/null 2>&1; then
  echo "ERROR: Claude CLI not found on PATH." >&2
  echo "Install: npm install -g @anthropic-ai/claude-code" >&2
  exit 1
fi

echo ""
echo "==> claude --version"
claude --version

echo ""
echo "==> claude auth preflight (may make a small API call)"

PREFLIGHT_PROMPT="Respond with exactly: OK"
PREFLIGHT_TIMEOUT_SECONDS="${CLAUDE_EXAMPLES_PREFLIGHT_TIMEOUT_SECONDS:-30}"
echo "    (timeout: ${PREFLIGHT_TIMEOUT_SECONDS}s; set CLAUDE_EXAMPLES_PREFLIGHT_TIMEOUT_SECONDS to adjust)"

preflight_out="$(mktemp)"
preflight_rc=0

if command -v timeout >/dev/null 2>&1; then
  timeout "${PREFLIGHT_TIMEOUT_SECONDS}s" \
    claude --print "$PREFLIGHT_PROMPT" --max-turns 1 --model haiku \
    >"$preflight_out" 2>&1 || preflight_rc=$?
else
  claude --print "$PREFLIGHT_PROMPT" --max-turns 1 --model haiku \
    >"$preflight_out" 2>&1 || preflight_rc=$?
fi

if [[ "$preflight_rc" -ne 0 ]]; then
  echo "ERROR: Claude CLI preflight failed or timed out (exit=$preflight_rc)." >&2
  echo "---- claude output ----" >&2
  cat "$preflight_out" >&2
  echo "-----------------------" >&2
  echo "Run: claude login" >&2
  rm -f "$preflight_out"
  exit 1
fi

rm -f "$preflight_out"

EXAMPLE_TIMEOUT_SECONDS="${CLAUDE_EXAMPLES_TIMEOUT_SECONDS:-900}"
echo ""
echo "==> examples timeout"
echo "    (timeout: ${EXAMPLE_TIMEOUT_SECONDS}s; set CLAUDE_EXAMPLES_TIMEOUT_SECONDS to adjust)"

# Always force-halt each `mix run` to avoid cases where OTP shutdown hangs
# (e.g., lingering ports/subprocesses after a successful CLI run).
export CLAUDE_EXAMPLES_FORCE_HALT="true"

examples=(
  "examples/basic_example.exs"
  "examples/session_features_example.exs"
  "examples/structured_output_live.exs"
  "examples/sandbox_settings_live.exs"
  "examples/tools_and_betas_live.exs"
  "examples/advanced_features/agents_live.exs"
  "examples/advanced_features/permissions_live.exs"
  "examples/advanced_features/sdk_mcp_live_demo.exs"
  "examples/streaming_tools/quick_demo.exs"
  "examples/streaming_tools/sdk_mcp_streaming.exs"
  "examples/hooks/context_injection.exs"
  "examples/hooks/basic_bash_blocking.exs"
  "examples/hooks/file_policy_enforcement.exs"
  "examples/hooks/logging_and_audit.exs"
  "examples/hooks/complete_workflow.exs"
  "examples/streaming_tools/basic_streaming_with_hooks.exs"
  "examples/runtime_control/control_parity_live.exs"
  "examples/assistant_error_live.exs"
  "examples/file_checkpointing_live.exs"
  "examples/filesystem_agents_live.exs"
)

for ex in "${examples[@]}"; do
  echo ""
  echo "==> mix run $ex"
  if command -v stty >/dev/null 2>&1; then
    stty sane >/dev/null 2>&1 || true
  fi
  if command -v timeout >/dev/null 2>&1; then
    # Use --foreground to avoid process group issues with :erlang.halt
    if ! timeout --foreground "${EXAMPLE_TIMEOUT_SECONDS}s" mix run "$ex"; then
      rc=$?
      echo "ERROR: example failed (exit=$rc): $ex" >&2
      exit "$rc"
    fi
  else
    if ! mix run "$ex"; then
      rc=$?
      echo "ERROR: example failed (exit=$rc): $ex" >&2
      exit "$rc"
    fi
  fi
  if command -v stty >/dev/null 2>&1; then
    stty sane >/dev/null 2>&1 || true
  fi

  echo "✓ Completed: $ex"
done

echo ""
echo "All examples completed."
