# OS User Switching Gap

- **What’s missing:** `ClaudeAgentSDK.Options` exposes `:user`, but none of the transports honor it when spawning the CLI; every path runs as the current BEAM user. Python’s subprocess transport passes `user=self._options.user` to `anyio.open_process`, enabling privilege drop or alternate accounts.
- **Evidence (Python):** `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/transport/subprocess_cli.py:118-214` resolves the CLI and calls `anyio.open_process(..., user=self._options.user)`, wiring the option through.
- **Evidence (Elixir):** `lib/claude_agent_sdk/options.ex:97-121` defines the `:user` field, but `Transport.Port`, `Process`, `Streaming.Session`, and `Client` never read it (no `options.user` usage outside struct definition), so the spawned CLI cannot change user.
- **Impact:** Elixir cannot match Python’s ability to run the CLI under a restricted service account or alternate OS user, limiting security posture and deployment parity (e.g., CI sandboxes that require non-privileged execution).
- **Proposed fix:** Thread `options.user` into transport/exec layers (Port, erlexec, and any custom transport), add validation, and cover with integration tests (ensuring commands run as the requested user when supported by the platform).
