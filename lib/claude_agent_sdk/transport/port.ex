defmodule ClaudeAgentSDK.Transport.Port do
  @moduledoc """
  Default transport implementation that uses Erlang `Port`s to communicate with the Claude CLI.

  The transport boots the CLI executable, relays JSON frames, and broadcasts inbound
  messages to all registered subscribers.
  """

  use GenServer

  import Kernel, except: [send: 2]

  @behaviour ClaudeAgentSDK.Transport

  @line_length 65_536
  alias ClaudeAgentSDK.{CLI, Options}

  defstruct port: nil,
            subscribers: %{},
            buffer: "",
            status: :disconnected,
            options: []

  @impl ClaudeAgentSDK.Transport
  def start_link(opts) when is_list(opts) do
    options = Keyword.get(opts, :options) || %Options{}

    with {:ok, {command, default_args}} <- resolve_command(opts) do
      args = Keyword.get(opts, :args, default_args)

      opts =
        opts
        |> Keyword.put(:command, command)
        |> Keyword.put(:args, args)
        |> __build_port_options__(options)

      GenServer.start_link(__MODULE__, opts)
    end
  end

  @doc false
  def __build_port_options__(opts, nil), do: __build_port_options__(opts, %Options{})

  def __build_port_options__(opts, %Options{} = options) do
    opts
    |> maybe_put_cd_from_options(options)
    |> maybe_put_env_from_options(options)
    |> maybe_put_line_length_from_options(options)
  end

  @impl ClaudeAgentSDK.Transport
  def send(transport, message) do
    GenServer.call(transport, {:send, message}, :infinity)
  end

  @impl ClaudeAgentSDK.Transport
  def subscribe(transport, pid) when is_pid(pid) do
    GenServer.call(transport, {:subscribe, pid})
  end

  @impl ClaudeAgentSDK.Transport
  def close(transport) do
    GenServer.stop(transport, :normal, 5_000)
  catch
    :exit, {:noproc, _} -> :ok
  end

  @impl ClaudeAgentSDK.Transport
  def status(transport) do
    GenServer.call(transport, :status)
  end

  ## GenServer callbacks

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)

    command = Keyword.fetch!(opts, :command)

    case open_port(command, opts) do
      {:ok, port} ->
        state = %__MODULE__{
          port: port,
          subscribers: %{},
          buffer: "",
          status: :connected,
          options: opts
        }

        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call({:send, _message}, _from, %{status: status} = state)
      when status != :connected or state.port == nil do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:send, message}, _from, state) do
    payload =
      message
      |> normalize_payload()
      |> ensure_newline()

    reply =
      try do
        true = Port.command(state.port, payload)
        :ok
      rescue
        MatchError ->
          {:error, :send_failed}

        ArgumentError ->
          {:error, :send_failed}
      catch
        :error, _reason ->
          {:error, :send_failed}
      end

    case reply do
      :ok ->
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:subscribe, pid}, _from, state) when is_pid(pid) do
    subscribers =
      case Map.fetch(state.subscribers, pid) do
        {:ok, _existing_ref} ->
          state.subscribers

        :error ->
          ref = Process.monitor(pid)
          Map.put(state.subscribers, pid, ref)
      end

    {:reply, :ok, %{state | subscribers: subscribers}}
  end

  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  @impl GenServer
  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) when is_binary(line) do
    state
    |> broadcast(line)
    |> noreply()
  end

  def handle_info({port, {:data, data}}, %{port: port} = state) when is_binary(data) do
    full = state.buffer <> data
    {complete_lines, remaining} = split_complete_lines(full)

    new_state =
      Enum.reduce(complete_lines, state, fn line, acc ->
        broadcast(acc, line)
      end)

    {:noreply, %{new_state | buffer: remaining}}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    new_state =
      state
      |> broadcast_exit(status)
      |> Map.put(:status, :disconnected)
      |> Map.put(:port, nil)

    {:noreply, new_state}
  end

  def handle_info({:EXIT, port, reason}, %{port: port} = state) do
    new_state =
      state
      |> broadcast_exit(reason)
      |> Map.put(:status, :disconnected)
      |> Map.put(:port, nil)

    {:noreply, new_state}
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    subscribers =
      case Map.pop(state.subscribers, pid) do
        {^ref, rest} -> rest
        {_, rest} -> rest
      end

    {:noreply, %{state | subscribers: subscribers}}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, %{port: port}) when is_port(port) do
    Port.close(port)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  ## Helpers

  defp resolve_command(opts) do
    command = Keyword.get(opts, :command)

    cond do
      is_binary(command) and File.exists?(command) ->
        {:ok, {command, Keyword.get(opts, :args, [])}}

      is_binary(command) ->
        case System.find_executable(command) do
          nil -> {:error, {:command_not_found, command}}
          path -> {:ok, {path, Keyword.get(opts, :args, [])}}
        end

      is_list(command) ->
        {:ok, {List.to_string(command), Keyword.get(opts, :args, [])}}

      # No explicit command - build from Options if provided
      true ->
        build_command_from_options(opts)
    end
  end

  defp build_command_from_options(opts) do
    case Keyword.get(opts, :options) do
      %Options{} = options ->
        case CLI.find_executable() do
          {:ok, executable} ->
            args = [
              "--output-format",
              "stream-json",
              "--input-format",
              "stream-json",
              "--verbose"
            ]

            args = args ++ Options.to_args(options)
            {:ok, {executable, args}}

          {:error, :not_found} ->
            {:error, {:command_not_found, "claude"}}
        end

      _ ->
        {:error, {:command_not_found, nil}}
    end
  end

  defp maybe_put_cd_from_options(opts, %Options{cwd: nil}), do: opts

  defp maybe_put_cd_from_options(opts, %Options{cwd: cwd}) when is_binary(cwd) do
    if not File.dir?(cwd) do
      File.mkdir_p!(cwd)
    end

    Keyword.put_new(opts, :cd, cwd)
  end

  defp maybe_put_cd_from_options(opts, _), do: opts

  defp maybe_put_line_length_from_options(opts, %Options{max_buffer_size: size})
       when is_integer(size) and size > 0 do
    Keyword.put_new(opts, :line_length, size)
  end

  defp maybe_put_line_length_from_options(opts, _), do: opts

  defp maybe_put_env_from_options(opts, %Options{} = options) do
    env_overrides = options.env || %{}

    merged_env =
      opts
      |> Keyword.get(:env)
      |> env_list_to_map()
      |> merge_with_system_env()
      |> merge_env_overrides(env_overrides)
      |> merge_user_env(options.user)
      |> maybe_put_file_checkpointing_env(options)

    if map_size(merged_env) == 0 do
      opts
    else
      Keyword.put(opts, :env, map_to_env_list(merged_env))
    end
  end

  defp env_list_to_map(nil), do: %{}

  defp env_list_to_map(list) when is_list(list) do
    Enum.reduce(list, %{}, fn
      {key, value}, acc ->
        Map.put(acc, to_string(key), to_string(value))

      other, acc when is_binary(other) ->
        Map.put(acc, other, "")
    end)
  end

  defp merge_with_system_env(map) do
    System.get_env()
    |> Enum.reduce(map, fn {key, value}, acc -> Map.put_new(acc, key, value) end)
  end

  defp merge_env_overrides(existing, overrides) do
    overrides
    |> Enum.reduce(existing, fn {key, value}, acc ->
      env_key = to_string(key)

      if is_nil(value) do
        Map.delete(acc, env_key)
      else
        Map.put(acc, env_key, to_string(value))
      end
    end)
    |> Map.put_new("CLAUDE_CODE_ENTRYPOINT", "sdk-elixir")
    |> Map.put_new("CLAUDE_AGENT_SDK_VERSION", sdk_version())
  end

  defp merge_user_env(env_map, nil), do: env_map

  defp merge_user_env(env_map, user) when is_binary(user) do
    env_map
    |> Map.put("USER", user)
    |> Map.put("LOGNAME", user)
  end

  defp maybe_put_file_checkpointing_env(env_map, %Options{enable_file_checkpointing: true}) do
    Map.put(env_map, "CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING", "true")
  end

  defp maybe_put_file_checkpointing_env(env_map, _options), do: env_map

  defp map_to_env_list(map) do
    Enum.map(map, fn {key, value} -> {key, value} end)
  end

  defp sdk_version do
    case Application.spec(:claude_agent_sdk, :vsn) do
      nil -> "unknown"
      version -> to_string(version)
    end
  end

  defp open_port(command, opts) do
    args = Keyword.get(opts, :args, [])
    env = Keyword.get(opts, :env)
    cd = Keyword.get(opts, :cd)
    line_length = Keyword.get(opts, :line_length, @line_length)

    port_opts =
      [
        :binary,
        :exit_status,
        {:line, line_length},
        :use_stdio,
        :hide,
        {:args, Enum.map(args, &to_charlist/1)}
      ]
      |> maybe_put_env(env)
      |> maybe_put_cd(cd)

    {:ok,
     Port.open(
       {:spawn_executable, to_charlist(command)},
       port_opts
     )}
  rescue
    ArgumentError -> {:error, :failed_to_open_port}
  end

  defp maybe_put_env(opts, nil), do: opts

  defp maybe_put_env(opts, env) when is_list(env) do
    env_chars =
      Enum.map(env, fn
        {key, value} when is_binary(key) and is_binary(value) ->
          {to_charlist(key), to_charlist(value)}

        {key, value} ->
          {to_charlist(to_string(key)), to_charlist(to_string(value))}
      end)

    [{:env, env_chars} | opts]
  end

  defp maybe_put_cd(opts, nil), do: opts
  defp maybe_put_cd(opts, cd), do: [{:cd, to_charlist(cd)} | opts]

  defp normalize_payload(message) when is_binary(message), do: message

  defp normalize_payload(message) when is_map(message) or is_list(message) do
    Jason.encode!(message)
  end

  defp normalize_payload(message), do: to_string(message)

  defp ensure_newline(payload) do
    if String.ends_with?(payload, "\n") do
      payload
    else
      payload <> "\n"
    end
  end

  defp split_complete_lines(""), do: {[], ""}

  defp split_complete_lines(data) do
    lines = String.split(data, "\n")

    case List.pop_at(lines, -1) do
      {nil, _} -> {[], ""}
      {"", rest} -> {rest, ""}
      {last, rest} -> {rest, last}
    end
  end

  defp broadcast(state, line) do
    Enum.each(state.subscribers, fn {pid, _ref} ->
      Kernel.send(pid, {:transport_message, line})
    end)

    state
  end

  defp broadcast_exit(state, reason) do
    Enum.each(state.subscribers, fn {pid, _ref} ->
      Kernel.send(pid, {:transport_exit, reason})
    end)

    state
  end

  defp noreply(state), do: {:noreply, state}
end
