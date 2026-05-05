defmodule ClaudeAgentSDK.GovernedLaunch do
  @moduledoc false

  alias ClaudeAgentSDK.Options
  alias CliSubprocessCore.{Command, GovernedAuthority}

  @launch_smuggling_fields [
    :cwd,
    :user,
    :executable,
    :executable_args,
    :path_to_claude_code_executable,
    :provider_backend,
    :anthropic_base_url,
    :anthropic_auth_token
  ]

  @model_payload_backend_keys [
    "config_values",
    "external_model",
    "oss_provider",
    "provider_backend"
  ]
  @model_payload_backend_atom_keys %{
    "config_values" => :config_values,
    "external_model" => :external_model,
    "oss_provider" => :oss_provider,
    "provider_backend" => :provider_backend
  }

  @spec authority(Options.t() | keyword() | map() | nil) ::
          {:ok, GovernedAuthority.t() | nil} | {:error, term()}
  def authority(%Options{governed_authority: authority}), do: GovernedAuthority.new(authority)

  def authority(opts) when is_list(opts),
    do: GovernedAuthority.new(Keyword.get(opts, :governed_authority))

  def authority(%{} = opts), do: GovernedAuthority.new(Map.get(opts, :governed_authority))
  def authority(nil), do: {:ok, nil}

  @spec governed?(Options.t() | keyword() | map() | nil) :: boolean()
  def governed?(input) do
    case authority(input) do
      {:ok, %GovernedAuthority{}} -> true
      _ -> false
    end
  end

  @spec validate_options(Options.t()) :: :ok | {:error, term()}
  def validate_options(%Options{} = options) do
    with {:ok, authority} <- authority(options) do
      validate_options(options, authority)
    end
  end

  @spec invocation([String.t()], Options.t()) :: {:ok, Command.t()} | {:error, term()}
  def invocation(args, %Options{} = options) when is_list(args) do
    with {:ok, %GovernedAuthority{} = authority} <- authority(options),
         :ok <- validate_options(options, authority) do
      {:ok,
       Command.new(
         GovernedAuthority.command_spec(authority),
         args,
         GovernedAuthority.launch_options(authority)
       )}
    end
  end

  @spec run_options(keyword(), Options.t()) :: keyword()
  def run_options(opts, %Options{} = options) when is_list(opts) do
    case authority(options) do
      {:ok, %GovernedAuthority{} = authority} -> Keyword.put(opts, :governed_authority, authority)
      _ -> opts
    end
  end

  @spec env_vars(Options.t()) :: map() | nil
  def env_vars(%Options{} = options) do
    case authority(options) do
      {:ok, %GovernedAuthority{} = authority} -> authority.env
      _ -> nil
    end
  end

  @spec mirror_config_root(Options.t()) :: String.t() | nil
  def mirror_config_root(%Options{} = options) do
    case authority(options) do
      {:ok, %GovernedAuthority{} = authority} ->
        authority.config_root || Map.get(authority.env, "CLAUDE_CONFIG_DIR") ||
          authority.auth_root

      _ ->
        nil
    end
  end

  @spec token_store_path(Options.t() | keyword() | map()) :: {:ok, String.t()} | {:error, term()}
  def token_store_path(input) do
    with {:ok, %GovernedAuthority{} = authority} <- authority(input),
         root when is_binary(root) <- authority.auth_root || authority.config_root do
      {:ok, Path.expand(Path.join(root, "token.json"))}
    else
      {:ok, nil} -> {:error, :missing_governed_authority}
      nil -> {:error, {:missing_governed_authority_field, :auth_root}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec check_auth(keyword()) :: {:ok, map()} | {:error, term()} | :standalone
  def check_auth(opts) when is_list(opts) do
    case authority(opts) do
      {:ok, %GovernedAuthority{} = authority} ->
        {:ok, Map.put(GovernedAuthority.redacted(authority), :source, :governed_authority)}

      {:ok, nil} ->
        :standalone

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_options(_options, nil), do: :ok

  defp validate_options(%Options{} = options, %GovernedAuthority{}) do
    cond do
      field = first_present_field(options, @launch_smuggling_fields) ->
        {:error, {:governed_launch_smuggling, field}}

      env_overrides?(options.env) ->
        {:error, {:governed_launch_smuggling, :env}}

      model_payload_env_overrides?(options.model_payload) ->
        {:error, {:governed_launch_smuggling, :model_payload, :env_overrides}}

      model_payload_backend_config?(options.model_payload) ->
        {:error, {:governed_launch_smuggling, :model_payload, :backend_metadata}}

      true ->
        :ok
    end
  end

  defp first_present_field(options, fields) do
    Enum.find(fields, fn field -> present?(Map.get(options, field)) end)
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?([]), do: false
  defp present?(%{} = value), do: map_size(value) > 0
  defp present?(_value), do: true

  defp env_overrides?(env) when is_map(env), do: map_size(env) > 0
  defp env_overrides?(_env), do: false

  defp model_payload_env_overrides?(payload) when is_map(payload) do
    case payload_value(payload, :env_overrides) do
      %{} = env -> map_size(env) > 0
      _ -> false
    end
  end

  defp model_payload_env_overrides?(_payload), do: false

  defp model_payload_backend_config?(payload) when is_map(payload) do
    case payload_value(payload, :backend_metadata) do
      %{} = metadata ->
        Enum.any?(@model_payload_backend_keys, &nonempty_backend_value?(metadata, &1))

      _ ->
        false
    end
  end

  defp model_payload_backend_config?(_payload), do: false

  defp nonempty_backend_value?(metadata, key) do
    atom_key = Map.fetch!(@model_payload_backend_atom_keys, key)

    case Map.get(metadata, key, Map.get(metadata, atom_key)) do
      nil -> false
      "" -> false
      [] -> false
      %{} = value -> map_size(value) > 0
      _ -> true
    end
  end

  defp payload_value(payload, key) when is_map(payload) do
    Map.get(payload, key, Map.get(payload, Atom.to_string(key)))
  end
end
