defmodule ClaudeAgentSDK.AuthChecker do
  @moduledoc """
  Authentication checker and environment validator for Claude Code SDK.

  This module provides functions to validate the authentication state and
  environment setup before making queries to Claude Code. It helps prevent
  authentication errors and provides helpful diagnostic information.

  ## Basic Usage

      # Quick boolean check
      if ClaudeAgentSDK.AuthChecker.authenticated?() do
        ClaudeAgentSDK.query("Hello!")
      else
        IO.puts("Please run: claude login")
      end

      # Full diagnostic check
      diagnosis = ClaudeAgentSDK.AuthChecker.diagnose()
      
      # Ensure ready or raise error
      ClaudeAgentSDK.AuthChecker.ensure_ready!()

  ## Authentication Methods

  The Claude CLI supports multiple authentication methods:
  - Anthropic API key via `claude login` or `ANTHROPIC_API_KEY` environment variable
  - Amazon Bedrock via `CLAUDE_AGENT_USE_BEDROCK=1` and AWS credentials
  - Google Vertex AI via `CLAUDE_AGENT_USE_VERTEX=1` and GCP credentials

  This module detects and validates all supported authentication methods.
  """

  alias ClaudeAgentSDK.{CLI, Runtime}
  alias ClaudeAgentSDK.Config.{Auth, Env, Timeouts}

  @type auth_status ::
          :ready | :cli_not_found | :not_authenticated | :invalid_credentials | :unknown

  @type diagnosis :: %{
          cli_installed: boolean(),
          cli_version: String.t() | nil,
          cli_path: String.t() | nil,
          cli_error: String.t() | nil,
          authenticated: boolean(),
          auth_method: String.t() | nil,
          auth_info: String.t() | nil,
          auth_error: String.t() | nil,
          api_key_source: String.t() | nil,
          status: auth_status(),
          recommendations: [String.t()],
          last_checked: DateTime.t()
        }

  @doc """
  Quick boolean check for authentication status.

  Returns `true` if Claude CLI is installed and properly authenticated,
  `false` otherwise.

  ## Examples

      if ClaudeAgentSDK.AuthChecker.authenticated?() do
        IO.puts("Ready to make queries")
      else
        IO.puts("Authentication required")
      end

  """
  @spec authenticated?() :: boolean()
  def authenticated? do
    case check_cli_auth_status() do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Performs comprehensive diagnostic check of the environment.

  Returns a detailed diagnosis map with information about CLI installation,
  authentication status, detected auth method, and recommendations.

  ## Returns

  A `t:diagnosis/0` map containing:
  - `cli_installed` - Whether the Claude CLI is installed
  - `cli_version` - Version of the installed CLI (if available)
  - `authenticated` - Whether authentication is working
  - `auth_method` - Detected authentication method
  - `api_key_source` - Source of API credentials
  - `status` - Overall status (see `t:auth_status/0`)
  - `recommendations` - List of recommended actions
  - `last_checked` - Timestamp of this check

  ## Examples

      diagnosis = ClaudeAgentSDK.AuthChecker.diagnose()
      
      case diagnosis.status do
        :ready ->
          IO.puts("✅ Ready to use Claude")
          
        :cli_not_found ->
          IO.puts("❌ Claude CLI not found")
          
        :not_authenticated ->
          IO.puts("❌ Not authenticated")
      end

  """
  @spec diagnose() :: diagnosis()
  def diagnose do
    timestamp = DateTime.utc_now()

    # Check CLI installation
    {cli_installed, cli_version} = check_cli_installation_private()

    if cli_installed do
      # Check authentication
      {authenticated, auth_info} = check_detailed_auth()

      status = determine_status(cli_installed, authenticated, auth_info)
      recommendations = generate_recommendations(status, auth_info)

      %{
        cli_installed: cli_installed,
        cli_version: cli_version,
        # Placeholder, could be improved
        cli_path: "/usr/bin/claude",
        cli_error: nil,
        authenticated: authenticated,
        auth_method: auth_info[:method],
        auth_info: if(authenticated, do: "Authenticated", else: nil),
        auth_error: if(authenticated, do: nil, else: "Not authenticated"),
        api_key_source: auth_info[:source],
        status: status,
        recommendations: recommendations,
        last_checked: timestamp
      }
    else
      %{
        cli_installed: false,
        cli_version: nil,
        cli_path: nil,
        cli_error: "Claude CLI not found",
        authenticated: false,
        auth_method: nil,
        auth_info: nil,
        auth_error: nil,
        api_key_source: nil,
        status: :cli_not_found,
        recommendations: [
          "Install Claude CLI: npm install -g @anthropic-ai/claude-code",
          "Verify installation: claude --version",
          "Authenticate: claude login"
        ],
        last_checked: timestamp
      }
    end
  end

  @doc """
  Ensures the environment is ready for Claude queries.

  Raises an exception with helpful error message if not ready.
  Returns `:ok` if ready to proceed.

  ## Examples

      # Will raise if not ready
      ClaudeAgentSDK.AuthChecker.ensure_ready!()
      
      # Safe to make queries now
      ClaudeAgentSDK.query("Hello!")

  ## Raises

  - `RuntimeError` - If CLI not found or authentication missing

  """
  @spec ensure_ready!() :: :ok
  def ensure_ready! do
    case diagnose() do
      %{status: :ready} ->
        :ok

      %{status: :cli_not_found} ->
        raise """
        Claude CLI not found. Please install it first:

        npm install -g @anthropic-ai/claude-code

        Then verify: claude --version
        """

      %{status: :not_authenticated} ->
        raise """
        Claude CLI not authenticated. Please authenticate first:

        claude login

        Or set environment variable: ANTHROPIC_API_KEY=your_key_here
        """

      %{status: status, recommendations: recommendations} ->
        recommendation_text = Enum.map_join(recommendations, "\n", &"  • #{&1}")

        raise """
        Claude Code environment not ready (status: #{status}).

        Recommendations:
        #{recommendation_text}
        """
    end
  end

  @doc """
  Checks authentication status and returns result tuple.

  Returns `{:ok, info}` if authenticated, `{:error, reason}` otherwise.

  ## Examples

      case ClaudeAgentSDK.AuthChecker.check_auth() do
        {:ok, info} -> IO.puts("Authenticated: \#{info}")
        {:error, reason} -> IO.puts("Auth failed: \#{reason}")
      end

  """
  @spec check_auth() :: {:ok, String.t()} | {:error, String.t()}
  def check_auth do
    case check_cli_auth_status() do
      {:ok, _} -> {:ok, "Authenticated"}
      {:error, reason} -> {:error, "Authentication failed: #{reason}"}
    end
  end

  @doc """
  Checks Claude CLI installation status.

  Returns `{:ok, %{path: path, version: version}}` if installed,
  `{:error, reason}` otherwise.

  ## Examples

      case ClaudeAgentSDK.AuthChecker.check_cli_installation() do
        {:ok, %{path: path, version: version}} -> 
          IO.puts("CLI installed at \#{path}, version \#{version}")
        {:error, reason} -> 
          IO.puts("CLI not found: \#{reason}")
      end

  """
  @spec check_cli_installation() :: {:ok, map()} | {:error, String.t()}
  def check_cli_installation do
    {installed, version} = check_cli_installation_private()

    if installed do
      {:ok, %{path: "/usr/bin/claude", version: version}}
    else
      {:error, "Claude CLI not found"}
    end
  end

  @doc """
  Checks if a specific authentication method is available.

  ## Parameters

  - `method` - Authentication method to check (`:anthropic`, `:bedrock`, or `:vertex`)

  ## Examples

      if ClaudeAgentSDK.AuthChecker.auth_method_available?(:bedrock) do
        IO.puts("AWS Bedrock authentication is configured")
      end

  """
  @spec auth_method_available?(atom()) :: boolean()
  def auth_method_available?(method) do
    case method do
      :anthropic ->
        check_anthropic_auth()

      :bedrock ->
        check_bedrock_auth()

      :vertex ->
        check_vertex_auth()

      _ ->
        false
    end
  end

  @doc """
  Gets the current API key source information.

  Returns information about where the API credentials are coming from.

  ## Examples

      case ClaudeAgentSDK.AuthChecker.get_api_key_source() do
        {:ok, "environment variable ANTHROPIC_API_KEY"} ->
          IO.puts("Using environment variable")
          
        {:ok, "claude login session"} ->
          IO.puts("Using stored session")
          
        {:error, reason} ->
          IO.puts("No valid API key: \#{reason}")
      end

  """
  @spec get_api_key_source() :: {:ok, String.t()} | {:error, String.t()}
  def get_api_key_source do
    cond do
      System.get_env(Env.anthropic_api_key()) ->
        {:ok, "environment variable ANTHROPIC_API_KEY"}

      System.get_env(Env.use_bedrock()) == "1" ->
        if check_aws_credentials() do
          {:ok, "AWS credentials for Bedrock"}
        else
          {:error, "CLAUDE_AGENT_USE_BEDROCK set but AWS credentials not found"}
        end

      System.get_env(Env.use_vertex()) == "1" ->
        if check_gcp_credentials() do
          {:ok, "Google Cloud credentials for Vertex AI"}
        else
          {:error, "CLAUDE_AGENT_USE_VERTEX set but GCP credentials not found"}
        end

      true ->
        case check_cli_session() do
          true -> {:ok, "claude login session"}
          false -> {:error, "no authentication method found"}
        end
    end
  end

  # Private helper functions

  if Mix.env() == :test do
    @doc false
    def run_command_with_timeout_for_test(command, timeout_ms) do
      run_command_with_timeout(command, timeout_ms)
    end
  end

  defp check_cli_installation_private do
    case CLI.find_executable() do
      {:ok, _path} ->
        case CLI.version() do
          {:ok, version} -> {true, version}
          {:error, _} -> {true, nil}
        end

      {:error, :not_found} ->
        {false, nil}
    end
  end

  defp check_cli_auth_status do
    # Check if mocking is enabled
    if Runtime.use_mock?() do
      {:ok, :authenticated}
    else
      execute_auth_test()
    end
  end

  defp execute_auth_test do
    case execute_with_timeout(
           "claude --print test --output-format json",
           Timeouts.auth_cli_test_ms()
         ) do
      {:ok, output} -> validate_cli_output(output)
      {:error, :timeout} -> {:error, :timeout}
      {:error, error} -> parse_cli_error(error)
    end
  end

  defp validate_cli_output(output) do
    case ClaudeAgentSDK.JSON.decode(output) do
      {:ok, _parsed} -> {:ok, :authenticated}
      {:error, _} -> {:error, :invalid_response}
    end
  end

  defp parse_cli_error(error) do
    cond do
      String.contains?(error, "not authenticated") or
        String.contains?(error, "login") or
          String.contains?(error, "API key") ->
        {:error, :not_authenticated}

      String.contains?(error, "network") or
          String.contains?(error, "connection") ->
        {:error, :network_error}

      true ->
        {:error, :unknown}
    end
  end

  defp check_detailed_auth do
    # Check different auth methods in order of preference
    cond do
      check_anthropic_auth() ->
        source = if System.get_env(Env.anthropic_api_key()), do: "env", else: "session"
        {true, %{method: "Anthropic API", source: source}}

      check_bedrock_auth() ->
        {true, %{method: "AWS Bedrock", source: "aws_credentials"}}

      check_vertex_auth() ->
        {true, %{method: "Google Vertex AI", source: "gcp_credentials"}}

      true ->
        {false, %{method: nil, source: nil}}
    end
  end

  defp check_anthropic_auth do
    # Check environment variable first
    if System.get_env(Env.anthropic_api_key()) do
      true
    else
      # Check CLI session
      check_cli_session()
    end
  end

  defp check_bedrock_auth do
    System.get_env(Env.use_bedrock()) == "1" and check_aws_credentials()
  end

  defp check_vertex_auth do
    System.get_env(Env.use_vertex()) == "1" and check_gcp_credentials()
  end

  defp check_cli_session do
    # Try a simple test command to see if CLI is authenticated
    case execute_with_timeout("claude --version", Timeouts.auth_cli_version_ms()) do
      {:ok, _output} ->
        # CLI works, now test auth with a minimal query
        case execute_with_timeout(
               "claude --print hello --max-turns 1",
               Timeouts.auth_cli_test_ms()
             ) do
          {:ok, _output} -> true
          {:error, _} -> false
        end

      {:error, _} ->
        false
    end
  end

  defp check_aws_credentials do
    # Check for AWS credentials in common locations
    System.get_env(Env.aws_access_key_id()) != nil or
      System.get_env(Env.aws_profile()) != nil or
      File.exists?(Path.expand(Auth.aws_credentials_path()))
  end

  defp check_gcp_credentials do
    # Check for GCP credentials
    System.get_env(Env.gcp_credentials()) != nil or
      System.get_env(Env.gcp_project()) != nil or
      File.exists?(Path.expand(Auth.gcp_credentials_path()))
  end

  defp determine_status(cli_installed, authenticated, auth_info) do
    cond do
      not cli_installed ->
        :cli_not_found

      not authenticated ->
        # Check if we have partial auth info indicating invalid credentials
        if auth_info[:method] && not authenticated do
          :invalid_credentials
        else
          :not_authenticated
        end

      authenticated and auth_info[:method] ->
        :ready

      true ->
        :unknown
    end
  end

  defp generate_recommendations(status, _auth_info) do
    case status do
      :ready ->
        ["Environment is ready for Claude queries"]

      :cli_not_found ->
        [
          "Install Claude CLI: npm install -g @anthropic-ai/claude-code",
          "Verify installation: claude --version"
        ]

      :not_authenticated ->
        base_recommendations = ["Run 'claude login' to authenticate"]
        additional = get_provider_specific_recommendations()
        base_recommendations ++ additional

      :invalid_credentials ->
        [
          "Check your API key or credentials",
          "Try re-authenticating: claude login",
          "Verify network connectivity"
        ]

      _ ->
        [
          "Run diagnostic: ClaudeAgentSDK.AuthChecker.diagnose()",
          "Check Claude CLI installation: claude --version",
          "Verify authentication: claude login"
        ]
    end
  end

  defp get_provider_specific_recommendations do
    cond do
      System.get_env(Env.use_bedrock()) == "1" ->
        ["Ensure AWS credentials are configured", "Check AWS_PROFILE or AWS_ACCESS_KEY_ID"]

      System.get_env(Env.use_vertex()) == "1" ->
        ["Ensure GCP credentials are configured", "Check GOOGLE_APPLICATION_CREDENTIALS"]

      true ->
        ["Or set ANTHROPIC_API_KEY environment variable"]
    end
  end

  defp execute_with_timeout(command, timeout_ms) do
    Runtime.ensure_erlexec_started!()
    run_command_with_timeout(command, timeout_ms)
  end

  defp run_command_with_timeout(command, timeout_ms) do
    case :exec.run(command, [:sync, :stdout, :stderr], timeout_ms) do
      {:ok, result} ->
        handle_successful_execution(result)

      {:error, error_data} ->
        handle_execution_error(error_data)
    end
  end

  defp handle_successful_execution(result) do
    stdout_data = get_in(result, [:stdout]) || []
    output = Enum.join(stdout_data, "")
    {:ok, output}
  end

  defp handle_execution_error(exit_status: status, stdout: stdout_data, stderr: stderr_data) do
    error_text = extract_error_text(stdout_data, stderr_data)
    {:error, "Command failed (exit #{status}): #{error_text}"}
  end

  defp handle_execution_error(:timeout), do: {:error, :timeout}

  defp handle_execution_error(reason), do: {:error, "Command failed: #{inspect(reason)}"}

  defp extract_error_text(stdout_data, stderr_data) do
    stdout_text = if is_list(stdout_data), do: Enum.join(stdout_data, ""), else: ""
    stderr_text = if is_list(stderr_data), do: Enum.join(stderr_data, ""), else: ""

    if stderr_text != "", do: stderr_text, else: stdout_text
  end
end
