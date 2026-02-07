defmodule ClaudeAgentSDK.Hooks do
  @moduledoc """
  Type definitions and utilities for Claude Code Hooks.

  Hooks are callback functions invoked by the Claude Code CLI at specific
  lifecycle events during agent execution. They enable:

  - Intercepting tool calls before/after execution
  - Adding contextual information automatically
  - Controlling execution flow based on runtime conditions
  - Implementing security policies and validation
  - Monitoring and auditing agent behavior

  ## Hook Events

  - `:pre_tool_use` - Before a tool executes
  - `:post_tool_use` - After a tool executes
  - `:post_tool_use_failure` - After a tool execution fails
  - `:user_prompt_submit` - When user submits a prompt
  - `:stop` - When the agent finishes
  - `:subagent_start` - When a subagent spawns
  - `:subagent_stop` - When a subagent finishes
  - `:pre_compact` - Before context compaction
  - `:notification` - When agent sends a notification
  - `:permission_request` - When a permission dialog would be shown
  - `:session_start` - When a session begins
  - `:session_end` - When a session ends

  ## Examples

      # Define a hook callback
      def check_bash(input, _tool_use_id, _context) do
        case input do
          %{"tool_name" => "Bash", "tool_input" => %{"command" => cmd}} ->
            if String.contains?(cmd, "rm -rf") do
              Output.deny("Dangerous command blocked")
            else
              Output.allow()
            end
          _ -> %{}
        end
      end

      # Configure hooks
      hooks = %{
        pre_tool_use: [
          Matcher.new("Bash", [&check_bash/3])
        ]
      }

  See: https://docs.anthropic.com/en/docs/claude-code/hooks
  """

  alias ClaudeAgentSDK.Hooks.{Matcher, Output}

  @typedoc """
  Hook event types supported by the SDK.

  """
  @type hook_event ::
          :pre_tool_use
          | :post_tool_use
          | :post_tool_use_failure
          | :user_prompt_submit
          | :stop
          | :subagent_start
          | :subagent_stop
          | :pre_compact
          | :notification
          | :permission_request
          | :session_start
          | :session_end

  @supported_events [
    :pre_tool_use,
    :post_tool_use,
    :post_tool_use_failure,
    :user_prompt_submit,
    :stop,
    :subagent_start,
    :subagent_stop,
    :pre_compact,
    :notification,
    :permission_request,
    :session_start,
    :session_end
  ]

  # All events are now supported. Kept for future use if events become unsupported.
  # @unsupported_events []

  @typedoc """
  Input data passed to hook callbacks.

  The structure varies by hook event. Common fields:
  - `hook_event_name` - String name of the event
  - `session_id` - Session identifier
  - `transcript_path` - Path to conversation transcript
  - `cwd` - Current working directory

  Event-specific fields:
  - PreToolUse/PostToolUse/PostToolUseFailure/PermissionRequest: `tool_name`, `tool_input`
  - PostToolUse: `tool_response`
  - PostToolUseFailure: `error`, `is_interrupt`
  - UserPromptSubmit: `prompt`
  - Stop/SubagentStop: `stop_hook_active`
  - SubagentStart/SubagentStop: `agent_id`, `agent_type`, `agent_transcript_path`
  - Notification: `message`, `title`, `notification_type`
  - PermissionRequest: `permission_suggestions`, `permission_mode`
  - SessionStart: `source`
  - SessionEnd: `reason`
  - PreCompact: `trigger`, `custom_instructions`
  """
  @type hook_input :: %{
          required(:hook_event_name) => String.t(),
          required(:session_id) => String.t(),
          required(:transcript_path) => String.t(),
          required(:cwd) => String.t(),
          # Tool-related
          optional(:tool_name) => String.t(),
          optional(:tool_input) => map(),
          optional(:tool_response) => term(),
          optional(:tool_use_id) => String.t(),
          # Subagent-related
          optional(:agent_id) => String.t(),
          optional(:agent_transcript_path) => String.t(),
          optional(:agent_type) => String.t(),
          # PostToolUseFailure-specific
          optional(:error) => String.t(),
          optional(:is_interrupt) => boolean(),
          # Notification-specific
          optional(:message) => String.t(),
          optional(:title) => String.t(),
          optional(:notification_type) => String.t(),
          # PermissionRequest-specific
          optional(:permission_suggestions) => [map()],
          optional(:permission_mode) => String.t(),
          # SessionStart-specific
          optional(:source) => String.t(),
          # SessionEnd-specific
          optional(:reason) => String.t(),
          # UserPromptSubmit/PreCompact
          optional(:prompt) => String.t(),
          optional(:trigger) => String.t(),
          optional(:custom_instructions) => String.t(),
          optional(:stop_hook_active) => boolean(),
          optional(atom()) => term()
        }

  @typedoc """
  Context information passed to hook callbacks.

  Currently contains:
  - `signal` - Optional abort signal reference for cooperative cancellation

  Note: Can be an empty map initially.
  """
  @type hook_context :: %{
          optional(:signal) => ClaudeAgentSDK.AbortSignal.t(),
          optional(atom()) => term()
        }

  @typedoc """
  Hook callback function signature.

  Receives:
  1. Input data (varies by event)
  2. Tool use ID (for tool-related hooks, nil otherwise)
  3. Context with abort signal

  Returns:
  - Hook output map controlling behavior (see `Output`)
  """
  @type hook_output :: Output.t() | term()

  @type hook_callback ::
          (hook_input(), String.t() | nil, hook_context() -> hook_output())

  @typedoc """
  Hook configuration map.

  Maps hook events to lists of matchers.

  ## Example

      %{
        pre_tool_use: [
          %Matcher{matcher: "Bash", hooks: [&check_bash/3]},
          %Matcher{matcher: "Write|Edit", hooks: [&check_files/3]}
        ],
        post_tool_use: [
          %Matcher{matcher: "*", hooks: [&log_usage/3]}
        ]
      }
  """
  @type hook_config :: %{
          hook_event() => [Matcher.t()]
        }

  @doc """
  Converts an Elixir hook event atom to CLI string format.

  ## Examples

      iex> ClaudeAgentSDK.Hooks.event_to_string(:pre_tool_use)
      "PreToolUse"

      iex> ClaudeAgentSDK.Hooks.event_to_string(:post_tool_use)
      "PostToolUse"
  """
  @spec event_to_string(hook_event()) :: String.t()
  def event_to_string(:pre_tool_use), do: "PreToolUse"
  def event_to_string(:post_tool_use), do: "PostToolUse"
  def event_to_string(:post_tool_use_failure), do: "PostToolUseFailure"
  def event_to_string(:user_prompt_submit), do: "UserPromptSubmit"
  def event_to_string(:stop), do: "Stop"
  def event_to_string(:subagent_start), do: "SubagentStart"
  def event_to_string(:subagent_stop), do: "SubagentStop"
  def event_to_string(:pre_compact), do: "PreCompact"
  def event_to_string(:notification), do: "Notification"
  def event_to_string(:permission_request), do: "PermissionRequest"
  def event_to_string(:session_start), do: "SessionStart"
  def event_to_string(:session_end), do: "SessionEnd"

  @doc """
  Converts a CLI hook event string to Elixir atom.

  Returns `nil` for unknown event strings.

  ## Examples

      iex> ClaudeAgentSDK.Hooks.string_to_event("PreToolUse")
      :pre_tool_use

      iex> ClaudeAgentSDK.Hooks.string_to_event("UnknownEvent")
      nil
  """
  @spec string_to_event(String.t()) :: hook_event() | nil
  def string_to_event("PreToolUse"), do: :pre_tool_use
  def string_to_event("PostToolUse"), do: :post_tool_use
  def string_to_event("PostToolUseFailure"), do: :post_tool_use_failure
  def string_to_event("UserPromptSubmit"), do: :user_prompt_submit
  def string_to_event("Stop"), do: :stop
  def string_to_event("SubagentStart"), do: :subagent_start
  def string_to_event("SubagentStop"), do: :subagent_stop
  def string_to_event("PreCompact"), do: :pre_compact
  def string_to_event("Notification"), do: :notification
  def string_to_event("PermissionRequest"), do: :permission_request
  def string_to_event("SessionStart"), do: :session_start
  def string_to_event("SessionEnd"), do: :session_end
  def string_to_event(_), do: nil

  @doc """
  Returns all valid hook event atoms.

  ## Examples

      iex> events = ClaudeAgentSDK.Hooks.all_valid_events()
      iex> :pre_tool_use in events
      true
      iex> length(events)
      12
  """
  @spec all_valid_events() :: [hook_event()]
  def all_valid_events do
    @supported_events
  end

  @doc """
  Validates a hook configuration.

  Returns `:ok` if valid, `{:error, reason}` otherwise.

  ## Examples

      iex> matcher = %ClaudeAgentSDK.Hooks.Matcher{
      ...>   matcher: "Bash",
      ...>   hooks: [fn _, _, _ -> %{} end]
      ...> }
      iex> ClaudeAgentSDK.Hooks.validate_config(%{pre_tool_use: [matcher]})
      :ok

      iex> ClaudeAgentSDK.Hooks.validate_config(%{invalid_event: []})
      {:error, "Invalid hook event: invalid_event"}
  """
  @spec validate_config(hook_config()) :: :ok | {:error, String.t()}
  def validate_config(config) when is_map(config) do
    Enum.reduce_while(config, :ok, fn {event, matchers}, _acc ->
      validate_config_entry(event, matchers)
    end)
  end

  def validate_config(_), do: {:error, "Hook config must be a map"}

  defp validate_config_entry(event, matchers) do
    cond do
      not is_atom(event) ->
        {:halt, {:error, "Hook event must be an atom, got: #{inspect(event)}"}}

      event not in all_valid_events() ->
        {:halt, {:error, "Invalid hook event: #{event}"}}

      not is_list(matchers) ->
        {:halt, {:error, "Matchers must be a list for event #{event}"}}

      true ->
        case validate_matchers(matchers) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
    end
  end

  @doc false
  # Validates a list of matchers
  defp validate_matchers(matchers) do
    Enum.reduce_while(matchers, :ok, fn matcher, _acc ->
      if match?(%Matcher{}, matcher) do
        {:cont, :ok}
      else
        {:halt, {:error, "Each matcher must be a HookMatcher struct"}}
      end
    end)
  end
end
