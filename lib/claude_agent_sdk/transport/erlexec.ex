defmodule ClaudeAgentSDK.Transport.Erlexec do
  @moduledoc """
  Transport implementation backed by erlexec.

  This transport supports OS-level user execution via erlexec's `:user` option,
  which `Port`-based transports cannot provide.
  """

  use GenServer

  import Kernel, except: [send: 2]

  @behaviour ClaudeAgentSDK.Transport

  alias ClaudeAgentSDK.{CLI, Options}
  alias ClaudeAgentSDK.Process, as: SDKProcess
  alias ClaudeAgentSDK.Transport.AgentsFile

  defstruct subprocess: nil,
            subscribers: MapSet.new(),
            stdout_buffer: "",
            status: :disconnected,
            stderr_callback: nil,
            temp_files: []

  @impl ClaudeAgentSDK.Transport
  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl ClaudeAgentSDK.Transport
  def send(transport, message) when is_pid(transport) and is_binary(message) do
    GenServer.call(transport, {:send, message})
  end

  @impl ClaudeAgentSDK.Transport
  def subscribe(transport, pid) when is_pid(transport) and is_pid(pid) do
    GenServer.call(transport, {:subscribe, pid})
  end

  @impl ClaudeAgentSDK.Transport
  def close(transport) when is_pid(transport) do
    GenServer.stop(transport, :normal)
  end

  @impl ClaudeAgentSDK.Transport
  def status(transport) when is_pid(transport) do
    GenServer.call(transport, :status)
  end

  @impl GenServer
  def init(opts) do
    options = Keyword.get(opts, :options) || %Options{}

    with {:ok, command, args, temp_files} <- resolve_command(opts, options),
         :ok <- validate_cwd(options.cwd),
         :ok <- ensure_erlexec_started(),
         {args, agent_temp_files} <- AgentsFile.externalize_agents_if_needed(args),
         cmd <- build_command(command, args),
         exec_opts <- build_exec_opts(options),
         {:ok, pid, os_pid} <- :exec.run(cmd, exec_opts) do
      {:ok,
       %__MODULE__{
         subprocess: {pid, os_pid},
         status: :connected,
         stderr_callback: options.stderr,
         temp_files: temp_files ++ agent_temp_files
       }}
    else
      {:error, reason} -> {:stop, reason}
      other -> {:stop, other}
    end
  end

  defp resolve_command(opts, options) do
    case Keyword.fetch(opts, :command) do
      {:ok, command} when is_binary(command) ->
        {:ok, command, Keyword.get(opts, :args, []), []}

      {:ok, _command} ->
        {:error, :invalid_command}

      :error ->
        case build_command_from_options(options) do
          {:ok, {cmd, args, temp_files}} -> {:ok, cmd, args, temp_files}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp validate_cwd(cwd) when is_binary(cwd) do
    if File.dir?(cwd) do
      :ok
    else
      {:error, {:cwd_not_found, cwd}}
    end
  end

  defp validate_cwd(_cwd), do: :ok

  defp ensure_erlexec_started do
    case Application.ensure_all_started(:erlexec) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:erlexec_not_started, reason}}
    end
  end

  @impl GenServer
  def handle_call({:subscribe, pid}, _from, state) do
    Process.monitor(pid)
    {:reply, :ok, %{state | subscribers: MapSet.put(state.subscribers, pid)}}
  end

  def handle_call({:send, message}, _from, %{subprocess: {pid, _os_pid}} = state) do
    :exec.send(pid, message)
    {:reply, :ok, state}
  catch
    _, _ -> {:reply, {:error, :send_failed}, state}
  end

  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  @impl GenServer
  def handle_info({:stdout, os_pid, data}, %{subprocess: {_pid, os_pid}} = state) do
    data = IO.iodata_to_binary(data)
    full = state.stdout_buffer <> data
    {complete_lines, remaining} = split_complete_lines(full)

    Enum.each(complete_lines, fn line ->
      broadcast(state.subscribers, {:transport_message, line})
    end)

    {:noreply, %{state | stdout_buffer: remaining}}
  end

  def handle_info({:stderr, _os_pid, data}, state) do
    data = IO.iodata_to_binary(data)
    lines = data |> String.split("\n") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

    if is_function(state.stderr_callback, 1) do
      Enum.each(lines, fn line -> state.stderr_callback.(line) end)
    end

    {:noreply, state}
  end

  def handle_info({:DOWN, os_pid, :process, pid, reason}, %{subprocess: {pid, os_pid}} = state) do
    broadcast(state.subscribers, {:transport_exit, reason})
    {:stop, :normal, %{state | status: :disconnected, subprocess: nil}}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  def handle_info(_other, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, %{subprocess: {pid, _os_pid}, temp_files: temp_files}) do
    :exec.stop(pid)
    _ = AgentsFile.cleanup_temp_files(temp_files)
    :ok
  catch
    _, _ -> :ok
  end

  def terminate(_reason, %{temp_files: temp_files}) do
    _ = AgentsFile.cleanup_temp_files(temp_files)
    :ok
  end

  defp broadcast(subscribers, message) do
    Enum.each(subscribers, fn pid -> Kernel.send(pid, message) end)
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

  defp build_command(command, args) when is_binary(command) and is_list(args) do
    quoted_args = Enum.map(args, &SDKProcess.__shell_escape__/1)
    Enum.join([command | quoted_args], " ")
  end

  defp build_exec_opts(%Options{} = options) do
    env =
      options
      |> SDKProcess.__env_vars__()
      |> Enum.map(fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    [:stdin, :stdout, :stderr, :monitor]
    |> maybe_put_env_option(env)
    |> maybe_put_user_option(options.user)
    |> maybe_put_cd_option(options.cwd)
  end

  defp maybe_put_env_option(opts, []), do: opts
  defp maybe_put_env_option(opts, env), do: [{:env, env} | opts]

  defp maybe_put_user_option(opts, nil), do: opts

  defp maybe_put_user_option(opts, user) when is_binary(user),
    do: [{:user, String.to_charlist(user)} | opts]

  defp maybe_put_cd_option(opts, nil), do: opts
  defp maybe_put_cd_option(opts, cwd) when is_binary(cwd), do: [{:cd, cwd} | opts]

  @doc false
  def __exec_opts__(%Options{} = options), do: build_exec_opts(options)

  defp build_command_from_options(%Options{} = options) do
    case CLI.find_executable() do
      {:ok, executable} ->
        args = [
          "--print",
          "--output-format",
          "stream-json",
          "--input-format",
          "stream-json",
          "--replay-user-messages",
          "--verbose"
        ]

        args = args ++ ClaudeAgentSDK.Options.to_args(options)
        {args, temp_files} = AgentsFile.externalize_agents_if_needed(args)
        {:ok, {executable, args, temp_files}}

      {:error, :not_found} ->
        {:error, :cli_not_found}
    end
  end
end
