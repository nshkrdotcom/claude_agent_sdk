defmodule ClaudeAgentSDK.CLI do
  @moduledoc """
  Claude CLI resolution and version helpers backed by the shared core policy.
  """

  alias ClaudeAgentSDK.Config.CLI, as: CLIConfig
  alias ClaudeAgentSDK.Config.Env
  alias ClaudeAgentSDK.Log, as: Logger
  alias ClaudeAgentSDK.Options
  alias CliSubprocessCore.{Command, CommandSpec, ProviderCLI}
  alias CliSubprocessCore.Transport.RunResult

  @doc false
  @spec find_command_spec() :: {:ok, CommandSpec.t()} | {:error, :not_found}
  def find_command_spec, do: resolve_command_spec(nil)

  @doc """
  Attempts to find the Claude CLI executable.
  """
  @spec find_executable() :: {:ok, String.t()} | {:error, :not_found}
  def find_executable do
    with {:ok, %CommandSpec{program: program}} <- find_command_spec() do
      {:ok, program}
    end
  end

  @doc false
  @spec resolve_command_spec(Options.t() | nil) :: {:ok, CommandSpec.t()} | {:error, :not_found}
  def resolve_command_spec(options) do
    provider_opts =
      options
      |> option_overrides()
      |> maybe_put_bundled_override()

    case ProviderCLI.resolve(:claude, provider_opts, provider_cli_opts()) do
      {:ok, %CommandSpec{} = spec} ->
        {:ok, spec}

      {:error, %ProviderCLI.Error{kind: :cli_not_found}} ->
        {:error, :not_found}

      {:error, _reason} ->
        {:error, :not_found}
    end
  end

  @doc """
  Resolves the CLI executable, honoring option overrides.
  """
  @spec resolve_executable(Options.t() | nil) :: {:ok, String.t()} | {:error, :not_found}
  def resolve_executable(options) do
    with {:ok, %CommandSpec{program: program}} <- resolve_command_spec(options) do
      {:ok, program}
    end
  end

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

  @doc false
  @spec resolve_command_spec!(Options.t() | nil) :: CommandSpec.t()
  def resolve_command_spec!(options) do
    case resolve_command_spec(options) do
      {:ok, %CommandSpec{} = spec} ->
        spec

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
  def installed?, do: match?({:ok, _}, find_command_spec())

  @doc """
  Returns the installed Claude CLI version as a string.
  """
  @spec version() :: {:ok, String.t()} | {:error, term()}
  def version do
    case find_command_spec() do
      {:ok, %CommandSpec{} = spec} ->
        case run_version(spec) do
          {:ok, %RunResult{} = result} ->
            parse_version(result.stdout)

          {:error, _reason} = error ->
            error
        end

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Returns the minimum supported Claude CLI version.
  """
  @spec minimum_version() :: String.t()
  def minimum_version, do: CLIConfig.minimum_version()

  @doc """
  Returns the recommended Claude CLI version for this SDK release.
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

  defp provider_cli_opts do
    [
      extra_keys: [:path_to_claude_code_executable],
      known_locations: known_locations(),
      path_candidates: CLIConfig.executable_candidates()
    ]
  end

  defp option_overrides(%Options{} = options) do
    []
    |> maybe_put_option(:path_to_claude_code_executable, options.path_to_claude_code_executable)
    |> maybe_put_option(:executable, options.executable)
  end

  defp option_overrides(_other), do: []

  defp maybe_put_option(opts, _key, nil), do: opts
  defp maybe_put_option(opts, _key, ""), do: opts
  defp maybe_put_option(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_put_bundled_override([]) do
    case bundled_path() do
      nil -> []
      path -> [command: path]
    end
  end

  defp maybe_put_bundled_override(opts), do: opts

  defp bundled_path do
    case Application.get_env(:claude_agent_sdk, :cli_bundled_path) do
      path when is_binary(path) and path != "" ->
        existing_file(path)

      _ ->
        default_bundled_path()
        |> existing_file()
    end
  end

  defp existing_file(path) when is_binary(path) do
    if File.regular?(path), do: path, else: nil
  end

  defp existing_file(_path), do: nil

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

  defp known_locations do
    case Application.get_env(:claude_agent_sdk, :cli_known_locations) do
      paths when is_list(paths) -> paths
      _ -> default_known_locations()
    end
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

  defp run_version(%CommandSpec{} = spec) do
    invocation = Command.new(spec, ["--version"])

    case CliSubprocessCore.Command.run(invocation, stderr: :separate) do
      {:ok, %RunResult{} = result} ->
        if RunResult.success?(result) do
          {:ok, result}
        else
          {:error, {:exit_status, result.exit.code}}
        end

      {:error, _reason} ->
        {:error, :parse_failed}
    end
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
