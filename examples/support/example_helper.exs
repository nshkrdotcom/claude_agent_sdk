defmodule Examples.Support do
  @moduledoc false

  alias ClaudeAgentSDK.CLI

  @examples_dir Path.expand("..", __DIR__)

  def examples_dir, do: @examples_dir

  def output_dir! do
    dir = Path.join(@examples_dir, "_output")
    File.mkdir_p!(dir)
    dir
  end

  # When running under `examples/run_all.sh`, we force-halt to avoid any cases where
  # background OTP apps or ports keep the VM alive after the script finishes.
  def halt_if_runner!(exit_code \\ 0) when is_integer(exit_code) do
    case System.get_env("CLAUDE_EXAMPLES_FORCE_HALT") do
      nil ->
        :ok

      value when is_binary(value) ->
        value = value |> String.trim() |> String.downcase()

        if value in ["1", "true", "yes", "y", "on"] do
          :erlang.halt(exit_code)
        end
    end

    :ok
  end

  def ensure_live! do
    Application.put_env(:claude_agent_sdk, :use_mock, false)

    case CLI.find_executable() do
      {:ok, _path} ->
        :ok

      {:error, :not_found} ->
        raise """
        Claude CLI not found.

        Install:
          npm install -g @anthropic-ai/claude-code

        Then authenticate:
          claude login
        """
    end
  end

  def header!(title) when is_binary(title) do
    IO.puts("\n" <> String.duplicate("=", 72))
    IO.puts(title)
    IO.puts(String.duplicate("=", 72))
    :ok
  end
end
