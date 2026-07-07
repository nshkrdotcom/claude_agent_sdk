defmodule ClaudeAgentSDK.Config.Sandbox do
  @moduledoc """
  Normalizes sandbox settings for the Claude CLI.

  The CLI `sandbox` settings object uses camelCase keys. This module maps the
  ergonomic snake_case Elixir keys (atoms or strings) for the known sandbox
  schema to their camelCase CLI equivalents, while passing any unrecognized key
  through unchanged — so a map that already uses camelCase keys is preserved
  verbatim (back-compat with the previous opaque `sandbox` map behavior).

  Recognized schema (Python `SandboxSettings` / `SandboxNetworkConfig`):

    * top level: `enabled`, `auto_allow_bash_if_sandboxed`, `excluded_commands`,
      `allow_unsandboxed_commands`, `network`, `ignore_violations`,
      `enable_weaker_nested_sandbox`
    * `network`: `allowed_domains`, `denied_domains`, `allow_managed_domains_only`,
      `allow_unix_sockets`, `allow_all_unix_sockets`, `allow_local_binding`,
      `allow_mach_lookup`, `http_proxy_port`, `socks_proxy_port`
    * `ignore_violations`: `file`, `network`
  """

  @key_map %{
    "enabled" => "enabled",
    "auto_allow_bash_if_sandboxed" => "autoAllowBashIfSandboxed",
    "excluded_commands" => "excludedCommands",
    "allow_unsandboxed_commands" => "allowUnsandboxedCommands",
    "network" => "network",
    "ignore_violations" => "ignoreViolations",
    "enable_weaker_nested_sandbox" => "enableWeakerNestedSandbox",
    "allowed_domains" => "allowedDomains",
    "denied_domains" => "deniedDomains",
    "allow_managed_domains_only" => "allowManagedDomainsOnly",
    "allow_unix_sockets" => "allowUnixSockets",
    "allow_all_unix_sockets" => "allowAllUnixSockets",
    "allow_local_binding" => "allowLocalBinding",
    "allow_mach_lookup" => "allowMachLookup",
    "http_proxy_port" => "httpProxyPort",
    "socks_proxy_port" => "socksProxyPort",
    "file" => "file"
  }

  @doc """
  Normalizes a sandbox settings map to the CLI's stringified camelCase shape.
  """
  @spec normalize(map()) :: map()
  def normalize(sandbox) when is_map(sandbox), do: deep_normalize(sandbox)

  defp deep_normalize(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      string_key = to_string(key)
      {Map.get(@key_map, string_key, string_key), normalize_value(value)}
    end)
  end

  defp normalize_value(value) when is_map(value), do: deep_normalize(value)
  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)
  defp normalize_value(value), do: value
end
