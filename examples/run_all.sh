#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat <<'EOF'
Usage: bash examples/run_all.sh [--ollama] [--ollama-model MODEL] [--cwd PATH] [--danger-full-access] [--ssh-host HOST] [--ssh-user USER] [--ssh-port PORT] [--ssh-identity-file PATH] [--help]

Options:
  --ollama               Run the Ollama-compatible example subset.
  --ollama-model MODEL   Override the Ollama model. Default: llama3.2
  --cwd PATH             Optional working directory passed through to the examples.
  --danger-full-access   Run examples with permission_mode=:bypass_permissions.
  --ssh-host HOST        Run the CLI-backed examples over execution_surface=:ssh_exec.
  --ssh-user USER        Override the SSH user.
  --ssh-port PORT        Override the SSH port.
  --ssh-identity-file PATH  Set the SSH identity file.
  --help                 Show this help text.

The standard runner already includes the live session-oriented lanes used for recovery hardening.
EOF
}

FORWARD_ARGS=()
SSH_HOST=""
SSH_AUX_SET=0
CWD_CONFIGURED=0
DANGER_FULL_ACCESS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ollama)
      export CLAUDE_EXAMPLES_BACKEND="ollama"
      shift
      ;;
    --ollama-model)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --ollama-model requires a model name." >&2
        exit 1
      fi

      export CLAUDE_EXAMPLES_BACKEND="ollama"
      export CLAUDE_EXAMPLES_OLLAMA_MODEL="$2"
      shift 2
      ;;
    --cwd)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --cwd requires a value." >&2
        exit 1
      fi

      CWD_CONFIGURED=1
      FORWARD_ARGS+=("$1" "$2")
      shift 2
      ;;
    --cwd=*)
      CWD_CONFIGURED=1
      FORWARD_ARGS+=("$1")
      shift
      ;;
    --danger-full-access)
      DANGER_FULL_ACCESS=1
      FORWARD_ARGS+=("$1")
      shift
      ;;
    --ssh-host)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --ssh-host requires a value." >&2
        exit 1
      fi

      SSH_HOST="$2"
      FORWARD_ARGS+=("$1" "$2")
      shift 2
      ;;
    --ssh-user|--ssh-port|--ssh-identity-file)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: $1 requires a value." >&2
        exit 1
      fi

      SSH_AUX_SET=1
      FORWARD_ARGS+=("$1" "$2")
      shift 2
      ;;
    --ssh-host=*|--ssh-user=*|--ssh-port=*|--ssh-identity-file=*)
      if [[ "$1" == --ssh-host=* ]]; then
        SSH_HOST="${1#*=}"
      else
        SSH_AUX_SET=1
      fi

      FORWARD_ARGS+=("$1")
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      echo "" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$SSH_HOST" && "$SSH_AUX_SET" -eq 1 ]]; then
  echo "ERROR: --ssh-user/--ssh-port/--ssh-identity-file require --ssh-host." >&2
  exit 1
fi

if command -v stty >/dev/null 2>&1; then
  trap 'stty sane >/dev/null 2>&1 || true' EXIT
fi
trap 'exit 130' INT
trap 'exit 1' TERM

echo "Running LIVE examples (real Claude CLI calls)."
echo "These may incur API costs."

BACKEND="${CLAUDE_EXAMPLES_BACKEND:-${CLAUDE_AGENT_PROVIDER_BACKEND:-anthropic}}"

default_preflight_timeout_seconds() {
  if [[ "$BACKEND" == "ollama" ]]; then
    echo 60
  else
    echo 30
  fi
}

require_positive_integer() {
  local name="$1"
  local value="$2"

  if ! [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" -le 0 ]]; then
    echo "ERROR: ${name} must be a positive integer (got: ${value})." >&2
    exit 1
  fi
}

if [[ -z "$SSH_HOST" ]]; then
  echo ""
  echo "==> Claude SDK CLI status"
  mix run -e "Code.require_file(Path.expand(\"examples/support/example_helper.exs\")); Examples.Support.cli_status!()"
fi

if [[ "$BACKEND" == "ollama" ]]; then
  OLLAMA_MODEL="${CLAUDE_EXAMPLES_OLLAMA_MODEL:-${CLAUDE_EXAMPLES_MODEL:-llama3.2}}"
  ANTHROPIC_BASE_URL="${CLAUDE_EXAMPLES_ANTHROPIC_BASE_URL:-${ANTHROPIC_BASE_URL:-http://localhost:11434}}"
  export CLAUDE_AGENT_PROVIDER_BACKEND="ollama"
  export ANTHROPIC_AUTH_TOKEN="${ANTHROPIC_AUTH_TOKEN:-ollama}"
  export ANTHROPIC_API_KEY=""
  export ANTHROPIC_BASE_URL
  export ANTHROPIC_MODEL="$OLLAMA_MODEL"
  export CLAUDE_AGENT_EXTERNAL_MODEL_OVERRIDES="$(cat <<JSON
{"haiku":"$OLLAMA_MODEL","sonnet":"$OLLAMA_MODEL","opus":"$OLLAMA_MODEL","sonnet[1m]":"$OLLAMA_MODEL","opus[1m]":"$OLLAMA_MODEL","legacy-sonnet":"$OLLAMA_MODEL"}
JSON
)"

  if [[ -z "$SSH_HOST" ]]; then
    if ! command -v ollama >/dev/null 2>&1; then
      echo "ERROR: Ollama CLI not found on PATH." >&2
      exit 1
    fi

    echo ""
    echo "==> ollama --version"
    ollama --version

    echo ""
    echo "==> ollama show $OLLAMA_MODEL"
    if ! ollama show "$OLLAMA_MODEL" >/dev/null 2>&1; then
      echo "ERROR: Ollama model not installed: $OLLAMA_MODEL" >&2
      exit 1
    fi
  fi

  echo "Using Ollama backend"
  echo "  base_url: $ANTHROPIC_BASE_URL"
  echo "  mapped model: $OLLAMA_MODEL"
fi

echo ""

if [[ "$BACKEND" == "ollama" ]]; then
  echo "Claude backend: Ollama via Anthropic-compatible API"
  echo "Claude CLI model: $OLLAMA_MODEL"
  echo "SDK model route: $OLLAMA_MODEL"
  echo "Backend env: ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL"
  echo "Model slot mapping: haiku/sonnet/opus -> $OLLAMA_MODEL"
else
  echo "Claude backend: standard Anthropic Claude CLI"
  echo "Claude CLI model: ${ANTHROPIC_MODEL:-haiku (preflight default unless examples override)}"
fi

if [[ -n "$SSH_HOST" ]]; then
  echo "Execution surface: ssh_exec host=${SSH_HOST}"
  if [[ "$CWD_CONFIGURED" -eq 1 ]]; then
    echo "Working directory override: configured via --cwd"
  fi
fi

if [[ "$DANGER_FULL_ACCESS" -eq 1 ]]; then
  echo "Permission override: bypass_permissions (--danger-full-access)"
fi

echo ""
echo "==> Claude live preflight (transport-aware; may make a small API call)"

PREFLIGHT_TIMEOUT_SECONDS="${CLAUDE_EXAMPLES_PREFLIGHT_TIMEOUT_SECONDS:-$(default_preflight_timeout_seconds)}"
PREFLIGHT_WRAPPER_HEADROOM_SECONDS="${CLAUDE_EXAMPLES_PREFLIGHT_WRAPPER_HEADROOM_SECONDS:-15}"

require_positive_integer "CLAUDE_EXAMPLES_PREFLIGHT_TIMEOUT_SECONDS" "$PREFLIGHT_TIMEOUT_SECONDS"
require_positive_integer \
  "CLAUDE_EXAMPLES_PREFLIGHT_WRAPPER_HEADROOM_SECONDS" \
  "$PREFLIGHT_WRAPPER_HEADROOM_SECONDS"

export CLAUDE_EXAMPLES_PREFLIGHT_TIMEOUT_SECONDS="$PREFLIGHT_TIMEOUT_SECONDS"
PREFLIGHT_WRAPPER_TIMEOUT_SECONDS=$((PREFLIGHT_TIMEOUT_SECONDS + PREFLIGHT_WRAPPER_HEADROOM_SECONDS))

echo "    (inner timeout: ${PREFLIGHT_TIMEOUT_SECONDS}s; wrapper timeout: ${PREFLIGHT_WRAPPER_TIMEOUT_SECONDS}s)"
echo "    (set CLAUDE_EXAMPLES_PREFLIGHT_TIMEOUT_SECONDS to adjust)"

preflight_out="$(mktemp)"
preflight_rc=0
preflight_cmd=(mix run -e "Code.require_file(Path.expand(\"examples/support/example_helper.exs\")); case Examples.Support.preflight!() do :ok -> :ok; {:error, reason} -> IO.puts(reason); System.halt(1) end")

if [[ ${#FORWARD_ARGS[@]} -gt 0 ]]; then
  preflight_cmd+=(-- "${FORWARD_ARGS[@]}")
fi

if command -v timeout >/dev/null 2>&1; then
  timeout --foreground "${PREFLIGHT_WRAPPER_TIMEOUT_SECONDS}s" \
    "${preflight_cmd[@]}" >"$preflight_out" 2>&1 || preflight_rc=$?
else
  "${preflight_cmd[@]}" >"$preflight_out" 2>&1 || preflight_rc=$?
fi

if [[ "$preflight_rc" -ne 0 ]]; then
  echo "ERROR: Claude live preflight failed or timed out (exit=$preflight_rc)." >&2
  echo "---- claude output ----" >&2
  cat "$preflight_out" >&2
  echo "-----------------------" >&2

  if [[ "$preflight_rc" -eq 124 ]]; then
    echo "Preflight exceeded the wrapper timeout (${PREFLIGHT_WRAPPER_TIMEOUT_SECONDS}s)." >&2
  elif grep -q "timed out after" "$preflight_out" || grep -q "Transport timeout" "$preflight_out"; then
    echo "Preflight exceeded the inner transport timeout (${PREFLIGHT_TIMEOUT_SECONDS}s)." >&2
  fi

  if [[ "$BACKEND" == "ollama" ]]; then
    echo "Hint: verify Ollama is reachable at ${ANTHROPIC_BASE_URL} and that ${OLLAMA_MODEL} is installed." >&2
    echo "Hint: cold model startup can be slow; increase CLAUDE_EXAMPLES_PREFLIGHT_TIMEOUT_SECONDS if needed." >&2
  else
    echo "Hint: authenticate with 'claude login', or set ANTHROPIC_API_KEY / CLAUDE_AGENT_OAUTH_TOKEN." >&2
    echo "Hint: increase CLAUDE_EXAMPLES_PREFLIGHT_TIMEOUT_SECONDS if Claude CLI startup is slow." >&2
  fi

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

default_examples=(
  "examples/basic_example.exs"
  "examples/session_features_example.exs"
  "examples/structured_output_live.exs"
  "examples/sandbox_settings_live.exs"
  "examples/tools_and_betas_live.exs"
  "examples/sdk_mcp_tools_live.exs"
  "examples/advanced_features/agents_live.exs"
  "examples/advanced_features/permissions_live.exs"
  "examples/advanced_features/sdk_mcp_live_demo.exs"
  "examples/advanced_features/subagent_spawning_live.exs"
  "examples/advanced_features/web_tools_live.exs"
  "examples/streaming_tools/quick_demo.exs"
  "examples/streaming_tools/sdk_mcp_streaming.exs"
  "examples/streaming_tools/stop_reason_probe.exs"
  "examples/streaming_tools/multi_turn_tool_streaming_session.exs"
  "examples/streaming_tools/subagent_streaming.exs"
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

examples=("examples/effort_gating_live.exs" "${default_examples[@]}")

if [[ "$BACKEND" == "ollama" ]]; then
  echo ""
  echo "==> Ollama mode"
  echo "    Running the example list against the Ollama-backed Claude path."
  echo "    Examples that require unsupported Ollama features may self-skip."
  echo "    Set CLAUDE_EXAMPLES_FORCE_UNSUPPORTED=true to force those runs."
fi

failures=()

for ex in "${examples[@]}"; do
  echo ""
  if [[ "${#FORWARD_ARGS[@]}" -gt 0 ]]; then
    echo "==> mix run $ex -- ${FORWARD_ARGS[*]}"
  else
    echo "==> mix run $ex"
  fi
  if command -v stty >/dev/null 2>&1; then
    stty sane >/dev/null 2>&1 || true
  fi
  rc=0
  if command -v timeout >/dev/null 2>&1; then
    # Use --foreground to avoid process group issues with :erlang.halt
    if [[ "${#FORWARD_ARGS[@]}" -gt 0 ]]; then
      timeout --foreground "${EXAMPLE_TIMEOUT_SECONDS}s" mix run "$ex" -- "${FORWARD_ARGS[@]}" || rc=$?
    else
      timeout --foreground "${EXAMPLE_TIMEOUT_SECONDS}s" mix run "$ex" || rc=$?
    fi
  else
    if [[ "${#FORWARD_ARGS[@]}" -gt 0 ]]; then
      mix run "$ex" -- "${FORWARD_ARGS[@]}" || rc=$?
    else
      mix run "$ex" || rc=$?
    fi
  fi

  if [[ "$rc" -ne 0 ]]; then
    echo "ERROR: example failed (exit=$rc): $ex" >&2
    failures+=("$ex (exit=$rc)")
    continue
  fi
  if command -v stty >/dev/null 2>&1; then
    stty sane >/dev/null 2>&1 || true
  fi

  echo "✓ Completed: $ex"
done

echo ""
if (( ${#failures[@]} > 0 )); then
  echo "Examples failed:"
  for ex in "${failures[@]}"; do
    echo "  - $ex"
  done
  exit 1
fi

echo "All examples completed."
