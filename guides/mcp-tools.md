# MCP Tools Guide

**Version:** 0.7.2 | **Last Updated:** 2025-12-29

---

## Table of Contents

1. [What is MCP (Model Context Protocol)](#what-is-mcp-model-context-protocol)
2. [MCP Server Types](#mcp-server-types)
3. [Creating Tools with deftool Macro](#creating-tools-with-deftool-macro)
4. [Tool Schema (JSON Schema Format)](#tool-schema-json-schema-format)
5. [Tool Execution and Return Values](#tool-execution-and-return-values)
6. [Creating SDK MCP Servers](#creating-sdk-mcp-servers)
7. [Tool Naming Convention](#tool-naming-convention)
8. [Using External MCP Servers](#using-external-mcp-servers)
9. [Combining MCP with Hooks and Permissions](#combining-mcp-with-hooks-and-permissions)
10. [Best Practices](#best-practices)

---

## What is MCP (Model Context Protocol)

MCP (Model Context Protocol) is an open protocol that enables integration between LLM applications and external tools/data sources. It uses JSON-RPC 2.0 for communication and provides a standardized way to extend Claude's capabilities with custom tools.

### Core Concepts

| Term | Description |
|------|-------------|
| **MCP Server** | A provider of tools, resources, or prompts |
| **Tool** | A function/capability that Claude can invoke |
| **Resource** | Data or context that Claude can access |
| **Host** | The LLM application (Claude Agent SDK) |
| **Client** | The MCP client that connects host to server |

### Protocol Notes (Python Parity)

- SDK MCP routing implements `initialize`, `tools/list`, `tools/call`, and `notifications/initialized`.
- `resources/list` and `prompts/list` return JSON-RPC method-not-found errors (matching the Python SDK).
- Tool names are kept as strings end-to-end; the registry normalizes tool names to strings to avoid atom leakage.

### Why Use MCP?

- **Standardized Protocol**: Works across different LLM applications
- **In-Process Execution**: SDK MCP tools run without subprocess overhead
- **Type Safety**: JSON Schema validation for tool inputs
- **Lifecycle Hooks**: Integrate with the SDK's hook system for validation/logging
- **Security**: Fine-grained permission control over tool execution

---

## MCP Server Types

The Claude Agent SDK supports two types of MCP servers:

### 1. SDK MCP Servers (In-Process)

Run directly within your Elixir application with no subprocess overhead.

```elixir
# Define tools inline and execute them in your BEAM VM
server = ClaudeAgentSDK.create_sdk_mcp_server(
  name: "my-tools",
  version: "1.0.0",
  tools: [MyTools.Calculator, MyTools.DateHelper]
)
```

**Benefits:**
- Zero subprocess overhead
- Direct access to your application state
- Native Elixir error handling
- Hot code reloading support

### 2. External MCP Servers (Subprocess)

Traditional MCP servers running as separate processes via stdio transport.

```elixir
# Use existing MCP server packages
external_server = %{
  type: :stdio,
  command: "npx",
  args: ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/files"]
}
```

**Benefits:**
- Use existing MCP server ecosystem
- Language-agnostic (Node.js, Python, etc.)
- Process isolation

### Comparison

| Feature | SDK MCP | External MCP |
|---------|---------|--------------|
| Overhead | Minimal | Subprocess spawn |
| State Access | Direct | IPC required |
| Language | Elixir only | Any |
| Hot Reload | Yes | No |
| Error Handling | Native | JSON-RPC |
| Existing Ecosystem | Build your own | NPM packages |

---

## Creating Tools with deftool Macro

The `deftool` macro provides a clean DSL for defining MCP tools.

### Basic Syntax

```elixir
defmodule MyTools do
  use ClaudeAgentSDK.Tool

  deftool :tool_name, "Tool description", %{schema} do
    def execute(input) do
      # Your implementation
      {:ok, %{"content" => [%{"type" => "text", "text" => "result"}]}}
    end
  end
end
```

### Complete Example

```elixir
defmodule Calculator do
  use ClaudeAgentSDK.Tool

  deftool :add, "Add two numbers together", %{
    type: "object",
    properties: %{
      a: %{type: "number", description: "First number to add"},
      b: %{type: "number", description: "Second number to add"}
    },
    required: ["a", "b"]
  } do
    def execute(%{"a" => a, "b" => b}) do
      result = a + b
      {:ok, %{"content" => [%{"type" => "text", "text" => "#{a} + #{b} = #{result}"}]}}
    end
  end

  deftool :multiply, "Multiply two numbers", %{
    type: "object",
    properties: %{
      a: %{type: "number", description: "First number"},
      b: %{type: "number", description: "Second number"}
    },
    required: ["a", "b"]
  } do
    def execute(%{"a" => a, "b" => b}) do
      result = a * b
      {:ok, %{"content" => [%{"type" => "text", "text" => "#{a} * #{b} = #{result}"}]}}
    end
  end

  deftool :factorial, "Calculate factorial of a number", %{
    type: "object",
    properties: %{
      n: %{type: "integer", description: "Non-negative integer", minimum: 0, maximum: 20}
    },
    required: ["n"]
  } do
    def execute(%{"n" => n}) when n >= 0 do
      result = factorial_calc(n)
      {:ok, %{"content" => [%{"type" => "text", "text" => "#{n}! = #{result}"}]}}
    end

    def execute(%{"n" => n}) do
      {:error, "Invalid input: #{n} must be non-negative"}
    end

    defp factorial_calc(0), do: 1
    defp factorial_calc(n), do: n * factorial_calc(n - 1)
  end
end
```

### What deftool Generates

The macro creates a nested module for each tool:

```elixir
# deftool :add, ... generates:
defmodule Calculator.Add do
  @name :add
  @description "Add two numbers together"
  @schema %{...}

  def name, do: @name
  def description, do: @description
  def schema, do: @schema

  # Your execute/1 implementation
  def execute(%{"a" => a, "b" => b}), do: ...
end
```

---

## Tool Schema (JSON Schema Format)

Tool schemas follow JSON Schema draft-07 format with some MCP-specific conventions.

### Schema Structure

```elixir
%{
  type: "object",           # Always "object" for tool inputs
  properties: %{            # Define each input parameter
    param_name: %{
      type: "string",       # Type: string, number, integer, boolean, array, object
      description: "...",   # Human-readable description (shown to Claude)
      enum: ["a", "b"],     # Optional: allowed values
      default: "value"      # Optional: default value
    }
  },
  required: ["param_name"]  # List of required parameters
}
```

### Common Property Types

#### String

```elixir
%{
  type: "string",
  description: "A text value",
  minLength: 1,
  maxLength: 1000,
  pattern: "^[a-z]+$"  # Regex pattern
}
```

#### Number / Integer

```elixir
%{
  type: "number",        # or "integer"
  description: "A numeric value",
  minimum: 0,
  maximum: 100,
  exclusiveMinimum: 0,
  exclusiveMaximum: 100
}
```

#### Boolean

```elixir
%{
  type: "boolean",
  description: "True or false",
  default: false
}
```

#### Array

```elixir
%{
  type: "array",
  description: "List of items",
  items: %{type: "string"},  # Type of array elements
  minItems: 1,
  maxItems: 10,
  uniqueItems: true
}
```

#### Enum

```elixir
%{
  type: "string",
  description: "One of the allowed values",
  enum: ["option1", "option2", "option3"]
}
```

#### Nested Object

```elixir
%{
  type: "object",
  properties: %{
    config: %{
      type: "object",
      properties: %{
        enabled: %{type: "boolean"},
        timeout: %{type: "integer"}
      }
    }
  }
}
```

### Complete Schema Example

```elixir
deftool :search_files, "Search for files matching criteria", %{
  type: "object",
  properties: %{
    directory: %{
      type: "string",
      description: "Directory to search in"
    },
    pattern: %{
      type: "string",
      description: "Glob pattern to match files",
      default: "*"
    },
    recursive: %{
      type: "boolean",
      description: "Search recursively",
      default: true
    },
    file_types: %{
      type: "array",
      description: "File extensions to include",
      items: %{type: "string"},
      default: []
    },
    max_results: %{
      type: "integer",
      description: "Maximum number of results",
      minimum: 1,
      maximum: 1000,
      default: 100
    }
  },
  required: ["directory"]
} do
  def execute(input) do
    # Implementation
  end
end
```

---

## Tool Execution and Return Values

### Success Return Format

Tools must return a tuple with content blocks:

```elixir
{:ok, %{
  "content" => [
    %{"type" => "text", "text" => "Your result here"}
  ]
}}
```

### Multiple Content Blocks

```elixir
{:ok, %{
  "content" => [
    %{"type" => "text", "text" => "Primary result"},
    %{"type" => "text", "text" => "Additional information"}
  ]
}}
```

### Error Return Format

For handled errors:

```elixir
{:error, "Error description"}
```

For errors that should be visible to Claude:

```elixir
{:ok, %{
  "content" => [
    %{"type" => "text", "text" => "Error: Invalid input"}
  ],
  "is_error" => true
}}
```

### Return Value Examples

#### Simple Text Result

```elixir
def execute(%{"query" => query}) do
  result = perform_search(query)
  {:ok, %{"content" => [%{"type" => "text", "text" => result}]}}
end
```

#### JSON Result

```elixir
def execute(%{"id" => id}) do
  data = fetch_data(id)
  json = Jason.encode!(data, pretty: true)
  {:ok, %{"content" => [%{"type" => "text", "text" => json}]}}
end
```

#### Structured Result with Metadata

```elixir
def execute(input) do
  {result, metadata} = process(input)

  content = """
  ## Result
  #{result}

  ## Metadata
  - Duration: #{metadata.duration_ms}ms
  - Items processed: #{metadata.count}
  """

  {:ok, %{"content" => [%{"type" => "text", "text" => content}]}}
end
```

#### Error Handling

```elixir
def execute(%{"file_path" => path}) do
  case File.read(path) do
    {:ok, content} ->
      {:ok, %{"content" => [%{"type" => "text", "text" => content}]}}

    {:error, :enoent} ->
      {:error, "File not found: #{path}"}

    {:error, :eacces} ->
      {:ok, %{
        "content" => [%{"type" => "text", "text" => "Permission denied: #{path}"}],
        "is_error" => true
      }}

    {:error, reason} ->
      {:error, "Failed to read file: #{inspect(reason)}"}
  end
end
```

---

## Creating SDK MCP Servers

Use `ClaudeAgentSDK.create_sdk_mcp_server/1` to create in-process MCP servers.

### Basic Usage

```elixir
server = ClaudeAgentSDK.create_sdk_mcp_server(
  name: "my-tools",
  version: "1.0.0",
  tools: [MyTools.Add, MyTools.Multiply]
)
```

### Server Configuration

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `name` | String | Yes | Unique server identifier |
| `version` | String | No | Server version (defaults to `1.0.0`) |
| `tools` | List | Yes | List of tool modules |

### Server Structure

The returned server map contains:

```elixir
%{
  type: :sdk,                    # Identifies as SDK MCP server
  name: "my-tools",              # Server name
  version: "1.0.0",              # Server version
  registry_pid: #PID<0.123.0>    # Tool registry process
}
```

Direct registry calls use string tool names:

```elixir
{:ok, result} =
  ClaudeAgentSDK.Tool.Registry.execute_tool(server.registry_pid, "add", %{"a" => 1, "b" => 2})
```

### Using with Options

```elixir
defmodule MathServer do
  def create do
    ClaudeAgentSDK.create_sdk_mcp_server(
      name: "math",
      version: "1.0.0",
      tools: [Calculator.Add, Calculator.Multiply, Calculator.Factorial]
    )
  end
end

# In your query
server = MathServer.create()

options = %ClaudeAgentSDK.Options{
  mcp_servers: %{"math" => server},
  allowed_tools: ["mcp__math__add", "mcp__math__multiply", "mcp__math__factorial"],
  permission_mode: :bypass_permissions
}

ClaudeAgentSDK.query("What is 15 + 27, then multiply by 3?", options)
|> Enum.to_list()
```

You can also pass a JSON string or file path via `mcp_servers` (alias for `mcp_config`):

```elixir
options = %Options{mcp_servers: "/path/to/mcp.json"}
```

### Complete Example

```elixir
defmodule MyApp.Tools.DateTime do
  use ClaudeAgentSDK.Tool

  deftool :current_time, "Get current time in specified timezone", %{
    type: "object",
    properties: %{
      timezone: %{
        type: "string",
        description: "Timezone (e.g., 'UTC', 'America/New_York')",
        default: "UTC"
      },
      format: %{
        type: "string",
        description: "Output format",
        enum: ["iso8601", "human", "unix"],
        default: "iso8601"
      }
    },
    required: []
  } do
    def execute(%{"timezone" => tz, "format" => format}) do
      now = DateTime.utc_now()

      result = case format do
        "iso8601" -> DateTime.to_iso8601(now)
        "human" -> Calendar.strftime(now, "%B %d, %Y at %H:%M:%S")
        "unix" -> DateTime.to_unix(now) |> to_string()
      end

      {:ok, %{"content" => [%{"type" => "text", "text" => "Current time (#{tz}): #{result}"}]}}
    end

    def execute(input) do
      execute(Map.merge(%{"timezone" => "UTC", "format" => "iso8601"}, input))
    end
  end
end

defmodule MyApp.ToolServer do
  alias MyApp.Tools.DateTime

  def start do
    ClaudeAgentSDK.create_sdk_mcp_server(
      name: "datetime",
      version: "1.0.0",
      tools: [DateTime.CurrentTime]
    )
  end
end

# Usage
server = MyApp.ToolServer.start()

options = %ClaudeAgentSDK.Options{
  mcp_servers: %{"datetime" => server},
  allowed_tools: ["mcp__datetime__current_time"]
}

ClaudeAgentSDK.query("What time is it?", options)
```

---

## Tool Naming Convention

MCP tools follow a strict naming convention: `mcp__<server>__<tool>`

### Format

```
mcp__<server_name>__<tool_name>
     ^           ^
     |           |
     |           +-- Double underscore separator
     +-- Prefix for MCP tools
```

### Examples

| Server Name | Tool Name | Full Tool Name |
|-------------|-----------|----------------|
| `calculator` | `add` | `mcp__calculator__add` |
| `math-tools` | `multiply` | `mcp__math-tools__multiply` |
| `my_server` | `do_something` | `mcp__my_server__do_something` |

### Using Tool Names

#### In allowed_tools

```elixir
options = %Options{
  mcp_servers: %{"calc" => server},
  allowed_tools: [
    "mcp__calc__add",
    "mcp__calc__multiply",
    "mcp__calc__divide"
  ]
}
```

#### In Hooks

```elixir
alias ClaudeAgentSDK.Hooks.{Matcher, Output}

hooks = %{
  pre_tool_use: [
    # Match specific MCP tool
    Matcher.new("mcp__calc__add", [&log_add/3]),

    # Match all tools from a server (regex)
    Matcher.new("mcp__calc__.*", [&audit_calc/3]),

    # Match all MCP tools
    Matcher.new("mcp__.*", [&log_mcp_usage/3])
  ]
}
```

#### Tool Name in Hook Input

```elixir
def my_hook(input, _tool_use_id, _context) do
  case input["tool_name"] do
    "mcp__calc__add" -> handle_add(input)
    "mcp__calc__multiply" -> handle_multiply(input)
    _ -> Output.allow()
  end
end
```

---

## Using External MCP Servers

External MCP servers run as separate processes and communicate via stdio transport.

### Basic Configuration

```elixir
external_server = %{
  type: :stdio,
  command: "npx",
  args: ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/files"]
}

options = %ClaudeAgentSDK.Options{
  mcp_servers: %{"filesystem" => external_server}
}
```

### Server Configuration Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | `:stdio` | Yes | Transport type (currently only stdio) |
| `command` | String | Yes | Command to execute |
| `args` | List | No | Command arguments |
| `env` | Map | No | Environment variables |

### Common External Servers

#### Filesystem Server

```elixir
%{
  type: :stdio,
  command: "npx",
  args: ["-y", "@modelcontextprotocol/server-filesystem", "/home/user/projects"]
}
```

#### GitHub Server

```elixir
%{
  type: :stdio,
  command: "npx",
  args: ["-y", "@modelcontextprotocol/server-github"],
  env: %{"GITHUB_TOKEN" => System.get_env("GITHUB_TOKEN")}
}
```

#### Custom Server

```elixir
%{
  type: :stdio,
  command: "python",
  args: ["-m", "my_mcp_server"],
  env: %{"CONFIG_PATH" => "/etc/my_server/config.json"}
}
```

### Combining SDK and External Servers

```elixir
# SDK MCP server
calc_server = ClaudeAgentSDK.create_sdk_mcp_server(
  name: "calc",
  version: "1.0.0",
  tools: [Calculator.Add, Calculator.Multiply]
)

# External MCP server
fs_server = %{
  type: :stdio,
  command: "npx",
  args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp/workspace"]
}

options = %ClaudeAgentSDK.Options{
  mcp_servers: %{
    "calc" => calc_server,
    "filesystem" => fs_server
  },
  allowed_tools: [
    "mcp__calc__add",
    "mcp__calc__multiply",
    "mcp__filesystem__read_file",
    "mcp__filesystem__write_file"
  ]
}
```

---

## Combining MCP with Hooks and Permissions

MCP tools integrate seamlessly with the SDK's hook and permission systems.

### Pre-Tool Hooks for MCP

```elixir
alias ClaudeAgentSDK.Hooks.{Matcher, Output}

def validate_mcp_tool(input, _tool_use_id, _context) do
  case input do
    %{"tool_name" => "mcp__calc__" <> _op, "tool_input" => params} ->
      # Validate numeric inputs
      if valid_numbers?(params) do
        Output.allow()
      else
        Output.deny("Invalid numeric input")
      end

    _ ->
      Output.allow()
  end
end

hooks = %{
  pre_tool_use: [
    Matcher.new("mcp__calc__.*", [&validate_mcp_tool/3])
  ]
}
```

### Post-Tool Hooks for Auditing

```elixir
def audit_mcp_usage(input, tool_use_id, _context) do
  Logger.info("MCP Tool Used",
    tool: input["tool_name"],
    tool_use_id: tool_use_id,
    input: input["tool_input"],
    result: input["tool_response"]
  )

  %{}  # Don't modify behavior
end

hooks = %{
  post_tool_use: [
    Matcher.new("mcp__.*", [&audit_mcp_usage/3])
  ]
}
```

### Permission Callbacks

```elixir
alias ClaudeAgentSDK.Permission.Result

permission_callback = fn context ->
  case context.tool_name do
    "mcp__filesystem__write_file" ->
      # Only allow writes to specific directory
      path = context.tool_input["path"]
      if String.starts_with?(path, "/tmp/workspace/") do
        Result.allow()
      else
        Result.deny("Writes only allowed in /tmp/workspace/")
      end

    "mcp__calc__" <> _ ->
      # Always allow calculator tools
      Result.allow()

    _ ->
      Result.allow()
  end
end

options = %ClaudeAgentSDK.Options{
  mcp_servers: %{"calc" => calc_server, "filesystem" => fs_server},
  can_use_tool: permission_callback,
  permission_mode: :default
}
```

### Complete Integration Example

```elixir
defmodule MyApp.SecureMCPSetup do
  alias ClaudeAgentSDK.{Options, Permission.Result}
  alias ClaudeAgentSDK.Hooks.{Matcher, Output}

  def build_options do
    calc_server = build_calc_server()
    hooks = build_hooks()
    permission_callback = build_permission_callback()

    %Options{
      mcp_servers: %{"calc" => calc_server},
      allowed_tools: ["mcp__calc__add", "mcp__calc__multiply"],
      hooks: hooks,
      can_use_tool: permission_callback,
      permission_mode: :default
    }
  end

  defp build_calc_server do
    ClaudeAgentSDK.create_sdk_mcp_server(
      name: "calc",
      version: "1.0.0",
      tools: [Calculator.Add, Calculator.Multiply]
    )
  end

  defp build_hooks do
    %{
      pre_tool_use: [
        # Log all MCP tool invocations
        Matcher.new("mcp__.*", [&log_invocation/3]),
        # Validate calculator inputs
        Matcher.new("mcp__calc__.*", [&validate_numbers/3])
      ],
      post_tool_use: [
        # Audit all MCP results
        Matcher.new("mcp__.*", [&audit_result/3])
      ]
    }
  end

  defp build_permission_callback do
    fn context ->
      # Add rate limiting for MCP tools
      if rate_limit_exceeded?(context.tool_name) do
        Result.deny("Rate limit exceeded")
      else
        Result.allow()
      end
    end
  end

  defp log_invocation(input, tool_use_id, _context) do
    IO.puts("[MCP] Invoking #{input["tool_name"]} (#{tool_use_id})")
    %{}
  end

  defp validate_numbers(%{"tool_input" => params}, _id, _ctx) do
    if Enum.all?(Map.values(params), &is_number/1) do
      Output.allow()
    else
      Output.deny("All inputs must be numbers")
    end
  end
  defp validate_numbers(_, _, _), do: Output.allow()

  defp audit_result(input, tool_use_id, _context) do
    IO.puts("[MCP] Completed #{input["tool_name"]} (#{tool_use_id})")
    %{}
  end

  defp rate_limit_exceeded?(_tool_name), do: false
end
```

---

## Best Practices

### Tool Design

1. **Single Responsibility**: Each tool should do one thing well
2. **Clear Descriptions**: Write descriptions that help Claude understand when to use the tool
3. **Validate Inputs**: Use JSON Schema constraints and runtime validation
4. **Handle Errors Gracefully**: Return meaningful error messages

```elixir
# Good: Clear, focused tool
deftool :get_user_by_id, "Fetch a user record by their unique ID", %{
  type: "object",
  properties: %{
    user_id: %{type: "string", description: "Unique user identifier (UUID format)"}
  },
  required: ["user_id"]
} do
  def execute(%{"user_id" => id}) do
    case Users.get(id) do
      {:ok, user} -> {:ok, %{"content" => [%{"type" => "text", "text" => format_user(user)}]}}
      {:error, :not_found} -> {:error, "User not found: #{id}"}
    end
  end
end

# Bad: Too broad, unclear purpose
deftool :do_stuff, "Does things with data", %{...}
```

### Schema Design

1. **Use Descriptive Property Names**: Self-documenting schemas
2. **Add Descriptions**: Help Claude understand each parameter
3. **Set Constraints**: Use min/max, patterns, enums
4. **Provide Defaults**: For optional parameters

```elixir
# Good: Well-documented schema
%{
  type: "object",
  properties: %{
    query: %{
      type: "string",
      description: "Search query string",
      minLength: 1,
      maxLength: 500
    },
    limit: %{
      type: "integer",
      description: "Maximum results to return",
      minimum: 1,
      maximum: 100,
      default: 10
    },
    sort_order: %{
      type: "string",
      description: "Result ordering",
      enum: ["asc", "desc"],
      default: "desc"
    }
  },
  required: ["query"]
}
```

### Error Handling

1. **Pattern Match Inputs**: Handle unexpected input gracefully
2. **Use is_error Flag**: For errors Claude should know about
3. **Provide Context**: Help Claude understand what went wrong

```elixir
def execute(%{"file_path" => path}) do
  case File.read(path) do
    {:ok, content} ->
      {:ok, %{"content" => [%{"type" => "text", "text" => content}]}}

    {:error, :enoent} ->
      {:ok, %{
        "content" => [%{"type" => "text", "text" => "File not found: #{path}. Please check the path and try again."}],
        "is_error" => true
      }}

    {:error, :eacces} ->
      {:ok, %{
        "content" => [%{"type" => "text", "text" => "Permission denied reading: #{path}"}],
        "is_error" => true
      }}

    {:error, reason} ->
      {:error, "Unexpected error reading #{path}: #{inspect(reason)}"}
  end
end

# Always handle unmatched patterns
def execute(input) do
  {:error, "Invalid input format: #{inspect(input)}"}
end
```

### Security

1. **Validate All Inputs**: Never trust user/Claude input
2. **Use Hooks for Authorization**: Integrate with your auth system
3. **Limit Scope**: Only expose necessary functionality
4. **Audit Usage**: Log tool invocations for monitoring

```elixir
# Security hook example
def security_check(input, _tool_use_id, context) do
  tool = input["tool_name"]
  user = context["user_id"]

  if authorized?(user, tool) do
    Output.allow()
  else
    Logger.warn("Unauthorized tool access", tool: tool, user: user)
    Output.deny("Not authorized to use #{tool}")
  end
end
```

### Performance

1. **Keep Tools Fast**: Aim for < 100ms execution time
2. **Use Async for Slow Operations**: Spawn tasks for long-running work
3. **Cache When Appropriate**: Avoid redundant computations
4. **Set Timeouts**: Prevent hanging operations

```elixir
def execute(%{"url" => url}) do
  # Use Task with timeout for external calls
  task = Task.async(fn -> HTTPClient.get(url) end)

  case Task.yield(task, 5000) || Task.shutdown(task) do
    {:ok, {:ok, response}} ->
      {:ok, %{"content" => [%{"type" => "text", "text" => response.body}]}}

    {:ok, {:error, reason}} ->
      {:error, "HTTP request failed: #{reason}"}

    nil ->
      {:error, "Request timed out after 5 seconds"}
  end
end
```

### Naming Conventions

1. **Use snake_case for Tool Names**: `calculate_total`, not `calculateTotal`
2. **Use Descriptive Server Names**: `user-management`, not `um`
3. **Group Related Tools**: Single server with multiple related tools

```elixir
# Good: Organized tool groupings
defmodule UserTools do
  use ClaudeAgentSDK.Tool

  deftool :get_user, "...", %{...}
  deftool :create_user, "...", %{...}
  deftool :update_user, "...", %{...}
  deftool :delete_user, "...", %{...}
end

server = ClaudeAgentSDK.create_sdk_mcp_server(
  name: "user-management",
  version: "1.0.0",
  tools: [UserTools.GetUser, UserTools.CreateUser, UserTools.UpdateUser, UserTools.DeleteUser]
)
```

---

## Examples

See these example files for working implementations:

- `examples/sdk_mcp_tools_live.exs` - Basic SDK MCP tools
- `examples/advanced_features/sdk_mcp_live_demo.exs` - Comprehensive MCP demo
- `examples/streaming_tools/sdk_mcp_streaming.exs` - Streaming with MCP tools

---

## Quick Reference

### Create a Tool

```elixir
defmodule MyTool do
  use ClaudeAgentSDK.Tool

  deftool :name, "description", %{type: "object", properties: %{...}} do
    def execute(input), do: {:ok, %{"content" => [%{"type" => "text", "text" => "result"}]}}
  end
end
```

### Create a Server

```elixir
server = ClaudeAgentSDK.create_sdk_mcp_server(
  name: "server-name",
  version: "1.0.0",
  tools: [MyTool.Name]
)
```

### Use in Query

```elixir
options = %ClaudeAgentSDK.Options{
  mcp_servers: %{"server-name" => server},
  allowed_tools: ["mcp__server-name__name"]
}

ClaudeAgentSDK.query("prompt", options)
```

---

## Documentation

- **Hooks Guide:** [hooks.md](hooks.md)
- **Configuration Guide:** [configuration.md](configuration.md)
- **Permissions Guide:** [permissions.md](permissions.md)

---

**Need Help?**
```elixir
iex> h ClaudeAgentSDK.Tool
iex> h ClaudeAgentSDK.create_sdk_mcp_server
iex> h ClaudeAgentSDK.Options
```
