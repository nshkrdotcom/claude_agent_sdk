# Implementation Prompt: Python SDK Port (f834ba9..0434749)

You are implementing a port of Python SDK changes to this Elixir SDK. This is a TDD-driven implementation task with strict quality gates.

## Success Criteria (All Must Pass)

```bash
mix compile --warnings-as-errors  # Zero warnings
mix test                          # All unit tests pass
mix test --include integration    # Integration tests pass (requires CLI)
mix dialyzer                      # All green, no warnings
mix format --check-formatted      # Code formatted
```

## Required Reading (Read These First)

### Design Documents (read in order)
1. `docs/20251217/python_sdk_port_f834_to_0434749/00_overview.md` - Summary and implementation order
2. `docs/20251217/python_sdk_port_f834_to_0434749/01_user_message_uuid.md` - UUID parsing tests
3. `docs/20251217/python_sdk_port_f834_to_0434749/02_bundled_cli_version_and_installation.md` - CLI version constant
4. `docs/20251217/python_sdk_port_f834_to_0434749/03_docker_e2e_test_infra.md` - Docker harness
5. `docs/20251217/python_sdk_port_f834_to_0434749/04_filesystem_agents_regression.md` - Integration test

### Source Files to Understand
- `lib/claude_agent_sdk/message.ex` - Message parsing, `maybe_put_uuid/2` at lines 347-351
- `lib/claude_agent_sdk/cli.ex` - CLI discovery, `@minimum_version` at line 12
- `lib/claude_agent_sdk/options.ex` - Options struct, `setting_sources` at line 85
- `lib/claude_agent_sdk/client.ex` - Client implementation, `--replay-user-messages` at line 1417
- `test/test_helper.exs` - Test exclusions at line 17

### Existing Tests to Reference
- `test/claude_agent_sdk/client_test.exs` - Client test patterns
- `test/integration/live_smoke_test.exs` - Integration test patterns
- `test/claude_agent_sdk/message_test.exs` - Message parsing tests (if exists)

### Python Reference (for behavior verification)
- `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_cli_version.py` - Version constant
- `anthropics/claude-agent-sdk-python/tests/test_message_parser.py` - UUID test at lines 34-46
- `anthropics/claude-agent-sdk-python/e2e-tests/test_agents_and_settings.py` - Filesystem agents test

---

## Implementation Tasks (TDD Order)

### Task 1: Add Unit Tests for UUID Parsing

**Test first, then verify existing code passes.**

Create or update `test/claude_agent_sdk/message_uuid_test.exs`:

```elixir
defmodule ClaudeAgentSDK.MessageUuidTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.Message

  describe "user message uuid parsing" do
    test "parses uuid from user message into data.uuid" do
      json = ~s({"type":"user","uuid":"msg-abc123-def456","message":{"content":[{"type":"text","text":"Hello"}]}})
      assert {:ok, message} = Message.from_json(json)
      assert message.type == :user
      assert message.data.uuid == "msg-abc123-def456"
    end

    test "handles user message without uuid gracefully" do
      json = ~s({"type":"user","message":{"content":[{"type":"text","text":"Hello"}]}})
      assert {:ok, message} = Message.from_json(json)
      assert message.type == :user
      refute Map.has_key?(message.data, :uuid)
    end

    test "handles empty uuid string" do
      json = ~s({"type":"user","uuid":"","message":{"content":[{"type":"text","text":"Hello"}]}})
      assert {:ok, message} = Message.from_json(json)
      assert message.type == :user
      refute Map.has_key?(message.data, :uuid)
    end
  end
end
```

Run: `mix test test/claude_agent_sdk/message_uuid_test.exs`

These tests should pass with existing code (no changes needed to message.ex for parsing).

### Task 2: Add `Message.user_uuid/1` Helper (Optional)

If adding the helper, test first:

```elixir
# Add to message_uuid_test.exs
describe "user_uuid/1 helper" do
  test "returns uuid from user message data" do
    message = %Message{type: :user, data: %{uuid: "msg-123"}, raw: %{}}
    assert Message.user_uuid(message) == "msg-123"
  end

  test "falls back to raw when data.uuid missing" do
    message = %Message{type: :user, data: %{}, raw: %{"uuid" => "msg-456"}}
    assert Message.user_uuid(message) == "msg-456"
  end

  test "returns nil for non-user messages" do
    message = %Message{type: :assistant, data: %{}, raw: %{}}
    assert Message.user_uuid(message) == nil
  end

  test "returns nil when no uuid present" do
    message = %Message{type: :user, data: %{}, raw: %{}}
    assert Message.user_uuid(message) == nil
  end
end
```

Then implement in `lib/claude_agent_sdk/message.ex`:

```elixir
@doc """
Returns the checkpoint UUID from a user message, or nil.

Used with file checkpointing to identify rewind targets.
"""
@spec user_uuid(t()) :: String.t() | nil
def user_uuid(%__MODULE__{type: :user, data: %{uuid: uuid}}) when is_binary(uuid) and uuid != "", do: uuid
def user_uuid(%__MODULE__{type: :user, raw: %{"uuid" => uuid}}) when is_binary(uuid) and uuid != "", do: uuid
def user_uuid(_), do: nil
```

### Task 3: Add CLI Recommended Version

**Test first:**

Create `test/claude_agent_sdk/cli_version_test.exs`:

```elixir
defmodule ClaudeAgentSDK.CLIVersionTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.CLI

  describe "version constants" do
    test "recommended_version/0 returns semver string" do
      version = CLI.recommended_version()
      assert is_binary(version)
      assert {:ok, _} = Version.parse(version)
    end

    test "recommended_version is >= minimum_version" do
      {:ok, recommended} = Version.parse(CLI.recommended_version())
      {:ok, minimum} = Version.parse(CLI.minimum_version())
      assert Version.compare(recommended, minimum) in [:eq, :gt]
    end

    test "recommended_version is 2.0.72" do
      assert CLI.recommended_version() == "2.0.72"
    end
  end
end
```

Then implement in `lib/claude_agent_sdk/cli.ex`:

```elixir
# Add after @minimum_version
@recommended_version "2.0.72"

@doc """
Returns the recommended Claude CLI version for this SDK release.

This version is tested and known to work with all SDK features including
file checkpointing, streaming control protocol, and partial messages.
"""
@spec recommended_version() :: String.t()
def recommended_version, do: @recommended_version
```

### Task 4: Add Filesystem Agents Integration Test

Create `test/integration/filesystem_agents_test.exs`:

```elixir
defmodule ClaudeAgentSDK.Integration.FilesystemAgentsTest do
  @moduledoc """
  Regression test for filesystem agents loaded via setting_sources.

  This test catches issue #406 class failures where the SDK silently
  terminates after init without producing assistant/result messages.
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  alias ClaudeAgentSDK.{Client, Message, Options}

  describe "filesystem agents via setting_sources" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "claude_fs_agents_test_#{:rand.uniform(100_000)}")
      agents_dir = Path.join([tmp_dir, ".claude", "agents"])
      File.mkdir_p!(agents_dir)

      agent_content = """
      ---
      name: fs-test-agent
      description: Filesystem test agent for SDK regression testing
      tools: Read
      ---

      # Filesystem Test Agent

      You are a simple test agent. When asked a question, provide a brief answer.
      """

      File.write!(Path.join(agents_dir, "fs-test-agent.md"), agent_content)

      on_exit(fn ->
        # Windows may hold file handles briefly
        Process.sleep(100)
        File.rm_rf!(tmp_dir)
      end)

      {:ok, tmp_dir: tmp_dir}
    end

    test "loads agent from filesystem and produces full response", %{tmp_dir: tmp_dir} do
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

      message_types = Enum.map(messages, & &1.type)

      # Core regression check: must have all message types
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

  defp extract_agent_names(%Message{raw: raw}) do
    (raw["agents"] || [])
    |> List.wrap()
    |> Enum.flat_map(fn
      name when is_binary(name) -> [name]
      %{"name" => name} when is_binary(name) -> [name]
      _ -> []
    end)
  end
end
```

Run with: `mix test --include integration test/integration/filesystem_agents_test.exs`

### Task 5: Add Docker Test Infrastructure

Create `Dockerfile.test` at repo root:

```dockerfile
# Dockerfile.test - Run SDK tests in containerized environment
FROM hexpm/elixir:1.18.3-erlang-27.3.3-debian-bookworm-20241016

RUN apt-get update && apt-get install -y \
    curl \
    git \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/root/.local/bin:$PATH"

WORKDIR /app
COPY . .

# Install Elixir tooling and dependencies
RUN mix local.hex --force && mix local.rebar --force
RUN mix deps.get
RUN mix compile --warnings-as-errors

# Verify CLI installation
RUN claude -v

# Default: run unit tests
CMD ["mix", "test"]
```

Create `scripts/test-docker.sh`:

```bash
#!/bin/bash
# Run SDK tests in Docker container
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "Building Docker test image..."
docker build -f Dockerfile.test -t claude-sdk-elixir-test .

case "${1:-unit}" in
    unit)
        echo "Running unit tests in Docker..."
        docker run --rm claude-sdk-elixir-test mix test
        ;;
    integration)
        if [ -z "$ANTHROPIC_API_KEY" ]; then
            echo "Error: ANTHROPIC_API_KEY required for integration tests"
            exit 1
        fi
        echo "Running integration tests in Docker..."
        docker run --rm -e ANTHROPIC_API_KEY \
            claude-sdk-elixir-test mix test --include integration
        ;;
    all)
        echo "Running all tests in Docker..."
        docker run --rm claude-sdk-elixir-test mix test
        if [ -n "$ANTHROPIC_API_KEY" ]; then
            docker run --rm -e ANTHROPIC_API_KEY \
                claude-sdk-elixir-test mix test --include integration
        fi
        ;;
    *)
        echo "Usage: $0 [unit|integration|all]"
        exit 1
        ;;
esac

echo "Done!"
```

Make executable: `chmod +x scripts/test-docker.sh`

Create `.dockerignore`:

```
.git
_build
deps
cover
.elixir_ls
*.beam
*.ez
*.log
.DS_Store
priv/_bundled/
doc/
```

### Task 6: Update .gitignore

Ensure these entries exist in `.gitignore`:

```gitignore
# Bundled CLI binaries (not committed)
priv/_bundled/
```

---

## Documentation Updates

### Update README.md

Add to the "Installation" or "Requirements" section:

```markdown
### Claude CLI Version

This SDK requires Claude Code CLI. Recommended version: **2.0.72**

Install via npm (for version pinning):
```bash
npm install -g @anthropic-ai/claude-code@2.0.72
```

Or via official installer (installs latest):
```bash
curl -fsSL https://claude.ai/install.sh | bash
```

Check installed version:
```elixir
ClaudeAgentSDK.CLI.recommended_version()  # => "2.0.72"
ClaudeAgentSDK.CLI.version()              # => {:ok, "2.0.XX"}
```
```

### Update CHANGELOG.md

Add entry for today's date:

```markdown
## [v0.6.7] - 2025-12-17

### Added
- `ClaudeAgentSDK.CLI.recommended_version/0` - Returns recommended CLI version (2.0.72)
- `ClaudeAgentSDK.Message.user_uuid/1` - Helper to extract checkpoint UUID from user messages
- Unit tests for user message UUID parsing
- Integration test for filesystem agents loaded via `setting_sources`
- Docker test infrastructure (`Dockerfile.test`, `scripts/test-docker.sh`)

### Changed
- Improved documentation for file checkpointing workflow

### Python SDK Parity
- Ports changes from Python SDK f834ba9..0434749 (v0.1.17-v0.1.18)
- Adds UUID parsing test parity with `test_parse_user_message_with_uuid`
- Adds CLI version tracking parity with `_cli_version.py`
- Adds filesystem agents regression test parity with `test_filesystem_agent_loading`
```

### Update mix.exs Version

Bump version from current to next patch:

```elixir
# In mix.exs, update:
@version "0.6.7"  # or appropriate next version
```

### Update examples/README.md

Add entry for new example (if created):

```markdown
### filesystem_agents_live.exs

Demonstrates loading agents from `.claude/agents/` directory using `setting_sources: ["project"]`.

```bash
elixir examples/filesystem_agents_live.exs
```
```

### Update examples/run_all.sh

Add new example if created:

```bash
# Add to the list of examples
run_example "filesystem_agents_live.exs" "Filesystem agents via setting_sources"
```

---

## Verification Checklist

Run these commands and ensure all pass:

```bash
# 1. Compile with no warnings
mix compile --warnings-as-errors

# 2. Format check
mix format --check-formatted

# 3. Unit tests pass
mix test

# 4. New UUID tests pass specifically
mix test test/claude_agent_sdk/message_uuid_test.exs
mix test test/claude_agent_sdk/cli_version_test.exs

# 5. Integration tests pass (requires CLI installed)
mix test --include integration

# 6. Dialyzer passes with no warnings
mix dialyzer

# 7. Docker build succeeds (optional but recommended)
docker build -f Dockerfile.test -t claude-sdk-test .

# 8. Docker unit tests pass
docker run --rm claude-sdk-test mix test
```

---

## Files to Create/Modify Summary

### New Files
- `test/claude_agent_sdk/message_uuid_test.exs`
- `test/claude_agent_sdk/cli_version_test.exs`
- `test/integration/filesystem_agents_test.exs`
- `Dockerfile.test`
- `scripts/test-docker.sh`
- `.dockerignore`
- `examples/filesystem_agents_live.exs` (optional)

### Modified Files
- `lib/claude_agent_sdk/cli.ex` - Add `@recommended_version` and `recommended_version/0`
- `lib/claude_agent_sdk/message.ex` - Add `user_uuid/1` helper (optional)
- `mix.exs` - Bump version
- `README.md` - Add CLI version section
- `CHANGELOG.md` - Add release notes
- `.gitignore` - Ensure `priv/_bundled/` entry
- `examples/README.md` - Add new example docs
- `examples/run_all.sh` - Add new example

---

## Order of Implementation

1. Read all design docs first
2. Write and run UUID parsing tests (should pass with existing code)
3. Add `user_uuid/1` helper with tests
4. Add `recommended_version/0` with tests
5. Add filesystem agents integration test
6. Add Docker infrastructure
7. Update all documentation
8. Bump version
9. Run full verification checklist
10. Commit with message: `feat: Port Python SDK changes f834ba9..0434749 (uuid, cli version, docker, filesystem agents)`
