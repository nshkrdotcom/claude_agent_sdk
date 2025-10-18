# Implementation Prompt: Critical Features using TDD

**Date:** 2025-10-17
**Target Features:** MCP Tool System, Agent Definitions, Permission System
**Approach:** Test-Driven Development (TDD) with Parallel Agent Execution

---

## Overview

This prompt orchestrates the implementation of three critical missing features using TDD methodology. Three specialized agents will work in parallel, each responsible for one feature area.

---

## Required Reading (ALL AGENTS - Read First)

### Core Design Documents
1. **[executive_summary.md](./executive_summary.md)**
   - Purpose: Understand overall gap context and priorities
   - Focus: Critical gaps section, recommendations

2. **[feature_gap_analysis.md](./feature_gap_analysis.md)**
   - Purpose: Detailed understanding of what's missing
   - Focus: Sections 2 (MCP Tools), 4 (Agents), 3 (Permissions)

3. **[api_comparison.md](./api_comparison.md)**
   - Purpose: See Python reference implementations
   - Focus: Sections 5 (MCP), 7 (Agents), 6 (Permissions)

4. **[implementation_roadmap.md](./implementation_roadmap.md)**
   - Purpose: Understand implementation plan and success criteria
   - Focus: Phase 1 sections for your assigned feature

5. **[architecture_differences.md](./architecture_differences.md)**
   - Purpose: Understand Elixir architectural patterns to follow
   - Focus: Section 1 (Concurrency), Section 2 (State Management)

### Elixir SDK Architecture (Understand Before Implementing)
6. **[../../ARCHITECTURE.md](../../ARCHITECTURE.md)**
   - Purpose: Understand existing SDK architecture
   - Focus: Module organization, GenServer patterns, existing abstractions

7. **[../../COMPREHENSIVE_MANUAL.md](../../COMPREHENSIVE_MANUAL.md)**
   - Purpose: Understand current SDK capabilities
   - Focus: How features integrate together

### Existing Elixir Codebase (Reference Implementations)
8. **[lib/claude_agent_sdk.ex](../../../lib/claude_agent_sdk.ex)**
   - Purpose: Main entry point, understand public API patterns
   - Focus: Function signatures, documentation style

9. **[lib/claude_agent_sdk/options.ex](../../../lib/claude_agent_sdk/options.ex)**
   - Purpose: Configuration patterns
   - Focus: Struct definition, validation, conversion to CLI args

10. **[lib/claude_agent_sdk/client.ex](../../../lib/claude_agent_sdk/client.ex)**
    - Purpose: GenServer patterns for stateful clients
    - Focus: State management, callbacks, message handling

11. **[lib/claude_agent_sdk/hooks/hooks.ex](../../../lib/claude_agent_sdk/hooks/hooks.ex)**
    - Purpose: Hook system architecture (reference for permissions)
    - Focus: Hook registration, callback invocation, pattern matching

12. **[lib/claude_agent_sdk/hooks/output.ex](../../../lib/claude_agent_sdk/hooks/output.ex)**
    - Purpose: Output builder pattern (reference for permissions)
    - Focus: Builder functions, validation, composition

### Testing Patterns (Critical for TDD)
13. **[test/claude_agent_sdk/client_test.exs](../../../test/claude_agent_sdk/client_test.exs)**
    - Purpose: GenServer testing patterns
    - Focus: Setup, assertions, async testing

14. **[test/claude_agent_sdk/hooks/hooks_test.exs](../../../test/claude_agent_sdk/hooks/hooks_test.exs)**
    - Purpose: Hook testing patterns
    - Focus: Callback testing, matcher testing

15. **[test/claude_agent_sdk/mock_test.exs](../../../test/claude_agent_sdk/mock_test.exs)**
    - Purpose: Mock framework usage
    - Focus: How to use SDK mocking in tests

### Python Reference (Understand Expected Behavior)
16. **[../../../claude-agent-sdk-python/src/claude_agent_sdk/__init__.py](../../../claude-agent-sdk-python/src/claude_agent_sdk/__init__.py)**
    - Purpose: Python public API exports
    - Focus: What types and functions are exposed

17. **[../../../claude-agent-sdk-python/src/claude_agent_sdk/types.py](../../../claude-agent-sdk-python/src/claude_agent_sdk/types.py)**
    - Purpose: Type definitions (convert to Elixir specs/structs)
    - Focus: Message types, option types, permission types

---

## Agent-Specific Required Reading

### Agent 1: MCP Tool System

#### Additional Python Reference
- **[claude-agent-sdk-python/examples/mcp_calculator.py](../../../claude-agent-sdk-python/examples/mcp_calculator.py)** (193 LOC)
  - Purpose: See complete example of tool usage
  - Focus: `@tool` decorator syntax, server creation, tool execution

- **[claude-agent-sdk-python/tests/test_sdk_mcp_integration.py](../../../claude-agent-sdk-python/tests/test_sdk_mcp_integration.py)** (265 LOC)
  - Purpose: Understand test coverage expectations
  - Focus: Tool registration tests, execution tests, error handling

#### Elixir Patterns to Study
- **[lib/claude_agent_sdk/process.ex](../../../lib/claude_agent_sdk/process.ex)** (570 LOC)
  - Purpose: Understand how to spawn and manage processes
  - Focus: Port communication, message streaming

- **Macro References** (if needed for `deftool` macro):
  - Elixir macro documentation
  - Module attribute usage (`@tool_metadata`)

#### Success Criteria (from roadmap)
Your implementation must:
- [ ] `deftool` macro compiles and registers tools
- [ ] In-process tool execution works (no subprocess)
- [ ] Tool registry GenServer manages tool lookup
- [ ] Example calculator tool is functional
- [ ] All tests pass with >80% coverage

---

### Agent 2: Agent Definitions

#### Additional Python Reference
- **[claude-agent-sdk-python/examples/agents.py](../../../claude-agent-sdk-python/examples/agents.py)** (124 LOC)
  - Purpose: See agent switching in action
  - Focus: Agent creation, configuration, switching API

- **[claude-agent-sdk-python/tests/test_agents_and_settings.py](../../../claude-agent-sdk-python/tests/e2e-tests/test_agents_and_settings.py)** (168 LOC)
  - Purpose: Agent testing patterns
  - Focus: Agent validation, switching behavior, context preservation

#### Elixir Patterns to Study
- **[lib/claude_agent_sdk/client.ex](../../../lib/claude_agent_sdk/client.ex)** (625 LOC)
  - Purpose: You'll be adding agent switching to this GenServer
  - Focus: State updates, handle_call patterns, state preservation

- **[lib/claude_agent_sdk/options.ex](../../../lib/claude_agent_sdk/options.ex)** (285 LOC)
  - Purpose: You'll add agent options here
  - Focus: Struct validation, option handling

#### Success Criteria (from roadmap)
Your implementation must:
- [ ] Agent struct defined with validation
- [ ] Agent configuration in options works
- [ ] `set_agent/2` function is implemented
- [ ] Agent switching preserves conversation context
- [ ] All tests pass with >80% coverage

---

### Agent 3: Permission System

#### Additional Python Reference
- **[claude-agent-sdk-python/examples/tool_permission_callback.py](../../../claude-agent-sdk-python/examples/tool_permission_callback.py)** (158 LOC)
  - Purpose: See permission callbacks in action
  - Focus: Callback signature, context usage, allow/deny logic

- **[claude-agent-sdk-python/tests/test_tool_callbacks.py](../../../claude-agent-sdk-python/tests/test_tool_callbacks.py)** (488 LOC)
  - Purpose: Permission testing patterns
  - Focus: Callback invocation, mode switching, permission updates

#### Elixir Patterns to Study
- **[lib/claude_agent_sdk/hooks/](../../../lib/claude_agent_sdk/hooks/)**
  - Purpose: Hooks provide the foundation for permissions
  - Focus: How to extend hooks for permission callbacks

- **[lib/claude_agent_sdk/hooks/output.ex](../../../lib/claude_agent_sdk/hooks/output.ex)** (387 LOC)
  - Purpose: Output builders can be adapted for permission results
  - Focus: Builder pattern, validation, composition

#### Success Criteria (from roadmap)
Your implementation must:
- [ ] Permission callback API is functional
- [ ] All 4 modes implemented (default, accept_edits, plan, bypass_permissions)
- [ ] Runtime mode switching works via `set_permission_mode/2`
- [ ] Permission context includes tool name, input, session info
- [ ] All tests pass with >80% coverage

---

## TDD Workflow Instructions

Once you've completed the required reading, follow this TDD workflow:

### Phase 1: Test Design (Days 1-2)

#### Step 1: Analyze Python Tests
- Read Python test files for your feature
- Understand test structure and coverage
- Identify edge cases being tested
- Note assertion patterns

#### Step 2: Design Elixir Test Suite
Create comprehensive test files with:
- Unit tests for each module/function
- Integration tests for feature workflows
- Edge case tests
- Error handling tests

#### Step 3: Write Failing Tests
- Implement test structure with `describe` blocks
- Write test cases with clear expectations
- Use stubs for implementation (intentionally fail)
- Ensure tests are runnable (`mix test`)

**Deliverable:** Complete test file(s) with all tests failing (red)

#### Self-Reflection Checkpoint
Before proceeding, review:
- [ ] Do tests cover all success paths?
- [ ] Do tests cover all error paths?
- [ ] Are edge cases tested?
- [ ] Are tests independent and isolated?
- [ ] Do test descriptions clearly state intent?
- [ ] Is test data realistic and representative?

---

### Phase 2: Implementation (Days 3-5)

#### Step 4: Implement Minimal Code (Green)
- Create module/function stubs
- Implement simplest logic to pass first test
- Run tests iteratively
- One test passing at a time

#### Step 5: Expand Implementation
- Add functionality for next failing test
- Keep implementation minimal but correct
- Focus on making tests pass
- Don't add features not covered by tests

#### Step 6: Achieve All Tests Passing
- Continue until all tests are green
- Fix bugs discovered during testing
- Handle edge cases properly

**Deliverable:** All tests passing (green)

#### Self-Reflection Checkpoint
Before refactoring, review:
- [ ] Are all tests passing?
- [ ] Does implementation match design from roadmap?
- [ ] Are error cases handled gracefully?
- [ ] Is the code understandable?
- [ ] Are there obvious code smells?

---

### Phase 3: Refactor (Days 6-7)

#### Step 7: Refactor for Quality
- Extract duplicated code
- Improve naming and clarity
- Add documentation (@moduledoc, @doc, @spec)
- Optimize performance if needed
- Keep tests passing throughout

#### Step 8: Integration Testing
- Test feature with existing SDK components
- Verify no regressions in other tests
- Test with mock framework
- Test example usage

#### Step 9: Documentation
- Add comprehensive @moduledoc
- Add @doc for all public functions
- Add @spec for type safety
- Create usage examples in docs
- Update relevant guides

**Deliverable:** Production-ready, documented code

#### Final Self-Reflection
Before declaring complete, review:
- [ ] All tests passing (including existing tests)
- [ ] Code is well-documented
- [ ] Examples work correctly
- [ ] Code follows Elixir conventions
- [ ] No obvious performance issues
- [ ] Error messages are helpful
- [ ] Success criteria from roadmap met

---

## Parallel Agent Execution

### Spawn Instructions

Once you've completed the initial required reading above, execute:

```elixir
# Spawn three parallel agents for TDD implementation

<agents>
spawn agent_1: MCP Tool System Agent
- Assigned Feature: MCP Tool System (Section 1.1 of roadmap)
- Timeline: 10-12 days
- Starting Point: Phase 1 - Test Design
- Required Reading: General + Agent 1 specific
- Success Criteria: All checkboxes in Agent 1 section

spawn agent_2: Agent Definitions Agent
- Assigned Feature: Agent Definitions (Section 1.2 of roadmap)
- Timeline: 5-7 days
- Starting Point: Phase 1 - Test Design
- Required Reading: General + Agent 2 specific
- Success Criteria: All checkboxes in Agent 2 section

spawn agent_3: Permission System Agent
- Assigned Feature: Permission System (Section 1.3 of roadmap)
- Timeline: 5-7 days
- Starting Point: Phase 1 - Test Design
- Required Reading: General + Agent 3 specific
- Success Criteria: All checkboxes in Agent 3 section
</agents>
```

### Agent Communication
- Agents work independently on separate features
- No inter-agent dependencies in Phase 1
- Coordinate during integration testing (Phase 2, Step 8)
- Report completion status to main orchestrator

---

## Implementation Guidelines

### Code Quality Standards

#### Elixir Conventions
- Follow [Elixir Style Guide](https://github.com/christopheradams/elixir_style_guide)
- Use `mix format` for consistent formatting
- Run `mix credo` for code quality checks
- Run `mix dialyzer` for type checking

#### Documentation Requirements
```elixir
defmodule ClaudeAgentSDK.YourModule do
  @moduledoc """
  Brief description of module purpose.

  Longer explanation with examples.

  ## Examples

      iex> YourModule.function(args)
      {:ok, result}
  """

  @doc """
  Function description.

  ## Parameters

    * `param1` - description
    * `param2` - description

  ## Returns

    * `{:ok, result}` - success case
    * `{:error, reason}` - error case

  ## Examples

      iex> function(valid_input)
      {:ok, result}

      iex> function(invalid_input)
      {:error, :invalid}
  """
  @spec function(String.t(), keyword()) :: {:ok, any()} | {:error, atom()}
  def function(param1, param2 \\ []) do
    # Implementation
  end
end
```

#### Testing Standards
```elixir
defmodule ClaudeAgentSDK.YourModuleTest do
  use ExUnit.Case, async: true

  describe "function/2" do
    test "returns success for valid input" do
      result = YourModule.function("valid", key: "value")
      assert {:ok, _} = result
    end

    test "returns error for invalid input" do
      result = YourModule.function("", key: "value")
      assert {:error, :invalid} = result
    end

    test "handles edge case: nil values" do
      result = YourModule.function(nil, [])
      assert {:error, _} = result
    end
  end

  describe "integration" do
    test "works with other SDK components" do
      # Integration test
    end
  end
end
```

### Error Handling Patterns
```elixir
# Use tagged tuples for expected errors
{:ok, result} | {:error, reason}

# Use raise for unexpected/programming errors
raise ArgumentError, "invalid argument"

# Provide helpful error messages
{:error, {:validation_failed, "tool name must be a string, got: #{inspect(value)}"}}
```

### GenServer Patterns
```elixir
defmodule ClaudeAgentSDK.YourServer do
  use GenServer

  # Client API
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def your_function(server \\ __MODULE__, arg) do
    GenServer.call(server, {:your_function, arg})
  end

  # Server Callbacks
  @impl true
  def init(opts) do
    state = %{
      # Initialize state
    }
    {:ok, state}
  end

  @impl true
  def handle_call({:your_function, arg}, _from, state) do
    # Handle call
    {:reply, result, new_state}
  end

  @impl true
  def terminate(reason, state) do
    # Cleanup
    :ok
  end
end
```

---

## Checkpoints and Reporting

### Daily Standup (Self-Report)
Each agent should report:
1. **Yesterday:** Tests written, tests passing, implementation progress
2. **Today:** Planning to work on (specific tests/functions)
3. **Blockers:** Any issues or questions

### Phase Completion Reports
At the end of each phase:
1. **Phase 1 Report:** Number of tests written, test coverage planned
2. **Phase 2 Report:** Tests passing percentage, implementation completeness
3. **Phase 3 Report:** Final metrics (coverage, quality scores, documentation)

### Metrics to Track
- **Test Count:** Total tests, passing tests, failing tests
- **Coverage:** Line coverage percentage (aim for >80%)
- **Quality:** Credo score, Dialyzer warnings
- **Documentation:** Functions documented, examples added

---

## Success Definition

Each feature is considered complete when:

### Technical Criteria
- [ ] All tests passing (100%)
- [ ] Test coverage >80%
- [ ] No Credo warnings
- [ ] No Dialyzer errors
- [ ] All public functions documented
- [ ] @specs for all public functions

### Functional Criteria
- [ ] Feature matches Python SDK behavior
- [ ] Integration with existing SDK works
- [ ] Examples run successfully
- [ ] No regressions in existing tests

### Quality Criteria
- [ ] Code follows Elixir conventions
- [ ] Error messages are clear and helpful
- [ ] Performance is acceptable
- [ ] Documentation is comprehensive

---

## Post-Implementation Integration

Once all three agents complete their features:

### Integration Phase
1. **Merge Order:** MCP Tools → Agents → Permissions
2. **Integration Testing:** Run full test suite after each merge
3. **Example Creation:** Create examples using all three features together
4. **Documentation Update:** Update main README with new features

### Final Validation
- [ ] All features work together
- [ ] No feature interactions cause issues
- [ ] Performance is acceptable with all features enabled
- [ ] Documentation is updated

---

## Common Pitfalls to Avoid

### TDD Pitfalls
- ❌ **Writing implementation before tests**
  - ✅ Always write failing test first

- ❌ **Testing implementation details**
  - ✅ Test behavior and contracts

- ❌ **Making tests pass by cheating**
  - ✅ Implement real logic, not hard-coded returns

- ❌ **Skipping refactor phase**
  - ✅ Always refactor after green

### Elixir-Specific Pitfalls
- ❌ **Mutable state patterns from other languages**
  - ✅ Use immutable data and GenServer state

- ❌ **Forgetting to handle all error cases**
  - ✅ Pattern match all return types

- ❌ **Not using OTP patterns**
  - ✅ Use GenServer, Supervisor for stateful components

- ❌ **Poor error messages**
  - ✅ Provide context in error tuples

### Integration Pitfalls
- ❌ **Breaking existing functionality**
  - ✅ Run full test suite frequently

- ❌ **Not testing with mock framework**
  - ✅ Use ClaudeAgentSDK.Mock in tests

- ❌ **Ignoring existing conventions**
  - ✅ Follow patterns from existing code

---

## Resources

### Elixir Documentation
- [Elixir Getting Started](https://elixir-lang.org/getting-started/introduction.html)
- [ExUnit Documentation](https://hexdocs.pm/ex_unit/ExUnit.html)
- [GenServer Guide](https://hexdocs.pm/elixir/GenServer.html)
- [Elixir Macros](https://elixir-lang.org/getting-started/meta/macros.html)

### Testing Resources
- [Testing Elixir Book](https://pragprog.com/titles/lmelixir/testing-elixir/)
- [ExUnit Best Practices](https://hexdocs.pm/ex_unit/ExUnit.html#module-best-practices)

### SDK-Specific
- Main README: `../../README.md`
- Architecture Doc: `../../ARCHITECTURE.md`
- Hooks Guide: `../../HOOKS_GUIDE.md`

---

## Questions and Support

If blocked or have questions:
1. **Review required reading** - Answer might be there
2. **Check Python tests** - See how Python SDK handles it
3. **Review existing Elixir patterns** - Look for similar code
4. **Consult roadmap** - Check success criteria and guidance

---

**Ready to begin? Start with required reading, then spawn the three agents!**
