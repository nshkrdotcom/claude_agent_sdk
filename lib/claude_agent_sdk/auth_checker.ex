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
  - Anthropic-compatible local backends such as Ollama via `ANTHROPIC_BASE_URL`
    and `ANTHROPIC_AUTH_TOKEN=ollama`
  - Amazon Bedrock via `CLAUDE_AGENT_USE_BEDROCK=1` and AWS credentials
  - Google Vertex AI via `CLAUDE_AGENT_USE_VERTEX=1` and GCP credentials

  This module detects and validates all supported authentication methods.
  """

  alias ClaudeAgentSDK.{CLI, Runtime}
  alias ClaudeAgentSDK.Config.{Auth, Env, Timeouts}
  alias CliSubprocessCore.Command, as: CoreCommand
  alias CliSubprocessCore.Command.Error, as: CoreCommandError
  alias CliSubprocessCore.Command.RunResult
  alias ExternalRuntimeTransport.Transport.Error, as: CoreTransportError

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

    case check_cli_installation_private() do
      {:ok, %{path: cli_path, version: cli_version}} ->
        {authenticated, auth_info} = check_detailed_auth(cli_path)

        status = determine_status(authenticated, auth_info)
        recommendations = generate_recommendations(status, auth_info)

        %{
          cli_installed: true,
          cli_version: cli_version,
          cli_path: cli_path,
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

      {:error, :not_found} ->
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
          recommendations: generate_recommendations(:cli_not_found, %{}),
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
    case check_cli_installation_private() do
      {:ok, cli_info} ->
        {:ok, cli_info}

      {:error, :not_found} ->
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
      :ollama ->
        check_ollama_auth()

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
    case api_key_source_from_env() do
      nil ->
        if check_cli_session() do
          {:ok, "claude login session"}
        else
          {:error, "no authentication method found"}
        end

      result ->
        result
    end
  end

  # Private helper functions

  @doc false
  def run_command_with_timeout_for_test(command, timeout_ms) do
    shell = System.find_executable("sh") || "/bin/sh"

    shell
    |> CoreCommand.new(["-lc", command])
    |> run_invocation_with_timeout(timeout_ms)
  end

  defp check_cli_installation_private do
    case CLI.find_executable() do
      {:ok, path} ->
        case cli_version(path) do
          {:ok, version} -> {:ok, %{path: path, version: version}}
          {:error, _} -> {:ok, %{path: path, version: nil}}
        end

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  defp check_cli_auth_status do
    if Runtime.use_mock?() do
      {:ok, :authenticated}
    else
      case CLI.find_executable() do
        {:ok, executable} ->
          execute_auth_test(executable)

        {:error, :not_found} ->
          {:error, :cli_not_found}
      end
    end
  end

  defp execute_auth_test(executable) when is_binary(executable) do
    case execute_cli_command(
           executable,
           ["--print", "test", "--output-format", "json"],
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
    if String.contains?(error, "not authenticated") or
         String.contains?(error, "login") or
         String.contains?(error, "API key") do
      {:error, :not_authenticated}
    else
      if String.contains?(error, "network") or
           String.contains?(error, "connection") do
        {:error, :network_error}
      else
        {:error, :unknown}
      end
    end
  end

  defp check_detailed_auth(executable) do
    # Check different auth methods in order of preference
    case {check_ollama_auth(), check_anthropic_auth(executable), check_bedrock_auth(),
          check_vertex_auth()} do
      {true, _, _, _} ->
        {true, %{method: "Ollama", source: "anthropic_compatible"}}

      {false, true, _, _} ->
        source = if System.get_env(Env.anthropic_api_key()), do: "env", else: "session"
        {true, %{method: "Anthropic API", source: source}}

      {false, false, true, _} ->
        {true, %{method: "AWS Bedrock", source: "aws_credentials"}}

      {false, false, false, true} ->
        {true, %{method: "Google Vertex AI", source: "gcp_credentials"}}

      {false, false, false, false} ->
        {false, %{method: nil, source: nil}}
    end
  end

  defp check_anthropic_auth do
    if System.get_env(Env.anthropic_api_key()) do
      true
    else
      check_cli_session()
    end
  end

  defp check_anthropic_auth(executable) do
    # Check environment variable first
    if System.get_env(Env.anthropic_api_key()) do
      true
    else
      check_cli_session(executable)
    end
  end

  defp check_bedrock_auth do
    System.get_env(Env.use_bedrock()) == "1" and check_aws_credentials()
  end

  defp check_vertex_auth do
    System.get_env(Env.use_vertex()) == "1" and check_gcp_credentials()
  end

  defp check_ollama_auth do
    case {
      System.get_env(Env.anthropic_auth_token()),
      System.get_env(Env.anthropic_base_url())
    } do
      {"ollama", base_url} when is_binary(base_url) and base_url != "" ->
        ollama_api_reachable?(base_url)

      _ ->
        false
    end
  end

  defp api_key_source_from_env do
    cond do
      is_binary(System.get_env(Env.anthropic_api_key())) ->
        {:ok, "environment variable ANTHROPIC_API_KEY"}

      ollama_env_configured?() ->
        ollama_api_source()

      System.get_env(Env.use_bedrock()) == "1" ->
        bedrock_api_source()

      System.get_env(Env.use_vertex()) == "1" ->
        vertex_api_source()

      true ->
        nil
    end
  end

  defp ollama_env_configured? do
    System.get_env(Env.anthropic_auth_token()) == "ollama" and
      is_binary(System.get_env(Env.anthropic_base_url()))
  end

  defp ollama_api_source do
    if check_ollama_auth() do
      {:ok, "Ollama via ANTHROPIC_BASE_URL"}
    else
      {:error, "ANTHROPIC_BASE_URL is set for Ollama but the Ollama API is not reachable"}
    end
  end

  defp bedrock_api_source do
    if check_aws_credentials() do
      {:ok, "AWS credentials for Bedrock"}
    else
      {:error, "CLAUDE_AGENT_USE_BEDROCK set but AWS credentials not found"}
    end
  end

  defp vertex_api_source do
    if check_gcp_credentials() do
      {:ok, "Google Cloud credentials for Vertex AI"}
    else
      {:error, "CLAUDE_AGENT_USE_VERTEX set but GCP credentials not found"}
    end
  end

  defp check_cli_session do
    case CLI.find_executable() do
      {:ok, executable} -> check_cli_session(executable)
      {:error, :not_found} -> false
    end
  end

  defp check_cli_session(executable) when is_binary(executable) do
    case execute_cli_command(executable, ["--version"], Timeouts.auth_cli_version_ms()) do
      {:ok, _output} ->
        case execute_cli_command(
               executable,
               ["--print", "hello", "--max-turns", "1"],
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

  defp determine_status(authenticated, auth_info) do
    case {authenticated, auth_info[:method]} do
      {false, nil} ->
        :not_authenticated

      {false, _method} ->
        :invalid_credentials

      {true, nil} ->
        :unknown

      {true, _method} ->
        :ready
    end
  end

  defp generate_recommendations(status, _auth_info) do
    case status do
      :ready ->
        ["Environment is ready for Claude queries"]

      :cli_not_found ->
        [
          "Install Claude CLI: npm install -g @anthropic-ai/claude-code",
          "Verify installation: claude --version",
          "Authenticate: claude login"
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
    case {
      System.get_env(Env.anthropic_auth_token()),
      System.get_env(Env.anthropic_base_url()),
      System.get_env(Env.use_bedrock()),
      System.get_env(Env.use_vertex())
    } do
      {"ollama", base_url, _, _} when is_binary(base_url) and base_url != "" ->
        [
          "Ensure the Ollama daemon is running and reachable at ANTHROPIC_BASE_URL",
          "Ensure the requested local model is installed in Ollama"
        ]

      {_, _, "1", _} ->
        ["Ensure AWS credentials are configured", "Check AWS_PROFILE or AWS_ACCESS_KEY_ID"]

      {_, _, _, "1"} ->
        ["Ensure GCP credentials are configured", "Check GOOGLE_APPLICATION_CREDENTIALS"]

      _ ->
        ["Or set ANTHROPIC_API_KEY environment variable"]
    end
  end

  defp ollama_api_reachable?(base_url) when is_binary(base_url) do
    url = String.trim_trailing(base_url, "/") <> "/api/tags"

    with {:ok, _} <- Application.ensure_all_started(:inets),
         {:ok, _} <- Application.ensure_all_started(:ssl) do
      case :httpc.request(:get, {String.to_charlist(url), []}, [{:timeout, 2_000}],
             body_format: :binary
           ) do
        {:ok, {{_http_version, status, _reason_phrase}, _headers, _body}}
        when status in 200..299 ->
          true

        _ ->
          false
      end
    end
  catch
    _, _ ->
      false
  end

  defp execute_cli_command(executable, args, timeout_ms)
       when is_binary(executable) and is_list(args) do
    executable
    |> CoreCommand.new(args)
    |> run_invocation_with_timeout(timeout_ms)
  end

  defp run_invocation_with_timeout(%CoreCommand{} = invocation, timeout_ms) do
    case CoreCommand.run(invocation, timeout: timeout_ms, stderr: :separate) do
      {:ok, %RunResult{} = result} ->
        handle_successful_execution(result)

      {:error, %CoreCommandError{} = error} ->
        handle_execution_error(error)
    end
  end

  defp handle_successful_execution(%RunResult{} = result) do
    if RunResult.success?(result) do
      {:ok, result.stdout}
    else
      error_text = extract_error_text(result.stdout, result.stderr)
      {:error, "Command failed (exit #{result.exit.code}): #{error_text}"}
    end
  end

  defp handle_execution_error(%CoreCommandError{
         reason: {:transport, %CoreTransportError{reason: :timeout}}
       }),
       do: {:error, :timeout}

  defp handle_execution_error(%CoreCommandError{} = error) do
    {:error, "Command failed: #{Exception.message(error)}"}
  end

  defp extract_error_text(stdout_text, stderr_text)
       when is_binary(stdout_text) and is_binary(stderr_text) do
    if stderr_text != "", do: stderr_text, else: stdout_text
  end

  defp cli_version(path) when is_binary(path) do
    invocation = CoreCommand.new(path, ["--version"])

    case CoreCommand.run(invocation, stderr: :separate) do
      {:ok, %RunResult{} = result} ->
        with true <- RunResult.success?(result),
             [_, version] <- Regex.run(~r/(\d+\.\d+\.\d+)/, result.stdout) do
          {:ok, version}
        else
          false -> {:error, {:exit_status, result.exit.code}}
          _ -> {:error, :parse_failed}
        end

      {:error, %CoreCommandError{} = error} ->
        {:error, error}
    end
  end
end
