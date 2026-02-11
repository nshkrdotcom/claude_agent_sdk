defmodule ClaudeAgentSDK.Config do
  @moduledoc """
  Top-level configuration facade for the SDK.

  Provides accessor functions for mock mode and CLI stream module
  selection, with deprecation handling for legacy keys.

  Domain-specific configuration is delegated to sub-modules:

  - `ClaudeAgentSDK.Config.Timeouts`      — all timeout values
  - `ClaudeAgentSDK.Config.Buffers`        — buffer sizes, truncation
  - `ClaudeAgentSDK.Config.Auth`           — auth paths, TTLs, prefixes
  - `ClaudeAgentSDK.Config.CLI`            — CLI versions, flags, paths
  - `ClaudeAgentSDK.Config.Env`            — environment variable names
  - `ClaudeAgentSDK.Config.Orchestration`  — concurrency, retries

  ## Runtime Configuration

  Every value can be overridden via `config :claude_agent_sdk`:

      config :claude_agent_sdk, ClaudeAgentSDK.Config.Timeouts,
        client_init_ms: 90_000,
        query_total_ms: 5_400_000

      config :claude_agent_sdk, ClaudeAgentSDK.Config.Buffers,
        max_stdout_buffer_bytes: 2_097_152

  See the **Configuration Internals** guide for the complete reference.
  """

  alias ClaudeAgentSDK.Log, as: Logger

  @legacy_process_module_warning_key {__MODULE__, :legacy_process_module_warning}

  @spec use_mock?() :: boolean()
  def use_mock? do
    Application.get_env(:claude_agent_sdk, :use_mock, false)
  end

  @spec cli_stream_module() :: module()
  def cli_stream_module do
    case Application.get_env(:claude_agent_sdk, :cli_stream_module) do
      nil ->
        case Application.get_env(:claude_agent_sdk, :process_module) do
          nil ->
            ClaudeAgentSDK.Query.CLIStream

          legacy_module ->
            warn_legacy_process_module(legacy_module)
            legacy_module
        end

      module ->
        module
    end
  end

  defp warn_legacy_process_module(legacy_module) do
    key = {@legacy_process_module_warning_key, legacy_module}

    unless :persistent_term.get(key, false) do
      :persistent_term.put(key, true)

      Logger.warning(
        "Config key :process_module is deprecated for query streaming. " <>
          "Use :cli_stream_module instead."
      )
    end
  end
end
