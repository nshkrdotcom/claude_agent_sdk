# Port: Filesystem Agents + `--setting-sources` Regression Coverage (Issue #406 Class)

## Background (Python)

Python added an end-to-end regression for a failure mode described in issue #406:

- When using `setting_sources=["project"]` with a `.claude/agents/` directory,
  the SDK could **silently terminate after the init SystemMessage**, never yielding:
  - AssistantMessage
  - ResultMessage

Python mitigations in v0.1.18:
- Adds a Docker harness to reproduce container-specific behavior
- Adds `e2e-tests/test_agents_and_settings.py::test_filesystem_agent_loading`
- Adds an example `examples/filesystem_agents.py`
- Adds a fixture agent file `.claude/agents/test-agent.md`

## Elixir Current State

### Good news

- Elixir supports `Options.setting_sources` and emits `--setting-sources` (default empty string).
- Elixir supports inline `Options.agents` (`--agents`) and active `--agent`.
- CLI discovery already checks `~/.claude/local/claude` and supports an optional `priv/_bundled/claude`.

### Gaps relevant to porting the regression

1. No Elixir integration test that exercises:
   - `setting_sources: ["project"]`
   - a `.claude/agents/*.md` file on disk
   - asserts **init → assistant → result**
2. Init metadata ergonomics:
   - Python reads `SystemMessage.data["agents"]`, `["slash_commands"]`, `["output_style"]`
   - Elixir currently retains this in `Message.raw` but only normalizes a small subset into `Message.data`

## Port Design (Elixir)

### 1) Add a targeted live/integration test

Add a new integration test module, e.g.:

- `test/integration/filesystem_agents_live_test.exs`

Test mechanics (mirrors Python’s tempdir approach):

1. Create a temp directory `project_dir`
2. Write `.claude/agents/fs-test-agent.md` with minimal frontmatter:
   ```md
   ---
   name: fs-test-agent
   description: Filesystem test agent
   tools: Read
   ---
   You are a simple test agent.
   ```
3. Run a query with:
   - `%Options{cwd: project_dir, setting_sources: ["project"], max_turns: 1, output_format: :stream_json}`
4. Collect emitted messages into a list
5. Assert:
   - at least one `%Message{type: :system, subtype: :init}`
   - at least one `%Message{type: :assistant}`
   - a final `%Message{type: :result, subtype: :success}` (or at least `:result`)
6. Verify the agent was loaded:
   - Preferred (if we add it): `init.data.agents`
   - Otherwise: `init.raw["agents"]` includes `"fs-test-agent"`

Tagging:
- `@moduletag :integration`
- `@moduletag :live`

#### Agent extraction helper (robust to shapes)

Python treats `agents` as “list of strings (names) or dicts with `name`”.
To avoid coupling to the exact shape, the Elixir test should normalize similarly:

```elixir
defp extract_agent_names(init_message) do
  agents = init_message.raw["agents"] || init_message.data[:agents] || []

  agents
  |> List.wrap()
  |> Enum.flat_map(fn
    name when is_binary(name) -> [name]
    %{"name" => name} when is_binary(name) -> [name]
    %{ "name" => name } when is_binary(name) -> [name]
    _ -> []
  end)
  |> Enum.reject(&(&1 == ""))
end
```

### 2) Add settings-source behavioral tests (optional)

Python also verifies settings source semantics:

- default (empty sources) loads no local settings
- `["user"]` excludes project commands
- `["user","project","local"]` includes local settings like `outputStyle`

We can add similar Elixir integration tests, but keep them minimal:

- Use a temp dir with `.claude/settings.local.json` containing:
  - `{"outputStyle":"local-test-style"}`
- Assert `init.raw["output_style"]` (or normalized data) matches expectations.

### 3) Improve init metadata ergonomics (recommended)

To make Elixir parity closer to Python, extend `ClaudeAgentSDK.Message` system init normalization to include:

- `agents`
- `slash_commands`
- `output_style`

Design options:

1. **Minimal additive** (lowest risk)
   - Keep existing atom-keyed fields
   - Add pass-through keys for these fields only
2. **Full pass-through**
   - Store the whole init payload under `data.init_raw` (still keep `message.raw` as-is)

The minimal additive approach is enough to support the regression test and improves devX without changing existing keys.

### 4) Add an Elixir example script (optional but useful)

Add `examples/filesystem_agents_live.exs` mirroring Python’s `examples/filesystem_agents.py`:

- runs with `setting_sources: ["project"]`
- points `cwd` at a directory containing `.claude/agents`
- prints which message types were received
- prints loaded agents from init payload

This becomes a practical repro script when debugging container-only issues.

## Proposed Elixir Touchpoints

- New: `test/integration/filesystem_agents_live_test.exs`
- Update (recommended): `lib/claude_agent_sdk/message.ex` (`build_system_data/2` for subtype `:init`) to include `agents`, `slash_commands`, `output_style`
- Update (if we normalize init fields): `lib/claude_agent_sdk/mock.ex` default system init payload should include representative `agents`/`output_style` keys so unit tests and examples stay realistic
- New (optional): `examples/filesystem_agents_live.exs`

## Docker Connection

Once the above integration test exists, it becomes the primary target for:

- `./scripts/test-docker.sh integration`
- a CI docker integration job (when credentials exist)

## Failure Signatures To Detect

The regression should explicitly fail if we see:

- Only init message received
- No assistant message
- No result message

The test should print the observed message types on failure for diagnosis.
