defmodule ClaudeAgentSDK.Config do
  @moduledoc false

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
