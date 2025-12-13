# Agent Prompt: Audit Python SDK Porting Documentation

## Context

You are auditing documentation for porting changes from the Python `claude-agent-sdk` to an Elixir port. The documentation was created by analyzing commits between `d553184` and `f834ba9` (versions v0.1.11 to v0.1.16) of the Python SDK.

## Your Task

Critically audit and edit the porting documentation in this directory. Your job is to:

1. **Verify accuracy** - Ensure the Python implementation details are correctly described
2. **Validate Elixir recommendations** - Check that proposed Elixir implementations are idiomatic and correct
3. **Identify gaps** - Find any missing details, edge cases, or implementation considerations
4. **Fix errors** - Correct any mistakes in code examples, type definitions, or explanations
5. **Improve clarity** - Enhance explanations where needed

## Repository Locations

- **Python SDK (original)**: `/home/home/p/g/n/claude_agent_sdk/anthropics/claude-agent-sdk-python/`
- **Elixir SDK (port target)**: `/home/home/p/g/n/claude_agent_sdk/`
- **Documentation to audit**: `/home/home/p/g/n/claude_agent_sdk/docs/20251213/python_sdk_porting/`

## Step-by-Step Audit Process

### Phase 1: Understand the Python Changes

First, analyze the actual Python SDK commits to understand what changed:

```bash
# Navigate to Python SDK
cd /home/home/p/g/n/claude_agent_sdk/anthropics/claude-agent-sdk-python

# View commit history
git log d553184..f834ba9 --oneline

# For each feature, examine the actual diff:
git show ea0ef25 -p  # Tools option
git show 4e56cb1 -p  # SDK beta support
git show 53482d8 -p  # File checkpointing
git show 3cbb9e5 -p  # Rate limit detection
git show 2d67166 -p  # Write lock
git show f21f63e -p  # Sandbox adapter
```

Read the following Python files to understand current implementation:
- `src/claude_agent_sdk/types.py` - Type definitions
- `src/claude_agent_sdk/_internal/transport/subprocess_cli.py` - CLI command building
- `src/claude_agent_sdk/_internal/query.py` - Query implementation
- `src/claude_agent_sdk/_internal/message_parser.py` - Message parsing
- `src/claude_agent_sdk/client.py` - Client implementation

### Phase 2: Understand the Elixir Codebase

Read the relevant Elixir files to understand current structure:

```elixir
# Core files to read:
lib/claude_agent_sdk/options.ex          # Options struct and CLI arg building
lib/claude_agent_sdk/message.ex          # Message parsing
lib/claude_agent_sdk/client.ex           # Bidirectional client
lib/claude_agent_sdk/process.ex          # CLI subprocess management
lib/claude_agent_sdk/control_protocol/protocol.ex  # Control protocol
lib/claude_agent_sdk/assistant_error.ex  # Error types
lib/claude_agent_sdk/option_builder.ex   # Option presets
```

### Phase 3: Audit Each Document

For each document in the directory, verify:

#### 00_overview.md
- [ ] Commit hashes and version numbers are correct
- [ ] File change summary matches actual diff
- [ ] Priority rankings make sense
- [ ] Implementation order is logical

#### 01_tools_option.md
- [ ] Python type definitions match actual `types.py`
- [ ] CLI flag generation logic matches `subprocess_cli.py`
- [ ] Three modes (array, empty, preset) are correctly described
- [ ] Elixir type definitions are idiomatic
- [ ] Elixir CLI arg builder handles all cases
- [ ] Test cases cover edge cases
- [ ] Difference from allowed_tools/disallowed_tools is accurate

#### 02_sdk_beta.md
- [ ] SdkBeta type definition is correct
- [ ] Beta values match Anthropic's documented betas
- [ ] CLI flag format is correct (`--betas` with comma-separated values)
- [ ] Elixir default value handling is correct (empty list vs nil)

#### 03_file_checkpointing.md
- [ ] Environment variable name is correct (`CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING`)
- [ ] Control protocol request format matches Python
- [ ] UserMessage UUID extraction is correctly documented
- [ ] Elixir GenServer call/response handling is correct
- [ ] Error handling for disabled checkpointing is appropriate

#### 04_rate_limit_detection.md
- [ ] Error field location is correct (nested in `message` vs root level)
- [ ] AssistantError types match what CLI actually sends
- [ ] Elixir already has partial implementation - verify accuracy
- [ ] Manual JSON parsing fallback handles error field

#### 05_write_lock.md
- [ ] Python race condition explanation is accurate
- [ ] Assessment of Elixir's GenServer serialization is correct
- [ ] Recommendation (lock needed vs not needed) is sound
- [ ] If lock IS needed, the implementation is correct

#### 06_sandbox_adapter.md
- [ ] All SandboxSettings fields are documented
- [ ] Settings merging logic (JSON vs file path) is correct
- [ ] Network config options are complete
- [ ] Key distinction (behavior vs restrictions) is clear

### Phase 4: Cross-Check Implementation Details

For each feature, verify the following mappings are correct:

| Python | Elixir | CLI Flag |
|--------|--------|----------|
| `ClaudeAgentOptions.tools` | `Options.tools` | `--tools` |
| `ClaudeAgentOptions.betas` | `Options.betas` | `--betas` |
| `ClaudeAgentOptions.enable_file_checkpointing` | `Options.enable_file_checkpointing` | env var |
| `ClaudeAgentOptions.sandbox` | `Options.sandbox` | merged into `--settings` |
| `AssistantMessage.error` | `Message.data.error` | - |
| `Query.rewind_files()` | `Client.rewind_files/2` | control protocol |

### Phase 5: Verify Test Coverage

For each feature, ensure tests cover:
- Happy path (feature works as expected)
- Edge cases (empty values, nil values, invalid input)
- Integration with existing features
- Error handling

### Phase 6: Check for Missing Items

Look for anything I may have missed:

1. **Other commits** - Are there any significant changes between d553184..f834ba9 not documented?
2. **Breaking changes** - Do any changes break backwards compatibility?
3. **Dependencies** - Are there new dependencies or version requirements?
4. **CLI version requirements** - What minimum CLI version is needed for each feature?
5. **Deprecations** - Are any existing features deprecated?

Run:
```bash
git log d553184..f834ba9 --oneline | wc -l  # Count total commits
git diff d553184..f834ba9 --stat             # See all changed files
```

## Output Format

After auditing, for each document:

1. **If changes needed**: Edit the file directly with corrections
2. **If major issues found**: Add a `## Audit Notes` section at the bottom documenting concerns
3. **If document is accurate**: No changes needed

Create a summary file `AUDIT_RESULTS.md` with:
- List of documents reviewed
- Changes made to each
- Any unresolved questions or concerns
- Recommendations for implementation priority adjustments

## Critical Questions to Answer

1. Does the Elixir SDK already implement any of these features? (Check for existing code)
2. Are there any Elixir-specific considerations not addressed? (OTP patterns, supervision, etc.)
3. Are the proposed type definitions compatible with existing Elixir SDK types?
4. Do the test examples actually compile and make sense?
5. Is the `build_settings_value` function for sandbox correctly handling all cases?
6. Is the error field extraction location correct for rate limit detection?

## Constraints

- Do NOT change the overall documentation structure (keep the numbered files)
- Do NOT add features not in the Python SDK commits
- Do focus on accuracy and correctness over style
- Do preserve existing working code examples
- Do add clarifying notes where the original documentation is ambiguous

## Starting Point

Begin by reading `00_overview.md` to understand the scope, then systematically work through each document. Use the Python SDK source code as the authoritative reference for implementation details.

Good luck with the audit!
