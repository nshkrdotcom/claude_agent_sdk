defmodule ClaudeAgentSDK.CLI do
  @moduledoc """
  Centralized Claude CLI discovery and version tracking.

  This module consolidates executable lookup logic and provides helpers
  for checking installation status, parsing the installed version, and
  warning when the detected version is below the supported minimum.
  """

  alias ClaudeAgentSDK.Config.CLI, as: CLIConfig
  alias ClaudeAgentSDK.Config.Env
  alias ClaudeAgentSDK.Log, as: Logger
  alias ClaudeAgentSDK.Options

  @doc """
  Attempts to find the Claude CLI executable.

  Tries candidates in order (`claude-code`, then `claude`) and returns
  `{:ok, path}` when found or `{:error, :not_found}` otherwise.
  """
  @spec find_executable() :: {:ok, String.t()} | {:error, :not_found}
  def find_executable do
    with nil <- find_bundled_executable(),
         nil <- find_on_path(CLIConfig.executable_candidates()),
         nil <- find_in_known_locations() do
      {:error, :not_found}
    else
      path when is_binary(path) -> {:ok, path}
    end
  end

  @doc """
  Resolves the CLI executable, honoring option overrides.

  When `path_to_claude_code_executable` or `executable` is set on the options,
  that value is used directly. Otherwise falls back to normal discovery.
  """
  @spec resolve_executable(Options.t() | nil) :: {:ok, String.t()} | {:error, :not_found}
  def resolve_executable(%Options{path_to_claude_code_executable: path})
      when is_binary(path) do
    {:ok, path}
  end

  def resolve_executable(%Options{executable: executable}) when is_binary(executable) do
    {:ok, executable}
  end

  def resolve_executable(_), do: find_executable()

  @doc """
  Like `resolve_executable/1` but raises when the CLI is not available.
  """
  @spec resolve_executable!(Options.t() | nil) :: String.t()
  def resolve_executable!(options) do
    case resolve_executable(options) do
      {:ok, path} ->
        path

      {:error, :not_found} ->
        raise ClaudeAgentSDK.Errors.CLINotFoundError,
          message: "Claude CLI not found. Please install with: #{CLIConfig.install_command()}"
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
        raise ClaudeAgentSDK.Errors.CLINotFoundError,
          message: "Claude CLI not found. Please install with: #{CLIConfig.install_command()}"
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
         {:ok, parsed} <- parse_version(output) do
      {:ok, parsed}
    else
      {:error, :not_found} = error ->
        error

      {_output, status} when is_integer(status) ->
        {:error, {:exit_status, status}}

      {:error, :parse_failed} ->
        {:error, :parse_failed}

      _ ->
        {:error, :parse_failed}
    end
  end

  @doc """
  Returns the minimum supported Claude CLI version.
  """
  @spec minimum_version() :: String.t()
  def minimum_version, do: CLIConfig.minimum_version()

  @doc """
  Returns the recommended Claude CLI version for this SDK release.

  This version is tested and known to work with all SDK features including
  file checkpointing, streaming control protocol, and partial messages.
  """
  @spec recommended_version() :: String.t()
  def recommended_version, do: CLIConfig.recommended_version()

  @doc """
  True if the installed version meets or exceeds the minimum.
  """
  @spec version_supported?() :: boolean()
  def version_supported? do
    with {:ok, installed} <- version(),
         {:ok, installed_version} <- Version.parse(installed),
         {:ok, minimum_version} <- Version.parse(CLIConfig.minimum_version()) do
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
    if System.get_env(Env.skip_version_check()) do
      :ok
    else
      do_warn_if_outdated()
    end
  end

  defp do_warn_if_outdated do
    case version() do
      {:ok, installed} ->
        warn_for_installed_version(installed)

      {:error, :not_found} ->
        Logger.warning(
          "Claude CLI not found. Minimum supported version: #{CLIConfig.minimum_version()}"
        )

      {:error, reason} ->
        Logger.warning(
          "Could not determine Claude CLI version (#{inspect(reason)}). Minimum supported: #{CLIConfig.minimum_version()}"
        )
    end

    :ok
  end

  defp find_bundled_executable do
    case Application.get_env(:claude_agent_sdk, :cli_bundled_path) do
      path when is_binary(path) ->
        if File.regular?(path), do: path, else: nil

      _ ->
        bundled_path = default_bundled_path()
        if is_binary(bundled_path) and File.regular?(bundled_path), do: bundled_path, else: nil
    end
  end

  defp default_bundled_path do
    cli_name =
      if match?({:win32, _}, :os.type()) do
        "claude.exe"
      else
        "claude"
      end

    case :code.priv_dir(:claude_agent_sdk) do
      dir when is_list(dir) ->
        dir
        |> List.to_string()
        |> Path.join("_bundled")
        |> Path.join(cli_name)

      _ ->
        nil
    end
  end

  defp find_on_path(candidates) when is_list(candidates) do
    Enum.find_value(candidates, fn candidate ->
      System.find_executable(candidate)
    end)
  end

  defp find_in_known_locations do
    known =
      case Application.get_env(:claude_agent_sdk, :cli_known_locations) do
        paths when is_list(paths) -> paths
        _ -> default_known_locations()
      end

    Enum.find_value(known, fn path ->
      if is_binary(path) and File.regular?(path), do: path, else: nil
    end)
  end

  defp default_known_locations do
    home = System.user_home!()

    [
      Path.join([home, ".npm-global", "bin", "claude"]),
      "/usr/local/bin/claude",
      Path.join([home, ".local", "bin", "claude"]),
      Path.join([home, "node_modules", ".bin", "claude"]),
      Path.join([home, ".yarn", "bin", "claude"]),
      Path.join([home, ".claude", "local", "claude"])
    ]
  end

  defp warn_for_installed_version(installed) do
    case {Version.parse(installed), Version.parse(CLIConfig.minimum_version())} do
      {{:ok, installed_version}, {:ok, minimum_version}} ->
        if Version.compare(installed_version, minimum_version) == :lt do
          Logger.warning(
            "Claude CLI version #{installed} is below minimum #{CLIConfig.minimum_version()}. Please upgrade."
          )
        end

      _ ->
        Logger.warning(
          "Could not parse Claude CLI version #{installed}. Minimum supported: #{CLIConfig.minimum_version()}"
        )
    end
  end

  defp parse_version(output) when is_binary(output) do
    case Regex.run(~r/(\d+\.\d+\.\d+)/, output) do
      [_, version] -> {:ok, version}
      _ -> {:error, :parse_failed}
    end
  end
end
