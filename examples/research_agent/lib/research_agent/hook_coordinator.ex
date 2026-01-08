defmodule ResearchAgent.HookCoordinator do
  @moduledoc """
  Builds and manages hook configurations for subagent tracking.

  The HookCoordinator creates Claude SDK hook callbacks that automatically
  track subagent spawn and completion events. This enables:

  - Automatic tracking of Task tool usage
  - Coordination between multiple parallel research agents
  - Audit logging of all tool calls

  ## Hook Types

  - `pre_tool_use` - Tracks Task tool spawns, records metadata
  - `post_tool_use` - Marks agents as completed, captures results

  ## Example

      {:ok, tracker} = SubagentTracker.start_link(name: :tracker)
      hooks = HookCoordinator.build_hooks(tracker)

      options = %Options{hooks: hooks}
      ClaudeAgentSDK.query("Research topic", options)
  """

  alias ClaudeAgentSDK.Hooks.{Matcher, Output}
  alias ResearchAgent.SubagentTracker
  require Logger

  @typedoc "Hook configuration map for Claude SDK"
  @type hooks_config :: %{
          pre_tool_use: [Matcher.t()],
          post_tool_use: [Matcher.t()]
        }

  @doc """
  Builds a complete hooks configuration for subagent tracking.

  ## Parameters

  - `tracker` - The SubagentTracker process to record events

  ## Returns

  A map suitable for use as the `:hooks` option in `ClaudeAgentSDK.Options`.

  ## Example

      hooks = HookCoordinator.build_hooks(tracker)
      options = %Options{hooks: hooks, ...}
  """
  @spec build_hooks(pid()) :: hooks_config()
  def build_hooks(tracker) do
    %{
      pre_tool_use: [
        Matcher.new("*", [
          create_spawn_tracker(tracker),
          create_audit_hook()
        ])
      ],
      post_tool_use: [
        Matcher.new("*", [
          create_completion_tracker(tracker)
        ])
      ]
    }
  end

  @doc """
  Creates an audit logging hook callback.

  Logs all tool calls for debugging and monitoring purposes.

  ## Returns

  A 3-arity function suitable for use as a hook callback.
  """
  @spec create_audit_hook() :: (map(), String.t() | nil, map() -> map())
  def create_audit_hook do
    fn input, tool_use_id, _context ->
      tool_name = Map.get(input, "tool_name", "unknown")
      Logger.debug("[Audit] Tool call: #{tool_name} (#{tool_use_id})")
      %{}
    end
  end

  # Private Functions

  @spec create_spawn_tracker(pid()) :: (map(), String.t() | nil, map() -> map())
  defp create_spawn_tracker(tracker) do
    fn input, tool_use_id, _context ->
      case input do
        %{"tool_name" => "Task", "tool_input" => tool_input} ->
          description = Map.get(tool_input, "description", "unknown task")
          subagent_type = Map.get(tool_input, "subagent_type", "general")

          # Track the spawn
          SubagentTracker.track_spawn(tracker, tool_use_id, subagent_type, %{
            description: description,
            spawned_at_iso: DateTime.utc_now() |> DateTime.to_iso8601()
          })

          Logger.info("[HookCoordinator] Task spawned: #{description} (#{subagent_type})")

          # Allow the tool to proceed
          Output.allow("Subagent tracked: #{tool_use_id}")

        _ ->
          # Not a Task tool, pass through
          %{}
      end
    end
  end

  @spec create_completion_tracker(pid()) :: (map(), String.t() | nil, map() -> map())
  defp create_completion_tracker(tracker) do
    fn input, tool_use_id, _context ->
      handle_completion(tracker, input, tool_use_id)
    end
  end

  defp handle_completion(
         tracker,
         %{"tool_name" => "Task", "tool_response" => response},
         tool_use_id
       ) do
    result = extract_task_result(response)
    SubagentTracker.track_complete(tracker, tool_use_id, result)
    Logger.info("[HookCoordinator] Task completed: #{tool_use_id}")
    %{}
  end

  defp handle_completion(_tracker, _input, _tool_use_id), do: %{}

  defp extract_task_result(%{"content" => content}), do: %{content: content}
  defp extract_task_result(other) when is_map(other), do: other
  defp extract_task_result(_), do: nil
end
