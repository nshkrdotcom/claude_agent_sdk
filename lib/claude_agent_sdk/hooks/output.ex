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

  @typedoc """
  Permission decision for PreToolUse hooks.
  """
  @type permission_decision :: :allow | :deny | :ask

  @typedoc """
  Hook-specific output for different event types.
  """
  @type hook_specific_output ::
          pre_tool_use_output()
          | post_tool_use_output()
          | user_prompt_submit_output()
          | session_start_output()

  @typedoc """
  PreToolUse hook-specific output.

  Controls whether a tool call proceeds:
  - `hookEventName` - Must be "PreToolUse"
  - `permissionDecision` - "allow", "deny", or "ask"
  - `permissionDecisionReason` - Explanation for the decision
  """
  @type pre_tool_use_output :: %{
          hookEventName: String.t(),
          permissionDecision: String.t(),
          permissionDecisionReason: String.t()
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
    # Basic validation - output must be a map
    # More comprehensive validation could check field types
    :ok
  end

  def validate(_), do: {:error, "Hook output must be a map"}

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
