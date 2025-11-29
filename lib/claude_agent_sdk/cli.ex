defmodule ClaudeAgentSDK.CLI do
  @moduledoc """
  Centralized Claude CLI discovery and version tracking.

  This module consolidates executable lookup logic and provides helpers
  for checking installation status, parsing the installed version, and
  warning when the detected version is below the supported minimum.
  """

  require Logger

  @minimum_version "1.0.0"
  @executable_candidates ["claude-code", "claude"]

  @doc """
  Attempts to find the Claude CLI executable.

  Tries candidates in order (`claude-code`, then `claude`) and returns
  `{:ok, path}` when found or `{:error, :not_found}` otherwise.
  """
  @spec find_executable() :: {:ok, String.t()} | {:error, :not_found}
  def find_executable do
    @executable_candidates
    |> Enum.find_value(fn candidate ->
      case System.find_executable(candidate) do
        nil -> nil
        path -> {:ok, path}
      end
    end)
    |> case do
      nil -> {:error, :not_found}
      result -> result
    end
  end

  @doc """
  Like `find_executable/0` but raises when the CLI is not available.
  """
  @spec find_executable!() :: String.t()
  def find_executable! do
    case find_executable() do
      {:ok, path} ->
        path

      {:error, :not_found} ->
        raise "Claude CLI not found. Please install with: npm install -g @anthropic-ai/claude-code"
    end
  end

  @doc """
  Returns true if the Claude CLI is installed and discoverable.
  """
  @spec installed?() :: boolean()
  def installed?, do: match?({:ok, _}, find_executable())

  @doc """
  Returns the installed Claude CLI version as a string.
  """
  @spec version() :: {:ok, String.t()} | {:error, term()}
  def version do
    with {:ok, executable} <- find_executable(),
         {output, 0} <- System.cmd(executable, ["--version"], stderr_to_stdout: true),
         {:ok, version} <- parse_version(output) do
      {:ok, version}
    else
      {:error, :not_found} = error ->
        error

      {:error, _reason} = error ->
        error

      {_output, status} ->
        {:error, {:exit_status, status}}

      :error ->
        {:error, :parse_failed}

      other ->
        cond do
          match?({:error, _}, other) -> other
          true -> {:error, :version_command_failed}
        end
    end
  end

  @doc """
  Returns the minimum supported Claude CLI version.
  """
  @spec minimum_version() :: String.t()
  def minimum_version, do: @minimum_version

  @doc """
  True if the installed version meets or exceeds the minimum.
  """
  @spec version_supported?() :: boolean()
  def version_supported? do
    with {:ok, installed} <- version(),
         {:ok, installed_version} <- Version.parse(installed),
         {:ok, minimum_version} <- Version.parse(@minimum_version) do
      Version.compare(installed_version, minimum_version) in [:eq, :gt]
    else
      _ -> false
    end
  end

  @doc """
  Emits a warning when the installed CLI is below the supported minimum or unknown.
  """
  @spec warn_if_outdated() :: :ok
  def warn_if_outdated do
    case version() do
      {:ok, installed} ->
        case {Version.parse(installed), Version.parse(@minimum_version)} do
          {{:ok, installed_version}, {:ok, minimum_version}} ->
            if Version.compare(installed_version, minimum_version) == :lt do
              Logger.warning(
                "Claude CLI version #{installed} is below minimum #{@minimum_version}. Please upgrade."
              )
            end

          _ ->
            Logger.warning(
              "Could not parse Claude CLI version #{installed}. Minimum supported: #{@minimum_version}"
            )
        end

      {:error, :not_found} ->
        Logger.warning("Claude CLI not found. Minimum supported version: #{@minimum_version}")

      {:error, reason} ->
        Logger.warning(
          "Could not determine Claude CLI version (#{inspect(reason)}). Minimum supported: #{@minimum_version}"
        )
    end

    :ok
  end

  defp parse_version(output) when is_binary(output) do
    case Regex.run(~r/(\d+\.\d+\.\d+)/, output) do
      [_, version] -> {:ok, version}
      _ -> {:error, :parse_failed}
    end
  end
end
