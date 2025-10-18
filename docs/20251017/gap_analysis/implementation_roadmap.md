# Implementation Roadmap: Achieving Feature Parity

**Date:** 2025-10-17
**Target:** 95% feature parity with Python SDK
**Estimated Timeline:** 4-6 weeks

---

## Current Status: 65-70% Parity

### Strengths (Elixir Advantages)
- ✅ Authentication system (multi-provider)
- ✅ Debug & diagnostics
- ✅ Concurrent orchestration
- ✅ Query/streaming core
- ✅ Hooks system

### Critical Gaps
- ❌ MCP tool system (0% complete)
- ❌ Agent definitions (0% complete)
- ⚠️ Permission system (30% complete)
- ⚠️ Transport abstraction (50% complete)
- ⚠️ Configuration options (55% complete)

---

## Phase 1: Critical Features (Weeks 1-3)

### 1.1 MCP Tool System (Week 1-2)
**Priority:** CRITICAL
**Effort:** 10-12 days
**Dependencies:** None

#### Tasks
1. **Define Tool Macro** (2 days)
   - Create `ClaudeAgentSDK.Tool` module
   - Implement `deftool/4` macro for tool definition
   - Support name, description, input schema
   - Generate tool metadata at compile time

2. **Implement Tool Registry** (2 days)
   - Create `ClaudeAgentSDK.Tool.Registry` GenServer
   - Register tools at compile time
   - Support runtime tool lookup
   - Handle tool execution dispatch

3. **SDK MCP Server** (3 days)
   - Implement `create_sdk_mcp_server/2`
   - Create in-process MCP server (no subprocess)
   - Handle MCP protocol for tool calls
   - Support tool result serialization

4. **Tool Execution Framework** (2 days)
   - Implement tool call routing
   - Handle async tool execution
   - Error handling and timeouts
   - Result formatting

5. **Integration & Testing** (2 days)
   - Integration with existing query flow
   - Unit tests for tool system
   - E2E tests with sample tools
   - Example: calculator tool

**Deliverables:**
```elixir
defmodule MyTools do
  use ClaudeAgentSDK.Tool

  deftool :calculator,
    "Performs basic calculations",
    %{
      type: "object",
      properties: %{
        expression: %{type: "string"}
      },
      required: ["expression"]
    } do
    def execute(%{"expression" => expr}) do
      # Implementation
      {:ok, result}
    end
  end
end

server = ClaudeAgentSDK.create_sdk_mcp_server(
  name: "my-tools",
  version: "1.0.0",
  tools: [MyTools.Calculator]
)

options = Options.new(mcp_servers: [server])
```

**Success Criteria:**
- [ ] `deftool` macro compiles and registers tools
- [ ] In-process tool execution works
- [ ] No subprocess overhead
- [ ] Example calculator tool functional
- [ ] Tests pass

---

### 1.2 Agent Definitions (Week 2-3)
**Priority:** HIGH
**Effort:** 5-7 days
**Dependencies:** None

#### Tasks
1. **Define Agent Struct** (1 day)
   - Create `ClaudeAgentSDK.Agent` module
   - Define agent struct with fields:
     - `name`, `description`, `prompt`
     - `allowed_tools`, `model`
   - Add validation

2. **Agent Configuration** (1 day)
   - Add `agents` and `agent` to `Options`
   - Support agent list in options
   - Set active agent on startup

3. **Agent Switching API** (2 days)
   - Add `set_agent/2` to `Client` GenServer
   - Handle agent transitions
   - Update system prompt on switch
   - Update allowed tools on switch

4. **Agent Context Management** (1 day)
   - Track current agent in client state
   - Preserve conversation context
   - Handle tool filtering per agent

5. **Testing & Examples** (1-2 days)
   - Unit tests for agent switching
   - Integration tests with multiple agents
   - Example: code agent + research agent

**Deliverables:**
```elixir
code_agent = %ClaudeAgentSDK.Agent{
  name: :code_expert,
  description: "Expert Python developer",
  prompt: "You are an expert Python developer...",
  allowed_tools: ["read", "write", "bash"],
  model: "claude-sonnet-4"
}

research_agent = %ClaudeAgentSDK.Agent{
  name: :researcher,
  description: "Research specialist",
  prompt: "You excel at research...",
  allowed_tools: ["websearch", "webfetch"],
  model: "claude-opus-4"
}

options = Options.new(
  agents: [code_agent, research_agent],
  agent: code_agent
)

{:ok, client} = Client.start_link(options)
Client.set_agent(client, research_agent)
```

**Success Criteria:**
- [ ] Agent struct defined and validated
- [ ] Agent configuration in options
- [ ] `set_agent/2` functional
- [ ] Agent switching preserves context
- [ ] Tests pass

---

### 1.3 Permission System Completion (Week 3)
**Priority:** MEDIUM-HIGH
**Effort:** 5-7 days
**Dependencies:** None

#### Tasks
1. **Permission Callback API** (2 days)
   - Define `can_use_tool` callback signature
   - Create `PermissionContext` struct
   - Add to options: `permission_mode`, `can_use_tool`
   - Implement callback invocation in tool execution

2. **Permission Modes** (2 days)
   - Implement 4 modes: `:default`, `:accept_edits`, `:plan`, `:bypass_permissions`
   - Mode-specific behavior
   - Mode switching via `set_permission_mode/2`

3. **Permission Updates** (2 days)
   - Create `PermissionUpdate` struct
   - Support add/remove/replace operations
   - Destination-aware updates (user/project/local/session)
   - Persistence of permission rules

4. **Testing** (1 day)
   - Unit tests for permission callbacks
   - Integration tests with different modes
   - Example: tool permission callback

**Deliverables:**
```elixir
defmodule MyApp.Permissions do
  def can_use_tool(context) do
    case {context.tool_name, context.input} do
      {"dangerous_tool", _} ->
        {:deny, reason: "Not allowed"}

      {"read", %{"file_path" => path}} ->
        if String.starts_with?(path, "/etc/") do
          {:deny, reason: "Cannot read system files"}
        else
          :allow
        end

      _ ->
        :allow
    end
  end
end

options = Options.new(
  permission_mode: :plan,
  can_use_tool: &MyApp.Permissions.can_use_tool/1
)

Client.set_permission_mode(client, :accept_edits)
```

**Success Criteria:**
- [ ] Permission callback functional
- [ ] All 4 modes implemented
- [ ] Runtime mode switching works
- [ ] Tests pass

---

## Phase 2: Enhanced Parity (Week 4)

### 2.1 Transport Abstraction (3-4 days)
**Priority:** MEDIUM
**Effort:** 3-4 days
**Dependencies:** None

#### Tasks
1. **Define Transport Behavior** (1 day)
   ```elixir
   defmodule ClaudeAgentSDK.Transport do
     @callback init(opts :: keyword()) :: {:ok, state :: any()} | {:error, term()}
     @callback send(state, message :: String.t()) :: {:ok, state} | {:error, term()}
     @callback receive(state) :: {:ok, Stream.t(), state} | {:error, term()}
     @callback close(state) :: :ok
   end
   ```

2. **Refactor CLI Transport** (1 day)
   - Move `Process.stream` to `Transport.CLI`
   - Implement behavior callbacks
   - Maintain backward compatibility

3. **Transport Configuration** (1 day)
   - Add `transport` option
   - Default to CLI transport
   - Support custom transport modules

4. **Documentation & Example** (0.5 day)
   - Document transport behavior
   - Example custom transport (HTTP/WebSocket)

**Success Criteria:**
- [ ] Transport behavior defined
- [ ] CLI transport refactored
- [ ] Custom transport possible
- [ ] Backward compatible

---

### 2.2 Runtime Control APIs (2-3 days)
**Priority:** MEDIUM
**Effort:** 2-3 days
**Dependencies:** None

#### Tasks
1. **Implement `interrupt/1`** (1 day)
   - Add to `Client` GenServer
   - Kill current process
   - Clean up state
   - Return control to user

2. **Implement `set_model/2`** (0.5 day)
   - Add to `Client` GenServer
   - Update model in options
   - Apply to next query

3. **Implement `set_max_turns/2`** (0.5 day)
   - Dynamic turn limit updates
   - Apply to current session

4. **Testing** (0.5-1 day)
   - Tests for each control method
   - Integration tests

**Deliverables:**
```elixir
Client.interrupt(client)
Client.set_model(client, "claude-opus-4")
Client.set_max_turns(client, 20)
```

**Success Criteria:**
- [ ] All control methods functional
- [ ] State updates properly
- [ ] Tests pass

---

### 2.3 Missing Configuration Options (1-2 days)
**Priority:** MEDIUM
**Effort:** 1-2 days
**Dependencies:** None

#### Tasks
1. **`include_partial_messages`** (0.5 day)
   - Add option to Options
   - Stream partial message updates
   - Document behavior

2. **`stderr_callback`** (0.5 day)
   - Add callback option
   - Capture stderr from process
   - Invoke callback on stderr output

3. **`setting_source`** (0.5 day)
   - Add explicit setting source control
   - Support: `:user`, `:project`, `:local`, `:session`
   - Map to CLI arguments

4. **`allowed_tools`** (0.5 day)
   - Add to options (currently via hooks)
   - Filter tools in options
   - More explicit than hooks

**Success Criteria:**
- [ ] All options implemented
- [ ] CLI integration works
- [ ] Tests pass

---

## Phase 3: Polish & Examples (Week 5-6)

### 3.1 Example Migration (3-5 days)
**Priority:** LOW-MEDIUM
**Effort:** 3-5 days
**Dependencies:** Phases 1-2 complete

#### Examples to Port
1. **Comprehensive hooks example** (1 day)
   - Port `hooks.py` (350 LOC)
   - Demonstrate all 6 hook types
   - Show output builders

2. **MCP tools example** (1 day)
   - Port `mcp_calculator.py` (193 LOC)
   - Demonstrate `deftool` macro
   - Show SDK MCP server creation

3. **Agent switching example** (0.5 day)
   - Port `agents.py` (124 LOC)
   - Demonstrate multiple agents
   - Show runtime switching

4. **Permission callback example** (0.5 day)
   - Port `tool_permission_callback.py` (158 LOC)
   - Demonstrate permission modes
   - Show callback logic

5. **Setting sources example** (0.5 day)
   - Port `setting_sources.py` (173 LOC)
   - Show user/project/local configs
   - Demonstrate precedence

6. **Partial messages example** (0.5 day)
   - Port `include_partial_messages.py` (62 LOC)
   - Show streaming partial updates

7. **Stderr callback example** (0.5 day)
   - Port `stderr_callback_example.py` (43 LOC)
   - Show error output handling

**Success Criteria:**
- [ ] 7 key examples ported
- [ ] Examples run successfully
- [ ] Documentation updated

---

### 3.2 Documentation Updates (2-3 days)
**Priority:** LOW-MEDIUM
**Effort:** 2-3 days
**Dependencies:** Phases 1-2 complete

#### Tasks
1. **API Documentation** (1 day)
   - Update all @moduledoc
   - Add examples to @doc
   - Document new features

2. **Migration Guide** (1 day)
   - Python → Elixir migration guide
   - API equivalency table
   - Common patterns

3. **Feature Comparison** (0.5 day)
   - Update README with feature matrix
   - Highlight Elixir advantages
   - Note Python parity status

4. **Changelog** (0.5 day)
   - Document new features
   - Breaking changes (if any)
   - Version bump to v0.4.0

**Success Criteria:**
- [ ] All modules documented
- [ ] Migration guide complete
- [ ] README updated
- [ ] Changelog current

---

### 3.3 Testing & Quality (2-3 days)
**Priority:** MEDIUM
**Effort:** 2-3 days
**Dependencies:** Phases 1-2 complete

#### Tasks
1. **Integration Test Suite** (1 day)
   - E2E tests for new features
   - Cross-feature integration tests
   - Live testing with Claude CLI

2. **Code Quality** (0.5 day)
   - Run Credo
   - Run Dialyzer
   - Fix warnings

3. **Performance Testing** (0.5 day)
   - Benchmark new features
   - Ensure no regressions
   - Profile memory usage

4. **Documentation Testing** (0.5 day)
   - Run doctests
   - Verify examples
   - Test code snippets in docs

**Success Criteria:**
- [ ] All tests pass
- [ ] No quality warnings
- [ ] Performance acceptable
- [ ] Doctests pass

---

## Timeline Summary

| Phase | Duration | Features | Completion |
|-------|----------|----------|------------|
| **Phase 1.1** | Week 1-2 (10-12 days) | MCP Tool System | 0% → 80% |
| **Phase 1.2** | Week 2-3 (5-7 days) | Agent Definitions | 0% → 95% |
| **Phase 1.3** | Week 3 (5-7 days) | Permission System | 30% → 95% |
| **Phase 2.1** | Week 4 (3-4 days) | Transport Abstraction | 50% → 95% |
| **Phase 2.2** | Week 4 (2-3 days) | Runtime Control | 50% → 95% |
| **Phase 2.3** | Week 4 (1-2 days) | Config Options | 55% → 90% |
| **Phase 3.1** | Week 5 (3-5 days) | Examples | 25% → 75% |
| **Phase 3.2** | Week 5-6 (2-3 days) | Documentation | - | - |
| **Phase 3.3** | Week 6 (2-3 days) | Testing & QA | - | - |
| **Total** | **4-6 weeks** | **All Features** | **65% → 95%** |

---

## Resource Requirements

### Development
- **1 Senior Elixir Engineer** (full-time)
  - Experience with macros, GenServers, protocols
  - Understanding of MCP protocol
  - Familiarity with Claude SDK

### Testing
- **Claude CLI Access** (all developers)
- **Test Anthropic API Keys**
- **Test environments** for Bedrock, Vertex (optional)

### Documentation
- **Technical Writer** (part-time, weeks 5-6)
  - Or developer time for documentation

---

## Risk Assessment

### High Risk
1. **MCP Tool System Complexity**
   - **Risk:** Macro implementation may be complex
   - **Mitigation:** Start with simple implementation, iterate
   - **Contingency:** 2-3 extra days budgeted

2. **Python SDK Changes**
   - **Risk:** Python SDK may update during development
   - **Mitigation:** Lock to specific Python SDK version for parity
   - **Contingency:** Budget 2-3 days for sync-up

### Medium Risk
3. **Permission System Integration**
   - **Risk:** May conflict with existing hooks
   - **Mitigation:** Design compatibility layer
   - **Contingency:** 1-2 extra days

4. **Transport Abstraction Breaking Changes**
   - **Risk:** May break existing code
   - **Mitigation:** Maintain backward compatibility
   - **Contingency:** Version as breaking change if needed

### Low Risk
5. **Example Migration**
   - **Risk:** Examples may not translate perfectly
   - **Mitigation:** Adapt to Elixir idioms where needed
   - **Contingency:** Document differences

---

## Success Metrics

### Quantitative
- [ ] **95% feature parity** achieved
- [ ] **All critical features** implemented (MCP, Agents, Permissions)
- [ ] **Test coverage** maintained at 80%+
- [ ] **All examples** running successfully
- [ ] **Zero high-severity bugs** in new code

### Qualitative
- [ ] **API feels idiomatic** to Elixir developers
- [ ] **Documentation is comprehensive** and clear
- [ ] **Migration path** from Python is straightforward
- [ ] **Performance** is acceptable (no regressions)
- [ ] **Code quality** meets project standards

---

## Post-Completion

### v0.4.0 Release
- Tag release
- Publish to Hex.pm
- Announce feature parity

### Future Enhancements (Beyond Parity)
1. **Elixir-Specific Features**
   - Distributed query execution
   - ETS-based result caching
   - Phoenix LiveView integration

2. **Advanced Orchestration**
   - Supervision tree integration
   - Backpressure handling
   - Resource pooling

3. **Monitoring & Observability**
   - Telemetry integration
   - Metrics export
   - Distributed tracing

---

## Conclusion

This roadmap provides a **structured path to 95% feature parity** with the Python SDK within **4-6 weeks**. The phased approach prioritizes critical features first (MCP tools, agents, permissions) while preserving Elixir's unique advantages (orchestration, auth, debugging).

**Key Success Factors:**
1. Focus on **critical gaps first** (Phase 1)
2. Maintain **backward compatibility**
3. Preserve **Elixir advantages**
4. Ensure **comprehensive testing**
5. Provide **excellent documentation**

With this roadmap, the Elixir SDK will achieve **functional equivalence** with Python while offering **superior capabilities** in orchestration, authentication, and debugging.
