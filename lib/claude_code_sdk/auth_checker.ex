defmodule ClaudeCodeSDK.AuthChecker do
  @moduledoc """
  Module for checking Claude CLI authentication status.

  Provides utilities to verify authentication status and diagnose
  authentication issues before making API calls.
  """

  @doc """
  Checks if the Claude CLI is properly authenticated.

  ## Returns

    - `{:ok, info}` - Authenticated, with info string
    - `{:error, reason}` - Not authenticated or error occurred

  ## Examples

      iex> ClaudeCodeSDK.AuthChecker.check_auth()
      {:ok, "Authenticated as user@example.com"}
      
      iex> ClaudeCodeSDK.AuthChecker.check_auth()
      {:error, "Not authenticated. Run 'claude login' to authenticate."}
  """
  @spec check_auth() :: {:ok, String.t()} | {:error, String.t()}
  def check_auth do
    case System.cmd("claude", ["auth", "status"], stderr_to_stdout: true) do
      {output, 0} ->
        info = String.trim(output)
        {:ok, info}

      {error_output, _code} ->
        error_msg = parse_auth_error(error_output)
        {:error, error_msg}
    end
  rescue
    e ->
      {:error, "Claude CLI command failed: #{inspect(e)}"}
  end

  @doc """
  Checks if authenticated, returning a boolean.

  ## Returns

    - `true` if authenticated
    - `false` if not authenticated or error occurred

  ## Examples

      iex> ClaudeCodeSDK.AuthChecker.authenticated?()
      true
  """
  @spec authenticated?() :: boolean()
  def authenticated? do
    case check_auth() do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Checks Claude CLI installation and provides diagnostic information.

  ## Returns

    - `{:ok, %{path: String.t(), version: String.t()}}` - CLI installed
    - `{:error, reason}` - CLI not found or error

  ## Examples

      iex> ClaudeCodeSDK.AuthChecker.check_cli_installation()
      {:ok, %{path: "/usr/local/bin/claude", version: "1.0.0"}}
  """
  @spec check_cli_installation() :: {:ok, map()} | {:error, String.t()}
  def check_cli_installation do
    case System.find_executable("claude") do
      nil ->
        {:error, "Claude CLI not found. Install with: npm install -g @anthropic-ai/claude-code"}

      path ->
        case get_cli_version() do
          {:ok, version} ->
            {:ok, %{path: path, version: version}}

          {:error, reason} ->
            {:error, "Claude CLI found at #{path} but #{reason}"}
        end
    end
  end

  @doc """
  Performs full diagnostic check of Claude CLI setup.

  Returns a map with diagnostic information including:
  - CLI installation status
  - Authentication status
  - Recommendations for fixing issues

  ## Examples

      iex> ClaudeCodeSDK.AuthChecker.diagnose()
      %{
        cli_installed: true,
        cli_path: "/usr/local/bin/claude",
        cli_version: "1.0.0",
        authenticated: true,
        auth_info: "Authenticated as user@example.com",
        status: :ready,
        recommendations: []
      }
  """
  @spec diagnose() :: map()
  def diagnose do
    cli_result = check_cli_installation()
    auth_result = check_auth()

    base_diagnosis = build_diagnosis(cli_result, auth_result)

    base_diagnosis
    |> add_status()
    |> add_recommendations()
  end

  @doc """
  Ensures the CLI is ready for use, raising an error if not.

  ## Returns

    - `:ok` if everything is ready

  ## Raises

    - `RuntimeError` if CLI is not installed or not authenticated

  ## Examples

      iex> ClaudeCodeSDK.AuthChecker.ensure_ready!()
      :ok
  """
  @spec ensure_ready!() :: :ok
  def ensure_ready! do
    diagnosis = diagnose()

    case diagnosis.status do
      :ready ->
        :ok

      :not_installed ->
        raise "Claude CLI not installed. #{Enum.join(diagnosis.recommendations, " ")}"

      :not_authenticated ->
        raise "Claude CLI not authenticated. #{Enum.join(diagnosis.recommendations, " ")}"
    end
  end

  # Private functions

  defp parse_auth_error(output) do
    cond do
      String.contains?(output, "not logged in") || String.contains?(output, "not authenticated") ->
        "Not authenticated. Run 'claude login' to authenticate."

      String.contains?(output, "command not found") ->
        "Claude CLI not found. Install with: npm install -g @anthropic-ai/claude-code"

      true ->
        "Authentication check failed: #{String.trim(output)}"
    end
  end

  defp get_cli_version do
    case System.cmd("claude", ["--version"], stderr_to_stdout: true) do
      {output, 0} ->
        version = output |> String.trim() |> parse_version()
        {:ok, version}

      {_, _} ->
        {:error, "version check failed"}
    end
  rescue
    _ -> {:error, "version command failed"}
  end

  defp parse_version(output) do
    # Handle various version output formats
    cond do
      # Format: "claude/1.0.0"
      match = Regex.run(~r/claude\/(\d+\.\d+\.\d+)/, output) ->
        Enum.at(match, 1)

      # Format: "1.0.0"
      match = Regex.run(~r/^(\d+\.\d+\.\d+)/, output) ->
        Enum.at(match, 1)

      # Format: "Claude CLI version 1.0.0"
      match = Regex.run(~r/version\s+(\d+\.\d+\.\d+)/i, output) ->
        Enum.at(match, 1)

      true ->
        String.trim(output)
    end
  end

  defp build_diagnosis({:ok, cli_info}, {:ok, auth_info}) do
    %{
      cli_installed: true,
      cli_path: cli_info.path,
      cli_version: cli_info.version,
      authenticated: true,
      auth_info: auth_info
    }
  end

  defp build_diagnosis({:ok, cli_info}, {:error, auth_error}) do
    %{
      cli_installed: true,
      cli_path: cli_info.path,
      cli_version: cli_info.version,
      authenticated: false,
      auth_error: auth_error
    }
  end

  defp build_diagnosis({:error, cli_error}, _) do
    %{
      cli_installed: false,
      cli_error: cli_error,
      authenticated: false
    }
  end

  defp add_status(diagnosis) do
    status =
      cond do
        not diagnosis.cli_installed -> :not_installed
        not diagnosis.authenticated -> :not_authenticated
        true -> :ready
      end

    Map.put(diagnosis, :status, status)
  end

  defp add_recommendations(diagnosis) do
    recommendations =
      case diagnosis.status do
        :ready ->
          []

        :not_installed ->
          ["Install Claude CLI with: npm install -g @anthropic-ai/claude-code"]

        :not_authenticated ->
          ["Run 'claude login' to authenticate with your Anthropic account"]
      end

    Map.put(diagnosis, :recommendations, recommendations)
  end
end
