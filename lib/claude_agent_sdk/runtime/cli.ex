defmodule ClaudeAgentSDK.Runtime.CLI do
  @moduledoc """
  Session-oriented runtime kit for the shared Claude CLI lane.
  """

  alias ClaudeAgentSDK.{CLI, Options}
  alias ClaudeAgentSDK.Config.CLI, as: CLIConfig
  alias ClaudeAgentSDK.Process, as: SDKProcess
  alias ClaudeAgentSDK.Streaming.EventParser
  alias CliSubprocessCore.Command
  alias CliSubprocessCore.Event, as: CoreEvent
  alias CliSubprocessCore.Payload
  alias CliSubprocessCore.ProviderProfiles.Claude, as: CoreClaude
  alias CliSubprocessCore.Session, as: CoreSession

  @runtime_metadata %{lane: :claude_agent_sdk_common_cli}

  defmodule ProjectionState do
    @moduledoc false

    defstruct accumulated_text: "",
              session_id: nil

    @type t :: %__MODULE__{
            accumulated_text: String.t(),
            session_id: String.t() | nil
          }
  end

  defmodule Profile do
    @moduledoc false

    @behaviour CliSubprocessCore.ProviderProfile

    alias ClaudeAgentSDK.Runtime.CLI
    alias CliSubprocessCore.ProviderProfiles.Claude, as: CoreClaude

    @impl true
    def id, do: :claude

    @impl true
    def capabilities, do: CoreClaude.capabilities()

    @impl true
    def build_invocation(opts) when is_list(opts), do: CLI.build_invocation(opts)

    @impl true
    def init_parser_state(opts), do: CoreClaude.init_parser_state(opts)

    @impl true
    def decode_stdout(line, state), do: CoreClaude.decode_stdout(line, state)

    @impl true
    def decode_stderr(chunk, state), do: CoreClaude.decode_stderr(chunk, state)

    @impl true
    def handle_exit(reason, state), do: CoreClaude.handle_exit(reason, state)

    @impl true
    def transport_options(opts), do: CoreClaude.transport_options(opts)
  end

  @type start_option ::
          {:options, Options.t()}
          | {:subscriber, pid() | {pid(), reference() | :legacy}}
          | {:metadata, map()}
          | {:transport_module, module()}
          | {:session_event_tag, atom()}
          | {:startup_mode, :eager | :lazy}
          | {:task_supervisor, pid() | atom()}
          | {:headless_timeout_ms, pos_integer() | :infinity}
          | {:max_buffer_size, pos_integer()}
          | {:max_stderr_buffer_size, pos_integer()}

  @spec start_session([start_option()]) ::
          {:ok, pid(), %{info: map(), projection_state: ProjectionState.t()}}
          | {:error, term()}
  def start_session(opts) when is_list(opts) do
    options = opts |> Keyword.get(:options, %Options{}) |> force_partial_messages()

    session_opts =
      build_session_options(
        options,
        Keyword.take(opts, [
          :subscriber,
          :metadata,
          :transport_module,
          :session_event_tag,
          :startup_mode,
          :task_supervisor,
          :headless_timeout_ms,
          :max_buffer_size,
          :max_stderr_buffer_size
        ])
      )

    case start_core_session(session_opts) do
      {:ok, session, info} ->
        {:ok, session, %{info: info, projection_state: new_projection_state(info)}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error in [ArgumentError] ->
      {:error, error}
  catch
    :exit, reason ->
      {:error, reason}
  end

  @spec subscribe(pid(), pid(), reference()) :: :ok | {:error, term()}
  def subscribe(session, pid, ref) when is_pid(session) and is_pid(pid) and is_reference(ref) do
    CoreSession.subscribe(session, pid, ref)
  end

  @spec send_input(pid(), iodata() | map() | list(), keyword()) :: :ok | {:error, term()}
  def send_input(session, input, opts \\ [])

  def send_input(session, input, opts) when is_pid(session) and is_binary(input) do
    CoreSession.send_input(session, user_message(input), opts)
  end

  def send_input(session, input, opts)
      when is_pid(session) and (is_map(input) or is_list(input)) do
    CoreSession.send_input(session, input, opts)
  end

  @spec end_input(pid()) :: :ok | {:error, term()}
  def end_input(session) when is_pid(session), do: CoreSession.end_input(session)

  @spec interrupt(pid()) :: :ok | {:error, term()}
  def interrupt(session) when is_pid(session), do: CoreSession.interrupt(session)

  @spec close(pid()) :: :ok
  def close(session) when is_pid(session), do: CoreSession.close(session)

  @spec info(pid()) :: map()
  def info(session) when is_pid(session), do: CoreSession.info(session)

  @spec capabilities() :: [atom()]
  def capabilities, do: CoreClaude.capabilities()

  @spec new_projection_state(map()) :: ProjectionState.t()
  def new_projection_state(_info \\ %{}) do
    %ProjectionState{}
  end

  @spec project_event(CoreEvent.t(), ProjectionState.t()) :: {[map()], ProjectionState.t()}
  def project_event(%CoreEvent{kind: :run_started}, %ProjectionState{} = state), do: {[], state}
  def project_event(%CoreEvent{kind: :stderr}, %ProjectionState{} = state), do: {[], state}

  def project_event(
        %CoreEvent{kind: :error, payload: %Payload.Error{} = payload},
        %ProjectionState{} = state
      ) do
    {[%{type: :error, error: payload.message, code: payload.code}], state}
  end

  def project_event(
        %CoreEvent{raw: raw, provider_session_id: provider_session_id},
        %ProjectionState{} = state
      )
      when is_map(raw) do
    {event_json, metadata} = unwrap_stream_event(raw, provider_session_id, state)

    {:ok, parsed_events, accumulated_text} =
      EventParser.parse_event(event_json, state.accumulated_text)

    events =
      parsed_events
      |> EventParser.attach_stream_metadata(metadata, event_json)
      |> Enum.map(&maybe_patch_session_id(&1, metadata[:session_id]))

    session_id = metadata[:session_id] || provider_session_id || state.session_id

    {events, %ProjectionState{state | accumulated_text: accumulated_text, session_id: session_id}}
  end

  def project_event(_event, %ProjectionState{} = state), do: {[], state}

  @spec build_invocation(keyword()) :: {:ok, Command.t()} | {:error, term()}
  def build_invocation(opts) when is_list(opts) do
    options = opts |> Keyword.get(:options, %Options{}) |> force_partial_messages()

    case CLI.resolve_executable(options) do
      {:ok, executable} ->
        args = CLIConfig.streaming_bidirectional_args() ++ Options.to_stream_json_args(options)

        {:ok,
         Command.new(executable, args,
           cwd: options.cwd,
           env: SDKProcess.__env_vars__(options)
         )}

      {:error, :not_found} ->
        {:error, :cli_not_found}
    end
  end

  defp build_session_options(%Options{} = options, runtime_opts) do
    metadata =
      @runtime_metadata
      |> Map.merge(Keyword.get(runtime_opts, :metadata, %{}))

    base_opts = [
      provider: :claude,
      profile: Profile,
      transport_module:
        Keyword.get(runtime_opts, :transport_module, ClaudeAgentSDK.Transport.Erlexec),
      subscriber: Keyword.get(runtime_opts, :subscriber),
      metadata: metadata,
      session_event_tag:
        Keyword.get(runtime_opts, :session_event_tag, :cli_subprocess_core_session),
      options: options,
      cwd: options.cwd,
      env: SDKProcess.__env_vars__(options),
      startup_mode: Keyword.get(runtime_opts, :startup_mode, :eager),
      task_supervisor: Keyword.get(runtime_opts, :task_supervisor),
      headless_timeout_ms: Keyword.get(runtime_opts, :headless_timeout_ms, :infinity),
      max_buffer_size: Keyword.get(runtime_opts, :max_buffer_size, options.max_buffer_size),
      max_stderr_buffer_size: Keyword.get(runtime_opts, :max_stderr_buffer_size),
      stderr_callback: options.stderr
    ]

    Enum.reject(base_opts, fn
      {_key, nil} -> true
      _pair -> false
    end)
  end

  defp force_partial_messages(%Options{} = options) do
    %{options | include_partial_messages: true}
  end

  defp user_message(input) when is_binary(input) do
    %{
      "type" => "user",
      "message" => %{"role" => "user", "content" => input}
    }
  end

  defp unwrap_stream_event(%{"type" => "stream_event"} = wrapper, provider_session_id, state) do
    event = Map.fetch!(wrapper, "event")

    metadata = %{
      parent_tool_use_id: Map.get(wrapper, "parent_tool_use_id"),
      uuid: Map.fetch!(wrapper, "uuid"),
      session_id: Map.get(wrapper, "session_id") || provider_session_id || state.session_id
    }

    {event, metadata}
  end

  defp unwrap_stream_event(event, provider_session_id, state) do
    metadata = %{
      parent_tool_use_id: Map.get(event, "parent_tool_use_id"),
      uuid: Map.get(event, "uuid"),
      session_id: Map.get(event, "session_id") || provider_session_id || state.session_id
    }

    {event, metadata}
  end

  defp maybe_patch_session_id(event, nil), do: event

  defp maybe_patch_session_id(event, session_id) do
    Map.put_new(event, :session_id, session_id)
  end

  defp start_core_session(session_opts) when is_list(session_opts) do
    ref = make_ref()
    previous_trap_exit? = Process.flag(:trap_exit, true)

    try do
      case CoreSession.start_link(Keyword.put(session_opts, :starter, {self(), ref})) do
        {:ok, session} ->
          receive do
            {:cli_subprocess_core_session_started, ^ref, info} ->
              {:ok, session, info}

            {:EXIT, ^session, reason} ->
              {:error, reason}
          after
            5_000 ->
              {:error, :session_start_timeout}
          end

        {:error, reason} ->
          {:error, reason}
      end
    after
      Process.flag(:trap_exit, previous_trap_exit?)
    end
  end
end
