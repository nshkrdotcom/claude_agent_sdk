# Port: Filesystem Agents + `--setting-sources` Regression Coverage (Issue #406 Class)

## Background (Python, commit a0ce44a)

Python added an end-to-end regression for a failure mode described in issue #406:

- When using `setting_sources=["project"]` with a `.claude/agents/` directory,
  the SDK could **silently terminate after the init SystemMessage**, never yielding:
  - AssistantMessage
  - ResultMessage

Python mitigations in v0.1.18:
- Adds `e2e-tests/test_agents_and_settings.py::test_filesystem_agent_loading` (lines 28-96)
- Adds example `examples/filesystem_agents.py` (107 lines)
- Adds fixture `.claude/agents/test-agent.md` (9 lines)
- Adds Docker harness (`Dockerfile.test`, `scripts/test-docker.sh`) to reproduce container behavior

## Elixir Current State

### What already works

- **`setting_sources` option:** `Options.setting_sources` at `lib/claude_agent_sdk/options.ex:85`
  - Emits `--setting-sources` flag via `add_setting_sources_args/2` at lines 635-641
  - Defaults to empty string `""` (no filesystem settings loaded)

- **Inline agents:** `Options.agents` and `Options.agent` supported
  - `add_agents_args/2` at lines 750-763 serializes to `--agents` JSON
  - `add_agent_args/2` at lines 766-769 emits `--agent`

- **CLI discovery:** `ClaudeAgentSDK.CLI.find_executable/0` checks:
  - `priv/_bundled/claude` (bundled)
  - PATH (`claude-code`, `claude`)
  - Known locations including `~/.claude/local/claude`

### Gaps

1. **No regression test** for filesystem agents loaded via `setting_sources: ["project"]`

2. **Init metadata not exposed in `Message.data`:**
   - Python reads `SystemMessage.data["agents"]`, `["slash_commands"]`, `["output_style"]`
   - Elixir's `build_system_data(:init, raw)` at `message.ex:426-435` only extracts:
     - `api_key_source`, `cwd`, `session_id`, `tools`, `mcp_servers`, `model`, `permission_mode`
   - `agents`, `output_style`, `slash_commands` only available in `Message.raw`

## Port Design (Elixir)

### 1) Add a targeted integration test (required)

Add `test/integration/filesystem_agents_test.exs`:

```elixir
defmodule ClaudeAgentSDK.Integration.FilesystemAgentsTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias ClaudeAgentSDK.{Client, Message, Options}

  describe "filesystem agents via setting_sources" do
    setup do
      # Create temp directory with agent file
      tmp_dir = Path.join(System.tmp_dir!(), "claude_test_#{:rand.uniform(100_000)}")
      agents_dir = Path.join([tmp_dir, ".claude", "agents"])
      File.mkdir_p!(agents_dir)

      agent_content = """
      ---
      name: fs-test-agent
      description: Filesystem test agent for SDK testing
      tools: Read
      ---

      # Filesystem Test Agent

      You are a simple test agent. When asked a question, provide a brief answer.
      """

      File.write!(Path.join(agents_dir, "fs-test-agent.md"), agent_content)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      {:ok, tmp_dir: tmp_dir}
    end

    test "loads agent and produces full response", %{tmp_dir: tmp_dir} do
      options = %Options{
        cwd: tmp_dir,
        setting_sources: ["project"],
        max_turns: 1,
        output_format: :stream_json
      }

      {:ok, client} = Client.start_link(options)
      :ok = Client.query(client, "Say hello in exactly 3 words")
      {:ok, messages} = Client.receive_response(client)
      Client.stop(client)

      # Collect message types
      message_types = Enum.map(messages, & &1.type)

      # Must have init, assistant, result
      assert :system in message_types, "Missing system (init) message"
      assert :assistant in message_types,
        "Missing assistant message - got only: #{inspect(message_types)}. " <>
        "This may indicate issue #406 (silent failure with filesystem agents)."
      assert :result in message_types, "Missing result message"

      # Verify agent was loaded from filesystem
      init = Enum.find(messages, &(&1.type == :system and &1.subtype == :init))
      agent_names = extract_agent_names(init)
      assert "fs-test-agent" in agent_names,
        "fs-test-agent not loaded from filesystem. Found: #{inspect(agent_names)}"
    end
  end

  # Extract agent names from init message (robust to different shapes)
  defp extract_agent_names(%Message{raw: raw}) do
    agents = raw["agents"] || []

    agents
    |> List.wrap()
    |> Enum.flat_map(fn
      name when is_binary(name) -> [name]
      %{"name" => name} when is_binary(name) -> [name]
      _ -> []
    end)
  end
end
```

**Tagging note:** Use `@moduletag :integration` (excluded by default in `test_helper.exs`). Run with `mix test --include integration`.

### 2) Optional: Improve init metadata ergonomics

Extend `build_system_data(:init, raw)` in `message.ex` to include additional fields:

```elixir
defp build_system_data(:init, raw) do
  %{
    api_key_source: raw["apiKeySource"],
    cwd: raw["cwd"],
    session_id: raw["session_id"],
    tools: raw["tools"] || [],
    mcp_servers: raw["mcp_servers"] || [],
    model: raw["model"],
    permission_mode: raw["permissionMode"],
    # New fields for parity
    agents: raw["agents"] || [],
    output_style: raw["output_style"],
    slash_commands: raw["slash_commands"] || []
  }
end
```

This allows tests and user code to access `message.data.agents` directly instead of `message.raw["agents"]`.

### 3) Optional: Add example script

Add `examples/filesystem_agents_live.exs` for manual testing:

```elixir
#!/usr/bin/env elixir
# Example: Loading filesystem-based agents via setting_sources
# Usage: elixir examples/filesystem_agents_live.exs

Mix.install([{:claude_agent_sdk, path: "."}])

alias ClaudeAgentSDK.{Client, Options}

# Use repo's .claude/agents/ if it exists, or create temp
cwd = if File.dir?(".claude/agents"), do: ".", else: System.tmp_dir!()

options = %Options{
  cwd: cwd,
  setting_sources: ["project"],
  max_turns: 1,
  output_format: :stream_json
}

{:ok, client} = Client.start_link(options)
:ok = Client.query(client, "Say hello in exactly 3 words")
{:ok, messages} = Client.receive_response(client)
Client.stop(client)

IO.puts("Message types received: #{inspect(Enum.map(messages, & &1.type))}")

init = Enum.find(messages, &(&1.type == :system and &1.subtype == :init))
IO.puts("Agents loaded: #{inspect(init.raw["agents"])}")
```

## Proposed Elixir Touchpoints

| File | Change | Priority |
|------|--------|----------|
| `test/integration/filesystem_agents_test.exs` | Regression test | Required |
| `lib/claude_agent_sdk/message.ex` | Add `agents`, `output_style`, `slash_commands` to init data | Optional |
| `examples/filesystem_agents_live.exs` | Example script | Optional |

## Docker Connection

Once the integration test exists, it's the primary target for:

- `./scripts/test-docker.sh integration`
- CI docker integration job (when secrets configured)

## Failure Signatures To Detect

The regression should explicitly fail if:

- Only init message received (no assistant)
- No result message
- Agent not loaded from filesystem

The test prints observed message types on failure for diagnosis.

## Risks / Open Questions

1. **Exact agent wire format** - The CLI may return agents as strings or objects. The test's `extract_agent_names/1` handles both.

2. **Temp directory cleanup on Windows** - May need `Process.sleep(500)` before cleanup if file handles are held open (Python does this).
