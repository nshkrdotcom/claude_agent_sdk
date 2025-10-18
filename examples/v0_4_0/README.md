# v0.4.0 Examples

Examples demonstrating the three major features added in v0.4.0:
- MCP Tool System
- Agent Definitions
- Permission Control

## Running Examples

All examples can be run with:

```bash
mix run examples/v0_4_0/EXAMPLE_NAME.exs
```

## Examples

### 1. MCP Calculator Tool (`mcp_calculator_tool.exs`)

Demonstrates creating in-process MCP tools using the `deftool` macro.

```bash
mix run examples/v0_4_0/mcp_calculator_tool.exs
```

**What it shows:**
- Defining tools with `deftool` macro
- Tool input schemas and validation
- Creating SDK MCP server with `create_sdk_mcp_server/1`
- Registering tools in the registry
- Direct tool execution
- Using tools in Claude queries

**Key concepts:**
- In-process tools (no subprocess overhead)
- Automatic `execute/1` and `__tool_metadata__/0` generation
- Tool registration and discovery
- Complex input schemas

---

### 2. Agent Switching (`agent_switching.exs`)

Demonstrates defining multiple agent profiles and switching between them at runtime.

```bash
mix run examples/v0_4_0/agent_switching.exs
```

**What it shows:**
- Defining agent profiles with `Agent.new/1`
- Configuring multiple agents in Options
- Runtime agent switching with `Client.set_agent/2`
- Querying current agent with `Client.get_agent/1`
- Listing available agents with `Client.get_available_agents/1`
- Each agent has different prompt, tools, and model

**Key concepts:**
- Multi-agent workflows
- Agent-specific configurations
- Runtime agent switching
- Context preservation across switches
- Different models for different agents

---

### 3. Permission Control (`permission_control.exs`)

Demonstrates fine-grained tool permission control using callbacks.

```bash
mix run examples/v0_4_0/permission_control.exs
```

**What it shows:**
- Defining permission callbacks
- Blocking dangerous operations
- Redirecting file writes to safe locations
- Logging tool usage
- Four permission modes (default, accept_edits, plan, bypass_permissions)
- Runtime permission mode switching
- Input modification before tool execution

**Key concepts:**
- Security-first tool execution
- Permission callbacks with context
- Tool input modification
- Execution interrupts for critical violations
- Permission modes for different security levels
- Audit logging

---

### 4. Full Feature Showcase (`full_feature_showcase.exs`)

Demonstrates all three features working together in a realistic workflow.

```bash
mix run examples/v0_4_0/full_feature_showcase.exs
```

**What it shows:**
- MCP tools, agents, and permissions integrated
- Realistic multi-agent workflow
- Security controls across agent switches
- Runtime configuration changes

**Key concepts:**
- Feature integration
- Real-world workflows
- Combining multiple features
- Complete SDK capabilities

---

## Example Output

### MCP Calculator Tool
```
=== MCP Calculator Tool Example ===

Creating SDK MCP server with calculator tools...
✅ Server created: calculator v1.0.0
   Type: sdk
   Registry PID: #PID<0.123.0>

📦 Registered tools (3):
   - add: Add two numbers together
   - multiply: Multiply two numbers
   - factorial: Calculate factorial of a number

--- Direct Tool Execution Demo ---

Executing tools directly (without Claude):
add(15, 27): 15 + 27 = 42
multiply(8, 9): 8 × 9 = 72
factorial(5): 5! = 120
```

### Agent Switching
```
=== Agent Switching Example ===

✅ Defined 3 agents:
   - code_expert: Expert Python programmer
   - researcher: Research and analysis specialist
   - technical_writer: Technical documentation expert

📋 Starting client with code_expert as active agent...

Current agent: code_expert

🔄 Switching agents...

1. Switching to researcher agent
   Active agent: researcher
   Model: claude-opus-4
   Allowed tools: ["WebSearch", "WebFetch", "Read"]

2. Switching to technical_writer agent
   Active agent: technical_writer
   Model: claude-sonnet-4
   Allowed tools: ["Read", "Write"]
```

### Permission Control
```
=== Permission Control Example ===

Testing permission callback with various scenarios:

✅ ALLOWED: Safe bash command

🚫 BLOCKED: Dangerous bash command: rm -rf /important/data...

⚠️  REDIRECTED: /etc/config.conf → /tmp/safe_output/config.conf

✅ ALLOWED: Write to /home/user/output.txt

📖 LOGGED: Reading /home/user/data.txt
```

---

## Key Takeaways

### MCP Tools
- Define tools once, use them anywhere
- No subprocess overhead
- Type-safe with schemas
- Easy to test and debug

### Agents
- Specialize behavior for different tasks
- Switch contexts without losing state
- Configure per-agent tools and models
- Clean separation of concerns

### Permissions
- Security-first approach
- Audit all tool usage
- Modify or block operations
- Multiple security levels

### Integration
- All features work together seamlessly
- Runtime configuration changes
- No conflicts or interference
- Clean, composable API

---

## Next Steps

After running these examples, check out:
- [Comprehensive Manual](../../COMPREHENSIVE_MANUAL.md) - Full API documentation
- [Hooks Guide](../../HOOKS_GUIDE.md) - Advanced hook system
- [Gap Analysis](../../docs/20251017/gap_analysis/README.md) - Feature parity details
- [Architecture](../../ARCHITECTURE.md) - System design

For more examples:
- `examples/` - Basic examples
- `examples/hooks/` - Hook system examples
- `test/` - Test suite for reference implementations
