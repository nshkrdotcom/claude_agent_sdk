#!/usr/bin/env bash
# CI backstop against dynamic atom creation from external data (BEAM atom
# table is capped and never GC'd). Fails if a dynamic-atom pattern appears in
# lib/ without an explicit same-line "# atom-safe:" review annotation.
# Safe alternatives: static lookup maps with string fallback (see
# ClaudeAgentSDK.Message.safe_subtype/2), String.to_existing_atom/1, or
# keeping the value a string. `keys: :atoms!` (existing atoms only) is safe;
# the grep targets bare `keys: :atoms`.
set -euo pipefail
cd "$(dirname "$0")/.."

if matches=$(rg -n --glob 'lib/**/*.ex' \
    -e 'String\.to_atom' -e 'List\.to_atom' \
    -e ':erlang\.(binary|list)_to_atom' \
    -e 'keys:\s*:atoms\b' -e ':"#\{' \
    lib 2>/dev/null | rg -v '# atom-safe:'); then
  echo "$matches"
  echo "atom-guard: dynamic-atom pattern in lib/ — use a static map or String.to_existing_atom, or annotate '# atom-safe:'" >&2
  exit 1
fi
echo "atom-guard: clean"
