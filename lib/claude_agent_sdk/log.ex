defmodule ClaudeAgentSDK.Log do
  @moduledoc """
  SDK-scoped logger wrapper with a configurable minimum log level.

  This avoids noisy output by default while still allowing callers to opt in to
  more verbose logs via application config.
  """

  require Logger

  @app :claude_agent_sdk

  @type level :: :debug | :info | :warning | :error

  @spec configure(keyword()) :: :ok
  def configure(opts) when is_list(opts) do
    case Keyword.fetch(opts, :level) do
      {:ok, level} ->
        Application.put_env(@app, :log_level, level)

      :error ->
        :ok
    end

    :ok
  end

  @spec debug(Logger.message(), keyword()) :: :ok
  def debug(message, metadata \\ []) do
    log(:debug, message, metadata)
  end

  @spec info(Logger.message(), keyword()) :: :ok
  def info(message, metadata \\ []) do
    log(:info, message, metadata)
  end

  @spec warning(Logger.message(), keyword()) :: :ok
  def warning(message, metadata \\ []) do
    log(:warning, message, metadata)
  end

  @spec error(Logger.message(), keyword()) :: :ok
  def error(message, metadata \\ []) do
    log(:error, message, metadata)
  end

  @spec log(level(), Logger.message(), keyword()) :: :ok
  def log(level, message, metadata \\ []) do
    if enabled?(level) do
      Logger.log(level, message, metadata)
    else
      :ok
    end
  end

  @spec enabled?(level()) :: boolean()
  def enabled?(level) do
    case Application.get_env(@app, :log_level, :warning) do
      nil ->
        Logger.compare_levels(level, :warning) != :lt

      :none ->
        false

      :off ->
        false

      false ->
        false

      min_level when min_level in [:debug, :info, :warning, :error] ->
        Logger.compare_levels(level, min_level) != :lt

      _ ->
        Logger.compare_levels(level, :warning) != :lt
    end
  end
end
