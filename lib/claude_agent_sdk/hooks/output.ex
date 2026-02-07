defmodule ClaudeAgentSDK.Hooks.Output do
  @moduledoc """
  Hook output structure and helpers.

  Represents the return value from hook callbacks. Hook output controls:

  - **Permission decisions** (PreToolUse): allow, deny, or ask
  - **Additional context** (PostToolUse, UserPromptSubmit): inject information for Claude
  - **Execution control**: continue or stop the agent
  - **User feedback**: system messages and reasons

  ## Output Fields

  - `continue` - Whether to continue execution (boolean)
  - `stopReason` - Message when stopping (string)
  - `suppressOutput` - Hide from transcript (boolean)
  - `systemMessage` - User-visible message (string)
  - `reason` - Claude-visible feedback (string)
  - `decision` - "block" for some events (string)
  - `hookSpecificOutput` - Event-specific control (map)

  ## Examples

      # Allow a tool
      Output.allow("Security check passed")

      # Deny a tool
      Output.deny("Dangerous command detected")

      # Add context after tool execution
      Output.add_context("PostToolUse", "Command completed in 2.3s")

      # Stop execution
      Output.stop("Critical error occurred")

      # Combine helpers
      Output.deny("Invalid file path")
      |> Output.with_system_message("File access restricted")
      |> Output.with_reason("Path outside allowed directory")

  See: https://docs.anthropic.com/en/docs/claude-code/hooks#hook-output
  """

  alias ClaudeAgentSDK.Permission.Result, as: PermissionResult

  @typedoc """
  Permission decision for PreToolUse hooks.
  """
  @type permission_decision :: :allow | :deny | :ask

  @typedoc """
  Hook-specific output for different event types.

  Includes both:
  - Event-specific complete shapes (e.g. PreToolUse, PermissionRequest)
  - Composable/partial shapes produced by helper pipelines
  """
  @type hook_specific_output ::
          pre_tool_use_output()
          | post_tool_use_output()
          | user_prompt_submit_output()
          | session_start_output()
          | permission_request_output()
          | composable_hook_specific_output()

  @typedoc """
  Composable hook-specific output used by helper pipelines.

  Helpers such as `with_additional_context/2`, `with_updated_input/2`,
  and `with_updated_mcp_output/2` can be chained onto outputs that do not
  yet have a fully event-qualified `hookSpecificOutput` map.
  """
  @type composable_hook_specific_output :: %{
          optional(:hookEventName) => String.t(),
          optional(:permissionDecision) => String.t() | map(),
          optional(:permissionDecisionReason) => String.t(),
          optional(:additionalContext) => String.t(),
          optional(:updatedInput) => map(),
          optional(:updatedMCPToolOutput) => term(),
          optional(:decision) => map(),
          optional(atom()) => term()
        }

  @typedoc """
  PreToolUse hook-specific output.

  Controls whether a tool call proceeds:
  - `hookEventName` - Must be "PreToolUse"
  - `permissionDecision` - "allow", "deny", or "ask"
  - `permissionDecisionReason` - Explanation for the decision
  - `updatedInput` - Optional modified tool input (via `with_updated_input/2`)
  """
  @type pre_tool_use_output :: %{
          :hookEventName => String.t(),
          :permissionDecision => String.t(),
          :permissionDecisionReason => String.t(),
          optional(:updatedInput) => map()
        }

  @typedoc """
  PostToolUse hook-specific output.

  Adds context for Claude to consider:
  - `hookEventName` - Must be "PostToolUse"
  - `additionalContext` - Information about tool execution
  """
  @type post_tool_use_output :: %{
          hookEventName: String.t(),
          additionalContext: String.t()
        }

  @typedoc """
  UserPromptSubmit hook-specific output.

  Adds context before processing prompt:
  - `hookEventName` - Must be "UserPromptSubmit"
  - `additionalContext` - Contextual information to inject
  """
  @type user_prompt_submit_output :: %{
          hookEventName: String.t(),
          additionalContext: String.t()
        }

  @typedoc """
  SessionStart hook-specific output.

  Adds context when session starts:
  - `hookEventName` - Must be "SessionStart"
  - `additionalContext` - Initial context for session
  """
  @type session_start_output :: %{
          hookEventName: String.t(),
          additionalContext: String.t()
        }

  @typedoc """
  PermissionRequest hook-specific output.

  Controls permission dialogs programmatically:
  - `hookEventName` - Must be "PermissionRequest"
  - `decision` - Permission decision map (e.g. `%{"type" => "allow"}`)
  """
  @type permission_request_output :: %{
          hookEventName: String.t(),
          decision: map()
        }

  @typedoc """
  Complete hook output map.

  All fields are optional. The CLI processes these fields to control behavior.
  """
  @type t :: %{
          optional(:continue) => boolean(),
          optional(:stopReason) => String.t(),
          optional(:suppressOutput) => boolean(),
          optional(:systemMessage) => String.t(),
          optional(:reason) => String.t(),
          optional(:decision) => String.t(),
          optional(:hookSpecificOutput) => hook_specific_output(),
          optional(atom()) => term()
        }

  @doc """
  Creates hook output to allow a PreToolUse.

  ## Parameters

  - `reason` - Explanation for allowing (default: "Approved")

  ## Examples

      Output.allow()
      # => %{hookSpecificOutput: %{hookEventName: "PreToolUse", permissionDecision: "allow", ...}}

      Output.allow("Security scan passed")
  """
  @spec allow(String.t()) :: t()
  def allow(reason \\ "Approved") do
    %{
      hookSpecificOutput: %{
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        permissionDecisionReason: reason
      }
    }
  end

  @doc """
  Creates hook output to deny a PreToolUse.

  ## Parameters

  - `reason` - Explanation for denying (required)

  ## Examples

      Output.deny("Dangerous command detected")
      Output.deny("File path not allowed")
  """
  @spec deny(String.t()) :: t()
  def deny(reason) when is_binary(reason) do
    %{
      hookSpecificOutput: %{
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: reason
      }
    }
  end

  @doc """
  Creates hook output to ask the user for permission.

  The CLI will prompt the user to confirm the tool use.

  ## Parameters

  - `reason` - Explanation for asking user (required)

  ## Examples

      Output.ask("Confirm deletion of 100 files")
      Output.ask("Review this API call before executing")
  """
  @spec ask(String.t()) :: t()
  def ask(reason) when is_binary(reason) do
    %{
      hookSpecificOutput: %{
        hookEventName: "PreToolUse",
        permissionDecision: "ask",
        permissionDecisionReason: reason
      }
    }
  end

  @doc """
  Creates hook output to add context.

  Used with PostToolUse, UserPromptSubmit, or SessionStart hooks.

  ## Parameters

  - `event_name` - Hook event name ("PostToolUse", "UserPromptSubmit", etc.)
  - `context` - Contextual information to inject

  ## Examples

      Output.add_context("PostToolUse", "Command took 2.3 seconds")
      Output.add_context("UserPromptSubmit", "Current time: 10:00 AM")
      Output.add_context("SessionStart", "Recent issues: #123, #124")
  """
  @spec add_context(String.t(), String.t()) :: t()
  def add_context(event_name, context) when is_binary(event_name) and is_binary(context) do
    %{
      hookSpecificOutput: %{
        hookEventName: event_name,
        additionalContext: context
      }
    }
  end

  @doc """
  Creates hook output to stop execution.

  ## Parameters

  - `reason` - Explanation for stopping

  ## Examples

      Output.stop("Critical error detected")
      Output.stop("Resource limit exceeded")
  """
  @spec stop(String.t()) :: t()
  def stop(reason) when is_binary(reason) do
    %{
      continue: false,
      stopReason: reason
    }
  end

  @doc """
  Creates hook output to block with decision field.

  Used for certain hooks to provide feedback to Claude.

  ## Parameters

  - `reason` - Explanation for blocking

  ## Examples

      Output.block("Tool execution failed validation")
  """
  @spec block(String.t()) :: t()
  def block(reason) when is_binary(reason) do
    %{
      decision: "block",
      reason: reason
    }
  end

  @doc """
  Creates hook output to continue execution.

  ## Examples

      Output.continue()
      # => %{continue: true}
  """
  @spec continue() :: t()
  def continue do
    %{continue: true}
  end

  @doc """
  Adds a system message to hook output.

  System messages are shown to the user but not to Claude.

  ## Parameters

  - `output` - Existing hook output
  - `message` - User-visible message

  ## Examples

      Output.deny("Command blocked")
      |> Output.with_system_message("Security policy violation")
  """
  @spec with_system_message(t(), String.t()) :: t()
  def with_system_message(output, message) when is_map(output) and is_binary(message) do
    Map.put(output, :systemMessage, message)
  end

  @doc """
  Adds a reason to hook output.

  Reasons are shown to Claude to help it understand what happened.

  ## Parameters

  - `output` - Existing hook output
  - `reason` - Claude-visible explanation

  ## Examples

      Output.deny("Invalid path")
      |> Output.with_reason("Path must be within /allowed directory")
  """
  @spec with_reason(t(), String.t()) :: t()
  def with_reason(output, reason) when is_map(output) and is_binary(reason) do
    Map.put(output, :reason, reason)
  end

  @doc """
  Marks output to be suppressed from transcript.

  ## Parameters

  - `output` - Existing hook output

  ## Examples

      Output.allow()
      |> Output.suppress_output()
  """
  @spec suppress_output(t()) :: t()
  def suppress_output(output) when is_map(output) do
    Map.put(output, :suppressOutput, true)
  end

  @doc """
  Marks hook output for asynchronous processing.

  When `async: true` is set, the hook callback can continue processing
  in the background while Claude continues execution. This is useful for
  hooks that perform slow operations (e.g., external API calls, logging).

  ## Parameters

  - `output` - Existing hook output

  ## Examples

      # Basic async output
      Output.async(%{continue: true})

      # Combined with allow
      Output.allow("Approved")
      |> Output.async()

      # With timeout
      Output.allow("Starting background check")
      |> Output.async()
      |> Output.with_async_timeout(30_000)
  """
  @spec async(t()) :: t()
  def async(output) when is_map(output) do
    Map.put(output, :async, true)
  end

  @doc """
  Sets the timeout for async hook processing.

  Must be used with `async/1`. The timeout is specified in milliseconds
  and defines how long the CLI will wait for the async operation to complete.

  ## Parameters

  - `output` - Existing hook output (should have `async: true`)
  - `timeout_ms` - Timeout in milliseconds

  ## Examples

      Output.allow("Processing")
      |> Output.async()
      |> Output.with_async_timeout(60_000)  # 60 second timeout
  """
  @spec with_async_timeout(t(), non_neg_integer()) :: t()
  def with_async_timeout(output, timeout_ms)
      when is_map(output) and is_integer(timeout_ms) and timeout_ms >= 0 do
    Map.put(output, :asyncTimeout, timeout_ms)
  end

  @doc """
  Modifies tool input before execution (PreToolUse hooks only).

  This helper allows hooks to sanitize, validate, or transform tool inputs
  before Claude executes the tool. The updated input replaces the original
  input for that tool execution.

  ## Parameters

  - `output` - Existing hook output
  - `updated_input` - Map of updated input values

  ## Examples

      # Sanitize file paths
      Output.allow("Path sanitized")
      |> Output.with_updated_input(%{"path" => sanitize_path(input["path"])})

      # Add default values
      Output.allow("Defaults applied")
      |> Output.with_updated_input(Map.put(input, "timeout", 30))

      # Validate and transform
      Output.allow("Input validated")
      |> Output.with_updated_input(%{
        "path" => expand_path(input["path"]),
        "validated" => true
      })
  """
  @spec with_updated_input(t(), map()) :: t()
  def with_updated_input(output, updated_input)
      when is_map(output) and is_map(updated_input) do
    hook_output = Map.get(output, :hookSpecificOutput, %{})
    updated_hook_output = Map.put(hook_output, :updatedInput, updated_input)
    Map.put(output, :hookSpecificOutput, updated_hook_output)
  end

  @doc """
  Adds additional context to hook output.

  This is a composable alternative to `add_context/2` that can be piped
  onto existing hook outputs. Works with PostToolUse, UserPromptSubmit,
  and SessionStart hooks.

  ## Parameters

  - `output` - Existing hook output
  - `context` - Contextual information to inject

  ## Examples

      Output.allow("Approved")
      |> Output.with_additional_context("Command took 2.3s")

      Output.continue()
      |> Output.with_additional_context("Current time: 10:00 AM")
  """
  @spec with_additional_context(t(), String.t()) :: t()
  def with_additional_context(output, context) when is_map(output) and is_binary(context) do
    hook_output = Map.get(output, :hookSpecificOutput, %{})
    updated = Map.put(hook_output, :additionalContext, context)
    Map.put(output, :hookSpecificOutput, updated)
  end

  @doc """
  Sets updated MCP tool output in hook output.

  Used for PostToolUse hooks to modify or annotate MCP tool responses
  before they're returned to Claude. Accepts any value type to match
  the Python SDK's `updatedMCPToolOutput: Any`.

  ## Parameters

  - `output` - Existing hook output
  - `mcp_output` - Updated MCP tool output (any type)

  ## Examples

      Output.continue()
      |> Output.with_updated_mcp_output(%{"content" => [%{"type" => "text", "text" => "filtered"}]})
  """
  @spec with_updated_mcp_output(t(), term()) :: t()
  def with_updated_mcp_output(output, mcp_output) when is_map(output) do
    hook_output = Map.get(output, :hookSpecificOutput, %{})
    updated = Map.put(hook_output, :updatedMCPToolOutput, mcp_output)
    Map.put(output, :hookSpecificOutput, updated)
  end

  @doc """
  Creates a PermissionRequest hook output with a permission decision.

  Used with PermissionRequest hooks to programmatically respond to
  permission dialogs without user interaction.

  Accepts either a `PermissionResult` struct (converted to the CLI wire
  format `%{"type" => "allow"}` / `%{"type" => "deny", "reason" => "..."}`)
  or a raw map that is passed through unchanged.

  ## Parameters

  - `result` - A `PermissionResult` struct or raw decision map

  ## Examples

      Output.permission_decision(Permission.Result.allow())

      Output.permission_decision(Permission.Result.deny("Not allowed"))

      # Raw map passthrough
      Output.permission_decision(%{"type" => "allow"})
  """
  @spec permission_decision(PermissionResult.t() | map()) :: t()
  def permission_decision(%PermissionResult{behavior: :allow}) do
    %{
      hookSpecificOutput: %{
        hookEventName: "PermissionRequest",
        decision: %{"type" => "allow"}
      }
    }
  end

  def permission_decision(%PermissionResult{behavior: :deny} = result) do
    %{
      hookSpecificOutput: %{
        hookEventName: "PermissionRequest",
        decision: %{"type" => "deny", "reason" => result.message || ""}
      }
    }
  end

  def permission_decision(decision) when is_map(decision) do
    %{
      hookSpecificOutput: %{
        hookEventName: "PermissionRequest",
        decision: decision
      }
    }
  end

  @doc """
  Creates a PermissionRequest hook output that allows the tool.

  Shorthand for `permission_decision(Permission.Result.allow())`.

  ## Examples

      Output.permission_allow()
  """
  @spec permission_allow() :: t()
  def permission_allow do
    permission_decision(PermissionResult.allow())
  end

  @doc """
  Creates a PermissionRequest hook output that denies the tool.

  Shorthand for `permission_decision(Permission.Result.deny(reason))`.

  ## Parameters

  - `reason` - Explanation for denying

  ## Examples

      Output.permission_deny("Tool not permitted in this context")
  """
  @spec permission_deny(String.t()) :: t()
  def permission_deny(reason) when is_binary(reason) do
    permission_decision(PermissionResult.deny(reason))
  end

  @doc """
  Validates hook output structure.

  Returns `:ok` if valid, `{:error, reason}` otherwise.

  ## Examples

      iex> Output.validate(%{continue: true})
      :ok

      iex> Output.validate("not a map")
      {:error, "Hook output must be a map"}
  """
  @spec validate(t()) :: :ok | {:error, String.t()}
  def validate(output) when is_map(output) do
    async = Map.get(output, :async) || Map.get(output, "async")
    async_timeout = Map.get(output, :asyncTimeout) || Map.get(output, "asyncTimeout")

    validate_async(async, async_timeout)
  end

  def validate(_), do: {:error, "Hook output must be a map"}

  defp validate_async(nil, nil), do: :ok
  defp validate_async(true, nil), do: :ok
  defp validate_async(true, timeout) when is_integer(timeout), do: :ok

  defp validate_async(true, _timeout),
    do: {:error, "asyncTimeout must be an integer (milliseconds)"}

  defp validate_async(nil, _timeout), do: {:error, "asyncTimeout requires async: true"}

  defp validate_async(_async, _timeout), do: {:error, "async must be true when present"}

  @doc """
  Converts Elixir output to JSON-compatible map for CLI.

  Converts atom keys to strings recursively.

  ## Examples

      iex> Output.to_json_map(%{continue: false, stopReason: "Error"})
      %{"continue" => false, "stopReason" => "Error"}

      iex> Output.to_json_map(%{hookSpecificOutput: %{hookEventName: "PreToolUse"}})
      %{"hookSpecificOutput" => %{"hookEventName" => "PreToolUse"}}
  """
  @spec to_json_map(t()) :: map()
  def to_json_map(output) when is_map(output) do
    output
    |> Enum.map(fn
      {key, value} when is_atom(key) ->
        {Atom.to_string(key), convert_value(value)}

      {key, value} ->
        {key, convert_value(value)}
    end)
    |> Map.new()
  end

  defp convert_value(value) when is_map(value) do
    to_json_map(value)
  end

  defp convert_value(value), do: value
end
