# Atom Safety

**Rule:** never create an atom from external or unbounded input at runtime.
The BEAM atom table is capped (about 1,048,576 entries by default) and atoms
are **never garbage-collected**. Turning attacker-, CLI-, JSON-, env-, or
model-registry-derived strings into atoms is a memory-exhaustion / node-crash
vector: one crafted stream of distinct strings can take the node down.

## Banned on untrusted input

- `String.to_atom/1`, `List.to_atom/1`
- `:erlang.binary_to_atom/1,2`, `:erlang.list_to_atom/1`
- interpolated sigil atoms — `:"#{var}"`
- `Jason.decode!(json, keys: :atoms)` (and the Poison equivalent)

## Safe patterns

1. **Static lookup with string fallback** — an explicit map (or `case`) from
   known strings to literal atoms, where unknown input **stays a string**.
   The canonical example in this SDK is `ClaudeAgentSDK.Message` subtype
   handling: a `@system_subtypes` module-attribute map consulted via
   `Map.get(@system_subtypes, subtype, subtype)`. New wire frames must follow
   this pattern — the static map is the whole point.
2. **`String.to_existing_atom/1`** — only when the atom is provably
   pre-defined (for example a whitelist the module itself declares). See
   `ClaudeAgentSDK.Auth.TokenStore.parse_provider/1` for a whitelist
   variant with an explicit default.
3. **Default string keys** — `Jason.decode/1` without `keys:`; or
   `keys: :atoms!` if atom keys are truly required (existing atoms only).
4. **Keep it a string** — MCP tool names, model IDs, and message subtypes do
   not need to be atoms at all.

## Guardrails in this workspace

Two independent guards run in `mix ci` across `claude_agent_sdk`,
`cli_subprocess_core`, and `agent_session_manager`:

- `Credo.Check.Warning.UnsafeToAtom`, enabled in each repo's `.credo.exs`
  (scoped to `lib/`).
- `scripts/atom_guard.sh` — an `rg` backstop that fails CI if a dynamic-atom
  pattern appears in `lib/` without a same-line `# atom-safe:` review
  annotation.

Reviewed compile-time sites (for example the `Module.concat/2` calls in
`ClaudeAgentSDK.Tool.deftool/2` macro expansion, which are bounded by the
number of `deftool` declarations in source) carry both a `# atom-safe:`
annotation and a `credo:disable-for-next-line` marker.
