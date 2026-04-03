defmodule ClaudeAgentSDK.ExamplesSupport do
  @moduledoc false

  alias ClaudeAgentSDK.{CLI, Options}
  alias ClaudeAgentSDK.Process, as: ClaudeProcess
  alias CliSubprocessCore.Command, as: CoreCommand
  alias CliSubprocessCore.Command.Error, as: CoreCommandError
  alias CliSubprocessCore.Command.RunResult
  alias CliSubprocessCore.CommandSpec
  alias CliSubprocessCore.ExecutionSurface
  alias ExternalRuntimeTransport.Transport.Error, as: CoreTransportError

  @preflight_prompt "Reply with exactly: OK"
  @default_preflight_timeout_seconds 30
  @default_ollama_preflight_timeout_seconds 60

  defmodule SSHContext do
    @moduledoc false

    @enforce_keys [:argv]
    defstruct argv: [],
              execution_surface: nil,
              example_cwd: nil,
              example_danger_full_access: false,
              ssh_host: nil,
              ssh_user: nil,
              ssh_port: nil,
              ssh_identity_file: nil

    @type t :: %__MODULE__{
            argv: [String.t()],
            execution_surface: ExecutionSurface.t() | nil,
            example_cwd: String.t() | nil,
            example_danger_full_access: boolean(),
            ssh_host: String.t() | nil,
            ssh_user: String.t() | nil,
            ssh_port: pos_integer() | nil,
            ssh_identity_file: String.t() | nil
          }
  end

  @context_key {__MODULE__, :ssh_context}
  @ssh_switches [
    cwd: :string,
    danger_full_access: :boolean,
    ssh_host: :string,
    ssh_identity_file: :string,
    ssh_port: :integer,
    ssh_user: :string
  ]

  @spec init!([String.t()]) :: SSHContext.t()
  def init!(argv \\ System.argv()) when is_list(argv) do
    case Process.get(@context_key) do
      %SSHContext{} = context ->
        context

      nil ->
        case parse_argv(argv) do
          {:ok, %SSHContext{} = context} ->
            System.argv(context.argv)
            Process.put(@context_key, context)
            context

          {:error, message} ->
            raise ArgumentError, message
        end
    end
  end

  @spec context() :: SSHContext.t()
  def context do
    case Process.get(@context_key) do
      %SSHContext{} = context -> context
      _ -> init!()
    end
  end

  @spec parse_argv([String.t()]) :: {:ok, SSHContext.t()} | {:error, String.t()}
  def parse_argv(argv) when is_list(argv) do
    {parsed, remaining, invalid} =
      argv
      |> Enum.reject(&(&1 == "--"))
      |> OptionParser.parse(strict: @ssh_switches)

    if invalid != [] do
      {:error, invalid_options_message(invalid)}
    else
      build_context(parsed, remaining)
    end
  end

  @spec ssh_enabled?() :: boolean()
  def ssh_enabled?, do: match?(%SSHContext{execution_surface: %ExecutionSurface{}}, context())

  @spec danger_full_access?() :: boolean()
  def danger_full_access?, do: context().example_danger_full_access == true

  @spec execution_surface() :: ExecutionSurface.t() | nil
  def execution_surface, do: context().execution_surface

  @spec with_execution_surface(struct() | map()) :: struct() | map()
  def with_execution_surface(options) when is_map(options) do
    options
    |> maybe_put_execution_surface()
    |> maybe_put_example_cwd()
    |> maybe_put_danger_full_access()
  end

  @spec cli_resolution_options() :: Options.t()
  def cli_resolution_options do
    %Options{}
    |> with_execution_surface()
  end

  @spec preflight_options() :: Options.t()
  def preflight_options do
    %Options{
      model: preflight_model(),
      max_turns: 1,
      output_format: :json,
      setting_sources: ["user"]
    }
    |> with_execution_surface()
  end

  @spec preflight() :: :ok | {:error, String.t()}
  def preflight do
    options = preflight_options()

    with {:ok, %CommandSpec{} = command_spec} <- CLI.resolve_command_spec(options),
         invocation <- preflight_invocation(command_spec, options),
         {:ok, %RunResult{} = result} <- CoreCommand.run(invocation, preflight_run_opts(options)),
         :ok <- validate_preflight_result(result) do
      :ok
    else
      {:error, :not_found} ->
        {:error, "Claude CLI not found. Install with: npm install -g @anthropic-ai/claude-code"}

      {:error, %CoreCommandError{reason: {:transport, %CoreTransportError{reason: :timeout}}}} ->
        {:error, preflight_timeout_error()}

      {:error, error} when is_exception(error) ->
        {:error, normalize_preflight_error(Exception.message(error))}

      {:error, error} ->
        {:error, normalize_preflight_error(error)}
    end
  end

  @doc false
  @spec preflight_timeout_seconds() :: pos_integer()
  def preflight_timeout_seconds do
    env_positive_integer("CLAUDE_EXAMPLES_PREFLIGHT_TIMEOUT_SECONDS") ||
      default_preflight_timeout_seconds()
  end

  @doc false
  @spec preflight_timeout_ms() :: pos_integer()
  def preflight_timeout_ms, do: preflight_timeout_seconds() * 1_000

  @doc false
  @spec preflight_auth_hint() :: String.t()
  def preflight_auth_hint do
    case preflight_backend() do
      :ollama ->
        "Verify Ollama is reachable at ANTHROPIC_BASE_URL and that the selected model is installed."

      :anthropic ->
        "Authenticate with `claude login`, or set ANTHROPIC_API_KEY / CLAUDE_AGENT_OAUTH_TOKEN."
    end
  end

  @doc false
  @spec preflight_timeout_hint() :: String.t()
  def preflight_timeout_hint do
    timeout_seconds = preflight_timeout_seconds()

    case preflight_backend() do
      :ollama ->
        "Ollama cold starts can exceed #{timeout_seconds}s. Increase CLAUDE_EXAMPLES_PREFLIGHT_TIMEOUT_SECONDS or warm the model first."

      :anthropic ->
        "Increase CLAUDE_EXAMPLES_PREFLIGHT_TIMEOUT_SECONDS if Claude CLI startup is slow in this environment."
    end
  end

  defp build_context(parsed, argv) do
    example_cwd = Keyword.get(parsed, :cwd)
    example_danger_full_access = Keyword.get(parsed, :danger_full_access, false)
    ssh_host = Keyword.get(parsed, :ssh_host)
    ssh_user = Keyword.get(parsed, :ssh_user)
    ssh_port = Keyword.get(parsed, :ssh_port)
    ssh_identity_file = Keyword.get(parsed, :ssh_identity_file)

    cond do
      is_nil(ssh_host) and Enum.any?([ssh_user, ssh_port, ssh_identity_file], &present?/1) ->
        {:error, "SSH example flags require --ssh-host when any other --ssh-* flag is set."}

      invalid_example_cwd?(example_cwd) ->
        {:error, "--cwd must be a non-empty path"}

      is_nil(ssh_host) ->
        {:ok,
         %SSHContext{
           argv: argv,
           example_cwd: normalize_example_cwd(example_cwd),
           example_danger_full_access: example_danger_full_access
         }}

      true ->
        with {:ok, {destination, parsed_user}} <- split_host(ssh_host),
             {:ok, effective_user} <- coalesce_user(parsed_user, ssh_user),
             {:ok, identity_file} <- normalize_identity_file(ssh_identity_file),
             {:ok, %ExecutionSurface{} = execution_surface} <-
               ExecutionSurface.new(
                 surface_kind: :ssh_exec,
                 transport_options:
                   []
                   |> Keyword.put(:destination, destination)
                   |> maybe_put(:ssh_user, effective_user)
                   |> maybe_put(:port, ssh_port)
                   |> maybe_put(:identity_file, identity_file)
               ) do
          {:ok,
           %SSHContext{
             argv: argv,
             execution_surface: execution_surface,
             example_cwd: normalize_example_cwd(example_cwd),
             example_danger_full_access: example_danger_full_access,
             ssh_host: destination,
             ssh_user: effective_user,
             ssh_port: ssh_port,
             ssh_identity_file: identity_file
           }}
        else
          {:error, reason} when is_binary(reason) -> {:error, reason}
          {:error, reason} -> {:error, "invalid SSH example flags: #{inspect(reason)}"}
        end
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(nil), do: false
  defp present?(_value), do: true

  defp split_host(ssh_host) when is_binary(ssh_host) do
    case String.trim(ssh_host) do
      "" ->
        {:error, "--ssh-host must be a non-empty host name"}

      trimmed ->
        case String.split(trimmed, "@", parts: 2) do
          [destination] ->
            {:ok, {destination, nil}}

          [inline_user, destination] when inline_user != "" and destination != "" ->
            {:ok, {destination, inline_user}}

          _other ->
            {:error, "--ssh-host must be either <host> or <user>@<host>"}
        end
    end
  end

  defp coalesce_user(nil, nil), do: {:ok, nil}
  defp coalesce_user(inline_user, nil), do: {:ok, inline_user}

  defp coalesce_user(nil, ssh_user) when is_binary(ssh_user) do
    case String.trim(ssh_user) do
      "" -> {:error, "--ssh-user must be a non-empty string"}
      trimmed -> {:ok, trimmed}
    end
  end

  defp coalesce_user(inline_user, ssh_user) when is_binary(ssh_user) do
    normalized = String.trim(ssh_user)

    cond do
      normalized == "" ->
        {:error, "--ssh-user must be a non-empty string"}

      normalized == inline_user ->
        {:ok, inline_user}

      true ->
        {:error,
         "--ssh-host already contains #{inspect(inline_user)}; omit --ssh-user or make it match"}
    end
  end

  defp normalize_identity_file(nil), do: {:ok, nil}

  defp normalize_identity_file(path) when is_binary(path) do
    case String.trim(path) do
      "" -> {:error, "--ssh-identity-file must be a non-empty path"}
      trimmed -> {:ok, Path.expand(trimmed)}
    end
  end

  defp invalid_options_message(invalid) when is_list(invalid) do
    rendered =
      Enum.map_join(invalid, ", ", fn
        {name, nil} -> "--#{name}"
        {name, value} -> "--#{name}=#{value}"
      end)

    "invalid example flags: #{rendered}. Supported flags: --cwd, --danger-full-access, --ssh-host, --ssh-user, --ssh-port, --ssh-identity-file"
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_put_execution_surface(options) when is_map(options) do
    case execution_surface() do
      %ExecutionSurface{} = surface -> Map.put(options, :execution_surface, surface)
      nil -> options
    end
  end

  defp maybe_put_example_cwd(options) when is_map(options) do
    case normalize_example_cwd(context().example_cwd) do
      cwd when is_binary(cwd) -> Map.put(options, :cwd, cwd)
      _ -> options
    end
  end

  defp maybe_put_danger_full_access(options) when is_map(options) do
    if danger_full_access?() do
      Map.put(options, :permission_mode, :bypass_permissions)
    else
      options
    end
  end

  defp preflight_model do
    case System.get_env("ANTHROPIC_MODEL") do
      model when is_binary(model) and model != "" -> model
      _ -> "haiku"
    end
  end

  defp preflight_invocation(%CommandSpec{} = command_spec, %Options{} = options) do
    CoreCommand.new(command_spec, Options.to_args(options) ++ ["--print", @preflight_prompt],
      cwd: options.cwd,
      env: ClaudeProcess.__env_vars__(options),
      user: options.user
    )
  end

  defp preflight_run_opts(%Options{} = options) do
    [timeout: preflight_timeout_ms(), stderr: :separate]
    |> Kernel.++(Options.execution_surface_options(options))
  end

  defp validate_preflight_result(%RunResult{} = result) do
    if RunResult.success?(result) do
      case Jason.decode(result.stdout) do
        {:ok, decoded} -> validate_preflight_payload(decoded)
        {:error, _reason} -> {:error, "Claude CLI preflight returned invalid JSON output"}
      end
    else
      {:error, preflight_error_text(result)}
    end
  end

  defp validate_preflight_payload(%{"is_error" => true, "result" => result})
       when is_binary(result) and result != "" do
    {:error, result}
  end

  defp validate_preflight_payload(%{"result" => result}) when is_binary(result), do: :ok
  defp validate_preflight_payload(%{}), do: :ok

  defp validate_preflight_payload(_other),
    do: {:error, "Claude CLI preflight returned invalid JSON output"}

  defp preflight_error_text(%RunResult{} = result) do
    result.stderr
    |> case do
      stderr when is_binary(stderr) and stderr != "" -> stderr
      _ -> result.stdout
    end
    |> String.trim()
    |> case do
      "" -> "Claude CLI preflight failed (exit=#{result.exit.code})"
      text -> text
    end
  end

  defp normalize_preflight_error(error) when is_binary(error) do
    trimmed = String.trim(error)

    case Jason.decode(trimmed) do
      {:ok, %{"result" => result}} when is_binary(result) and result != "" ->
        result

      {:ok, inner} when is_binary(inner) ->
        normalize_preflight_error(inner)

      _ ->
        trimmed
    end
  end

  defp normalize_preflight_error(error), do: inspect(error)

  defp preflight_timeout_error do
    "Claude CLI preflight timed out after #{preflight_timeout_seconds()}s. " <>
      preflight_timeout_hint()
  end

  defp default_preflight_timeout_seconds do
    case preflight_backend() do
      :ollama -> @default_ollama_preflight_timeout_seconds
      :anthropic -> @default_preflight_timeout_seconds
    end
  end

  defp preflight_backend do
    cond do
      normalized_env("CLAUDE_AGENT_PROVIDER_BACKEND") == "ollama" ->
        :ollama

      normalized_env("CLAUDE_EXAMPLES_BACKEND") == "ollama" ->
        :ollama

      System.get_env("ANTHROPIC_AUTH_TOKEN") == "ollama" and
          present?(System.get_env("ANTHROPIC_BASE_URL")) ->
        :ollama

      true ->
        :anthropic
    end
  end

  defp env_positive_integer(name) when is_binary(name) do
    case System.get_env(name) do
      value when is_binary(value) ->
        case Integer.parse(String.trim(value)) do
          {parsed, ""} when parsed > 0 -> parsed
          _ -> nil
        end

      _other ->
        nil
    end
  end

  defp invalid_example_cwd?(nil), do: false
  defp invalid_example_cwd?(path) when is_binary(path), do: String.trim(path) == ""

  defp normalize_example_cwd(nil), do: nil
  defp normalize_example_cwd(path) when is_binary(path), do: String.trim(path)

  defp normalized_env(name) when is_binary(name) do
    case System.get_env(name) do
      nil -> nil
      value -> value |> String.trim() |> String.downcase()
    end
  end
end
