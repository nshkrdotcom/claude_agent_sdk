defmodule ResearchAgent.Coordinator do
  @moduledoc """
  Supervises and coordinates research agent components.

  The Coordinator manages the lifecycle of:
  - SubagentTracker - for monitoring parallel agents
  - TranscriptLogger - for session recording

  It provides a unified interface for accessing hooks and status
  information across all components.

  ## Architecture

  ```
  Coordinator (Supervisor)
      |
      +-- SubagentTracker (GenServer + ETS)
      |
      +-- TranscriptLogger (GenServer)
  ```

  ## Example

      {:ok, coord} = Coordinator.start_link(output_dir: "./output")

      hooks = Coordinator.get_hooks(coord)
      options = %Options{hooks: hooks}

      ClaudeAgentSDK.query("Research topic", options)

      status = Coordinator.get_status(coord)
      # => %{subagent_count: 5, tracker_status: :running, ...}
  """

  use Supervisor
  require Logger

  alias ResearchAgent.{HookCoordinator, SubagentTracker, TranscriptLogger}

  @typedoc "Coordinator status"
  @type status :: %{
          tracker_status: :running | :stopped,
          logger_status: :running | :stopped,
          subagent_count: non_neg_integer()
        }

  @doc """
  Starts the Coordinator supervisor.

  ## Options

  - `:output_dir` - Directory for output files (required)
  - `:session_id` - Unique session ID (auto-generated if not provided)

  ## Example

      {:ok, coord} = Coordinator.start_link(output_dir: "./research_output")
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    output_dir = Keyword.fetch!(opts, :output_dir)
    session_id = Keyword.get(opts, :session_id, generate_session_id())

    init_arg = %{output_dir: output_dir, session_id: session_id}
    Supervisor.start_link(__MODULE__, init_arg, [])
  end

  @impl true
  def init(init_arg) do
    # Generate unique names for this coordinator instance
    tracker_name = :"tracker_#{init_arg.session_id}"
    _logger_name = :"logger_#{init_arg.session_id}"

    children = [
      %{
        id: :subagent_tracker,
        start: {SubagentTracker, :start_link, [[name: tracker_name]]}
      },
      %{
        id: :transcript_logger,
        start:
          {TranscriptLogger, :start_link,
           [[output_dir: init_arg.output_dir, session_id: init_arg.session_id]]}
      }
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Gets the SubagentTracker process.
  """
  @spec get_tracker(pid()) :: pid() | nil
  def get_tracker(coordinator) do
    children = Supervisor.which_children(coordinator)

    case Enum.find(children, fn {id, _, _, _} -> id == :subagent_tracker end) do
      {_, pid, _, _} when is_pid(pid) -> pid
      _ -> nil
    end
  end

  @doc """
  Gets the TranscriptLogger process.
  """
  @spec get_logger(pid()) :: pid() | nil
  def get_logger(coordinator) do
    children = Supervisor.which_children(coordinator)

    case Enum.find(children, fn {id, _, _, _} -> id == :transcript_logger end) do
      {_, pid, _, _} when is_pid(pid) -> pid
      _ -> nil
    end
  end

  @doc """
  Builds hooks configuration using this coordinator's tracker.

  ## Returns

  A hooks map suitable for `ClaudeAgentSDK.Options`.
  """
  @spec get_hooks(pid()) :: HookCoordinator.hooks_config()
  def get_hooks(coordinator) do
    tracker = get_tracker(coordinator)
    HookCoordinator.build_hooks(tracker)
  end

  @doc """
  Returns the current status of all components.
  """
  @spec get_status(pid()) :: status()
  def get_status(coordinator) do
    tracker = get_tracker(coordinator)
    logger = get_logger(coordinator)

    tracker_status = if tracker && Process.alive?(tracker), do: :running, else: :stopped
    logger_status = if logger && Process.alive?(logger), do: :running, else: :stopped

    subagent_count =
      if tracker_status == :running do
        summary = SubagentTracker.get_summary(tracker)
        summary.total
      else
        0
      end

    %{
      tracker_status: tracker_status,
      logger_status: logger_status,
      subagent_count: subagent_count
    }
  end

  # Private Functions

  defp generate_session_id do
    :crypto.strong_rand_bytes(8)
    |> Base.url_encode64(padding: false)
  end
end
