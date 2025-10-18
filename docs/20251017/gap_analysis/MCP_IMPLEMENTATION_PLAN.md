# MCP Tool System Implementation Plan

**Date:** 2025-10-17
**Status:** Infrastructure Ready (60% complete)
**Goal:** 100% feature parity with Python SDK MCP tool system
**Reference:** `docs/20251017/gap_analysis/001_errors.md`

---

## Current State Analysis

### ✅ What's Working
1. **Tool.Registry GenServer** - Fully implemented and tested
2. **`create_sdk_mcp_server/2`** - Server creation function ready
3. **`deftool` macro skeleton** - Macro compiles, generates modules
4. **Test suite** - Comprehensive tests written (29 tests total)
5. **Infrastructure** - All supporting code in place

### ❌ What's Missing
1. **Execute function injection** - The `deftool` macro doesn't inject the `execute/1` function from the do block
2. **Tool metadata collection** - The `@tools` module attribute isn't being accumulated properly
3. **Agent name field** - Agent.name is nil (should be set from struct creation)

### 🔍 Root Cause Analysis from 001_errors.md

**Problem 1: Execute function not generated**
- Lines 66-70, 87-91, 97-101: `UndefinedFunctionError` for `execute/1`
- Lines 107-110: `function_exported?(TestTools.Add, :execute, 1)` returns false
- Root cause: Line 151 in tool.ex has the block injection commented out

**Problem 2: Tool registration failing**
- Lines 74-82: `assert length(tools) == 3` fails (left: 0, right: 3)
- Root cause: `@tools` module attribute not accumulating across multiple `deftool` calls

**Problem 3: Missing __tool_metadata__/0**
- Lines 672-690: "CalculatorTools.Add is not a valid tool module (missing __tool_metadata__/0)"
- The module is created but `__tool_metadata__/0` isn't accessible
- Root cause: Module.create doesn't expose functions properly

**Problem 4: Agent.name is nil**
- Lines 424-440: Agent struct has `name: nil` instead of the key from the map
- Root cause: Agent.new/1 doesn't set the name field properly

---

## Implementation Plan

### Phase 1: Fix Agent.name Field (15 minutes)

**Issue:** Agent structs have `name: nil` when created from keyword list
**Impact:** Agent tests 13-20 failing (8 tests)

**Fix:**
```elixir
# In lib/claude_agent_sdk/agent.ex

def new(opts) when is_list(opts) do
  # Extract name from opts if present
  name = Keyword.get(opts, :name)

  struct(__MODULE__, Keyword.put(opts, :name, name))
  |> validate()
end
```

**Tests to verify:**
- `test/claude_agent_sdk/client_agents_test.exs`: Lines 312-556

---

### Phase 2: Fix deftool Macro - Execute Function Injection (2-3 hours)

**Issue:** The `execute/1` function isn't being injected into generated modules
**Impact:** All MCP tool tests failing (29 tests)

#### Approach 1: Use `defoverridable` with default implementation

```elixir
defmacro deftool(name, description, input_schema, do: block) when is_atom(name) do
  module_name = name |> Atom.to_string() |> Macro.camelize() |> String.to_atom()

  quote location: :keep do
    tool_module = Module.concat(__MODULE__, unquote(module_name))
    tool_name_val = unquote(name)
    desc = unquote(description)
    schema = unquote(Macro.escape(input_schema))

    # Define the nested tool module
    defmodule Module.concat(__MODULE__, unquote(module_name)) do
      @moduledoc """
      Tool: #{unquote(description)}
      """

      @tool_name unquote(name)
      @tool_description unquote(description)
      @tool_input_schema unquote(Macro.escape(input_schema))

      def __tool_metadata__ do
        %{
          name: @tool_name,
          description: @tool_description,
          input_schema: @tool_input_schema,
          module: __MODULE__
        }
      end

      # Inject the execute function from the do block
      unquote(block)
    end

    # Register tool metadata
    @tools {unquote(name), Module.concat(__MODULE__, unquote(module_name))}
  end
end
```

#### Approach 2: Simpler - Just use defmodule directly

The issue with Module.create is that it's too low-level. Use `defmodule` instead:

```elixir
defmacro deftool(name, description, input_schema, do: block) when is_atom(name) do
  module_name = name |> Atom.to_string() |> Macro.camelize() |> String.to_atom()

  quote location: :keep do
    # Use defmodule instead of Module.create
    defmodule Module.concat(__MODULE__, unquote(module_name)) do
      @moduledoc """
      Tool: #{unquote(description)}

      ## Input Schema

      ```elixir
      #{inspect(unquote(Macro.escape(input_schema)), pretty: true)}
      ```
      """

      @tool_name unquote(name)
      @tool_description unquote(description)
      @tool_input_schema unquote(Macro.escape(input_schema))

      @doc """
      Returns metadata about this tool.
      """
      def __tool_metadata__ do
        %{
          name: @tool_name,
          description: @tool_description,
          input_schema: @tool_input_schema,
          module: __MODULE__
        }
      end

      # CRITICAL: This injects the execute function
      unquote(block)
    end

    # Register tool with parent module
    Module.put_attribute(__MODULE__, :tools, %{
      name: unquote(name),
      module: Module.concat(__MODULE__, unquote(module_name))
    })
  end
end
```

**Key changes:**
1. Replace `Module.create` with `defmodule`
2. Uncomment and fix the `unquote(block)` line
3. Use `Module.put_attribute` to accumulate tools
4. Remove the binding of desc/schema variables (not needed with defmodule)

**Tests to verify:**
- `test/claude_agent_sdk/tool_test.exs`: All tests
- `test/claude_agent_sdk/tool/edge_cases_test.exs`: All tests
- `test/claude_agent_sdk/sdk_mcp_server_test.exs`: All tests

---

### Phase 3: Fix Tool Registration (@tools accumulation) (30 minutes)

**Issue:** The `@tools` module attribute doesn't accumulate across multiple `deftool` calls
**Impact:** `ClaudeAgentSDK.Tool.list_tools/1` returns empty list

**Current approach (broken):**
```elixir
@tools %{name: ..., module: ...}  # This overwrites, doesn't accumulate
```

**Fixed approach:**
```elixir
# In deftool macro, use Module.put_attribute with accumulate: true
Module.put_attribute(__MODULE__, :tools, tool_metadata)

# In __using__ macro, register accumulator
Module.register_attribute(__MODULE__, :tools, accumulate: true)
```

**Implementation:**

```elixir
defmacro __using__(_opts) do
  quote do
    import ClaudeAgentSDK.Tool, only: [deftool: 3, deftool: 4]

    # Register @tools as accumulating attribute
    Module.register_attribute(__MODULE__, :tools, accumulate: true)

    @before_compile ClaudeAgentSDK.Tool
  end
end

defmacro __before_compile__(_env) do
  quote do
    def __tools__ do
      # Get all accumulated tools
      @tools
    end
  end
end
```

Then update `list_tools/1`:
```elixir
def list_tools(module) do
  if function_exported?(module, :__tools__, 0) do
    module.__tools__()
  else
    []
  end
end
```

**Tests to verify:**
- `test/claude_agent_sdk/tool_test.exs:93` - "tools are discoverable"

---

### Phase 4: Integration Testing (1 hour)

Once the macro is fixed, run all tests:

```bash
mix test test/claude_agent_sdk/tool_test.exs
mix test test/claude_agent_sdk/tool/
mix test test/claude_agent_sdk/sdk_mcp_server_test.exs
```

**Expected results:**
- All 29 MCP tool tests passing
- Total: 389/389 tests passing (100%)
- Zero failures, zero warnings

---

## Detailed Implementation Steps

### Step 1: Fix Agent.name (15 min)

1. Edit `lib/claude_agent_sdk/agent.ex`
2. Modify `new/1` to properly set name field
3. Run: `mix test test/claude_agent_sdk/client_agents_test.exs`
4. Verify: 8 additional tests pass

### Step 2: Refactor deftool Macro (2-3 hours)

1. **Backup current implementation**
   ```bash
   cp lib/claude_agent_sdk/tool.ex lib/claude_agent_sdk/tool.ex.backup
   ```

2. **Implement new defmodule-based approach**
   - Replace `Module.create` with `defmodule`
   - Ensure `unquote(block)` works properly
   - Fix module attribute handling

3. **Test incrementally**
   ```bash
   # Test basic tool creation
   mix test test/claude_agent_sdk/tool_test.exs:67

   # Test execute function
   mix test test/claude_agent_sdk/tool_test.exs:69

   # Test tool registration
   mix test test/claude_agent_sdk/tool_test.exs:93
   ```

4. **Fix issues as they arise**
   - If `execute/1` not found: Check `unquote(block)` placement
   - If metadata missing: Check `__tool_metadata__/0` definition
   - If module not found: Check `Module.concat` usage

### Step 3: Fix Tool Registration (30 min)

1. **Add `__using__` macro with accumulate attribute**
2. **Add `__before_compile__` to expose `__tools__/0`**
3. **Update `list_tools/1` to call `__tools__/0`**
4. **Test:**
   ```bash
   mix test test/claude_agent_sdk/tool_test.exs:93
   ```

### Step 4: Integration & Validation (1 hour)

1. **Run full MCP test suite**
   ```bash
   mix test --only sdk_mcp
   mix test --only tool
   ```

2. **Run all tests**
   ```bash
   mix test
   ```

3. **Verify zero warnings**
   ```bash
   mix compile --warnings-as-errors
   ```

4. **Manual smoke test**
   ```elixir
   defmodule TestTools do
     use ClaudeAgentSDK.Tool

     deftool :greet, "Greets a person", %{type: "object"} do
       def execute(%{"name" => name}) do
         {:ok, %{"content" => [%{"type" => "text", "text" => "Hello, #{name}!"}]}}
       end
     end
   end

   # Should work:
   TestTools.Greet.execute(%{"name" => "Alice"})
   # => {:ok, %{"content" => [%{"type" => "text", "text" => "Hello, Alice!"}]}}

   # Should work:
   ClaudeAgentSDK.Tool.list_tools(TestTools)
   # => [%{name: :greet, module: TestTools.Greet, ...}]
   ```

---

## Success Criteria

### Compilation
- [ ] Zero compilation errors
- [ ] Zero compilation warnings
- [ ] All 41 files compile cleanly

### Tests
- [ ] All 419 tests passing
- [ ] Zero test failures
- [ ] Zero test warnings (except intentionally skipped)
- [ ] Specifically:
  - [ ] 29 MCP tool tests passing
  - [ ] 8 agent tests passing (currently failing due to Agent.name)
  - [ ] 360 existing tests still passing

### Functionality
- [ ] `deftool` macro creates nested modules
- [ ] `execute/1` function is generated and callable
- [ ] `__tool_metadata__/0` returns correct metadata
- [ ] `list_tools/1` returns all registered tools
- [ ] `create_sdk_mcp_server/2` creates working servers
- [ ] Tool.Registry executes tools correctly
- [ ] Agent.new/1` sets name field properly

### Code Quality
- [ ] Code follows Elixir conventions
- [ ] Functions have @doc and @spec
- [ ] Modules have @moduledoc
- [ ] No dead code or TODOs

---

## Estimated Timeline

| Task | Time | Cumulative |
|------|------|------------|
| **Phase 1:** Fix Agent.name | 15 min | 15 min |
| **Phase 2:** Fix deftool macro | 2-3 hours | 2.25-3.25 hours |
| **Phase 3:** Fix tool registration | 30 min | 2.75-3.75 hours |
| **Phase 4:** Integration testing | 1 hour | 3.75-4.75 hours |
| **Buffer for issues** | 1-2 hours | 4.75-6.75 hours |
| **Total** | **~5-7 hours** | - |

---

## Risk Assessment

### High Risk
- **Macro complexity**: Elixir macros can be tricky
  - **Mitigation:** Use simpler `defmodule` instead of `Module.create`
  - **Fallback:** Simplified API without macro (function-based)

### Medium Risk
- **Module attribute accumulation**: May not work as expected
  - **Mitigation:** Test incrementally, use `Module.put_attribute`
  - **Fallback:** Store tools in process dictionary or registry

### Low Risk
- **Test compatibility**: Tests may need updates
  - **Mitigation:** Tests are well-written and comprehensive
  - **Fallback:** Update tests if API changes slightly

---

## Alternative Approach (If Macro Fails)

If the macro approach proves too complex, use a simpler function-based API:

```elixir
# Instead of:
deftool :greet, "Greets", schema do
  def execute(input), do: ...
end

# Use:
ClaudeAgentSDK.Tool.define(__MODULE__, :greet, "Greets", schema, fn input ->
  # implementation
end)
```

This is less elegant but guaranteed to work. Can add macro sugar later.

---

## Next Steps

1. ✅ Read and understand this plan
2. ⏭️  Implement Phase 1 (Agent.name fix)
3. ⏭️  Implement Phase 2 (deftool macro fix)
4. ⏭️  Implement Phase 3 (tool registration fix)
5. ⏭️  Run integration tests
6. ⏭️  Commit with all tests passing

---

## References

- **Error log:** `docs/20251017/gap_analysis/001_errors.md`
- **Python reference:** `claude-agent-sdk-python/examples/mcp_calculator.py`
- **Python tests:** `claude-agent-sdk-python/tests/test_sdk_mcp_integration.py`
- **Current implementation:** `lib/claude_agent_sdk/tool.ex`
- **Test file:** `test/claude_agent_sdk/tool_test.exs`
- **Elixir macro guide:** https://elixir-lang.org/getting-started/meta/macros.html
