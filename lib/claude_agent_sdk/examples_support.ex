defmodule ClaudeAgentSDK.ExamplesSupport do
  @moduledoc false

  alias ClaudeAgentSDK.Options
  alias CliSubprocessCore.ExecutionSurface

  defmodule SSHContext do
    @moduledoc false

    @enforce_keys [:argv]
    defstruct argv: [],
              execution_surface: nil,
              ssh_host: nil,
              ssh_user: nil,
              ssh_port: nil,
              ssh_identity_file: nil

    @type t :: %__MODULE__{
            argv: [String.t()],
            execution_surface: ExecutionSurface.t() | nil,
            ssh_host: String.t() | nil,
            ssh_user: String.t() | nil,
            ssh_port: pos_integer() | nil,
            ssh_identity_file: String.t() | nil
          }
  end

  @context_key {__MODULE__, :ssh_context}
  @ssh_switches [
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

  @spec execution_surface() :: ExecutionSurface.t() | nil
  def execution_surface, do: context().execution_surface

  @spec with_execution_surface(struct() | map()) :: struct() | map()
  def with_execution_surface(options) when is_map(options) do
    case execution_surface() do
      %ExecutionSurface{} = surface -> Map.put(options, :execution_surface, surface)
      nil -> options
    end
  end

  @spec cli_resolution_options() :: Options.t()
  def cli_resolution_options do
    %Options{}
    |> with_execution_surface()
  end

  defp build_context(parsed, argv) do
    ssh_host = Keyword.get(parsed, :ssh_host)
    ssh_user = Keyword.get(parsed, :ssh_user)
    ssh_port = Keyword.get(parsed, :ssh_port)
    ssh_identity_file = Keyword.get(parsed, :ssh_identity_file)

    cond do
      is_nil(ssh_host) and Enum.any?([ssh_user, ssh_port, ssh_identity_file], &present?/1) ->
        {:error, "SSH example flags require --ssh-host when any other --ssh-* flag is set."}

      is_nil(ssh_host) ->
        {:ok, %SSHContext{argv: argv}}

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

    "invalid example SSH flags: #{rendered}. Supported flags: --ssh-host, --ssh-user, --ssh-port, --ssh-identity-file"
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
