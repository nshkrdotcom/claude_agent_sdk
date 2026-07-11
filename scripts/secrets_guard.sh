#!/usr/bin/env bash
# CI backstop against secret-leak regressions:
#  1. config/runtime.exs must not snapshot the entire OS environment —
#     snapshot an allowlist instead.
#  2. A module in lib/ that defines a struct and mentions a secret-named
#     field must carry Inspect redaction (@derive {Inspect, except: [...]}
#     or defimpl Inspect), or a "# secret-safe:" review annotation on (or
#     directly above) each secret-named line.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0

if [ -f config/runtime.exs ] &&
   rg -n 'System\.get_env\(\)\s*$|System\.get_env\(\)\s*\)?\s*$' config/runtime.exs |
     rg -iv 'snapshot|allowlist|Map\.take|Map\.filter' >/dev/null 2>&1; then
  echo "secrets-guard: config/runtime.exs snapshots the whole env — snapshot an allowlist instead" >&2
  fail=1
fi

for file in $(rg -l --glob 'lib/**/*.ex' \
    -e ':(token|api_key|secret|password|auth_token|credential|bearer)\b' \
    -e '(anthropic_auth_token|oauth_token):' \
    lib 2>/dev/null || true); do
  rg -q 'defstruct' "$file" || continue
  rg -q '@derive \{Inspect|defimpl Inspect' "$file" && continue

  if ! awk '
    {
      cur_safe = index($0, "# secret-safe:") > 0
      if ($0 ~ /:(token|api_key|secret|password|auth_token|credential|bearer)(,|\]| |:|$)/ ||
          $0 ~ /(anthropic_auth_token|oauth_token):/) {
        if (!cur_safe && !prev_safe) bad = 1
      }
      prev_safe = cur_safe
    }
    END { exit bad }
  ' "$file"; then
    echo "secrets-guard: $file declares a secret-named struct field without Inspect redaction (annotate '# secret-safe:' if reviewed)" >&2
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "secrets-guard: clean"
