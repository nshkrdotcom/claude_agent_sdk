# Environment Variables & Secrets

How this SDK (and its sibling repos `cli_subprocess_core` and
`agent_session_manager`) handle environment-driven configuration and
credentials, and the rules that keep secrets out of logs and builds.

## The architecture

- **All env reads are runtime.** `config/runtime.exs` snapshots the OS
  environment into Application config once at boot; every read goes through
  the internal <code>ClaudeAgentSDK.Env</code> wrapper over that snapshot.
  Nothing reads env at compile time, so a release built on CI cannot bake in a
  build-machine value.
- **Variable names live in one registry** — `ClaudeAgentSDK.Config.Env` —
  not in string literals scattered through the code.
- **The snapshot is allowlisted.** `runtime.exs` copies only
  `Config.Env.all_known_vars/0` plus the `CLAUDE_`/`ANTHROPIC_` namespaces
  (`Config.Env.snapshot/1`). A whole-`System.get_env()` copy would spread
  every unrelated secret in the parent environment (database URLs, CI
  tokens) into inspectable Application config. **When adding a new env
  read, add the name to `all_known_vars/0`** (or use a `CLAUDE_`-prefixed
  name, which passes automatically).
- **CLI subprocesses are isolated.** The child env is built from the
  `Config.Env.passthrough_vars/0` allowlist (+ per-call overrides) and
  passed with `clear_env?: true` — the `claude` CLI sees only what the SDK
  hands it, not the whole node environment.

## The rules

1. **Read config at runtime, never compile-time.** Env-driven config —
   especially secrets — belongs in `config/runtime.exs` or inside a
   function, never in a module attribute or compile-time `config.exs`.
2. **Redact secrets from `inspect`.** Any struct holding a token, key, or
   password must carry `@derive {Inspect, except: [:the_secret_field]}`
   (or a custom `Inspect` impl). Structs get inspected in OTP crash
   reports, `Logger` metadata, and error tuples. In this SDK:
   `AuthManager` (`:token`) and `Options` (`:anthropic_auth_token`,
   `:env`) are redacted.
3. **Log names, not values.** Emit `env_keys: Map.keys(env)`; never log an
   env map's values or a raw token. Return offending **keys** in error
   tuples, not the full env (see `CliSubprocessCore.Command` env
   validation).
4. **Allowlist, don't snapshot-all** — for the runtime snapshot and for
   subprocess environments alike.
5. **Fail fast on required secrets.** Prefer raising at the launch
   boundary over letting a silent `nil` surface as a confusing failure
   later.
6. **Never commit secrets.** `.env` is gitignored in all three repos
   (`*.env.example` templates are fine); no literal keys in source or
   compile-time config. Token files are written `0600` (created with
   restrictive permissions before content is written, then renamed into
   place).
7. **Tests run with no secrets.** `mix test` passes with an empty
   environment; live paths are gated behind env flags
   (`LIVE_TESTS`, `CLAUDE_EXAMPLES_BACKEND`).

## Guardrails

`scripts/secrets_guard.sh` runs in `mix ci` across all three repos and
fails on:

- a `config/runtime.exs` that snapshots the whole env instead of an
  allowlist, and
- a `defstruct` in `lib/` declaring a secret-named field
  (`token`/`api_key`/`secret`/`password`/`auth_token`/`credential`/`bearer`)
  in a module without Inspect redaction.

Reviewed false positives (for example key-name registries, which hold
names rather than values) carry a same-line `# secret-safe:` annotation.
