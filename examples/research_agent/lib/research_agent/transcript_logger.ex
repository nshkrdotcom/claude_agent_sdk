defmodule ResearchAgent.TranscriptLogger do
  @moduledoc """
  Records session transcripts for analysis and debugging.

  The TranscriptLogger captures all events during a research session,
  including user inputs, agent responses, tool calls, and subagent
  coordination. This provides:

  - Complete audit trail of research sessions
  - Post-session analysis capabilities
  - Debugging information for multi-agent workflows

  ## Event Types

  - `:user_input` - User messages and commands
  - `:agent_response` - Claude's responses
  - `:tool_call` - Tool invocations
  - `:agent_spawn` - Subagent creation
  - `:agent_complete` - Subagent completion
  - `:research_start` / `:research_end` - Session boundaries

  ## Example

      {:ok, logger} = TranscriptLogger.start_link(
        output_dir: "./output",
        session_id: "abc123"
      )

      TranscriptLogger.log_event(logger, :user_input, %{content: "Research AI"})
      TranscriptLogger.log_event(logger, :agent_response, %{content: "Starting..."})

      {:ok, path} = TranscriptLogger.save_transcript(logger)
  """

  use GenServer
  require Logger

  @typedoc "Logged event structure"
  @type event :: %{
          event_type: atom(),
          timestamp: String.t(),
          data: map()
        }

  @typedoc "Event summary statistics"
  @type summary :: %{
          event_count: non_neg_integer(),
          by_type: %{atom() => non_neg_integer()}
        }

  # Client API

  @doc """
  Starts the TranscriptLogger.

  ## Options

  - `:output_dir` - Directory for saving transcripts (required)
  - `:session_id` - Unique session identifier (required)

  ## Example

      {:ok, logger} = TranscriptLogger.start_link(
        output_dir: "/tmp/research",
        session_id: "session_123"
      )
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    output_dir = Keyword.fetch!(opts, :output_dir)
    session_id = Keyword.fetch!(opts, :session_id)

    GenServer.start_link(__MODULE__, %{output_dir: output_dir, session_id: session_id}, [])
  end

  @doc """
  Logs an event to the transcript.

  ## Parameters

  - `logger` - The logger process
  - `event_type` - Type of event (atom)
  - `data` - Event data (map)

  ## Example

      TranscriptLogger.log_event(logger, :tool_call, %{
        tool: "WebSearch",
        query: "AI safety research"
      })
  """
  @spec log_event(pid(), atom(), map()) :: :ok
  def log_event(logger, event_type, data) do
    GenServer.cast(logger, {:log_event, event_type, data})
  end

  @doc """
  Retrieves all logged events.
  """
  @spec get_events(pid()) :: [event()]
  def get_events(logger) do
    GenServer.call(logger, :get_events)
  end

  @doc """
  Saves the transcript to a JSON file.

  ## Returns

  - `{:ok, path}` - Path to the saved file
  - `{:error, reason}` - If saving failed
  """
  @spec save_transcript(pid()) :: {:ok, String.t()} | {:error, term()}
  def save_transcript(logger) do
    GenServer.call(logger, :save_transcript)
  end

  @doc """
  Returns summary statistics about logged events.
  """
  @spec get_summary(pid()) :: summary()
  def get_summary(logger) do
    GenServer.call(logger, :get_summary)
  end

  # Server Callbacks

  @impl true
  def init(config) do
    # Ensure output directory exists
    File.mkdir_p!(config.output_dir)

    state = %{
      output_dir: config.output_dir,
      session_id: config.session_id,
      events: [],
      started_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:log_event, event_type, data}, state) do
    event = %{
      event_type: event_type,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      data: data
    }

    {:noreply, %{state | events: state.events ++ [event]}}
  end

  @impl true
  def handle_call(:get_events, _from, state) do
    {:reply, state.events, state}
  end

  @impl true
  def handle_call(:get_summary, _from, state) do
    by_type =
      state.events
      |> Enum.group_by(& &1.event_type)
      |> Enum.map(fn {type, events} -> {type, length(events)} end)
      |> Map.new()

    summary = %{
      event_count: length(state.events),
      by_type: by_type
    }

    {:reply, summary, state}
  end

  @impl true
  def handle_call(:save_transcript, _from, state) do
    filename = "transcript_#{state.session_id}_#{timestamp_string()}.json"
    path = Path.join(state.output_dir, filename)

    transcript = %{
      session_id: state.session_id,
      started_at: state.started_at,
      saved_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      event_count: length(state.events),
      events: state.events
    }

    case Jason.encode(transcript, pretty: true) do
      {:ok, json} ->
        case File.write(path, json) do
          :ok ->
            Logger.info("[TranscriptLogger] Saved transcript to #{path}")
            {:reply, {:ok, path}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp timestamp_string do
    DateTime.utc_now()
    |> DateTime.to_iso8601()
    |> String.replace(":", "-")
    |> String.replace(".", "-")
  end
end
