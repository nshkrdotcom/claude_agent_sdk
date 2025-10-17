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
  - `:user_prompt_submit` - When user submits a prompt
  - `:stop` - When the agent finishes
  - `:subagent_stop` - When a subagent finishes
  - `:pre_compact` - Before context compaction

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

  Note: SessionStart, SessionEnd, and Notification hooks are not supported
  in SDK mode due to CLI limitations.
  """
  @type hook_event ::
          :pre_tool_use
          | :post_tool_use
          | :user_prompt_submit
          | :stop
          | :subagent_stop
          | :pre_compact

  @typedoc """
  Input data passed to hook callbacks.

  The structure varies by hook event. Common fields:
  - `hook_event_name` - String name of the event
  - `session_id` - Session identifier
  - `transcript_path` - Path to conversation transcript
  - `cwd` - Current working directory

  Event-specific fields:
  - PreToolUse/PostToolUse: `tool_name`, `tool_input`, `tool_response`
  - UserPromptSubmit: `prompt`
  - Stop/SubagentStop: `stop_hook_active`
  - PreCompact: `trigger`, `custom_instructions`
  """
  @type hook_input :: %{
          required(:hook_event_name) => String.t(),
          required(:session_id) => String.t(),
          required(:transcript_path) => String.t(),
          required(:cwd) => String.t(),
          optional(:tool_name) => String.t(),
          optional(:tool_input) => map(),
          optional(:tool_response) => term(),
          optional(:prompt) => String.t(),
          optional(:message) => String.t(),
          optional(:trigger) => String.t(),
          optional(:custom_instructions) => String.t(),
          optional(:stop_hook_active) => boolean(),
          optional(atom()) => term()
        }

  @typedoc """
  Context information passed to hook callbacks.

  Currently contains:
  - `signal` - Optional abort signal reference (reserved for future use)

  Note: Can be an empty map initially.
  """
  @type hook_context :: %{
          optional(:signal) => reference(),
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
  @type hook_callback ::
          (hook_input(), String.t() | nil, hook_context() -> Output.t())

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
  def event_to_string(:user_prompt_submit), do: "UserPromptSubmit"
  def event_to_string(:stop), do: "Stop"
  def event_to_string(:subagent_stop), do: "SubagentStop"
  def event_to_string(:pre_compact), do: "PreCompact"

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
  def string_to_event("UserPromptSubmit"), do: :user_prompt_submit
  def string_to_event("Stop"), do: :stop
  def string_to_event("SubagentStop"), do: :subagent_stop
  def string_to_event("PreCompact"), do: :pre_compact
  def string_to_event(_), do: nil

  @doc """
  Returns all valid hook event atoms.

  ## Examples

      iex> events = ClaudeAgentSDK.Hooks.all_valid_events()
      iex> :pre_tool_use in events
      true
      iex> length(events)
      6
  """
  @spec all_valid_events() :: [hook_event()]
  def all_valid_events do
    [:pre_tool_use, :post_tool_use, :user_prompt_submit, :stop, :subagent_stop, :pre_compact]
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
    config
    |> Enum.reduce_while(:ok, fn {event, matchers}, _acc ->
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
    end)
  end

  def validate_config(_), do: {:error, "Hook config must be a map"}

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
