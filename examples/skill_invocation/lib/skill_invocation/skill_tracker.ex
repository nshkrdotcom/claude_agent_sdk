defmodule SkillInvocation.SkillTracker do
  @moduledoc """
  GenServer for tracking Skill tool invocations via hooks.

  This module provides hook callbacks for pre_tool_use and post_tool_use events
  that specifically track when the Skill tool is invoked by Claude. It maintains
  a history of all skill invocations with their status, timing, and results.

  ## Usage

      # Start the tracker
      {:ok, tracker} = SkillTracker.start_link()

      # Create hooks that use the tracker
      hooks = SkillTracker.create_hooks(tracker)

      # Use hooks in Options
      options = %Options{hooks: hooks}

      # Later, get statistics
      stats = SkillTracker.get_stats(tracker)

  ## Hook Integration

  The tracker provides two hook callbacks:

    * `pre_tool_use_hook/4` - Tracks when a Skill tool is about to be invoked
    * `post_tool_use_hook/4` - Records completion status of Skill invocations

  ## Tracked Data

  Each invocation record includes:

    * `tool_use_id` - Unique identifier for the tool use
    * `skill_name` - Name of the skill being invoked
    * `args` - Optional arguments passed to the skill
    * `status` - `:started` or `:completed`
    * `result` - `:success` or `:error` (after completion)
    * `started_at` - Timestamp when invocation started
    * `completed_at` - Timestamp when invocation completed
  """

  use GenServer

  alias ClaudeAgentSDK.Hooks.Matcher

  @typedoc """
  A tracked skill invocation record.
  """
  @type invocation :: %{
          tool_use_id: String.t(),
          skill_name: String.t(),
          args: String.t() | nil,
          status: :started | :completed,
          result: :success | :error | nil,
          started_at: DateTime.t(),
          completed_at: DateTime.t() | nil
        }

  @typedoc """
  Statistics about tracked skill invocations.
  """
  @type stats :: %{
          total: non_neg_integer(),
          by_skill: %{String.t() => non_neg_integer()}
        }

  @type state :: %{
          invocations: %{String.t() => invocation()}
        }

  ## Public API

  @doc """
  Starts the SkillTracker GenServer.

  ## Options

    * `:name` - Optional name for the GenServer. If `nil`, process is not registered.

  ## Examples

      {:ok, pid} = SkillTracker.start_link()
      {:ok, pid} = SkillTracker.start_link(name: MyApp.SkillTracker)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, %{}, gen_opts)
  end

  @doc """
  Tracks a new skill invocation.

  Called by the pre_tool_use hook when a Skill tool is about to execute.

  ## Parameters

    * `tracker` - Tracker PID or registered name
    * `tool_use_id` - Unique identifier for this tool use
    * `skill_name` - Name of the skill being invoked
    * `args` - Optional arguments string

  ## Examples

      :ok = SkillTracker.track_skill_invocation(tracker, "tool_123", "commit", "-m 'fix'")
  """
  @spec track_skill_invocation(GenServer.server(), String.t(), String.t(), String.t() | nil) ::
          :ok
  def track_skill_invocation(tracker, tool_use_id, skill_name, args) do
    GenServer.call(tracker, {:track, tool_use_id, skill_name, args})
  end

  @doc """
  Marks a skill invocation as completed.

  Called by the post_tool_use hook when a Skill tool finishes executing.

  ## Parameters

    * `tracker` - Tracker PID or registered name
    * `tool_use_id` - Unique identifier for the tool use
    * `result` - `:success` or `:error`

  ## Examples

      :ok = SkillTracker.complete_skill_invocation(tracker, "tool_123", :success)
  """
  @spec complete_skill_invocation(GenServer.server(), String.t(), :success | :error) ::
          :ok | {:error, :not_found}
  def complete_skill_invocation(tracker, tool_use_id, result) do
    GenServer.call(tracker, {:complete, tool_use_id, result})
  end

  @doc """
  Gets all tracked invocations.

  Returns invocations in chronological order (oldest first).

  ## Examples

      invocations = SkillTracker.get_invocations(tracker)
  """
  @spec get_invocations(GenServer.server()) :: [invocation()]
  def get_invocations(tracker) do
    GenServer.call(tracker, :get_invocations)
  end

  @doc """
  Gets statistics about tracked invocations.

  ## Returns

  A map containing:
    * `total` - Total number of invocations
    * `by_skill` - Map of skill name to invocation count

  ## Examples

      stats = SkillTracker.get_stats(tracker)
      # => %{total: 5, by_skill: %{"commit" => 3, "pdf" => 2}}
  """
  @spec get_stats(GenServer.server()) :: stats()
  def get_stats(tracker) do
    GenServer.call(tracker, :get_stats)
  end

  @doc """
  Clears all tracked invocations.

  ## Examples

      :ok = SkillTracker.clear(tracker)
  """
  @spec clear(GenServer.server()) :: :ok
  def clear(tracker) do
    GenServer.call(tracker, :clear)
  end

  @doc """
  Creates hook configuration for tracking Skill invocations.

  Returns a hooks map that can be used in `ClaudeAgentSDK.Options`.

  ## Parameters

    * `tracker` - Tracker PID or registered name

  ## Examples

      {:ok, tracker} = SkillTracker.start_link()
      hooks = SkillTracker.create_hooks(tracker)
      options = %Options{model: "haiku", hooks: hooks}
  """
  @spec create_hooks(GenServer.server()) :: ClaudeAgentSDK.Hooks.hook_config()
  def create_hooks(tracker) do
    %{
      pre_tool_use: [
        Matcher.new("Skill", [
          fn input, tool_use_id, context ->
            pre_tool_use_hook(tracker, input, tool_use_id, context)
          end
        ])
      ],
      post_tool_use: [
        Matcher.new("Skill", [
          fn input, tool_use_id, context ->
            post_tool_use_hook(tracker, input, tool_use_id, context)
          end
        ])
      ]
    }
  end

  @doc """
  Pre-tool-use hook callback for tracking Skill invocations.

  This function is designed to be used as a hook callback. It tracks the start
  of a Skill tool invocation.

  ## Parameters

    * `tracker` - Tracker PID or registered name
    * `input` - Hook input map containing tool_name and tool_input
    * `tool_use_id` - Unique identifier for the tool use
    * `_context` - Hook context (unused)

  ## Returns

  Always returns an empty map (no hook modifications).
  """
  @spec pre_tool_use_hook(
          GenServer.server(),
          ClaudeAgentSDK.Hooks.hook_input(),
          String.t() | nil,
          ClaudeAgentSDK.Hooks.hook_context()
        ) :: map()
  def pre_tool_use_hook(tracker, input, tool_use_id, _context) do
    tool_name = input["tool_name"]

    if tool_name == "Skill" do
      tool_input = input["tool_input"] || %{}
      skill_name = tool_input["skill"] || "unknown"
      args = tool_input["args"]

      track_skill_invocation(tracker, tool_use_id, skill_name, args)
    end

    %{}
  end

  @doc """
  Post-tool-use hook callback for completing Skill invocations.

  This function is designed to be used as a hook callback. It marks a Skill
  tool invocation as completed with its result status.

  ## Parameters

    * `tracker` - Tracker PID or registered name
    * `input` - Hook input map containing tool_name and tool_response
    * `tool_use_id` - Unique identifier for the tool use
    * `_context` - Hook context (unused)

  ## Returns

  Always returns an empty map (no hook modifications).
  """
  @spec post_tool_use_hook(
          GenServer.server(),
          ClaudeAgentSDK.Hooks.hook_input(),
          String.t() | nil,
          ClaudeAgentSDK.Hooks.hook_context()
        ) :: map()
  def post_tool_use_hook(tracker, input, tool_use_id, _context) do
    tool_name = input["tool_name"]

    if tool_name == "Skill" do
      tool_response = input["tool_response"] || %{}
      is_error = tool_response["is_error"] || false
      result = if is_error, do: :error, else: :success

      complete_skill_invocation(tracker, tool_use_id, result)
    end

    %{}
  end

  ## GenServer Callbacks

  @impl true
  def init(_opts) do
    {:ok, %{invocations: %{}}}
  end

  @impl true
  def handle_call({:track, tool_use_id, skill_name, args}, _from, state) do
    invocation = %{
      tool_use_id: tool_use_id,
      skill_name: skill_name,
      args: args,
      status: :started,
      result: nil,
      started_at: DateTime.utc_now(),
      completed_at: nil
    }

    new_invocations = Map.put(state.invocations, tool_use_id, invocation)
    {:reply, :ok, %{state | invocations: new_invocations}}
  end

  def handle_call({:complete, tool_use_id, result}, _from, state) do
    case Map.get(state.invocations, tool_use_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      invocation ->
        updated =
          invocation
          |> Map.put(:status, :completed)
          |> Map.put(:result, result)
          |> Map.put(:completed_at, DateTime.utc_now())

        new_invocations = Map.put(state.invocations, tool_use_id, updated)
        {:reply, :ok, %{state | invocations: new_invocations}}
    end
  end

  def handle_call(:get_invocations, _from, state) do
    # Return invocations sorted by started_at
    invocations =
      state.invocations
      |> Map.values()
      |> Enum.sort_by(& &1.started_at, DateTime)

    {:reply, invocations, state}
  end

  def handle_call(:get_stats, _from, state) do
    invocations = Map.values(state.invocations)

    by_skill =
      invocations
      |> Enum.group_by(& &1.skill_name)
      |> Enum.map(fn {name, list} -> {name, length(list)} end)
      |> Map.new()

    stats = %{
      total: length(invocations),
      by_skill: by_skill
    }

    {:reply, stats, state}
  end

  def handle_call(:clear, _from, _state) do
    {:reply, :ok, %{invocations: %{}}}
  end
end
